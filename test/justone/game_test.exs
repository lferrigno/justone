defmodule Justone.GameTest do
  use Justone.DataCase, async: true

  alias Justone.Game

  describe "games" do
    test "create_game/1 creates a game with a unique code" do
      {:ok, game} = Game.create_game(%{"owner_session_id" => "session-123", "max_players" => 5})

      assert game.code != nil
      assert String.length(game.code) == 6
      assert game.owner_session_id == "session-123"
      assert game.max_players == 5
      assert game.status == "waiting"
    end

    test "create_game/1 generates different codes for each game" do
      {:ok, game1} = Game.create_game(%{"owner_session_id" => "session-1"})
      {:ok, game2} = Game.create_game(%{"owner_session_id" => "session-2"})

      assert game1.code != game2.code
    end

    test "get_game_by_code/1 returns the game" do
      {:ok, game} = Game.create_game(%{"owner_session_id" => "session-123"})
      fetched = Game.get_game_by_code(game.code)

      assert fetched.id == game.id
    end

    test "list_joinable_games/0 only returns waiting games" do
      {:ok, waiting_game} = Game.create_game(%{"owner_session_id" => "session-1"})
      {:ok, playing_game} = Game.create_game(%{"owner_session_id" => "session-2"})
      Game.update_game(playing_game, %{status: "playing"})

      games = Game.list_joinable_games()
      game_ids = Enum.map(games, & &1.id)

      assert waiting_game.id in game_ids
      refute playing_game.id in game_ids
    end

    test "update_game/2 updates game attributes" do
      {:ok, game} = Game.create_game(%{"owner_session_id" => "session-123"})
      {:ok, updated} = Game.update_game(game, %{status: "playing", current_round: 1})

      assert updated.status == "playing"
      assert updated.current_round == 1
    end
  end

  describe "players" do
    setup do
      {:ok, game} = Game.create_game(%{"owner_session_id" => "owner-session"})
      %{game: game}
    end

    test "create_player/1 adds a player to the game", %{game: game} do
      {:ok, player} =
        Game.create_player(%{
          game_id: game.id,
          session_id: "player-session",
          nickname: "TestPlayer"
        })

      assert player.nickname == "TestPlayer"
      assert player.session_id == "player-session"
      assert player.game_id == game.id
    end

    test "get_player_by_session/2 finds the player", %{game: game} do
      {:ok, _player} =
        Game.create_player(%{
          game_id: game.id,
          session_id: "player-session",
          nickname: "TestPlayer"
        })

      found = Game.get_player_by_session(game.id, "player-session")
      assert found.nickname == "TestPlayer"
    end

    test "list_players/1 returns all players in a game", %{game: game} do
      {:ok, _p1} =
        Game.create_player(%{game_id: game.id, session_id: "s1", nickname: "Player1"})

      {:ok, _p2} =
        Game.create_player(%{game_id: game.id, session_id: "s2", nickname: "Player2"})

      players = Game.list_players(game.id)
      assert length(players) == 2
    end

    test "count_players/1 returns correct count", %{game: game} do
      assert Game.count_players(game.id) == 0

      {:ok, _} = Game.create_player(%{game_id: game.id, session_id: "s1", nickname: "P1"})
      assert Game.count_players(game.id) == 1

      {:ok, _} = Game.create_player(%{game_id: game.id, session_id: "s2", nickname: "P2"})
      assert Game.count_players(game.id) == 2
    end

    test "set_guesser/2 marks the correct player as guesser", %{game: game} do
      {:ok, p1} = Game.create_player(%{game_id: game.id, session_id: "s1", nickname: "P1"})
      {:ok, _p2} = Game.create_player(%{game_id: game.id, session_id: "s2", nickname: "P2"})

      Game.set_guesser(game.id, p1.id)

      players = Game.list_players(game.id)
      guesser = Enum.find(players, & &1.is_guesser)

      assert guesser.id == p1.id
    end

    test "player cannot join same game twice with same session", %{game: game} do
      {:ok, _} = Game.create_player(%{game_id: game.id, session_id: "s1", nickname: "P1"})

      assert {:error, _changeset} =
               Game.create_player(%{game_id: game.id, session_id: "s1", nickname: "P1Again"})
    end
  end

  describe "words" do
    test "get_random_word/1 returns a word" do
      # Seed a word first
      {:ok, _word} = Game.create_word(%{word: "prueba", language: "es"})

      word = Game.get_random_word("es")
      assert word != nil
      assert word.language == "es"
    end

    test "get_random_word_excluding/2 excludes specified words" do
      {:ok, w1} = Game.create_word(%{word: "excluida", language: "es"})
      {:ok, _w2} = Game.create_word(%{word: "incluida", language: "es"})

      word = Game.get_random_word_excluding("es", [w1.id])

      # If we get a word, it should not be the excluded one
      if word do
        assert word.id != w1.id
      end
    end
  end

  describe "clues" do
    setup do
      {:ok, game} = Game.create_game(%{"owner_session_id" => "owner"})
      {:ok, player} = Game.create_player(%{game_id: game.id, session_id: "p1", nickname: "P1"})
      %{game: game, player: player}
    end

    test "create_clue/1 creates a clue", %{game: game, player: player} do
      {:ok, clue} =
        Game.create_clue(%{
          game_id: game.id,
          player_id: player.id,
          clue: "pista",
          round: 1
        })

      assert clue.clue == "pista"
      assert clue.round == 1
    end

    test "list_clues_for_round/2 returns clues for specific round", %{game: game, player: player} do
      {:ok, _c1} =
        Game.create_clue(%{game_id: game.id, player_id: player.id, clue: "round1", round: 1})

      {:ok, p2} = Game.create_player(%{game_id: game.id, session_id: "p2", nickname: "P2"})

      {:ok, _c2} =
        Game.create_clue(%{game_id: game.id, player_id: p2.id, clue: "round2", round: 2})

      round1_clues = Game.list_clues_for_round(game.id, 1)
      assert length(round1_clues) == 1
      assert hd(round1_clues).clue == "round1"
    end

    test "mark_duplicate_clues/2 identifies duplicates", %{game: game} do
      {:ok, p1} = Game.create_player(%{game_id: game.id, session_id: "pa", nickname: "PA"})
      {:ok, p2} = Game.create_player(%{game_id: game.id, session_id: "pb", nickname: "PB"})
      {:ok, p3} = Game.create_player(%{game_id: game.id, session_id: "pc", nickname: "PC"})

      {:ok, _} = Game.create_clue(%{game_id: game.id, player_id: p1.id, clue: "mismo", round: 1})
      {:ok, _} = Game.create_clue(%{game_id: game.id, player_id: p2.id, clue: "MISMO", round: 1})
      {:ok, _} = Game.create_clue(%{game_id: game.id, player_id: p3.id, clue: "diferente", round: 1})

      {:ok, duplicate_ids} = Game.mark_duplicate_clues(game.id, 1)

      assert length(duplicate_ids) == 2

      clues = Game.list_clues_for_round(game.id, 1)
      duplicates = Enum.filter(clues, & &1.is_duplicate)

      assert length(duplicates) == 2
      assert Enum.all?(duplicates, fn c -> String.downcase(c.clue) == "mismo" end)
    end
  end

  describe "state persistence" do
    setup do
      {:ok, game} = Game.create_game(%{"owner_session_id" => "owner"})
      {:ok, word} = Game.create_word(%{word: "prueba_persist", language: "es"})
      {:ok, p1} = Game.create_player(%{game_id: game.id, session_id: "s1", nickname: "P1"})
      {:ok, p2} = Game.create_player(%{game_id: game.id, session_id: "s2", nickname: "P2"})
      %{game: game, word: word, players: [p1, p2]}
    end

    test "save_game_state/2 saves state to database", %{game: game, word: word, players: [p1, _p2]} do
      state = %{
        game: game,
        phase: :clue_submission,
        players: [p1],
        current_word: word,
        clues: %{p1.id => %{clue: "test", player: p1}},
        revealed_clues: [],
        used_word_ids: [word.id],
        guesser_index: 1,
        last_guess: nil,
        last_result: nil
      }

      assert {:ok, updated_game} = Game.save_game_state(game.code, state)
      assert updated_game.state_snapshot != nil
      assert updated_game.last_activity_at != nil
    end

    test "restore_game_state/1 restores saved state", %{game: game, word: word, players: [p1, p2]} do
      state = %{
        game: game,
        phase: :guessing,
        players: [p1, p2],
        current_word: word,
        clues: %{p1.id => %{clue: "testclue", player: p1}},
        revealed_clues: [%{"player_id" => p1.id, "clue" => "testclue", "is_duplicate" => false}],
        used_word_ids: [word.id],
        guesser_index: 2,
        last_guess: "myguess",
        last_result: true
      }

      {:ok, _} = Game.save_game_state(game.code, state)

      restored = Game.restore_game_state(game.code)

      assert restored != nil
      assert restored.phase == :guessing
      assert restored.guesser_index == 2
      assert restored.last_guess == "myguess"
      assert restored.last_result == true
      assert restored.current_word.id == word.id
      assert length(restored.used_word_ids) == 1
    end

    test "restore_game_state/1 returns nil for game without snapshot", %{game: game} do
      assert Game.restore_game_state(game.code) == nil
    end

    test "restore_game_state/1 returns nil for non-existent game" do
      assert Game.restore_game_state("NOEXIST") == nil
    end

    test "clear_game_state/1 removes the snapshot", %{game: game, word: word, players: [p1, _p2]} do
      state = %{
        game: game,
        phase: :clue_submission,
        players: [p1],
        current_word: word,
        clues: %{},
        revealed_clues: [],
        used_word_ids: [],
        guesser_index: 0,
        last_guess: nil,
        last_result: nil
      }

      {:ok, _} = Game.save_game_state(game.code, state)
      {:ok, cleared} = Game.clear_game_state(game.code)

      assert cleared.state_snapshot == nil
      assert Game.restore_game_state(game.code) == nil
    end

    test "list_recoverable_games/0 returns playing games with snapshots", %{game: game, word: word, players: [p1, _p2]} do
      state = %{
        game: game,
        phase: :clue_submission,
        players: [p1],
        current_word: word,
        clues: %{},
        revealed_clues: [],
        used_word_ids: [],
        guesser_index: 0,
        last_guess: nil,
        last_result: nil
      }

      # Game is still in waiting status, shouldn't be recoverable
      {:ok, _} = Game.save_game_state(game.code, state)
      recoverable = Game.list_recoverable_games()
      refute Enum.any?(recoverable, &(&1.id == game.id))

      # Update to playing status
      {:ok, _updated_game} = Game.update_game(game, %{status: "playing"})

      recoverable = Game.list_recoverable_games()
      assert Enum.any?(recoverable, &(&1.id == game.id))
    end
  end
end
