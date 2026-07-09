defmodule GridMediaManagerWeb.PromotionAssetControllerTest do
  use GridMediaManagerWeb.ConnCase

  alias GridMediaManager.Campaigns

  test "serves a generated grid share-card SVG", %{conn: conn} do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "brave-new-world")

    conn = get(conn, ~p"/campaigns/#{campaign.id}/share-card.svg")

    assert response_content_type(conn, :svg) == "image/svg+xml; charset=utf-8"
    assert response(conn, 200) =~ "What can a brave new world teach us?"
    assert response(conn, 200) =~ "RationalGrid.ai"
  end

  test "serves a generated highlight share-card SVG", %{conn: conn} do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "brave-new-world")

    conn = get(conn, ~p"/campaigns/#{campaign.id}/highlights/123/share-card.svg")

    assert response_content_type(conn, :svg) == "image/svg+xml; charset=utf-8"
    assert response(conn, 200) =~ "Perfect comfort can become a cage."
    assert response(conn, 200) =~ "RationalGrid.ai"
  end

  test "returns 404 for a missing highlight card", %{conn: conn} do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "brave-new-world")

    conn = get(conn, ~p"/campaigns/#{campaign.id}/highlights/999/share-card.svg")

    assert response(conn, 404) == "Highlight not found"
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
            "id" => "2",
            "class" => "answer",
            "title" => "What Can a Brave New World Teach Us?",
            "excerpt" => "A dystopian lesson about comfort."
          }
        ]
      }
    }
  end
end
