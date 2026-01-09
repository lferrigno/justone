defmodule Justone.Game.Game do
  @moduledoc """
  Schema for a Just One game session.

  ## Fields

  - `code` - Unique 6-character alphanumeric code for joining (e.g., "A1B2C3")
  - `status` - Game state: "waiting" (lobby), "playing" (in progress), "finished" (game over)
  - `owner_session_id` - Session ID of the player who created the game (controls game flow)
  - `max_players` - Maximum players allowed (3-20, default 7)
  - `current_round` - Current round number (1 to total_rounds)
  - `total_rounds` - Number of rounds in the game (default 13)
  - `score` - Points earned (1 point per correct guess)
  - `current_word_id` - Foreign key to the word being guessed this round
  - `state_snapshot` - Serialized GenServer state for crash recovery
  - `last_activity_at` - Timestamp of last state save (for cleanup of stale games)

  ## Associations

  - `current_word` - The Word being guessed this round
  - `players` - All players in this game
  - `clues` - All clues submitted across all rounds
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @max_players_limit 20

  schema "games" do
    field :code, :string
    field :status, :string, default: "waiting"
    field :owner_session_id, :string
    field :max_players, :integer, default: 7
    field :current_round, :integer, default: 0
    field :total_rounds, :integer, default: 13
    field :score, :integer, default: 0
    field :state_snapshot, :map
    field :last_activity_at, :utc_datetime

    belongs_to :current_word, Justone.Game.Word
    has_many :players, Justone.Game.Player
    has_many :clues, Justone.Game.Clue

    timestamps()
  end

  def changeset(game, attrs) do
    game
    |> cast(attrs, [:code, :status, :owner_session_id, :max_players, :current_round, :total_rounds, :current_word_id, :score, :state_snapshot, :last_activity_at])
    |> validate_required([:code, :owner_session_id])
    |> validate_inclusion(:status, ["waiting", "playing", "finished"])
    |> validate_number(:max_players, greater_than: 2, less_than_or_equal_to: @max_players_limit)
    |> unique_constraint(:code)
  end

  def generate_code do
    :crypto.strong_rand_bytes(3)
    |> Base.encode16()
    |> String.upcase()
  end
end
