defmodule GridMediaManagerWeb.WeeklyLiveTest do
  use GridMediaManagerWeb.ConnCase
  import Phoenix.LiveViewTest
  alias GridMediaManager.Weekly

  test "weekly desk starts and resumes one saved run", %{conn: conn} do
    {:ok, view, _} = live(conn, "/weekly")
    assert has_element?(view, "#weekly-run-form")
    attrs = Weekly.default_attrs() |> Map.new(fn {k, v} -> {k, to_string(v)} end)
    view |> form("#weekly-run-form", run: attrs) |> render_submit()
    [r] = Weekly.list()
    assert_redirect(view, "/weekly/#{r.id}")
    {:ok, view, _} = live(conn, "/weekly/#{r.id}")
    assert has_element?(view, "#weekly-status", "analysing")
    assert has_element?(view, "#weekly-evidence")
    refute has_element?(view, "#schedule-weekly-run")
  end

  test "completed full-queue run shows no generation or schedule action", %{conn: conn} do
    {:ok, r} = Weekly.create(Weekly.default_attrs())
    Weekly.save(r, %{status: "completed"})
    {:ok, view, _} = live(conn, "/weekly/#{r.id}")
    assert has_element?(view, "#weekly-completed")
    refute has_element?(view, "#schedule-weekly-run")
    refute has_element?(view, "#render-weekly-media")
  end
end
