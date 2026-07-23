defmodule GridMediaManager.RationalGrid.GridIndexTest do
  use GridMediaManager.DataCase, async: false

  alias GridMediaManager.RationalGrid.GridIndex

  test "replaces the saved list while preserving the API order" do
    assert {:ok, _} = GridIndex.replace_all([grid("first-grid", 0), grid("second-grid", 1)])

    assert [%{slug: "first-grid", position: 0}, %{slug: "second-grid", position: 1}] =
             GridIndex.list()

    assert %DateTime{} = GridIndex.last_refreshed_at()

    assert {:ok, _} = GridIndex.replace_all([grid("fresh-grid", 0)])

    assert [%{slug: "fresh-grid", position: 0}] = GridIndex.list()
  end

  test "filters saved grids by tag" do
    assert {:ok, _} =
             GridIndex.replace_all([
               grid("science-grid", 0, ["Science", "Research"]),
               grid("art-grid", 1, ["Art"])
             ])

    assert [%{slug: "science-grid"}] = GridIndex.list(tag: "Science")
    assert GridIndex.list(tag: "Missing") == []
    assert GridIndex.list_tags() == ["Art", "Research", "Science"]
  end

  defp grid(slug, _position, tags \\ ["Testing"]) do
    %{
      slug: slug,
      title: String.capitalize(String.replace(slug, "-", " ")),
      url: "https://rationalgrid.ai/g/#{slug}",
      graph_url: nil,
      tags: tags,
      node_count: 3,
      source: slug
    }
  end
end
