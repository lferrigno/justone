defmodule Justone.Repo.Migrations.CreateClues do
  use Ecto.Migration

  def change do
    create table(:clues, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :clue, :string, null: false
      add :round, :integer, null: false
      add :is_duplicate, :boolean, default: false
      add :game_id, references(:games, type: :binary_id, on_delete: :delete_all), null: false
      add :player_id, references(:players, type: :binary_id, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:clues, [:game_id, :round])
    create unique_index(:clues, [:game_id, :round, :player_id])
  end
end
