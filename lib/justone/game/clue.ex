defmodule Justone.Game.Clue do
  @moduledoc """
  Schema for clues submitted by players.

  In Just One, non-guesser players each submit a one-word clue to help the
  guesser identify the secret word. If two or more players submit the same
  clue (case-insensitive), those clues are marked as duplicates and hidden
  from the guesser.

  ## Fields

  - `clue` - The one-word hint submitted by the player (1-50 characters)
  - `round` - Which round this clue was submitted for
  - `is_duplicate` - Whether another player submitted the same clue

  ## Associations

  - `game` - The game this clue belongs to
  - `player` - The player who submitted this clue

  ## Constraints

  Each player can only submit one clue per round (unique on game_id + round + player_id).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "clues" do
    field :clue, :string
    field :round, :integer
    field :is_duplicate, :boolean, default: false

    belongs_to :game, Justone.Game.Game
    belongs_to :player, Justone.Game.Player

    timestamps()
  end

  def changeset(clue, attrs) do
    clue
    |> cast(attrs, [:clue, :round, :is_duplicate, :game_id, :player_id])
    |> validate_required([:clue, :round, :game_id, :player_id])
    |> validate_length(:clue, min: 1, max: 50)
    |> unique_constraint([:game_id, :round, :player_id])
  end
end
