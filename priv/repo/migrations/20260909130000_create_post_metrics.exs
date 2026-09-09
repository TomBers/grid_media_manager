defmodule GridMediaManager.Repo.Migrations.CreatePostMetrics do
  use Ecto.Migration

  def change do
    create table(:post_metrics) do
      add :post_draft_id, references(:post_drafts, on_delete: :delete_all), null: false
      add :external_post_id, :string, null: false
      add :platform, :string, null: false
      add :metrics, :map, null: false, default: %{}
      add :sent_at, :utc_datetime, null: false
      add :metrics_updated_at, :utc_datetime
      add :fetched_at, :utc_datetime, null: false
    end

    create unique_index(:post_metrics, [:post_draft_id])
    create index(:post_metrics, [:platform, :sent_at])
  end
end
