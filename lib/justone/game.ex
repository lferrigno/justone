defmodule Justone.Game do
  @moduledoc """
  The Game context handles all game-related operations.
  """

  import Ecto.Query, warn: false
  alias Justone.Repo
  alias Justone.Game.{Game, Player, Word, Clue}

  # Games

  def list_joinable_games do
    Game
    |> where([g], g.status == "waiting")
    |> preload(:players)
    |> order_by([g], desc: g.inserted_at)
    |> Repo.all()
  end

  def get_game!(id), do: Repo.get!(Game, id)

  def get_game_by_code(code) do
    Game
    |> where([g], g.code == ^code)
    |> preload([:players, :current_word, :clues])
    |> Repo.one()
  end

  def create_game(attrs \\ %{}) do
    code = generate_unique_code()

    %Game{}
    |> Game.changeset(Map.put(attrs, "code", code))
    |> Repo.insert()
  end

  def update_game(%Game{} = game, attrs) do
    game
    |> Game.changeset(attrs)
    |> Repo.update()
  end

  def delete_game(%Game{} = game) do
    Repo.delete(game)
  end

  defp generate_unique_code do
    code = Game.generate_code()

    case get_game_by_code(code) do
      nil -> code
      _ -> generate_unique_code()
    end
  end

  # Players

  def get_player!(id), do: Repo.get!(Player, id)

  def get_player_by_session(game_id, session_id) do
    Player
    |> where([p], p.game_id == ^game_id and p.session_id == ^session_id)
    |> Repo.one()
  end

  def create_player(attrs \\ %{}) do
    %Player{}
    |> Player.changeset(attrs)
    |> Repo.insert()
  end

  def update_player(%Player{} = player, attrs) do
    player
    |> Player.changeset(attrs)
    |> Repo.update()
  end

  def delete_player(%Player{} = player) do
    Repo.delete(player)
  end

  def count_players(game_id) do
    Player
    |> where([p], p.game_id == ^game_id)
    |> Repo.aggregate(:count)
  end

  def list_players(game_id) do
    Player
    |> where([p], p.game_id == ^game_id)
    |> order_by([p], asc: p.inserted_at)
    |> Repo.all()
  end

  def set_guesser(game_id, player_id) do
    # Reset all guessers
    from(p in Player, where: p.game_id == ^game_id)
    |> Repo.update_all(set: [is_guesser: false])

    # Set the new guesser
    from(p in Player, where: p.id == ^player_id)
    |> Repo.update_all(set: [is_guesser: true])
  end

  # Words

  def get_random_word(language \\ "es") do
    Word
    |> where([w], w.language == ^language)
    |> order_by(fragment("RANDOM()"))
    |> limit(1)
    |> Repo.one()
  end

  def get_random_word_excluding(language, exclude_ids) when is_list(exclude_ids) do
    Word
    |> where([w], w.language == ^language and w.id not in ^exclude_ids)
    |> order_by(fragment("RANDOM()"))
    |> limit(1)
    |> Repo.one()
  end

  def create_word(attrs \\ %{}) do
    %Word{}
    |> Word.changeset(attrs)
    |> Repo.insert()
  end

  # Clues

  def create_clue(attrs \\ %{}) do
    %Clue{}
    |> Clue.changeset(attrs)
    |> Repo.insert()
  end

  def list_clues_for_round(game_id, round) do
    Clue
    |> where([c], c.game_id == ^game_id and c.round == ^round)
    |> preload(:player)
    |> Repo.all()
  end

  def mark_duplicate_clues(game_id, round) do
    clues = list_clues_for_round(game_id, round)

    # Group by normalized clue (lowercase, trimmed)
    grouped =
      clues
      |> Enum.group_by(fn c -> String.downcase(String.trim(c.clue)) end)

    # Find duplicates
    duplicate_ids =
      grouped
      |> Enum.filter(fn {_key, group} -> length(group) > 1 end)
      |> Enum.flat_map(fn {_key, group} -> Enum.map(group, & &1.id) end)

    # Mark as duplicates
    from(c in Clue, where: c.id in ^duplicate_ids)
    |> Repo.update_all(set: [is_duplicate: true])

    {:ok, duplicate_ids}
  end

  def all_clues_submitted?(game_id, round, expected_count) do
    submitted =
      Clue
      |> where([c], c.game_id == ^game_id and c.round == ^round)
      |> Repo.aggregate(:count)

    submitted >= expected_count
  end

  # State Persistence

  @doc """
  Save the current game server state to the database.
  The state is serialized to a map that can be stored in the state_snapshot column.
  """
  def save_game_state(game_code, server_state) when is_map(server_state) do
    case get_game_by_code(game_code) do
      nil ->
        {:error, :game_not_found}

      game ->
        snapshot = serialize_state(server_state)

        game
        |> Game.changeset(%{
          state_snapshot: snapshot,
          last_activity_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.update()
    end
  end

  @doc """
  Restore game server state from the database snapshot.
  Returns the deserialized state or nil if no snapshot exists.
  """
  def restore_game_state(game_code) do
    case get_game_by_code(game_code) do
      nil ->
        nil

      %{state_snapshot: nil} ->
        nil

      %{state_snapshot: snapshot} = game ->
        deserialize_state(snapshot, game)
    end
  end

  @doc """
  List all games that have state snapshots and are still active (playing status).
  Used for recovery on application startup.
  """
  def list_recoverable_games do
    Game
    |> where([g], g.status == "playing" and not is_nil(g.state_snapshot))
    |> preload([:players, :current_word, :clues])
    |> Repo.all()
  end

  @doc """
  Clear the state snapshot for a game (e.g., when game finishes).
  """
  def clear_game_state(game_code) do
    case get_game_by_code(game_code) do
      nil ->
        {:error, :game_not_found}

      game ->
        game
        |> Game.changeset(%{state_snapshot: nil})
        |> Repo.update()
    end
  end

  # Serialize GenServer state to a storable map
  defp serialize_state(state) do
    %{
      "phase" => to_string(state.phase),
      "guesser_index" => state.guesser_index,
      "used_word_ids" => state.used_word_ids,
      "current_word_id" => state.current_word && state.current_word.id,
      "clues" => serialize_clues(state.clues),
      "revealed_clues" => state.revealed_clues,
      "last_guess" => state.last_guess,
      "last_result" => state.last_result
    }
  end

  defp serialize_clues(clues) when is_map(clues) do
    clues
    |> Enum.map(fn {player_id, clue_data} ->
      {player_id, %{
        "clue" => clue_data.clue,
        "player_id" => clue_data.player.id
      }}
    end)
    |> Enum.into(%{})
  end

  defp serialize_clues(_), do: %{}

  # Deserialize stored map back to GenServer state
  defp deserialize_state(snapshot, game) do
    players = list_players(game.id)
    current_word = if snapshot["current_word_id"] do
      Repo.get(Word, snapshot["current_word_id"])
    else
      game.current_word
    end

    %{
      game: game,
      phase: String.to_existing_atom(snapshot["phase"]),
      players: players,
      current_word: current_word,
      clues: deserialize_clues(snapshot["clues"], players),
      revealed_clues: snapshot["revealed_clues"] || [],
      used_word_ids: snapshot["used_word_ids"] || [],
      guesser_index: snapshot["guesser_index"] || 0,
      last_guess: snapshot["last_guess"],
      last_result: snapshot["last_result"]
    }
  end

  defp deserialize_clues(clues, players) when is_map(clues) do
    players_by_id = Map.new(players, fn p -> {p.id, p} end)

    clues
    |> Enum.map(fn {player_id, clue_data} ->
      player = Map.get(players_by_id, clue_data["player_id"])
      {player_id, %{clue: clue_data["clue"], player: player}}
    end)
    |> Enum.into(%{})
  end

  defp deserialize_clues(_, _), do: %{}
end
