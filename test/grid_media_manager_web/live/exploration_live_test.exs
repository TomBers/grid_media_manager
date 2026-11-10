defmodule GridMediaManagerWeb.ExplorationLiveTest do
  use GridMediaManagerWeb.ConnCase
  import Phoenix.LiveViewTest
  import GridMediaManager.RationalGridMCPHelpers
  alias GridMediaManager.RationalGrid.Explorations

  test "disconnected studio offers account linking", %{conn: conn} do
    {:ok, view, _} = live(conn, "/explorations")
    assert has_element?(view, "#connect-rationalgrid[data-method='post']")
    assert has_element?(view, "#recommend-exploration[disabled]")
  end

  test "proposal selection, background completion, review and campaign navigation", %{conn: conn} do
    setup_http()
    connected()
    {:ok, view, _} = live(conn, "/explorations")

    view
    |> form("#exploration-proposal-form",
      exploration: %{
        question: "Can evidence change minds?",
        rationale: "A question informed by weaker results."
      }
    )
    |> render_submit()

    [e] = Explorations.list()
    assert_patch(view, "/explorations/#{e.id}")
    assert has_element?(view, "#start-exploration")
    refute has_element?(view, "#create-exploration-campaign")
    view |> element("#start-exploration") |> render_click()
    refute has_element?(view, "#start-exploration")

    stub(fn conn ->
      rpc(conn, fn
        "explore_question", _ ->
          %{"request_id" => e.request_id, "status" => "completed", "grid" => grid()}

        "read_grid", args ->
          page(args["offset"])
      end)
    end)

    Explorations.process_next()
    send(view.pid, :refresh)
    assert has_element?(view, "#exploration-node-node-1")
    assert has_element?(view, "#exploration-evidence")
    view |> element("#create-exploration-campaign") |> render_click()
    campaign_id = Explorations.get!(e.id).campaign_id
    assert_redirect(view, "/campaigns/#{campaign_id}/studio")
  end
end
