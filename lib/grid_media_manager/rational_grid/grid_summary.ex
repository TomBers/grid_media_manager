defmodule GridMediaManager.RationalGrid.GridSummary do
  use Ecto.Schema
  import Ecto.Changeset

  schema "rational_grid_summaries" do
    field :slug, :string
    field :title, :string
    field :url, :string
    field :graph_url, :string
    field :tags, {:array, :string}, default: []
    field :node_count, :integer
    field :source, :string
    field :position, :integer
    field :refreshed_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(grid_summary, attrs) do
    grid_summary
    |> cast(attrs, [
      :slug,
      :title,
      :url,
      :graph_url,
      :tags,
      :node_count,
      :source,
      :position,
      :refreshed_at
    ])
    |> validate_required([:slug, :title, :source, :position, :refreshed_at])
    |> unique_constraint(:slug)
  end
end
