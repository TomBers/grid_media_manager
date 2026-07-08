defmodule GridMediaManager.Campaigns.Campaign do
  use Ecto.Schema
  import Ecto.Changeset

  alias GridMediaManager.Campaigns.MediaAsset
  alias GridMediaManager.Campaigns.PostDraft

  schema "campaigns" do
    field :source_input, :string
    field :slug, :string
    field :title, :string
    field :grid_url, :string
    field :graph_url, :string
    field :tags, {:array, :string}, default: []
    field :node_count, :integer
    field :raw_payload, :map, default: %{}
    field :fetched_at, :utc_datetime

    has_many :media_assets, MediaAsset
    has_many :post_drafts, PostDraft

    timestamps(type: :utc_datetime)
  end

  def changeset(campaign, attrs) do
    campaign
    |> cast(attrs, [
      :source_input,
      :slug,
      :title,
      :grid_url,
      :graph_url,
      :tags,
      :node_count,
      :raw_payload,
      :fetched_at
    ])
    |> validate_required([:slug, :title, :raw_payload, :fetched_at])
    |> validate_length(:slug, min: 2, max: 255)
    |> unique_constraint(:slug)
  end
end
