defmodule GridMediaManager.Repo.Migrations.CreateRationalGridSummaries do
  use Ecto.Migration

  def change do
    create table(:rational_grid_summaries) do
      add :slug, :string, null: false
      add :title, :string, null: false
      add :url, :text
      add :graph_url, :text
      add :tags, {:array, :string}, null: false, default: []
      add :node_count, :integer
      add :source, :string, null: false
      add :position, :integer, null: false
      add :refreshed_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:rational_grid_summaries, [:slug])
    create index(:rational_grid_summaries, [:position])
  end
end
