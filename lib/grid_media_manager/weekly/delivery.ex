defmodule GridMediaManager.Weekly.Delivery do
  use Ecto.Schema

  schema "weekly_deliveries" do
    belongs_to :run, GridMediaManager.Weekly.Run
    belongs_to :story, GridMediaManager.Weekly.Story
    belongs_to :post_draft, GridMediaManager.Campaigns.PostDraft
    field :platform, :string
    field :scheduled_for, :utc_datetime
    field :window, :string
    field :status, :string, default: "prepared"
    field :body_hash, :string
    field :external_post_id, :string
    field :attempted_at, :utc_datetime
    field :checks, :integer, default: 0
    field :error, :string
    timestamps(type: :utc_datetime)
  end
end
