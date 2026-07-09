defmodule GridMediaManager.Campaigns.MediaAsset do
  use Ecto.Schema
  import Ecto.Changeset

  alias GridMediaManager.Campaigns.Campaign
  alias GridMediaManager.Campaigns.PostDraft

  schema "media_assets" do
    field :title, :string
    field :kind, :string
    field :url, :string
    field :mime_type, :string
    field :text, :string
    field :node_id, :string
    field :highlight_id, :integer
    field :recommended_platforms, {:array, :string}, default: []
    field :style, :string, default: "editorial_dark"
    field :source_type, :string
    field :source_id, :string
    field :metadata, :map, default: %{}

    belongs_to :campaign, Campaign
    has_many :post_drafts, PostDraft

    timestamps(type: :utc_datetime)
  end

  def changeset(media_asset, attrs) do
    media_asset
    |> cast(attrs, [
      :campaign_id,
      :title,
      :kind,
      :url,
      :mime_type,
      :text,
      :node_id,
      :highlight_id,
      :recommended_platforms,
      :style,
      :source_type,
      :source_id,
      :metadata
    ])
    |> validate_required([:campaign_id, :title, :kind, :url])
    |> unique_constraint(:url, name: :media_assets_campaign_id_url_index)
  end
end
