defmodule Justone.Repo.Migrations.CreateWords do
  use Ecto.Migration

  def change do
    create table(:words, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :word, :string, null: false
      add :language, :string, default: "es", null: false

      timestamps()
    end

    create unique_index(:words, [:word, :language])
  end
end
