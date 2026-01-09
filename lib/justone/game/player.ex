defmodule Justone.Game.Player do
  @moduledoc """
  Schema for a player in a Just One game.

  Players are identified by a browser session ID (no authentication required).
  Each player can only join a game once per session.

  ## Fields

  - `session_id` - Browser session identifier (used to recognize returning players)
  - `nickname` - Display name chosen by the player (1-20 characters)
  - `is_guesser` - Whether this player is the guesser for the current round

  ## Associations

  - `game` - The game this player belongs to
  - `clues` - Clues submitted by this player across all rounds
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "players" do
    field :session_id, :string
    field :nickname, :string
    field :is_guesser, :boolean, default: false

    belongs_to :game, Justone.Game.Game
    has_many :clues, Justone.Game.Clue

    timestamps()
  end

  def changeset(player, attrs) do
    player
    |> cast(attrs, [:session_id, :nickname, :is_guesser, :game_id])
    |> validate_required([:session_id, :nickname, :game_id])
    |> validate_length(:nickname, min: 1, max: 20)
    |> unique_constraint([:game_id, :session_id])
  end
end
