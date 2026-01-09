# Claude Code Guidelines

This file contains project conventions and decisions for AI-assisted development.

## Documentation Requirements

When modifying the codebase, keep these in sync:

1. **Schema changes** (`lib/justone/game/*.ex`)
   - Update the `@moduledoc` in the schema file
   - Update `README.md` Database Schema section
   - Create a migration for any new fields

2. **Game phases or state changes** (`lib/justone/game/server.ex`)
   - Update `DEVELOPMENT.md` state structure section
   - Update `README.md` Game Phases section if adding new phases

3. **New context functions** (`lib/justone/game.ex`)
   - Add `@doc` with description
   - Update `DEVELOPMENT.md` if it's a key function

## Architecture Decisions

### State Management
- Each game has one GenServer process (`Justone.Game.Server`)
- State is persisted to PostgreSQL every 30 seconds during gameplay
- On crash/restart, active games are recovered from `state_snapshot` column
- Recovery module (`Justone.Game.Recovery`) runs on application startup

### Authentication
- No user accounts - players identified by browser session ID only
- Session ID stored in Phoenix session, passed to LiveView as `session_id`
- Nickname required to join a game (1-20 characters)

### Game Flow
- Owner (creator) controls game: start, reveal clues, next round
- Guesser rotates each round
- Duplicate clues detected case-insensitively and hidden from guesser

## Coding Conventions

### Forms and Inputs
- Use `<form phx-submit="...">` instead of `phx-change` for reliable input capture
- Always include `name` attribute on form inputs

### Testing
- Run `mix test` before committing
- Add tests for new context functions in `test/justone/game_test.exs`
- Add tests for new server functionality in `test/justone/game/server_test.exs`

### Database
- All tables use `binary_id` (UUID) as primary key
- Timestamps are `utc_datetime`
- Run `mix ecto.migrate` after creating migrations

## File Locations

| Purpose | File |
|---------|------|
| Game state machine | `lib/justone/game/server.ex` |
| Database operations | `lib/justone/game.ex` |
| Game UI | `lib/justone_web/live/game_live.ex` |
| Lobby UI | `lib/justone_web/live/lobby_live.ex` |
| Ecto schemas | `lib/justone/game/*.ex` |
| Tests | `test/justone/` |
| Word seeds | `priv/repo/seeds.exs` |
