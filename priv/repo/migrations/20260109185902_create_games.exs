defmodule Justone.Repo.Migrations.CreateGames do
  use Ecto.Migration

  def change do
    create table(:games, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :code, :string, size: 6, null: false
      add :status, :string, default: "waiting", null: false
      add :owner_session_id, :string, null: false
      add :max_players, :integer, default: 7, null: false
      add :current_round, :integer, default: 0
      add :total_rounds, :integer, default: 13
      add :current_word_id, references(:words, type: :binary_id, on_delete: :nilify_all)
      add :score, :integer, default: 0

      timestamps()
    end

    create unique_index(:games, [:code])
    create index(:games, [:status])
  end
end
