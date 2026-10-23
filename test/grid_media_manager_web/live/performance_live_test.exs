defmodule GridMediaManagerWeb.PerformanceLiveTest do
  use GridMediaManagerWeb.ConnCase
  import Phoenix.LiveViewTest

  test "results can switch channels and show the missing-data state", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/results")
    assert has_element?(view, "#results-x[aria-pressed=true]")
    assert has_element?(view, "#performance-empty")
    view |> element("#results-instagram") |> render_click()
    assert has_element?(view, "#results-instagram[aria-pressed=true]")
    assert has_element?(view, "#results-x[aria-pressed=false]")
    assert has_element?(view, "#performance-freshness")
    assert has_element?(view, "#sync-performance")
  end
end
