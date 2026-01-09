defmodule Justone.Game.Word do
  @moduledoc """
  Schema for words that players must guess.

  Words are seeded from `priv/repo/seeds.exs` and selected randomly each round.
  The game tracks which words have been used to avoid repetition within a game.

  ## Fields

  - `word` - The word to be guessed (e.g., "perro", "montaña")
  - `language` - Language code for the word (default "es" for Spanish)

  ## Notes

  Words are unique per language, so "apple" can exist in both "en" and "es"
  but not twice in the same language.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "words" do
    field :word, :string
    field :language, :string, default: "es"

    timestamps()
  end

  def changeset(word, attrs) do
    word
    |> cast(attrs, [:word, :language])
    |> validate_required([:word])
    |> unique_constraint([:word, :language])
  end
end
