defmodule GridMediaManager.Repo.Migrations.SeparateStudioStateAndConstrainDrafts do
  use Ecto.Migration

  def up do
    alter table(:campaigns) do
      add :studio_state, :map, null: false, default: %{}
    end

    execute("""
    UPDATE campaigns
    SET studio_state = COALESCE(raw_payload->'share_studio', '{}'::jsonb)
    """)

    execute("""
    DELETE FROM post_drafts
    WHERE id IN (
      SELECT id
      FROM (
        SELECT id,
               ROW_NUMBER() OVER (
                 PARTITION BY campaign_id, platform, angle, media_asset_id
                 ORDER BY
                   CASE status
                     WHEN 'published' THEN 6
                     WHEN 'scheduled' THEN 5
                     WHEN 'approved' THEN 4
                     WHEN 'copied' THEN 3
                     WHEN 'failed' THEN 2
                     ELSE 1
                   END DESC,
                   updated_at DESC,
                   id DESC
               ) AS duplicate_number
        FROM post_drafts
        WHERE media_asset_id IS NOT NULL
      ) ranked_asset_drafts
      WHERE duplicate_number > 1
    )
    """)

    execute("""
    DELETE FROM post_drafts
    WHERE id IN (
      SELECT id
      FROM (
        SELECT id,
               ROW_NUMBER() OVER (
                 PARTITION BY campaign_id, platform, angle
                 ORDER BY
                   CASE status
                     WHEN 'published' THEN 6
                     WHEN 'scheduled' THEN 5
                     WHEN 'approved' THEN 4
                     WHEN 'copied' THEN 3
                     WHEN 'failed' THEN 2
                     ELSE 1
                   END DESC,
                   updated_at DESC,
                   id DESC
               ) AS duplicate_number
        FROM post_drafts
        WHERE media_asset_id IS NULL
      ) ranked_campaign_drafts
      WHERE duplicate_number > 1
    )
    """)

    create unique_index(
             :post_drafts,
             [:campaign_id, :platform, :angle, :media_asset_id],
             where: "media_asset_id IS NOT NULL",
             name: :post_drafts_unique_asset_destination
           )

    create unique_index(
             :post_drafts,
             [:campaign_id, :platform, :angle],
             where: "media_asset_id IS NULL",
             name: :post_drafts_unique_campaign_destination
           )
  end

  def down do
    drop_if_exists index(:post_drafts, [], name: :post_drafts_unique_asset_destination)
    drop_if_exists index(:post_drafts, [], name: :post_drafts_unique_campaign_destination)

    alter table(:campaigns) do
      remove :studio_state
    end
  end
end
