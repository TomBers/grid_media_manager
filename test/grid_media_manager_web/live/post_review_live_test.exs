defmodule GridMediaManagerWeb.PostReviewLiveTest do
  use GridMediaManagerWeb.ConnCase

  import Phoenix.LiveViewTest

  alias GridMediaManager.Campaigns
  alias GridMediaManager.Social.Platforms

  test "shows proposed posts once per logical package and approves the global queue", %{
    conn: conn
  } do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "post-review-queue")

    {:ok, view, _html} = live(conn, ~p"/posts/review")

    assert has_element?(view, "#post-review-summary")
    assert has_element?(view, "#post-review-packages article")
    assert has_element?(view, "#approve-all-posts", "Approve")
    assert has_element?(view, "[id^='open-post-page-']", campaign.title)
    assert has_element?(view, "[id^='open-post-page-'][href='/campaigns/#{campaign.id}/studio']")
    assert has_element?(view, "#post-review-packages", "Suggested publish time")

    assert Campaigns.list_post_drafts(campaign)
           |> Enum.all?(&match?(%DateTime{}, &1.suggested_for))

    view |> element("#approve-all-posts") |> render_click()

    drafts = Campaigns.list_post_drafts(campaign)
    assert Enum.all?(drafts, &(&1.platform in Platforms.ids()))
    assert Enum.all?(drafts, &(&1.status == "approved"))
    assert has_element?(view, "#approve-all-posts[disabled]")
    assert has_element?(view, "#flash-info", "Approved")
    assert has_element?(view, "#empty-post-review-packages")
  end

  test "removes a proposed post package from the global queue", %{conn: conn} do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "post-review-delete")

    {:ok, view, _html} = live(conn, ~p"/posts/review")

    before_count = length(Campaigns.list_post_drafts(campaign))

    remove_button =
      element(
        view,
        "#post-review-packages article:first-of-type button[id^='remove-post-package-']"
      )

    assert render_click(remove_button) =~ "Removed the proposal"
    assert length(Campaigns.list_post_drafts(campaign)) < before_count
    assert has_element?(view, "#flash-info", "Removed the proposal")
  end

  defp simplified_payload do
    %{
      "metadata" => %{
        "title" => "A post review queue",
        "slug" => "post-review-queue",
        "url" => "https://rationalgrid.ai/g/post-review-queue",
        "node_count" => 1,
        "tags" => ["Reasoning"]
      },
      "graph" => %{
        "nodes" => [
          %{
            "id" => "1",
            "class" => "answer",
            "title" => "A useful idea",
            "content" => "A coherent explanation can become a useful post."
          }
        ],
        "edges" => []
      },
      "highlights" => []
    }
  end
end
