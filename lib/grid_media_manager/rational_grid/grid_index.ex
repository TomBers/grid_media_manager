defmodule GridMediaManager.RationalGrid.GridIndex do
  @moduledoc """
  Persists the RationalGrid promotion index so the import page can open quickly
  without fetching the same list on every visit.
  """

  import Ecto.Query

  alias GridMediaManager.RationalGrid.GridSummary
  alias GridMediaManager.Repo

  def list(opts \\ []) do
    GridSummary
    |> filter_tag(opts[:tag])
    |> filter_query(opts[:query])
    |> order_by([grid], asc: grid.position, asc: grid.title)
    |> maybe_limit(opts[:limit])
    |> maybe_offset(opts[:offset])
    |> Repo.all()
  end

  def count(opts \\ []) do
    GridSummary
    |> filter_tag(opts[:tag])
    |> filter_query(opts[:query])
    |> Repo.aggregate(:count)
  end

  def list_tags do
    GridSummary
    |> select([grid], grid.tags)
    |> Repo.all()
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.sort()
  end

  def last_refreshed_at do
    Repo.one(from grid in GridSummary, select: max(grid.refreshed_at))
  end

  def replace_all(grids) when is_list(grids) do
    refreshed_at = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.transaction(fn ->
      Repo.delete_all(GridSummary)

      grids
      |> Enum.with_index()
      |> Enum.map(fn {grid, position} ->
        grid
        |> summary_attrs(position, refreshed_at)
        |> then(&GridSummary.changeset(%GridSummary{}, &1))
        |> Repo.insert!()
      end)
    end)
  end

  defp summary_attrs(grid, position, refreshed_at) do
    %{
      slug: grid.slug,
      title: grid.title,
      url: grid.url,
      graph_url: grid.graph_url,
      tags: grid.tags || [],
      node_count: grid.node_count,
      source: grid.source,
      position: position,
      refreshed_at: refreshed_at
    }
  end

  defp filter_tag(query, tag) when tag in [nil, ""], do: query

  defp filter_tag(query, tag) do
    where(query, [grid], fragment("? = ANY(?)", ^tag, grid.tags))
  end

  defp filter_query(query, value) when value in [nil, ""], do: query

  defp filter_query(query, value) do
    term = "%#{String.replace(value, "%", "\\%")}%"

    where(
      query,
      [grid],
      ilike(grid.title, ^term) or ilike(grid.slug, ^term) or
        fragment("array_to_string(?, ' ') ILIKE ?", grid.tags, ^term)
    )
  end

  defp maybe_limit(query, limit) when is_integer(limit) and limit > 0, do: limit(query, ^limit)
  defp maybe_limit(query, _limit), do: query

  defp maybe_offset(query, offset) when is_integer(offset) and offset > 0,
    do: offset(query, ^offset)

  defp maybe_offset(query, _offset), do: query
end
