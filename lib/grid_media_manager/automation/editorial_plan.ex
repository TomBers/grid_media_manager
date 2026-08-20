defmodule GridMediaManager.Automation.EditorialPlan do
  use Ecto.Schema
  import Ecto.Changeset

  alias GridMediaManager.Automation.EditorialBatch
  alias GridMediaManager.Campaigns.Campaign

  @statuses ~w(planned failed)

  schema "editorial_plans" do
    field :position, :integer
    field :topic, :string
    field :source_slug, :string
    field :source_title, :string
    field :selected_keys, {:array, :string}, default: []
    field :hook, :string
    field :rationale, :string
    field :confidence, :float
    field :recommended_format, :string
    field :recommended_platforms, {:array, :string}, default: []
    field :status, :string, default: "planned"
    field :error_message, :string
    field :selection_details, :map, default: %{}

    belongs_to :editorial_batch, EditorialBatch
    belongs_to :campaign, Campaign

    timestamps(type: :utc_datetime)
  end

  def changeset(plan, attrs) do
    plan
    |> cast(attrs, [
      :editorial_batch_id,
      :campaign_id,
      :position,
      :topic,
      :source_slug,
      :source_title,
      :selected_keys,
      :hook,
      :rationale,
      :confidence,
      :recommended_format,
      :recommended_platforms,
      :status,
      :error_message,
      :selection_details
    ])
    |> validate_required([:editorial_batch_id, :position, :topic, :status])
    |> validate_number(:position, greater_than: 0, less_than_or_equal_to: 10)
    |> validate_number(:confidence, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint([:editorial_batch_id, :position])
  end
end
