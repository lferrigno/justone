defmodule Justone.Repo.Migrations.CreatePlayers do
  use Ecto.Migration

  def change do
    create table(:players, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :session_id, :string, null: false
      add :nickname, :string, null: false
      add :is_guesser, :boolean, default: false
      add :game_id, references(:games, type: :binary_id, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:players, [:game_id])
    create unique_index(:players, [:game_id, :session_id])
  end
end
