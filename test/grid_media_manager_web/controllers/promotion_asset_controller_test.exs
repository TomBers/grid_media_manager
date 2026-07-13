defmodule GridMediaManagerWeb.PromotionAssetControllerTest do
  use GridMediaManagerWeb.ConnCase

  alias GridMediaManager.Campaigns
  alias GridMediaManager.Promotion.CarouselVideo
  alias GridMediaManager.Promotion.ShareCard

  test "serves a generated grid share-card SVG", %{conn: conn} do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "brave-new-world")

    conn = get(conn, ~p"/campaigns/#{campaign.id}/share-card.svg")

    assert response_content_type(conn, :svg) == "image/svg+xml; charset=utf-8"
    assert response(conn, 200) =~ "What can a brave new world teach us?"
    assert response(conn, 200) =~ "RationalGrid.ai"
  end

  test "serves styled grid title card variants", %{conn: conn} do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "brave-new-world")

    conn = get(conn, ~p"/campaigns/#{campaign.id}/share-card.svg?style=gradient_poster")

    assert response(conn, 200) =~ "#2e1065"
    assert response(conn, 200) =~ "#f0abfc"
  end

  test "serves a generated key-node share-card SVG", %{conn: conn} do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "brave-new-world")

    conn = get(conn, ~p"/campaigns/#{campaign.id}/nodes/2/share-card.svg")

    assert response_content_type(conn, :svg) == "image/svg+xml; charset=utf-8"
    assert response(conn, 200) =~ "What Can a Brave New World Teach Us?"
    assert response(conn, 200) =~ "A dystopian lesson about comfort."
    assert response(conn, 200) =~ "RationalGrid.ai"
  end

  test "serves true minimal light and dark foundations", %{conn: conn} do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "minimal-foundations")

    light_conn = get(conn, ~p"/campaigns/#{campaign.id}/share-card.svg?style=minimal_light")
    light_svg = response(light_conn, 200)

    assert light_svg =~ ~s(stop-color="#ffffff")
    assert light_svg =~ ~s(fill="#000000")
    assert light_svg =~ ~s(fill-opacity="0")
    refute light_svg =~ "#fb7185"
    refute light_svg =~ "#22d3ee"

    dark_conn =
      get(recycle(conn), ~p"/campaigns/#{campaign.id}/share-card.svg?style=minimal_dark")

    dark_svg = response(dark_conn, 200)

    assert dark_svg =~ ~s(stop-color="#000000")
    assert dark_svg =~ ~s(fill="#ffffff")
    assert dark_svg =~ ~s(fill-opacity="0")
    refute dark_svg =~ "#fb7185"
    refute dark_svg =~ "#22d3ee"
  end

  test "removes social decoration from minimal question cards", %{conn: conn} do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "minimal-question")
    question = "If a drug like soma existed today..."
    question_id = ShareCard.question_id(question)

    conn =
      get(
        conn,
        ~p"/campaigns/#{campaign.id}/questions/#{question_id}/share-card.svg?style=minimal_light"
      )

    svg = response(conn, 200)
    assert svg =~ ~s(stroke="#111111" stroke-opacity="0")
    assert svg =~ ~s(fill="#000000")
    refute svg =~ "#fb7185"
    refute svg =~ "#22d3ee"
  end

  test "serves styled key-node card variants", %{conn: conn} do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "brave-new-world")

    conn = get(conn, ~p"/campaigns/#{campaign.id}/nodes/2/share-card.svg?style=minimal_academic")

    assert response(conn, 200) =~ "#f8fafc"
    assert response(conn, 200) =~ "#0f172a"
  end

  test "serves LinkedIn square explainers for key nodes", %{conn: conn} do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "linkedin-explainer")

    conn =
      get(
        conn,
        ~p"/campaigns/#{campaign.id}/nodes/2/share-card.svg?style=minimal_light&format=linkedin"
      )

    svg = response(conn, 200)
    assert response_content_type(conn, :svg) == "image/svg+xml; charset=utf-8"
    assert svg =~ "width=\"1200\""
    assert svg =~ "height=\"1200\""
    assert svg =~ "LINKEDIN · answer"
    assert svg =~ "A dystopian lesson about comfort."
  end

  test "serves portrait reading cards for key nodes", %{conn: conn} do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "brave-new-world")

    conn =
      get(
        conn,
        ~p"/campaigns/#{campaign.id}/nodes/2/share-card.svg?style=warm_paper&format=portrait"
      )

    assert response_content_type(conn, :svg) == "image/svg+xml; charset=utf-8"
    assert response(conn, 200) =~ "width=\"1080\""
    assert response(conn, 200) =~ "height=\"1350\""
    assert response(conn, 200) =~ "What Can a Brave New World Teach Us?"
  end

  test "renders dedicated full-screen frames for short video", %{} do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "short-frame")
    node = ShareCard.find_key_node(campaign, "2")
    svg = ShareCard.node_short_video_frame_svg(campaign, node, "gradient_poster", 1)

    assert svg =~ "width=\"1080\""
    assert svg =~ "height=\"1920\""
    assert svg =~ "font-size=\"90\""
    assert svg =~ "SHORT · 1/"
  end

  test "serves carousel slides for key nodes", %{conn: conn} do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "brave-new-world")

    conn =
      get(
        conn,
        ~p"/campaigns/#{campaign.id}/nodes/2/carousel.svg?style=gradient_poster&slide=1"
      )

    assert response_content_type(conn, :svg) == "image/svg+xml; charset=utf-8"
    assert response(conn, 200) =~ "width=\"1080\""
    assert response(conn, 200) =~ "1 /"
    assert response(conn, 200) =~ "RationalGrid.ai"
  end

  test "serves rasterized PNG carousel slides for social publishing", %{conn: conn} do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "brave-new-world")

    conn =
      get(
        conn,
        ~p"/campaigns/#{campaign.id}/nodes/2/carousel.png?style=gradient_poster&slide=1"
      )

    assert response_content_type(conn, :png) == "image/png; charset=utf-8"
    assert response(conn, 200) |> binary_part(0, 8) == <<137, 80, 78, 71, 13, 10, 26, 10>>
  end

  test "serves a vertical MP4 carousel video for short-form platforms", %{conn: conn} do
    assert {:ok, campaign} =
             Campaigns.import_payload(simplified_payload(), "carousel-video-route")

    conn =
      get(
        conn,
        ~p"/campaigns/#{campaign.id}/nodes/2/carousel.mp4?style=gradient_poster"
      )

    if CarouselVideo.available?() do
      assert get_resp_header(conn, "content-type") |> List.first() =~ "video/mp4"
      assert response(conn, 200) |> binary_part(4, 4) == "ftyp"
      assert get_resp_header(conn, "content-disposition") |> List.first() =~ ".mp4"
    else
      assert response(conn, 503) == "Video rendering requires FFmpeg"
    end
  end

  test "keeps long key-node content inside the generated SVG text area", %{conn: conn} do
    assert {:ok, campaign} = Campaigns.import_payload(long_key_node_payload(), "long-node")

    conn = get(conn, ~p"/campaigns/#{campaign.id}/nodes/long-node/share-card.svg")
    svg = response(conn, 200)

    assert response_content_type(conn, :svg) == "image/svg+xml; charset=utf-8"
    assert svg =~ "…"

    tspan_y_values =
      ~r/<tspan x="112" y="(\d+)">/
      |> Regex.scan(svg, capture: :all_but_first)
      |> List.flatten()
      |> Enum.map(&String.to_integer/1)

    assert tspan_y_values != []
    assert Enum.all?(tspan_y_values, &(&1 <= 494))
  end

  test "serves a generated question quote-card SVG", %{conn: conn} do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "brave-new-world")
    question = "If a drug like soma existed today..."
    question_id = ShareCard.question_id(question)

    conn = get(conn, ~p"/campaigns/#{campaign.id}/questions/#{question_id}/share-card.svg")

    assert response_content_type(conn, :svg) == "image/svg+xml; charset=utf-8"
    assert response(conn, 200) =~ question
    assert response(conn, 200) =~ "RationalGrid.ai"
  end

  test "serves styled question quote-card variants", %{conn: conn} do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "brave-new-world")
    question = "If a drug like soma existed today..."
    question_id = ShareCard.question_id(question)

    conn =
      get(
        conn,
        ~p"/campaigns/#{campaign.id}/questions/#{question_id}/share-card.svg?style=gradient_poster"
      )

    assert response(conn, 200) =~ "#2e1065"
    assert response(conn, 200) =~ "#f0abfc"
  end

  test "serves a generated highlight share-card SVG", %{conn: conn} do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "brave-new-world")

    conn = get(conn, ~p"/campaigns/#{campaign.id}/highlights/123/share-card.svg")

    assert response_content_type(conn, :svg) == "image/svg+xml; charset=utf-8"
    assert response(conn, 200) =~ "Perfect comfort can become a cage."
    assert response(conn, 200) =~ "RationalGrid.ai"
  end

  test "returns 404 for a missing key-node card", %{conn: conn} do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "brave-new-world")

    conn = get(conn, ~p"/campaigns/#{campaign.id}/nodes/999/share-card.svg")

    assert response(conn, 404) == "Key node not found"
  end

  test "returns 404 for a missing question quote card", %{conn: conn} do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "brave-new-world")

    conn = get(conn, ~p"/campaigns/#{campaign.id}/questions/missing-question/share-card.svg")

    assert response(conn, 404) == "Question not found"
  end

  test "returns 404 for a missing highlight card", %{conn: conn} do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "brave-new-world")

    conn = get(conn, ~p"/campaigns/#{campaign.id}/highlights/999/share-card.svg")

    assert response(conn, 404) == "Highlight not found"
  end

  defp long_key_node_payload do
    title =
      "The Extremely Detailed Social Mechanism by Which Comfort, Algorithmic Recommendation, Institutional Incentives, and Personal Fear Can Mutually Reinforce Each Other"

    excerpt =
      Enum.map_join(1..36, " ", fn index ->
        "This is sentence #{index} explaining how a longer key node can contain enough nuanced argumentation to overflow a naive social card layout unless the card adapts its type size and line count."
      end)

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
          "node_id" => "long-node",
          "title" => title,
          "content" => excerpt,
          "excerpt" => excerpt
        },
        "follow_up_questions" => [],
        "user_questions" => [],
        "highlights" => [],
        "key_nodes" => [
          %{
            "id" => "long-node",
            "class" => "second_order",
            "title" => title,
            "excerpt" => excerpt
          }
        ]
      }
    }
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
