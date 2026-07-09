defmodule GridMediaManagerWeb.ShareStudioLiveTest do
  use GridMediaManagerWeb.ConnCase

  import Phoenix.LiveViewTest

  alias GridMediaManager.Campaigns

  test "renders grid summary, media assets, and draft composer", %{conn: conn} do
    assert {:ok, campaign} = Campaigns.import_payload(sample_payload(), "res.json")

    {:ok, view, _html} = live(conn, ~p"/campaigns/#{campaign.id}")

    assert has_element?(view, "#grid-summary-panel")
    assert has_element?(view, "#asset-gallery-panel")
    assert has_element?(view, "#draft-composer-panel")
    assert has_element?(view, "#platform-tab-linkedin")
    assert has_element?(view, "#post-drafts")
  end

  test "renders simplified content payload sections without assets", %{conn: conn} do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "brave-new-world")

    {:ok, view, _html} = live(conn, ~p"/campaigns/#{campaign.id}")

    assert has_element?(view, "#origin-question-section")
    assert has_element?(view, "#first-answer-excerpt-section")
    assert has_element?(view, "#follow-up-questions-section")
    assert has_element?(view, "#user-questions-section")
    assert has_element?(view, "#highlights-section")
    assert has_element?(view, "#generate-key-node-image-1")
    assert has_element?(view, "#media-assets article")
    refute has_element?(view, "#empty-media-assets:only-child")
  end

  test "generates a key-node image from the key-node button", %{conn: conn} do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "brave-new-world")

    {:ok, view, _html} = live(conn, ~p"/campaigns/#{campaign.id}")

    view
    |> element("#generate-key-node-image-1")
    |> render_click()

    assets = Campaigns.list_media_assets(campaign)
    assert Enum.any?(assets, &(&1.kind == "key_node_card" and &1.node_id == "1"))
    assert has_element?(view, "#generate-key-node-image-1[disabled]")
  end

  test "saves edited draft copy", %{conn: conn} do
    assert {:ok, campaign} = Campaigns.import_payload(sample_payload(), "res.json")
    [draft | _] = Campaigns.list_post_drafts(campaign, platform: "x", media_asset_id: "campaign")

    {:ok, view, _html} = live(conn, ~p"/campaigns/#{campaign.id}")

    view
    |> form("#draft-form-#{draft.id}", post_draft: %{body: "Updated copy from the editor"})
    |> render_change()

    assert Campaigns.get_post_draft!(draft.id).body == "Updated copy from the editor"
  end

  defp sample_payload do
    "res.json"
    |> File.read!()
    |> Jason.decode!()
  end

  defp simplified_payload do
    %{
      "grid" => %{
        "title" => "What can a brave new world teach us?",
        "slug" => "what-can-a-brave-new-world-teach-us-1964bc",
        "url" => "https://rationalgrid.com/g/what-can-a-brave-new-world-teach-us-1964bc",
        "tags" => ["Dystopian Literature", "Social Philosophy"],
        "node_count" => 5,
        "inserted_at" => "2026-07-01T00:00:00Z",
        "updated_at" => "2026-07-02T00:00:00Z"
      },
      "content" => %{
        "origin_question" => "What can a brave new world teach us?",
        "first_answer" => %{
          "node_id" => "2",
          "title" => "What Can a Brave New World Teach Us?",
          "content" => "Long answer",
          "excerpt" => "A dystopian lesson about comfort."
        },
        "follow_up_questions" => ["If a drug like soma existed today..."],
        "user_questions" => [
          %{"node_id" => "4", "question" => "If a drug like soma existed today..."}
        ],
        "highlights" => [
          %{
            "id" => 123,
            "node_id" => "2",
            "text" => "Perfect comfort can become a cage.",
            "note" => nil
          }
        ],
        "key_nodes" => [
          %{
            "id" => "1",
            "class" => "origin",
            "title" => "What can a brave new world teach us?",
            "excerpt" => "What can a brave new world teach us?"
          }
        ]
      }
    }
  end
end
