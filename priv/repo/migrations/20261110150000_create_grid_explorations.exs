defmodule GridMediaManager.Repo.Migrations.CreateGridExplorations do
  use Ecto.Migration

  def change do
    create table(:rational_grid_connections) do
      add :key, :string, null: false
      add :client_id, :string, null: false
      add :credentials, :text
      add :expires_at, :utc_datetime
      add :status, :string, null: false, default: "disconnected"
      timestamps(type: :utc_datetime)
    end

    create unique_index(:rational_grid_connections, [:key])

    create table(:grid_explorations) do
      add :request_id, :uuid, null: false
      add :connection_id, references(:rational_grid_connections), null: false
      add :question, :text, null: false
      add :rationale, :text, null: false
      add :tool, :string, null: false, default: "explore_question"
      add :arguments, :map, null: false, default: %{}
      add :evidence, :map, null: false, default: %{}
      add :status, :string, null: false, default: "proposed"
      add :result, :map, null: false, default: %{}
      add :payload, :map, null: false, default: %{}
      add :error, :string
      add :attempts, :integer, null: false, default: 0
      add :next_run_at, :utc_datetime
      add :campaign_id, references(:campaigns)
      timestamps(type: :utc_datetime)
    end

    create unique_index(:grid_explorations, [:request_id])
    create index(:grid_explorations, [:status, :next_run_at])
  end
end
