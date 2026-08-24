defmodule GridMediaManager.Automation.EditorialBatch do
  use Ecto.Schema
  import Ecto.Changeset

  alias GridMediaManager.Automation.EditorialPlan

  @statuses ~w(pending planning completed partial failed)

  schema "editorial_batches" do
    field :topics, {:array, :string}, default: []
    field :requested_count, :integer, default: 3
    field :theme, :string
    field :status, :string, default: "pending"
    field :model, :string
    field :error_message, :string

    has_many :plans, EditorialPlan

    timestamps(type: :utc_datetime)
  end

  def changeset(batch, attrs) do
    batch
    |> cast(attrs, [:topics, :requested_count, :theme, :status, :model, :error_message])
    |> validate_required([:topics, :requested_count, :status])
    |> validate_number(:requested_count, greater_than_or_equal_to: 1, less_than_or_equal_to: 10)
    |> validate_inclusion(:status, @statuses)
    |> validate_topics()
  end

  defp validate_topics(changeset) do
    topics = get_field(changeset, :topics) || []

    cond do
      Enum.any?(topics, &(not is_binary(&1) or String.trim(&1) == "")) ->
        add_error(changeset, :topics, "must contain only non-empty topics")

      topics != [] and length(topics) != get_field(changeset, :requested_count) ->
        add_error(changeset, :topics, "must match the requested count")

      topics |> Enum.map(&String.downcase/1) |> Enum.uniq() |> length() != length(topics) ->
        add_error(changeset, :topics, "must be different")

      true ->
        changeset
    end
  end
end
