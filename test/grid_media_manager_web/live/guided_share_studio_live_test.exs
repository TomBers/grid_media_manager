defmodule GridMediaManagerWeb.GuidedShareStudioLiveTest do
  use GridMediaManagerWeb.ConnCase

  import Phoenix.LiveViewTest

  alias GridMediaManager.Campaigns

  test "redirects safely when the campaign no longer exists", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, "/campaigns/999999/studio")
  end

  test "surfaces and preselects the recommended conversation starter", %{conn: conn} do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "guided-curation")

    {:ok, view, _html} = live(conn, ~p"/campaigns/#{campaign.id}/studio")

    assert has_element?(view, "#guided-share-studio")
    assert has_element?(view, "#open-post-review[href='/posts/review']", "Review proposed posts")
    assert has_element?(view, "#stage-curate")
    assert has_element?(view, "#studio-progress")
    assert has_element?(view, "#candidate-type-legend", "Longer answers · multi-slide ideas")
    assert has_element?(view, "#content-candidates [id^='select-aspect-question-']")
    assert has_element?(view, "#content-candidates", "chars")
    assert has_element?(view, "#content-candidates", "slide")
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

    assert has_element?(view, "#content-candidates", "Question")
    assert has_element?(view, "#content-candidates", "What evidence would change your mind?")
    assert has_element?(view, "#content-candidates", "Found inside “The case for uncertainty”.")

    view |> element("#continue-to-design") |> render_click()
    view |> element("#continue-to-generate") |> render_click()
    view |> element("#generate-story-package") |> render_click()
    await_generation(view)

    assert Enum.any?(Campaigns.list_media_assets(campaign), &(&1.kind == "curated_carousel"))
  end

  test "steps through curation and design to generate a multi-asset package", %{conn: conn} do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "guided-package")

    assert {:ok, campaign} =
             Campaigns.set_pexels_background(campaign, %{
               id: 42,
               alt: "A calm backdrop",
               photographer: "A photographer",
               photographer_url: "https://www.pexels.com/@photographer",
               pexels_url: "https://www.pexels.com/photo/42",
               portrait_url: "https://images.example/portrait.jpg",
               original_url: "https://images.example/original.jpg"
             })

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
    assert has_element?(view, "#content-mode-video")
    assert has_element?(view, "#content-mode-text")
    assert has_element?(view, "#content-mode-long-form", "Longer post")
    assert has_element?(view, "#pexels-background-picker")

    view
    |> element("#guided-style-warm_paper")
    |> render_click()

    view |> element("#content-mode-text") |> render_click()

    view
    |> element("#continue-to-generate")
    |> render_click()

    assert has_element?(view, "#stage-generate")

    view
    |> element("#generate-story-package")
    |> render_click()

    await_generation(view)

    assert has_element?(view, "#stage-review")
    assert has_element?(view, "#guided-output-assets article")
    assert has_element?(view, "#guided-review-drafts article")

    assets = Campaigns.list_media_assets(campaign)
    assert [%{kind: "curated_carousel", style: "warm_paper"} = carousel] = assets
    assert carousel.metadata["slide_count"] >= 3
    assert List.last(carousel.metadata["slides"])["label"] == "Learn more"
    last_slide = carousel.metadata["slide_count"]
    assert carousel.metadata["selected_slide_indexes"] == Enum.to_list(1..last_slide)
    assert has_element?(view, "#curated-carousel-order-#{carousel.id}")

    assert has_element?(
             view,
             "#curated-carousel-slides-#{carousel.id}[data-cover-image-url='https://images.example/portrait.jpg']"
           )

    view
    |> element("#curated-carousel-slide-#{carousel.id}-2")
    |> render_click()

    assert has_element?(view, "#guided-output-preview-#{carousel.id}")
    assert has_element?(view, "#curated-carousel-slides-#{carousel.id}[data-preview-slide='2']")

    view
    |> element("#move-curated-carousel-slide-down-#{carousel.id}-1")
    |> render_click()

    assert Campaigns.get_media_asset!(carousel.id).metadata["selected_slide_indexes"] ==
             [2, 1] ++ Enum.to_list(3..last_slide)

    assert Enum.any?(
             Campaigns.list_post_drafts(campaign, platform: "x"),
             &(&1.media_asset_id == carousel.id)
           )
  end

  test "selects one longer answer for the long-form post mode", %{conn: conn} do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "guided-long-form")

    {:ok, view, _html} = live(conn, ~p"/campaigns/#{campaign.id}/studio")

    view |> element("#continue-to-design") |> render_click()
    view |> element("#content-mode-long-form") |> render_click()

    assert has_element?(view, "#story-package-default", "Longer post selected")

    view |> element("#continue-to-generate") |> render_click()

    assert has_element?(view, "#generate-platform-summary", "LinkedIn and Facebook")
    assert has_element?(view, "#selected-aspects", "Longer answer")
    assert has_element?(view, "#generate-story-package", "Generate longer post")
  end

  test "combines multiple selected moments into one carousel output", %{conn: conn} do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "guided-combined")

    {:ok, view, _html} = live(conn, ~p"/campaigns/#{campaign.id}/studio")

    view |> element("#select-aspect-highlight-123") |> render_click()
    view |> element("#select-aspect-key-node-1") |> render_click()
    view |> element("#continue-to-design") |> render_click()
    assert has_element?(view, "#content-mode-video")
    view |> element("#content-mode-video") |> render_click()
    view |> element("#continue-to-generate") |> render_click()
    view |> element("#generate-story-package") |> render_click()
    await_generation(view)

    assets = Campaigns.list_media_assets(campaign)
    carousel = Enum.find(assets, &(&1.kind == "curated_carousel"))
    assert carousel
    assert carousel.metadata["slide_count"] >= 4

    assert List.last(carousel.metadata["slides"])["title"] == "Continue on RationalGrid.ai"
  end

  test "restores the generated post screen after a refresh", %{conn: conn} do
    assert {:ok, campaign} =
             Campaigns.import_payload(simplified_payload(), "guided-resume-review")

    {:ok, view, _html} = live(conn, ~p"/campaigns/#{campaign.id}/studio")

    view |> element("#continue-to-design") |> render_click()
    view |> element("#content-mode-text") |> render_click()
    view |> element("#continue-to-generate") |> render_click()
    view |> element("#generate-story-package") |> render_click()
    await_generation(view)

    [asset] = Campaigns.list_media_assets(campaign)

    resume_path =
      ~p"/campaigns/#{campaign.id}/studio?#{[step: "review", assets: Integer.to_string(asset.id), platform: "x,linkedin,facebook", asset: "all"]}"

    assert_patch(view, resume_path)

    batch_id = asset.metadata["generation_batch_id"]
    assert has_element?(view, "#resume-package-#{batch_id}[href='#{resume_path}']")

    {:ok, resumed_view, _html} = live(conn, resume_path)

    assert has_element?(resumed_view, "#stage-review")
    assert has_element?(resumed_view, "#guided-output-#{asset.id}")
    assert has_element?(resumed_view, "#guided-review-drafts article")
    assert has_element?(resumed_view, "#resume-package-#{batch_id}")
  end

  test "edits and approves associated copy during review", %{conn: conn} do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "guided-review")

    {:ok, view, _html} = live(conn, ~p"/campaigns/#{campaign.id}/studio")

    view |> element("#continue-to-design") |> render_click()
    view |> element("#content-mode-text") |> render_click()
    view |> element("#continue-to-generate") |> render_click()
    view |> element("#generate-story-package") |> render_click()
    await_generation(view)

    [asset] = Campaigns.list_media_assets(campaign)

    [draft] =
      Campaigns.list_post_drafts(campaign,
        platform: "x",
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

  defp await_generation(view, attempts \\ 300)

  defp await_generation(_view, 0), do: flunk("timed out waiting for package generation")

  defp await_generation(view, attempts) do
    if has_element?(view, "#stage-review") or has_element?(view, "#generation-error") do
      :ok
    else
      Process.sleep(100)
      await_generation(view, attempts - 1)
    end
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
