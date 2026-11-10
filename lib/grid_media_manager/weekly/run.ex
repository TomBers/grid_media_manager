defmodule GridMediaManager.Weekly.Run do
  use Ecto.Schema
  import Ecto.Changeset

  schema "weekly_runs" do
    field :status, :string, default: "analysing"
    field :theme, :string
    field :start_date, :date
    field :end_date, :date
    field :evidence, :map, default: %{}
    field :quotas, :map, default: %{}
    field :windows, :map, default: %{}
    field :story_count, :integer, default: 0
    field :error, :string
    field :attempts, :integer, default: 0
    field :next_run_at, :utc_datetime
    field :lease_until, :utc_datetime
    field :lease_token, Ecto.UUID
    belongs_to :batch, GridMediaManager.Automation.EditorialBatch
    has_many :stories, GridMediaManager.Weekly.Story
    has_many :deliveries, GridMediaManager.Weekly.Delivery
    timestamps(type: :utc_datetime)
  end

  def changeset(run, attrs) do
    run
    |> cast(attrs, [:theme, :start_date, :end_date])
    |> validate_required([:theme, :start_date, :end_date])
    |> validate_length(:theme, min: 3, max: 2000)
    |> validate_dates()
  end

  defp validate_dates(c) do
    start = get_field(c, :start_date)
    finish = get_field(c, :end_date)

    cond do
      not is_struct(start, Date) or not is_struct(finish, Date) ->
        c

      Date.compare(start, Date.utc_today()) == :lt ->
        add_error(c, :start_date, "must be today or later")

      Date.diff(finish, start) not in 0..6 ->
        add_error(c, :end_date, "must be within seven days of the start")

      true ->
        c
    end
  end
end
