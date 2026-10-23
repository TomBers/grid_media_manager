defmodule GridMediaManager.Social.PostMetric do
  use Ecto.Schema

  schema "post_metrics" do
    belongs_to :post_draft, GridMediaManager.Campaigns.PostDraft
    field :external_post_id, :string
    field :platform, :string
    field :metrics, :map, default: %{}
    field :sent_at, :utc_datetime
    field :metrics_updated_at, :utc_datetime
    field :fetched_at, :utc_datetime
  end
end
