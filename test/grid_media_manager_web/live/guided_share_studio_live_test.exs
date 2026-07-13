defmodule GridMediaManagerWeb.GuidedShareStudioLiveTest do
  use GridMediaManagerWeb.ConnCase

  import Phoenix.LiveViewTest

  alias GridMediaManager.Campaigns

  test "surfaces and preselects the recommended conversation starter", %{conn: conn} do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "guided-curation")

    {:ok, view, _html} = live(conn, ~p"/campaigns/#{campaign.id}/studio")

    assert has_element?(view, "#guided-share-studio")
    assert has_element?(view, "#stage-curate")
    assert has_element?(view, "#studio-progress")
    assert has_element?(view, "#content-candidates [id^='select-aspect-question-']")
    assert has_element?(view, "#selected-aspects", "If a drug like soma existed today...")
    assert has_element?(view, "#continue-to-design:not([disabled])")

    view
    |> element("#candidate-filter-highlight")
    |> render_click()

    assert has_element?(view, "#select-aspect-highlight-123")
    refute has_element?(view, "#content-candidates [id^='select-aspect-question-']")
  end

  test "labels questions extracted from answer bodies with their source", %{conn: conn} do
    assert {:ok, campaign} =
             Campaigns.import_payload(answer_question_payload(), "guided-answer-questions")

    {:ok, view, _html} = live(conn, ~p"/campaigns/#{campaign.id}/studio")

    assert has_element?(view, "#content-candidates", "Answer question")
    assert has_element?(view, "#content-candidates", "What evidence would change your mind?")
    assert has_element?(view, "#content-candidates", "Found inside “The case for uncertainty”.")

    view |> element("#continue-to-design") |> render_click()
    view |> element("#continue-to-generate") |> render_click()
    view |> element("#generate-story-package") |> render_click()

    assert Enum.any?(Campaigns.list_media_assets(campaign), fn asset ->
             asset.kind == "question_quote_card" and asset.node_id == "answer-1"
           end)
  end

  test "steps through curation and design to generate a multi-asset package", %{conn: conn} do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "guided-package")

    {:ok, view, _html} = live(conn, ~p"/campaigns/#{campaign.id}/studio")

    view
    |> element("#select-aspect-highlight-123")
    |> render_click()

    view
    |> element("#select-aspect-key-node-1")
    |> render_click()

    view
    |> element("#continue-to-design")
    |> render_click()

    assert has_element?(view, "#stage-design")
    assert has_element?(view, "#guided-style-minimal_light", "Minimal light")
    assert has_element?(view, "#guided-style-minimal_dark", "Minimal dark")
    assert has_element?(view, "#guided-format-linkedin", "LinkedIn explainer")
    assert has_element?(view, "#guided-format-portrait", "Instagram portrait")
    assert has_element?(view, "#guided-format-carousel", "Instagram carousel + Shorts")

    view
    |> element("#guided-style-warm_paper")
    |> render_click()

    view
    |> element("#guided-format-portrait")
    |> render_click()

    view
    |> element("#continue-to-generate")
    |> render_click()

    assert has_element?(view, "#stage-generate")

    view
    |> element("#generate-story-package")
    |> render_click()

    assert has_element?(view, "#stage-review")
    assert has_element?(view, "#guided-platform-youtube")
    assert has_element?(view, "#guided-output-assets article")
    assert has_element?(view, "#guided-review-drafts article")

    assets = Campaigns.list_media_assets(campaign)
    assert length(assets) == 3
    assert length(Campaigns.list_post_drafts(campaign, platform: "linkedin")) == 3
    assert length(Campaigns.list_post_drafts(campaign, platform: "instagram")) == 6

    assert Enum.any?(assets, &(&1.kind == "question_quote_card" and &1.style == "warm_paper"))
    assert Enum.any?(assets, &(&1.kind == "highlight_card" and &1.style == "warm_paper"))

    assert Enum.any?(assets, fn asset ->
             asset.kind == "key_node_card" and asset.style == "warm_paper" and
               asset.metadata["format"] == "portrait"
           end)
  end

  test "edits and approves associated copy during review", %{conn: conn} do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "guided-review")

    {:ok, view, _html} = live(conn, ~p"/campaigns/#{campaign.id}/studio")

    view |> element("#continue-to-design") |> render_click()
    view |> element("#continue-to-generate") |> render_click()
    view |> element("#generate-story-package") |> render_click()

    [asset] = Campaigns.list_media_assets(campaign)

    [draft] =
      Campaigns.list_post_drafts(campaign,
        platform: "linkedin",
        media_asset_id: asset.id
      )

    view
    |> form("#guided-draft-form-#{draft.id}",
      post_draft: %{body: "A sharper invitation to join the conversation."}
    )
    |> render_change()

    assert Campaigns.get_post_draft!(draft.id).body ==
             "A sharper invitation to join the conversation."

    view
    |> element("#guided-approve-draft-#{draft.id}")
    |> render_click()

    assert Campaigns.get_post_draft!(draft.id).status == "approved"
    assert has_element?(view, "#guided-draft-#{draft.id}", "Approved")
  end

  defp answer_question_payload do
    %{
      "metadata" => %{
        "title" => "How should we reason under uncertainty?",
        "slug" => "reason-under-uncertainty-guided",
        "url" => "https://rationalgrid.ai/g/reason-under-uncertainty-guided",
        "node_count" => 2,
        "tags" => ["Reasoning"]
      },
      "graph" => %{
        "nodes" => [
          %{
            "id" => "origin-1",
            "class" => "origin",
            "content" => "How should we reason under uncertainty?"
          },
          %{
            "id" => "answer-1",
            "class" => "answer",
            "title" => "The case for uncertainty",
            "content" =>
              "Certainty can hide weak assumptions. What evidence would change your mind? Which belief carries the greatest downside if it is wrong?"
          }
        ],
        "edges" => []
      },
      "highlights" => []
    }
  end

  defp simplified_payload do
    %{
      "grid" => %{
        "title" => "What can a brave new world teach us?",
        "slug" => "what-can-a-brave-new-world-teach-us-guided",
        "url" => "https://rationalgrid.ai/g/what-can-a-brave-new-world-teach-us-guided",
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
            "note" => "A useful tension for discussion."
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
