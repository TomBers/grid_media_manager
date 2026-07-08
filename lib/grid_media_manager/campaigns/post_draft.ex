defmodule GridMediaManager.Campaigns.PostDraft do
  use Ecto.Schema
  import Ecto.Changeset

  alias GridMediaManager.Campaigns.Campaign
  alias GridMediaManager.Campaigns.MediaAsset

  @statuses ~w(draft copied scheduled published failed)

  schema "post_drafts" do
    field :platform, :string
    field :angle, :string
    field :body, :string
    field :status, :string, default: "draft"
    field :copied_at, :utc_datetime
    field :scheduled_for, :utc_datetime
    field :published_at, :utc_datetime
    field :external_post_id, :string
    field :error_message, :string

    belongs_to :campaign, Campaign
    belongs_to :media_asset, MediaAsset

    timestamps(type: :utc_datetime)
  end

  def changeset(post_draft, attrs) do
    post_draft
    |> cast(attrs, [
      :campaign_id,
      :media_asset_id,
      :platform,
      :angle,
      :body,
      :status,
      :copied_at,
      :scheduled_for,
      :published_at,
      :external_post_id,
      :error_message
    ])
    |> validate_required([:campaign_id, :platform, :angle, :body, :status])
    |> validate_inclusion(:status, @statuses)
  end

  def statuses, do: @statuses
end
