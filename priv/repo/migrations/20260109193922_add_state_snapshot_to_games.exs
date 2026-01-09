defmodule Justone.Repo.Migrations.AddStateSnapshotToGames do
  use Ecto.Migration

  def change do
    alter table(:games) do
      add :state_snapshot, :map
      add :last_activity_at, :utc_datetime
    end

    create index(:games, [:status, :last_activity_at])
  end
end
