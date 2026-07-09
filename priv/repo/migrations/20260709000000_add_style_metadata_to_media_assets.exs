defmodule GridMediaManager.Repo.Migrations.AddStyleMetadataToMediaAssets do
  use Ecto.Migration

  def change do
    alter table(:media_assets) do
      add :style, :string, null: false, default: "editorial_dark"
      add :source_type, :string
      add :source_id, :string
      add :metadata, :map, null: false, default: %{}
    end

    create index(:media_assets, [:campaign_id, :kind, :style])
    create index(:media_assets, [:campaign_id, :source_type, :source_id, :style])
  end
end
