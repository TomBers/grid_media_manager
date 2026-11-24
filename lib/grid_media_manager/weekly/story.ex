defmodule GridMediaManager.Weekly.Story do
  use Ecto.Schema

  schema "weekly_stories" do
    belongs_to :run, GridMediaManager.Weekly.Run
    belongs_to :exploration, GridMediaManager.RationalGrid.Exploration
    belongs_to :plan, GridMediaManager.Automation.EditorialPlan
    field :position, :integer
    field :question, :string
    field :rationale, :string
    field :status, :string, default: "proposed"
    field :copy, :map, default: %{}
    field :copy_fingerprint, :string
    field :review, :map, default: %{}
    field :public, :boolean, default: false
    field :error, :string
    timestamps(type: :utc_datetime)
  end
end
