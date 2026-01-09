# Just One

A real-time multiplayer implementation of the cooperative word game "Just One" built with Elixir, Phoenix LiveView, and Tailwind CSS.

## About the Game

**Just One** is a cooperative party game where players try to help one person guess a mystery word by giving one-word clues. The twist: if two or more players give the same clue, those clues are eliminated before the guesser sees them!

- 3-20 players
- 13 rounds per game
- Score points for correct guesses

## Tech Stack

- **Elixir 1.18+** / **Erlang/OTP 27+**
- **Phoenix 1.8** with LiveView for real-time UI
- **PostgreSQL 16** for persistence
- **Tailwind CSS** for responsive styling
- **Docker** for database

## Quick Start

### Prerequisites

- Elixir 1.18+ installed
- Docker and Docker Compose

### Setup

```bash
# Clone and enter the project
cd justone

# Start PostgreSQL
docker compose up -d

# Install dependencies
mix deps.get

# Setup database (create, migrate, seed)
mix ecto.setup

# Start the server
mix phx.server
```

Open http://localhost:4000 in your browser.

### Running Tests

```bash
# Create test database
MIX_ENV=test mix ecto.create
MIX_ENV=test mix ecto.migrate

# Run tests
mix test
```

### Reset Database

```bash
mix ecto.reset
```

## How to Play

1. **Create a game** from the lobby (set max players 3-20)
2. **Share the game code** with friends
3. **Join** by entering your nickname
4. **Owner starts** the game when 3+ players have joined
5. Each round:
   - One player is the **guesser** (rotates each round)
   - Others see the secret word and write a **one-word clue**
   - **Duplicate clues are removed** automatically
   - Guesser sees remaining clues and **guesses the word**
   - Correct guess = 1 point
6. After 13 rounds, see your final score!

## Project Structure

```
lib/
├── justone/                    # Business logic
│   ├── game.ex                 # Game context (database operations)
│   └── game/
│       ├── game.ex             # Game schema
│       ├── player.ex           # Player schema
│       ├── word.ex             # Word schema
│       ├── clue.ex             # Clue schema
│       ├── server.ex           # GenServer for game state
│       └── supervisor.ex       # DynamicSupervisor helpers
│
├── justone_web/                # Web layer
│   ├── live/
│   │   ├── lobby_live.ex       # Lobby: list/create games
│   │   ├── game_live.ex        # Game room: join/play
│   │   └── live_auth.ex        # Session handling
│   ├── presence.ex             # Phoenix Presence
│   └── router.ex               # Routes

priv/
├── repo/
│   ├── migrations/             # Database migrations
│   └── seeds.exs               # 100 Spanish words

test/
├── justone/
│   ├── game_test.exs           # Context tests
│   └── game/
│       └── server_test.exs     # GenServer tests
```

## Architecture

### Real-time State Management

Each game has its own **GenServer** (`Justone.Game.Server`) that:
- Holds live game state in memory
- Manages game phases (waiting → clue_submission → clue_comparison → guessing → round_result)
- Broadcasts updates via **Phoenix PubSub**
- Persists important data to PostgreSQL

### Game Phases

```
:waiting           → Players joining, owner can start
:clue_submission   → Non-guessers write clues
:clue_comparison   → Review clues, duplicates marked
:guessing          → Guesser sees valid clues, submits guess
:round_result      → Show if correct, owner advances
:finished          → Game over, show final score
```

### Database Schema

```
words       → id, word, language
games       → id, code, status, owner_session_id, max_players, current_round,
              total_rounds, score, current_word_id, state_snapshot, last_activity_at
players     → id, game_id, session_id, nickname, is_guesser
clues       → id, game_id, player_id, round, clue, is_duplicate
```

The `state_snapshot` field stores serialized game state for crash recovery.

## Configuration

### Environment Variables

Default database config in `config/dev.exs`:
```elixir
hostname: "localhost"
username: "postgres"
password: "postgres"
database: "justone_dev"
port: 5432
```

### Game Settings

In `lib/justone/game/game.ex`:
```elixir
@max_players_limit 20      # Hard limit
default max_players: 7     # Default when creating
default total_rounds: 13   # Rounds per game
```

## License

MIT
