defmodule Justone.Game.ServerTest do
  use Justone.DataCase, async: false

  alias Justone.Game
  alias Justone.Game.Server
  alias Justone.Game.ServerSupervisor

  setup do
    # Seed some words for the tests
    for word <- ["perro", "gato", "casa", "árbol", "sol"] do
      Game.create_word(%{word: word, language: "es"})
    end

    {:ok, game} = Game.create_game(%{"owner_session_id" => "owner-session", "max_players" => 7})
    {:ok, _pid} = ServerSupervisor.start_game_server(game.code)

    on_exit(fn ->
      ServerSupervisor.stop_game_server(game.code)
    end)

    %{game: game, owner_session: "owner-session"}
  end

  describe "joining games" do
    test "players can join a waiting game", %{game: game} do
      assert {:ok, player} = Server.join(game.code, "player-1", "Alice")
      assert player.nickname == "Alice"
    end

    test "same player cannot join twice", %{game: game} do
      {:ok, _} = Server.join(game.code, "player-1", "Alice")
      assert {:ok, :already_joined} = Server.join(game.code, "player-1", "Alice Again")
    end

    test "game state reflects joined players", %{game: game} do
      {:ok, _} = Server.join(game.code, "player-1", "Alice")
      {:ok, _} = Server.join(game.code, "player-2", "Bob")

      {:ok, state} = Server.get_state(game.code)
      assert length(state.players) == 2
      nicknames = Enum.map(state.players, & &1.nickname)
      assert "Alice" in nicknames
      assert "Bob" in nicknames
    end

    test "cannot join a full game", %{game: _game} do
      # Create a game with max 3 players
      {:ok, small_game} =
        Game.create_game(%{"owner_session_id" => "owner2", "max_players" => 3})

      {:ok, _} = ServerSupervisor.start_game_server(small_game.code)

      {:ok, _} = Server.join(small_game.code, "p1", "P1")
      {:ok, _} = Server.join(small_game.code, "p2", "P2")
      {:ok, _} = Server.join(small_game.code, "p3", "P3")

      assert {:error, :game_full} = Server.join(small_game.code, "p4", "P4")

      ServerSupervisor.stop_game_server(small_game.code)
    end
  end

  describe "starting games" do
    test "owner can start game with enough players", %{game: game, owner_session: owner} do
      {:ok, _} = Server.join(game.code, "p1", "Alice")
      {:ok, _} = Server.join(game.code, "p2", "Bob")
      {:ok, _} = Server.join(game.code, "p3", "Charlie")

      assert :ok = Server.start_game(game.code, owner)

      {:ok, state} = Server.get_state(game.code)
      assert state.status == "playing"
      assert state.phase == :clue_submission
      assert state.current_round == 1
    end

    test "non-owner cannot start game", %{game: game} do
      {:ok, _} = Server.join(game.code, "p1", "Alice")
      {:ok, _} = Server.join(game.code, "p2", "Bob")
      {:ok, _} = Server.join(game.code, "p3", "Charlie")

      assert {:error, :not_owner} = Server.start_game(game.code, "p1")
    end

    test "cannot start game with less than 3 players", %{game: game, owner_session: owner} do
      {:ok, _} = Server.join(game.code, "p1", "Alice")
      {:ok, _} = Server.join(game.code, "p2", "Bob")

      assert {:error, :not_enough_players} = Server.start_game(game.code, owner)
    end

    test "game assigns a guesser when started", %{game: game, owner_session: owner} do
      {:ok, _} = Server.join(game.code, "p1", "Alice")
      {:ok, _} = Server.join(game.code, "p2", "Bob")
      {:ok, _} = Server.join(game.code, "p3", "Charlie")

      :ok = Server.start_game(game.code, owner)

      {:ok, state} = Server.get_state(game.code)
      assert state.guesser_id != nil
      guesser = Enum.find(state.players, & &1.is_guesser)
      assert guesser != nil
    end

    test "game has a current word when started", %{game: game, owner_session: owner} do
      {:ok, _} = Server.join(game.code, "p1", "Alice")
      {:ok, _} = Server.join(game.code, "p2", "Bob")
      {:ok, _} = Server.join(game.code, "p3", "Charlie")

      :ok = Server.start_game(game.code, owner)

      {:ok, state} = Server.get_state(game.code)
      assert state.current_word != nil
    end
  end

  describe "clue submission" do
    setup %{game: game, owner_session: owner} do
      {:ok, _} = Server.join(game.code, "p1", "Alice")
      {:ok, _} = Server.join(game.code, "p2", "Bob")
      {:ok, _} = Server.join(game.code, "p3", "Charlie")
      :ok = Server.start_game(game.code, owner)

      {:ok, state} = Server.get_state(game.code)
      guesser = Enum.find(state.players, & &1.is_guesser)
      non_guessers = Enum.reject(state.players, & &1.is_guesser)

      %{guesser: guesser, non_guessers: non_guessers}
    end

    test "non-guesser can submit a clue", %{game: game, non_guessers: [player | _]} do
      assert :ok = Server.submit_clue(game.code, player.session_id, "pista")

      {:ok, state} = Server.get_state(game.code)
      assert player.id in state.clues_submitted
    end

    test "guesser cannot submit a clue", %{game: game, guesser: guesser} do
      assert {:error, :guesser_cannot_submit} =
               Server.submit_clue(game.code, guesser.session_id, "pista")
    end

    test "cannot submit clue twice", %{game: game, non_guessers: [player | _]} do
      :ok = Server.submit_clue(game.code, player.session_id, "pista1")

      assert {:error, :already_submitted} =
               Server.submit_clue(game.code, player.session_id, "pista2")
    end

    test "phase changes to clue_comparison when all submit", %{game: game, non_guessers: players} do
      for player <- players do
        Server.submit_clue(game.code, player.session_id, "pista_#{player.nickname}")
      end

      {:ok, state} = Server.get_state(game.code)
      assert state.phase == :clue_comparison
    end
  end

  describe "guessing" do
    setup %{game: game, owner_session: owner} do
      {:ok, _} = Server.join(game.code, "p1", "Alice")
      {:ok, _} = Server.join(game.code, "p2", "Bob")
      {:ok, _} = Server.join(game.code, "p3", "Charlie")
      :ok = Server.start_game(game.code, owner)

      {:ok, state} = Server.get_state(game.code)
      guesser = Enum.find(state.players, & &1.is_guesser)
      non_guessers = Enum.reject(state.players, & &1.is_guesser)

      # Submit all clues
      for player <- non_guessers do
        Server.submit_clue(game.code, player.session_id, "pista")
      end

      # Reveal clues
      Server.reveal_clues(game.code, owner)

      %{guesser: guesser, non_guessers: non_guessers}
    end

    test "guesser can submit a guess", %{game: game, guesser: guesser} do
      {:ok, state} = Server.get_state(game.code)
      word = state.current_word

      assert {:ok, true} = Server.submit_guess(game.code, guesser.session_id, word)
    end

    test "correct guess increments score", %{game: game, guesser: guesser} do
      {:ok, state} = Server.get_state(game.code)
      word = state.current_word
      initial_score = state.score

      {:ok, true} = Server.submit_guess(game.code, guesser.session_id, word)

      {:ok, new_state} = Server.get_state(game.code)
      assert new_state.score == initial_score + 1
    end

    test "incorrect guess does not increment score", %{game: game, guesser: guesser} do
      {:ok, state} = Server.get_state(game.code)
      initial_score = state.score

      {:ok, false} = Server.submit_guess(game.code, guesser.session_id, "wronganswer")

      {:ok, new_state} = Server.get_state(game.code)
      assert new_state.score == initial_score
    end

    test "non-guesser cannot guess", %{game: game, non_guessers: [player | _]} do
      assert {:error, :not_guesser} = Server.submit_guess(game.code, player.session_id, "guess")
    end

    test "phase changes to round_result after guess", %{game: game, guesser: guesser} do
      Server.submit_guess(game.code, guesser.session_id, "anyguess")

      {:ok, state} = Server.get_state(game.code)
      assert state.phase == :round_result
    end
  end

  describe "next round" do
    setup %{game: game, owner_session: owner} do
      {:ok, _} = Server.join(game.code, "p1", "Alice")
      {:ok, _} = Server.join(game.code, "p2", "Bob")
      {:ok, _} = Server.join(game.code, "p3", "Charlie")
      :ok = Server.start_game(game.code, owner)

      {:ok, state} = Server.get_state(game.code)
      guesser = Enum.find(state.players, & &1.is_guesser)
      non_guessers = Enum.reject(state.players, & &1.is_guesser)

      # Complete a round
      for player <- non_guessers do
        Server.submit_clue(game.code, player.session_id, "pista")
      end

      Server.reveal_clues(game.code, owner)
      Server.submit_guess(game.code, guesser.session_id, "guess")

      %{guesser: guesser}
    end

    test "owner can advance to next round", %{game: game, owner_session: owner} do
      {:ok, state_before} = Server.get_state(game.code)
      round_before = state_before.current_round

      :ok = Server.next_round(game.code, owner)

      {:ok, state_after} = Server.get_state(game.code)
      assert state_after.current_round == round_before + 1
      assert state_after.phase == :clue_submission
    end

    test "non-owner cannot advance round", %{game: game} do
      assert {:error, :not_owner} = Server.next_round(game.code, "p1")
    end

    test "guesser rotates each round", %{game: game, owner_session: owner, guesser: first_guesser} do
      :ok = Server.next_round(game.code, owner)

      {:ok, state} = Server.get_state(game.code)
      new_guesser = Enum.find(state.players, & &1.is_guesser)

      # Guesser should have changed (in a 3 player game)
      assert new_guesser.id != first_guesser.id
    end
  end
end
