defmodule GridMediaManager.RationalGrid.Exploration do
  use Ecto.Schema
  import Ecto.Changeset

  schema "grid_explorations" do
    field :request_id, Ecto.UUID
    field :question, :string
    field :rationale, :string
    field :tool, :string, default: "explore_question"
    field :arguments, :map, default: %{}
    field :evidence, :map, default: %{}
    field :status, :string, default: "proposed"
    field :result, :map, default: %{}
    field :payload, :map, default: %{}
    field :error, :string
    field :attempts, :integer, default: 0
    field :next_run_at, :utc_datetime
    belongs_to :connection, GridMediaManager.RationalGrid.Connection
    belongs_to :campaign, GridMediaManager.Campaigns.Campaign
    timestamps(type: :utc_datetime)
  end

  def proposal_changeset(exploration, attrs) do
    exploration
    |> cast(attrs, [:question, :rationale])
    |> validate_required([:question, :rationale])
    |> validate_length(:question, min: 3, max: 4000)
    |> validate_length(:rationale, min: 3, max: 2000)
  end
end
