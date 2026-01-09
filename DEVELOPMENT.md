# Development Guide

This document explains the codebase architecture and how to continue developing the Just One game.

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Key Files](#key-files)
- [Adding Features](#adding-features)
- [Common Tasks](#common-tasks)
- [Future Improvements](#future-improvements)

---

## Architecture Overview

### Three-Layer Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    LiveView Layer                        │
│  (lobby_live.ex, game_live.ex)                          │
│  - Renders UI                                            │
│  - Handles user events                                   │
│  - Subscribes to PubSub                                  │
└─────────────────────┬───────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────┐
│                   GenServer Layer                        │
│  (game/server.ex)                                        │
│  - Holds live game state                                 │
│  - Manages game logic & phases                           │
│  - Broadcasts state changes                              │
└─────────────────────┬───────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────┐
│                   Context Layer                          │
│  (game.ex)                                               │
│  - Database CRUD operations                              │
│  - Business logic helpers                                │
└─────────────────────┬───────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────┐
│                   Database Layer                         │
│  (Ecto Schemas: game.ex, player.ex, word.ex, clue.ex)   │
└─────────────────────────────────────────────────────────┘
```

### Data Flow

1. **User action** → LiveView receives event
2. **LiveView** → Calls GenServer function
3. **GenServer** → Updates state, calls Context for persistence
4. **GenServer** → Broadcasts change via PubSub
5. **LiveView** → Receives broadcast, updates assigns
6. **LiveView** → Re-renders UI

---

## Key Files

### `lib/justone/game/server.ex` - Game State Machine

The heart of the game logic. Each game has one GenServer process.

```elixir
# State structure
%{
  game: %Game{},           # Database record
  phase: :waiting,         # Current game phase
  players: [...],          # List of players
  current_word: %Word{},   # Word to guess
  clues: %{},              # player_id => %{clue: "", player: %Player{}}
  revealed_clues: [...],   # Processed clues with is_duplicate flag
  used_word_ids: [...],    # Words already used this game
  guesser_index: 0,        # For rotating guesser
  last_guess: nil,         # Last submitted guess
  last_result: nil         # true/false for last guess
}
```

**Key functions:**
- `join/3` - Add player to game
- `start_game/2` - Begin playing (owner only)
- `submit_clue/3` - Submit a clue (non-guesser)
- `reveal_clues/2` - Show clues to guesser (owner)
- `submit_guess/3` - Guess the word (guesser)
- `next_round/2` - Advance to next round (owner)

### `lib/justone/game.ex` - Context Module

Database operations. All Ecto queries go here.

```elixir
# Games
create_game(attrs)
get_game_by_code(code)
update_game(game, attrs)
list_joinable_games()

# Players
create_player(attrs)
get_player_by_session(game_id, session_id)
list_players(game_id)
set_guesser(game_id, player_id)

# Words
get_random_word(language)
get_random_word_excluding(language, exclude_ids)

# Clues
create_clue(attrs)
list_clues_for_round(game_id, round)
mark_duplicate_clues(game_id, round)
```

### `lib/justone_web/live/game_live.ex` - Game UI

The main game interface. Uses function components for each phase:

```elixir
defp join_form(assigns)        # Nickname input
defp game_view(assigns)        # Main game container
defp score_bar(assigns)        # Round/score display
defp waiting_room(assigns)     # Pre-game lobby
defp clue_submission(assigns)  # Write clue phase
defp clue_comparison(assigns)  # Review duplicates
defp guessing_phase(assigns)   # Guesser's turn
defp round_result(assigns)     # Correct/incorrect
defp game_finished(assigns)    # Final score
defp players_list(assigns)     # Player badges
```

---

## Adding Features

### Adding a New Game Phase

1. **Update server.ex state machine:**
```elixir
# Add phase atom to sanitize_state/1
defp sanitize_state(state) do
  %{
    ...
    phase: state.phase,  # :new_phase
    ...
  }
end

# Add transition logic
def handle_call({:new_action, ...}, _from, state) do
  new_state = %{state | phase: :new_phase}
  broadcast(game.code, {:phase_changed, sanitize_state(new_state)})
  {:reply, :ok, new_state, @timeout}
end
```

2. **Add LiveView handler:**
```elixir
# In game_live.ex
def handle_info({:phase_changed, state}, socket) do
  {:noreply, assign(socket, game_state: state)}
end
```

3. **Add UI component:**
```elixir
# In game_live.ex render
<%= case @game_state.phase do %>
  <% :new_phase -> %>
    <.new_phase_component game_state={@game_state} />
  ...
<% end %>

defp new_phase_component(assigns) do
  ~H"""
  <div>...</div>
  """
end
```

### Adding a New Database Field

1. **Create migration:**
```bash
mix ecto.gen.migration add_field_to_games
```

2. **Edit migration:**
```elixir
def change do
  alter table(:games) do
    add :new_field, :string, default: "value"
  end
end
```

3. **Update schema:**
```elixir
# In lib/justone/game/game.ex
schema "games" do
  field :new_field, :string, default: "value"
  ...
end

def changeset(game, attrs) do
  game
  |> cast(attrs, [..., :new_field])
  ...
end
```

4. **Run migration:**
```bash
mix ecto.migrate
```

### Adding Words in a New Language

1. **Edit seeds.exs:**
```elixir
english_words = ["dog", "cat", ...]

for word <- english_words do
  case Repo.get_by(Word, word: word, language: "en") do
    nil ->
      %Word{}
      |> Word.changeset(%{word: word, language: "en"})
      |> Repo.insert!()
    _ -> :ok
  end
end
```

2. **Run seeds:**
```bash
mix run priv/repo/seeds.exs
```

3. **Update game to use language:**
```elixir
# In server.ex start_round/1
word = Game.get_random_word_excluding(game.language, used_word_ids)
```

---

## Common Tasks

### Debug a Game Server

```elixir
# In IEx (iex -S mix phx.server)

# Find game server by code
{:ok, state} = Justone.Game.Server.get_state("ABC123")

# See all running games
Registry.select(Justone.GameRegistry, [{{:"$1", :_, :_}, [], [:"$1"]}])

# Manually broadcast
Phoenix.PubSub.broadcast(Justone.PubSub, "game:ABC123", {:test, "hello"})
```

### Add a New Event Handler

```elixir
# 1. Add client API in server.ex
def new_action(game_id, session_id, data) do
  GenServer.call(via_tuple(game_id), {:new_action, session_id, data})
end

# 2. Add server callback
@impl true
def handle_call({:new_action, session_id, data}, _from, state) do
  # Validate, update state, broadcast
  {:reply, :ok, new_state, @timeout}
end

# 3. Add LiveView event handler
def handle_event("new_action", params, socket) do
  Server.new_action(socket.assigns.game_code, socket.assigns.session_id, params)
  {:noreply, socket}
end

# 4. Add PubSub handler
def handle_info({:new_action_done, state}, socket) do
  {:noreply, assign(socket, game_state: state)}
end
```

### Run Specific Tests

```bash
# Single file
mix test test/justone/game_test.exs

# Single test (by line number)
mix test test/justone/game_test.exs:25

# By tag
mix test --only focus
```

---

## Future Improvements

### High Priority

- [ ] **Player disconnection handling** - Remove inactive players, handle reconnection
- [ ] **Game timeout** - Auto-cleanup abandoned games
- [ ] **Skip/pass option** - Guesser can skip if no good clues
- [ ] **Timer per phase** - Add time limits for clue submission

### Medium Priority

- [ ] **Multiple languages** - Add English, French word lists
- [ ] **Custom word lists** - Let creator upload words
- [ ] **Private games** - Password-protected rooms
- [ ] **Spectator mode** - Watch without playing
- [ ] **Sound effects** - Correct/incorrect sounds

### Low Priority

- [ ] **Game history** - Save past games and scores
- [ ] **Leaderboards** - Track best scores
- [ ] **User accounts** - Optional registration
- [ ] **PWA support** - Installable on mobile
- [ ] **Dark mode** - Theme toggle

### Code Quality

- [ ] Add LiveView tests for game_live.ex
- [ ] Add property-based tests for game logic
- [ ] Add Credo for linting
- [ ] Add Dialyzer for type checking
- [ ] Add CI/CD pipeline

---

## Useful Commands

```bash
# Development
mix phx.server              # Start server
iex -S mix phx.server       # Start with IEx
mix test                    # Run tests
mix test --cover            # Test coverage

# Database
mix ecto.create             # Create DB
mix ecto.migrate            # Run migrations
mix ecto.rollback           # Undo last migration
mix ecto.reset              # Drop + create + migrate + seed
mix ecto.gen.migration NAME # New migration

# Dependencies
mix deps.get                # Install deps
mix deps.update --all       # Update all deps

# Code quality
mix format                  # Format code
mix compile --warnings-as-errors
```

---

## Resources

- [Phoenix LiveView Docs](https://hexdocs.pm/phoenix_live_view)
- [Ecto Docs](https://hexdocs.pm/ecto)
- [GenServer Docs](https://hexdocs.pm/elixir/GenServer.html)
- [Phoenix PubSub](https://hexdocs.pm/phoenix_pubsub)
- [Tailwind CSS](https://tailwindcss.com/docs)
