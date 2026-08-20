defmodule GridMediaManagerWeb.AutopilotLiveTest do
  use GridMediaManagerWeb.ConnCase

  import Phoenix.LiveViewTest

  alias GridMediaManager.Automation

  test "starts an autonomous run from a count and optional theme", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/automation/new")

    assert has_element?(view, "#autopilot-form")
    assert has_element?(view, "#autopilot-form select[name='autopilot[count]']")
    assert has_element?(view, "#autopilot-form input[name='autopilot[theme]']")

    view
    |> form("#autopilot-form", autopilot: %{count: "2", theme: "Human agency"})
    |> render_submit()

    [batch] = Automation.list_recent_batches(1)
    assert batch.requested_count == 2
    assert batch.theme == "Human agency"
    assert batch.topics == []
    assert_redirected(view, ~p"/automation/#{batch.id}")
  end
end
