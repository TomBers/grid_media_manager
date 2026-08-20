defmodule GridMediaManagerWeb.GridImportLiveTest do
  use GridMediaManagerWeb.ConnCase

  import Phoenix.LiveViewTest

  alias GridMediaManager.RationalGrid.GridIndex

  test "shows the locally saved grid list when the page opens", %{conn: conn} do
    assert {:ok, [summary]} = GridIndex.replace_all([grid("surprising-grid", ["Testing"])])

    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "#load-remote-grids-button", "Refresh grid list")
    assert has_element?(view, "#remote-grids-last-refreshed", "Saved locally")
    assert has_element?(view, "#remote-grid-#{summary.id}", "A surprising grid")
    assert has_element?(view, "#import-remote-grid-#{summary.id}", "Open in studio")
  end

  test "filters the local grid stream by tag", %{conn: conn} do
    assert {:ok, [science_summary, art_summary]} =
             GridIndex.replace_all([
               grid("surprising-science", ["Science"]),
               grid("surprising-art", ["Art"])
             ])

    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "#remote-grid-#{science_summary.id}")
    assert has_element?(view, "#remote-grid-#{art_summary.id}")

    view
    |> form("#remote-grid-filter-form", filter: %{tag: "Science"})
    |> render_change()

    assert has_element?(view, "#remote-grid-#{science_summary.id}")
    refute has_element?(view, "#remote-grid-#{art_summary.id}")
  end

  test "links to the editorial autopilot", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "#open-editorial-autopilot[href='/automation/new']")
  end

  defp grid(slug, tags) do
    %{
      slug: slug,
      title: "A surprising grid",
      url: "https://rationalgrid.ai/g/#{slug}",
      graph_url: nil,
      tags: tags,
      node_count: 5,
      source: slug
    }
  end
end
