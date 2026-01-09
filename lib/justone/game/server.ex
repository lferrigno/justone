defmodule Justone.Game.Server do
  @moduledoc """
  GenServer that manages game state for a single game.
  """
  use GenServer

  alias Justone.Game
  alias Phoenix.PubSub

  @timeout :timer.hours(2)
  @persist_interval :timer.seconds(30)

  # Client API

  def start_link(game_id) do
    GenServer.start_link(__MODULE__, game_id, name: via_tuple(game_id))
  end

  def via_tuple(game_id) do
    {:via, Registry, {Justone.GameRegistry, game_id}}
  end

  def get_state(game_id) do
    GenServer.call(via_tuple(game_id), :get_state)
  end

  def join(game_id, session_id, nickname) do
    GenServer.call(via_tuple(game_id), {:join, session_id, nickname})
  end

  def leave(game_id, session_id) do
    GenServer.call(via_tuple(game_id), {:leave, session_id})
  end

  def start_game(game_id, session_id) do
    GenServer.call(via_tuple(game_id), {:start_game, session_id})
  end

  def submit_clue(game_id, session_id, clue) do
    GenServer.call(via_tuple(game_id), {:submit_clue, session_id, clue})
  end

  def reveal_clues(game_id, session_id) do
    GenServer.call(via_tuple(game_id), {:reveal_clues, session_id})
  end

  def submit_guess(game_id, session_id, guess) do
    GenServer.call(via_tuple(game_id), {:submit_guess, session_id, guess})
  end

  def next_round(game_id, session_id) do
    GenServer.call(via_tuple(game_id), {:next_round, session_id})
  end

  # Server callbacks

  @impl true
  def init(game_id) do
    game = Game.get_game_by_code(game_id)

    if game do
      # Try to restore from saved state, otherwise create fresh state
      state = case Game.restore_game_state(game_id) do
        nil ->
          %{
            game: game,
            phase: :waiting,
            players: Game.list_players(game.id),
            current_word: nil,
            clues: %{},
            revealed_clues: [],
            used_word_ids: [],
            guesser_index: 0,
            last_guess: nil,
            last_result: nil
          }

        restored_state ->
          restored_state
      end

      # Schedule periodic state persistence
      schedule_persist()

      {:ok, state, @timeout}
    else
      {:stop, :game_not_found}
    end
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, sanitize_state(state)}, state, @timeout}
  end

  @impl true
  def handle_call({:join, session_id, nickname}, _from, state) do
    %{game: game, players: players} = state

    cond do
      game.status != "waiting" ->
        {:reply, {:error, :game_already_started}, state, @timeout}

      length(players) >= game.max_players ->
        {:reply, {:error, :game_full}, state, @timeout}

      Enum.any?(players, &(&1.session_id == session_id)) ->
        {:reply, {:ok, :already_joined}, state, @timeout}

      true ->
        case Game.create_player(%{
               game_id: game.id,
               session_id: session_id,
               nickname: nickname
             }) do
          {:ok, player} ->
            new_players = players ++ [player]
            new_state = %{state | players: new_players}
            broadcast(game.code, {:player_joined, player})
            {:reply, {:ok, player}, new_state, @timeout}

          {:error, changeset} ->
            {:reply, {:error, changeset}, state, @timeout}
        end
    end
  end

  @impl true
  def handle_call({:leave, session_id}, _from, state) do
    %{game: game, players: players} = state

    case Enum.find(players, &(&1.session_id == session_id)) do
      nil ->
        {:reply, {:error, :not_in_game}, state, @timeout}

      player ->
        Game.delete_player(player)
        new_players = Enum.reject(players, &(&1.id == player.id))
        new_state = %{state | players: new_players}
        broadcast(game.code, {:player_left, player})
        {:reply, :ok, new_state, @timeout}
    end
  end

  @impl true
  def handle_call({:start_game, session_id}, _from, state) do
    %{game: game, players: players} = state

    cond do
      game.owner_session_id != session_id ->
        {:reply, {:error, :not_owner}, state, @timeout}

      length(players) < 3 ->
        {:reply, {:error, :not_enough_players}, state, @timeout}

      game.status != "waiting" ->
        {:reply, {:error, :game_already_started}, state, @timeout}

      true ->
        {:ok, updated_game} = Game.update_game(game, %{status: "playing", current_round: 1})
        new_state = start_round(%{state | game: updated_game})
        broadcast(game.code, {:game_started, sanitize_state(new_state)})
        {:reply, :ok, new_state, @timeout}
    end
  end

  @impl true
  def handle_call({:submit_clue, session_id, clue}, _from, state) do
    %{game: game, players: players, phase: phase, clues: clues} = state

    player = Enum.find(players, &(&1.session_id == session_id))
    guesser = get_current_guesser(state)

    cond do
      phase != :clue_submission ->
        {:reply, {:error, :wrong_phase}, state, @timeout}

      player == nil ->
        {:reply, {:error, :not_in_game}, state, @timeout}

      player.id == guesser.id ->
        {:reply, {:error, :guesser_cannot_submit}, state, @timeout}

      Map.has_key?(clues, player.id) ->
        {:reply, {:error, :already_submitted}, state, @timeout}

      true ->
        new_clues = Map.put(clues, player.id, %{clue: clue, player: player})
        new_state = %{state | clues: new_clues}

        broadcast(game.code, {:clue_submitted, player.id})

        # Check if all non-guessers have submitted
        expected_count = length(players) - 1

        if map_size(new_clues) >= expected_count do
          new_state = process_clues(new_state)
          broadcast(game.code, {:all_clues_submitted, sanitize_state(new_state)})
          {:reply, :ok, new_state, @timeout}
        else
          {:reply, :ok, new_state, @timeout}
        end
    end
  end

  @impl true
  def handle_call({:reveal_clues, session_id}, _from, state) do
    %{game: game, phase: phase} = state

    cond do
      game.owner_session_id != session_id ->
        {:reply, {:error, :not_owner}, state, @timeout}

      phase != :clue_comparison ->
        {:reply, {:error, :wrong_phase}, state, @timeout}

      true ->
        new_state = %{state | phase: :guessing}
        broadcast(game.code, {:clues_revealed, sanitize_state(new_state)})
        {:reply, :ok, new_state, @timeout}
    end
  end

  @impl true
  def handle_call({:submit_guess, session_id, guess}, _from, state) do
    %{game: game, phase: phase, current_word: word} = state
    guesser = get_current_guesser(state)

    cond do
      phase != :guessing ->
        {:reply, {:error, :wrong_phase}, state, @timeout}

      guesser.session_id != session_id ->
        {:reply, {:error, :not_guesser}, state, @timeout}

      true ->
        correct = String.downcase(String.trim(guess)) == String.downcase(word.word)

        new_score =
          if correct do
            game.score + 1
          else
            game.score
          end

        {:ok, updated_game} = Game.update_game(game, %{score: new_score})

        new_state = %{
          state
          | game: updated_game,
            phase: :round_result,
            last_guess: guess,
            last_result: correct
        }

        broadcast(game.code, {:guess_submitted, guess, correct, sanitize_state(new_state)})
        {:reply, {:ok, correct}, new_state, @timeout}
    end
  end

  @impl true
  def handle_call({:next_round, session_id}, _from, state) do
    %{game: game, phase: phase} = state

    cond do
      game.owner_session_id != session_id ->
        {:reply, {:error, :not_owner}, state, @timeout}

      phase != :round_result ->
        {:reply, {:error, :wrong_phase}, state, @timeout}

      game.current_round >= game.total_rounds ->
        {:ok, updated_game} = Game.update_game(game, %{status: "finished"})
        new_state = %{state | game: updated_game, phase: :finished}
        # Clear persisted state since game is finished
        Game.clear_game_state(game.code)
        broadcast(game.code, {:game_finished, sanitize_state(new_state)})
        {:reply, {:ok, :game_finished}, new_state, @timeout}

      true ->
        {:ok, updated_game} =
          Game.update_game(game, %{current_round: game.current_round + 1})

        new_state = start_round(%{state | game: updated_game})
        broadcast(game.code, {:next_round, sanitize_state(new_state)})
        {:reply, :ok, new_state, @timeout}
    end
  end

  @impl true
  def handle_info(:timeout, state) do
    # Clear state before stopping
    Game.clear_game_state(state.game.code)
    {:stop, :normal, state}
  end

  @impl true
  def handle_info(:persist_state, state) do
    # Only persist if game is in progress
    if state.phase != :waiting and state.phase != :finished do
      Game.save_game_state(state.game.code, state)
    end

    # Schedule next persistence
    schedule_persist()

    {:noreply, state, @timeout}
  end

  # Private functions

  defp schedule_persist do
    Process.send_after(self(), :persist_state, @persist_interval)
  end

  defp start_round(state) do
    %{game: game, players: players, guesser_index: guesser_index, used_word_ids: used_word_ids} =
      state

    # Rotate guesser
    new_guesser_index = rem(guesser_index, length(players))
    guesser = Enum.at(players, new_guesser_index)

    # Set guesser in database
    Game.set_guesser(game.id, guesser.id)

    # Update players with guesser status
    updated_players =
      Enum.map(players, fn p ->
        %{p | is_guesser: p.id == guesser.id}
      end)

    # Get a new word
    word = Game.get_random_word_excluding("es", used_word_ids)

    %{
      state
      | phase: :clue_submission,
        players: updated_players,
        current_word: word,
        clues: %{},
        revealed_clues: [],
        guesser_index: new_guesser_index + 1,
        used_word_ids: [word.id | used_word_ids],
        last_guess: nil,
        last_result: nil
    }
  end

  defp process_clues(state) do
    %{clues: clues} = state

    # Group clues by normalized version
    grouped =
      clues
      |> Enum.group_by(fn {_player_id, %{clue: clue}} ->
        String.downcase(String.trim(clue))
      end)

    # Mark duplicates
    revealed =
      clues
      |> Enum.map(fn {player_id, %{clue: clue, player: player}} ->
        normalized = String.downcase(String.trim(clue))
        is_duplicate = length(Map.get(grouped, normalized, [])) > 1

        %{
          player_id: player_id,
          player_nickname: player.nickname,
          clue: clue,
          is_duplicate: is_duplicate
        }
      end)

    %{state | phase: :clue_comparison, revealed_clues: revealed}
  end

  defp get_current_guesser(state) do
    Enum.find(state.players, & &1.is_guesser)
  end

  defp sanitize_state(state) do
    guesser = get_current_guesser(state)

    %{
      game_code: state.game.code,
      status: state.game.status,
      phase: state.phase,
      current_round: state.game.current_round,
      total_rounds: state.game.total_rounds,
      score: state.game.score,
      max_players: state.game.max_players,
      owner_session_id: state.game.owner_session_id,
      players:
        Enum.map(state.players, fn p ->
          %{id: p.id, nickname: p.nickname, is_guesser: p.is_guesser, session_id: p.session_id}
        end),
      guesser_id: guesser && guesser.id,
      current_word: state.current_word && state.current_word.word,
      clues_submitted: Map.keys(state.clues),
      revealed_clues: state.revealed_clues,
      last_guess: state.last_guess,
      last_result: state.last_result
    }
  end

  defp broadcast(game_code, message) do
    PubSub.broadcast(Justone.PubSub, "game:#{game_code}", message)
  end
end
