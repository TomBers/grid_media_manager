defmodule GridMediaManagerWeb.PromotionAssetControllerTest do
  use GridMediaManagerWeb.ConnCase

  alias GridMediaManager.Campaigns
  alias GridMediaManager.Promotion.CarouselVideo
  alias GridMediaManager.Promotion.ShareCard
  alias GridMediaManager.Studio.Workflow

  test "serves a generated grid share-card PNG", %{conn: conn} do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "brave-new-world")

    conn = get(conn, ~p"/campaigns/#{campaign.id}/share-card.png")
    assert_png_response(conn)
  end

  test "serves styled grid title card variants", %{conn: conn} do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "brave-new-world")

    conn = get(conn, ~p"/campaigns/#{campaign.id}/share-card.png?style=gradient_poster")
    assert_png_response(conn)

    svg = ShareCard.graph_image_svg(campaign, "gradient_poster")
    assert svg =~ "#2e1065"
    assert svg =~ "#f0abfc"
  end

  test "serves a generated key-node share-card PNG", %{conn: conn} do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "brave-new-world")

    conn = get(conn, ~p"/campaigns/#{campaign.id}/nodes/2/share-card.png")
    assert_png_response(conn)
  end

  test "serves true minimal light and dark foundations", %{} do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "minimal-foundations")

    light_svg = ShareCard.graph_image_svg(campaign, "minimal_light")

    assert light_svg =~ ~s(stop-color="#ffffff")
    assert light_svg =~ ~s(fill="#000000")
    assert light_svg =~ ~s(fill-opacity="0")
    refute light_svg =~ "#fb7185"
    refute light_svg =~ "#22d3ee"

    dark_svg = ShareCard.graph_image_svg(campaign, "minimal_dark")

    assert dark_svg =~ ~s(stop-color="#000000")
    assert dark_svg =~ ~s(fill="#ffffff")
    assert dark_svg =~ ~s(fill-opacity="0")
    refute dark_svg =~ "#fb7185"
    refute dark_svg =~ "#22d3ee"
  end

  test "removes social decoration from minimal question cards", %{} do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "minimal-question")
    question = "If a drug like soma existed today..."
    question_id = ShareCard.question_id(question)

    question = ShareCard.find_question(campaign, question_id)
    svg = ShareCard.question_platform_image_svg(campaign, question, "minimal_light", "landscape")
    assert svg =~ ~s(stroke="#111111" stroke-opacity="0")
    assert svg =~ ~s(fill="#000000")
    refute svg =~ "#fb7185"
    refute svg =~ "#22d3ee"
  end

  test "serves styled key-node card variants", %{} do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "brave-new-world")
    node = ShareCard.find_key_node(campaign, "2")
    svg = ShareCard.node_image_svg(campaign, node, "minimal_academic")

    assert svg =~ "#f8fafc"
    assert svg =~ "#0f172a"
  end

  test "serves LinkedIn square explainers for key nodes", %{conn: conn} do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "linkedin-explainer")

    conn =
      get(
        conn,
        ~p"/campaigns/#{campaign.id}/nodes/2/share-card.png?style=minimal_light&format=linkedin"
      )

    assert_png_response(conn)
    node = ShareCard.find_key_node(campaign, "2")
    svg = ShareCard.node_linkedin_image_svg(campaign, node, "minimal_light")
    assert svg =~ "width=\"1200\""
    assert svg =~ "height=\"1200\""
    refute svg =~ "LINKEDIN · answer"
    assert svg =~ "A dystopian lesson about comfort."
  end

  test "serves portrait reading cards for key nodes", %{conn: conn} do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "brave-new-world")

    conn =
      get(
        conn,
        ~p"/campaigns/#{campaign.id}/nodes/2/share-card.png?style=warm_paper&format=portrait"
      )

    assert_png_response(conn)
    node = ShareCard.find_key_node(campaign, "2")
    svg = ShareCard.node_reading_image_svg(campaign, node, "warm_paper")
    assert svg =~ "width=\"1080\""
    assert svg =~ "height=\"1350\""
    assert svg =~ "What Can a Brave New World Teach Us?"
  end

  test "renders dedicated full-screen frames for short video", %{} do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "short-frame")
    node = ShareCard.find_key_node(campaign, "2")
    svg = ShareCard.node_short_video_frame_svg(campaign, node, "gradient_poster", 1)

    assert svg =~ "width=\"1080\""
    assert svg =~ "height=\"1920\""
    assert svg =~ "font-size=\"90\""
    assert svg =~ ">THESIS</text>"
    refute svg =~ "SHORT · 1/"
  end

  test "renders carousel slide layouts internally", %{} do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "brave-new-world")
    node = ShareCard.find_key_node(campaign, "2")
    svg = ShareCard.node_carousel_image_svg(campaign, node, "gradient_poster", 1)

    assert svg =~ "width=\"1080\""
    assert svg =~ "1 /"
    assert svg =~ "RationalGrid.ai"
  end

  test "fits complete long-form copy into video frames without truncation", %{} do
    assert {:ok, campaign} = Campaigns.import_payload(long_key_node_payload(), "long-video-node")
    node = ShareCard.find_key_node(campaign, "long-node")

    frames =
      campaign
      |> ShareCard.carousel_slides(node)
      |> Enum.with_index(1)
      |> Enum.map(fn {_slide, index} ->
        ShareCard.node_short_video_frame_svg(campaign, node, "editorial_dark", index)
      end)

    assert Enum.any?(frames, &String.contains?(&1, "sentence 36"))
    refute Enum.any?(frames, &String.contains?(&1, "…"))
  end

  test "serves slides from a combined mixed-content carousel", %{conn: conn} do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "combined-route")

    candidates =
      campaign
      |> Workflow.candidates()
      |> Enum.take(3)

    assert {:ok, asset} =
             Campaigns.generate_curated_carousel(campaign, candidates, "gradient_poster")

    path =
      ShareCard.curated_carousel_image_path(
        campaign,
        asset.source_id,
        2,
        asset.style
      )

    conn = get(conn, path)
    assert_png_response(conn)

    video_conn =
      get(
        recycle(conn),
        CarouselVideo.curated_video_path(campaign, asset.source_id, asset.style)
      )

    if CarouselVideo.available?() do
      video = response(video_conn, 200)
      assert binary_part(video, 4, 4) == "ftyp"
      assert video =~ "soun"
    else
      assert response(video_conn, 503) == "Video rendering requires FFmpeg"
    end
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
      video = response(conn, 200)
      assert binary_part(video, 4, 4) == "ftyp"
      assert video =~ "soun"
      assert video =~ "mp4a"
      assert get_resp_header(conn, "content-disposition") |> List.first() =~ ".mp4"
    else
      assert response(conn, 503) == "Video rendering requires FFmpeg"
    end
  end

  test "keeps long key-node content inside the generated layout", %{} do
    assert {:ok, campaign} = Campaigns.import_payload(long_key_node_payload(), "long-node")
    node = ShareCard.find_key_node(campaign, "long-node")
    svg = ShareCard.node_image_svg(campaign, node)

    assert svg =~ "…"

    tspan_y_values =
      ~r/<tspan x="112" y="(\d+)">/
      |> Regex.scan(svg, capture: :all_but_first)
      |> List.flatten()
      |> Enum.map(&String.to_integer/1)

    assert tspan_y_values != []
    assert Enum.all?(tspan_y_values, &(&1 <= 494))
  end

  test "serves a generated question quote-card PNG", %{conn: conn} do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "brave-new-world")
    question = "If a drug like soma existed today..."
    question_id = ShareCard.question_id(question)

    conn = get(conn, ~p"/campaigns/#{campaign.id}/questions/#{question_id}/share-card.png")
    assert_png_response(conn)
  end

  test "serves LinkedIn and Instagram question/highlight layouts", %{conn: conn} do
    assert {:ok, campaign} =
             Campaigns.import_payload(simplified_payload(), "platform-quote-routes")

    question = "If a drug like soma existed today..."
    question_id = ShareCard.question_id(question)

    question_conn =
      get(
        conn,
        ~p"/campaigns/#{campaign.id}/questions/#{question_id}/share-card.png?style=minimal_light&format=linkedin"
      )

    assert_png_response(question_conn)
    question_map = ShareCard.find_question(campaign, question_id)

    question_svg =
      ShareCard.question_platform_image_svg(campaign, question_map, "minimal_light", "linkedin")

    assert question_svg =~ "width=\"1200\""
    assert question_svg =~ "height=\"1200\""
    refute question_svg =~ "LINKEDIN · FOLLOW UP QUESTION"

    highlight_conn =
      get(
        recycle(conn),
        ~p"/campaigns/#{campaign.id}/highlights/123/share-card.png?style=minimal_dark&format=portrait"
      )

    assert_png_response(highlight_conn)
    highlight = ShareCard.find_highlight(campaign, 123)

    highlight_svg =
      ShareCard.highlight_platform_image_svg(campaign, highlight, "minimal_dark", "portrait")

    assert highlight_svg =~ "width=\"1080\""
    assert highlight_svg =~ "height=\"1350\""
    refute highlight_svg =~ "INSTAGRAM · HIGHLIGHT"
  end

  test "serves an uploadable question Short", %{conn: conn} do
    assert {:ok, campaign} =
             Campaigns.import_payload(simplified_payload(), "question-short-route")

    question = "If a drug like soma existed today..."
    question_id = ShareCard.question_id(question)

    conn =
      get(
        conn,
        ~p"/campaigns/#{campaign.id}/questions/#{question_id}/short.mp4?style=gradient_poster"
      )

    if CarouselVideo.available?() do
      assert get_resp_header(conn, "content-type") |> List.first() =~ "video/mp4"
      video = response(conn, 200)
      assert binary_part(video, 4, 4) == "ftyp"
      assert video =~ "soun"
      assert video =~ "mp4a"
    else
      assert response(conn, 503) == "Video rendering requires FFmpeg"
    end
  end

  test "serves styled question quote-card variants", %{conn: conn} do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "brave-new-world")
    question = "If a drug like soma existed today..."
    question_id = ShareCard.question_id(question)

    conn =
      get(
        conn,
        ~p"/campaigns/#{campaign.id}/questions/#{question_id}/share-card.png?style=gradient_poster"
      )

    assert_png_response(conn)
    question_map = ShareCard.find_question(campaign, question_id)
    svg = ShareCard.question_image_svg(campaign, question_map, "gradient_poster")
    assert svg =~ "#2e1065"
    assert svg =~ "#f0abfc"
  end

  test "serves a generated highlight share-card PNG", %{conn: conn} do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "brave-new-world")

    conn = get(conn, ~p"/campaigns/#{campaign.id}/highlights/123/share-card.png")
    assert_png_response(conn)
  end

  test "returns 404 for a missing key-node card", %{conn: conn} do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "brave-new-world")

    conn = get(conn, ~p"/campaigns/#{campaign.id}/nodes/999/share-card.png")

    assert response(conn, 404) == "Key node not found"
  end

  test "returns 404 for a missing question quote card", %{conn: conn} do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "brave-new-world")

    conn = get(conn, ~p"/campaigns/#{campaign.id}/questions/missing-question/share-card.png")

    assert response(conn, 404) == "Question not found"
  end

  test "returns 404 for a missing highlight card", %{conn: conn} do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "brave-new-world")

    conn = get(conn, ~p"/campaigns/#{campaign.id}/highlights/999/share-card.png")

    assert response(conn, 404) == "Highlight not found"
  end

  defp assert_png_response(conn) do
    assert response_content_type(conn, :png) == "image/png; charset=utf-8"
    assert response(conn, 200) |> binary_part(0, 8) == <<137, 80, 78, 71, 13, 10, 26, 10>>
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
