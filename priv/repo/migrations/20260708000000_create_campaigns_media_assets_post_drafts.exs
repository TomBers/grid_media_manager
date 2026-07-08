defmodule GridMediaManager.Repo.Migrations.CreateCampaignsMediaAssetsPostDrafts do
  use Ecto.Migration

  def change do
    create table(:campaigns) do
      add :source_input, :text
      add :slug, :string, null: false
      add :title, :string, null: false
      add :grid_url, :text
      add :graph_url, :text
      add :tags, {:array, :string}, null: false, default: []
      add :node_count, :integer
      add :raw_payload, :map, null: false, default: %{}
      add :fetched_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:campaigns, [:slug])

    create table(:media_assets) do
      add :campaign_id, references(:campaigns, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :kind, :string, null: false
      add :url, :text, null: false
      add :mime_type, :string
      add :text, :text
      add :node_id, :string
      add :highlight_id, :integer
      add :recommended_platforms, {:array, :string}, null: false, default: []

      timestamps(type: :utc_datetime)
    end

    create index(:media_assets, [:campaign_id])
    create unique_index(:media_assets, [:campaign_id, :url])

    create table(:post_drafts) do
      add :campaign_id, references(:campaigns, on_delete: :delete_all), null: false
      add :media_asset_id, references(:media_assets, on_delete: :nilify_all)
      add :platform, :string, null: false
      add :angle, :string, null: false
      add :body, :text, null: false
      add :status, :string, null: false, default: "draft"
      add :copied_at, :utc_datetime
      add :scheduled_for, :utc_datetime
      add :published_at, :utc_datetime
      add :external_post_id, :string
      add :error_message, :text

      timestamps(type: :utc_datetime)
    end

    create index(:post_drafts, [:campaign_id])
    create index(:post_drafts, [:media_asset_id])
    create index(:post_drafts, [:campaign_id, :platform])
    create index(:post_drafts, [:status, :scheduled_for])
  end
end
