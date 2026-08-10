defmodule GridMediaManagerWeb.GuidedShareStudioLiveTest do
  use GridMediaManagerWeb.ConnCase

  import Phoenix.LiveViewTest

  alias GridMediaManager.Campaigns
  alias GridMediaManager.Studio.Workflow

  test "redirects safely when the campaign no longer exists", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, "/campaigns/999999/studio")
  end

  test "surfaces the recommended conversation starter without selecting it", %{conn: conn} do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "guided-curation")

    {:ok, view, _html} = live(conn, ~p"/campaigns/#{campaign.id}/studio")

    assert has_element?(view, "#guided-share-studio")
    refute has_element?(view, "#previous-outputs")
    assert has_element?(view, "#stage-curate")
    assert has_element?(view, "#studio-progress")
    assert has_element?(view, "#content-candidates [id^='select-aspect-question-']")
    assert has_element?(view, "#content-candidates", "Story thread")
    assert has_element?(view, "#content-candidates", "Best opener")
    assert has_element?(view, "#story-queue", "0 of 6 moments selected")
    refute has_element?(view, "#selected-aspects", "If a drug like soma existed today...")
    assert has_element?(view, "#continue-to-design[disabled]")

    select_recommended_question(view, campaign)

    assert has_element?(view, "#selected-aspects", "If a drug like soma existed today...")
    assert has_element?(view, "#continue-to-design:not([disabled])")

    view |> element("#candidate-filter-selected") |> render_click()

    assert has_element?(view, "#content-candidates [id^='select-aspect-question-']")
    refute has_element?(view, "#select-aspect-highlight-123")
  end

  test "labels questions extracted from answer bodies with their source", %{conn: conn} do
    assert {:ok, campaign} =
             Campaigns.import_payload(answer_question_payload(), "guided-answer-questions")

    {:ok, view, _html} = live(conn, ~p"/campaigns/#{campaign.id}/studio")

    assert has_element?(view, "#content-candidates", "Question")
    assert has_element?(view, "#content-candidates", "What evidence would change your mind?")
    assert has_element?(view, "#content-candidates", "Found inside “The case for uncertainty”.")

    select_recommended_question(view, campaign)
    view |> element("#continue-to-design") |> render_click()
    view |> element("#create-story-package") |> render_click()
    await_generation(view)

    assert Enum.any?(Campaigns.list_media_assets(campaign), &(&1.kind == "curated_carousel"))
  end

  test "orders signals as question and answer threads using the node stream", %{conn: conn} do
    assert {:ok, campaign} =
             Campaigns.import_payload(cognitive_order_payload(), "guided-cognitive-order")

    assert {:ok, campaign} =
             Campaigns.save_guided_studio_state(campaign, %{
               "selected_keys" => ["key_node:3"]
             })

    {:ok, view, _html} = live(conn, ~p"/campaigns/#{campaign.id}/studio")

    assert has_element?(view, "#candidate-group-node-1 + #candidate-group-node-3")
    assert has_element?(view, "#candidate-group-node-1", "Story thread 1")
    assert has_element?(view, "#candidate-group-node-3", "Story thread 2")

    assert has_element?(
             view,
             "#candidate-group-node-3 [href='#candidate-group-node-1']",
             "Continues from Story thread 1"
           )

    assert has_element?(
             view,
             "#candidate-group-node-1",
             "Origin question"
           )

    assert has_element?(
             view,
             "#candidate-group-node-1 article:nth-of-type(1)#candidate-key-node-2",
             "Answer"
           )

    assert has_element?(
             view,
             "#candidate-group-node-3 [id^='select-aspect-question-']"
           )

    assert has_element?(
             view,
             "#candidate-group-node-3 article:nth-of-type(1)#candidate-key-node-4",
             "Answer"
           )

    assert has_element?(
             view,
             "#candidate-group-node-3 article:nth-of-type(2)#candidate-highlight-41",
             "Highlight"
           )

    refute has_element?(view, "#candidate-key-node-3")
    assert has_element?(view, "#story-queue", "1 of 6 moments selected")

    assert has_element?(view, "#thread-body-node-3")
    view |> element("#toggle-thread-control-node-3") |> render_click()
    refute has_element?(view, "#thread-body-node-3")
    assert has_element?(view, "#toggle-thread-control-node-3[aria-label='Expand Story thread 2']")
    view |> element("#toggle-thread-control-node-3") |> render_click()
    assert has_element?(view, "#thread-body-node-3")

    view |> element("#candidate-filter-with_highlights") |> render_click()
    refute has_element?(view, "#candidate-group-node-1")
    assert has_element?(view, "#candidate-group-node-3", "What evidence would change")
    assert has_element?(view, "#candidate-key-node-4")
    assert has_element?(view, "#candidate-highlight-41")
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

    select_recommended_question(view, campaign)

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
    assert has_element?(view, "#content-mode-long-form", "Long post")
    assert has_element?(view, "#pexels-background-picker")
    assert has_element?(view, "#package-brief")
    assert has_element?(view, "#studio-progress > li:nth-child(3)")
    refute has_element?(view, "#studio-progress > li:nth-child(4)")
    refute has_element?(view, "#progress-step-generate")
    assert has_element?(view, "#guided-style-picker > button:nth-child(6)")
    refute has_element?(view, "#guided-style-picker > button:nth-child(7)")

    view |> element("#back-to-curate") |> render_click()

    assert has_element?(view, "#stage-curate")
    assert has_element?(view, "#content-candidates [id^='select-aspect-']")
    assert has_element?(view, "#story-queue", "3 of 6 moments selected")

    view |> element("#continue-to-design") |> render_click()

    assert has_element?(view, "#stage-design")
    assert has_element?(view, "#package-brief", "3 story moments")

    view |> element("#content-mode-long-form") |> render_click()

    assert has_element?(
             view,
             "#package-brief",
             "3 selected moments become one editable text post"
           )

    view |> element("#back-to-curate") |> render_click()
    assert has_element?(view, "#content-candidates [id^='select-aspect-question-']")
    assert has_element?(view, "#story-queue", "3 of 6 moments selected")

    view |> element("#continue-to-design") |> render_click()
    view |> element("#content-mode-video") |> render_click()
    assert has_element?(view, "#package-brief", "3 story moments")

    view
    |> element("#guided-style-warm_paper")
    |> render_click()

    view |> element("#content-mode-text") |> render_click()

    view
    |> element("#create-story-package")
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

    assert Enum.at(carousel.metadata["slides"], 1)["kind"] in ["quote", "highlight"]
    assert has_element?(view, "#guided-output-preview-#{carousel.id}")
    assert has_element?(view, "#curated-carousel-slides-#{carousel.id}[data-preview-slide='2']")
    assert has_element?(view, "#asset-slide-form-#{carousel.id}-2", "Main text")
    refute has_element?(view, "#asset-slide-body-#{carousel.id}-2")

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

  test "turns selected questions, answers, and highlights into one long-form post", %{conn: conn} do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "guided-long-form")

    {:ok, view, _html} = live(conn, ~p"/campaigns/#{campaign.id}/studio")

    select_recommended_question(view, campaign)
    view |> element("#select-aspect-highlight-123") |> render_click()
    view |> element("#select-aspect-key-node-1") |> render_click()
    view |> element("#continue-to-design") |> render_click()
    view |> element("#content-mode-long-form") |> render_click()

    assert has_element?(view, "#content-mode-long-form", "Long post")

    assert has_element?(view, "#design-platform-summary", "LinkedIn and Facebook")

    assert has_element?(
             view,
             "#package-brief",
             "3 selected moments become one editable text post"
           )

    assert has_element?(view, "#create-story-package", "Create post")

    view |> element("#create-story-package") |> render_click()
    await_generation(view)

    asset =
      campaign
      |> Campaigns.list_media_assets()
      |> Enum.find(&(&1.kind == "long_form_post"))

    assert asset
    assert asset.text =~ "If a drug like soma existed today"
    assert asset.text =~ "Perfect comfort can become a cage."
    assert asset.text =~ "Long answer"

    assert Enum.map(asset.metadata["sources"], & &1["type"]) == [
             "question",
             "highlight",
             "key_node"
           ]

    assert has_element?(view, "#curated-carousel-slides-#{asset.id}[data-auto-save='true']")
  end

  test "combines multiple selected moments into one carousel output", %{conn: conn} do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "guided-combined")

    {:ok, view, _html} = live(conn, ~p"/campaigns/#{campaign.id}/studio")

    select_recommended_question(view, campaign)
    view |> element("#select-aspect-highlight-123") |> render_click()
    view |> element("#select-aspect-key-node-1") |> render_click()
    view |> element("#continue-to-design") |> render_click()
    assert has_element?(view, "#content-mode-video")
    view |> element("#content-mode-video") |> render_click()
    view |> element("#create-story-package") |> render_click()
    await_generation(view)

    assets = Campaigns.list_media_assets(campaign)
    carousel = Enum.find(assets, &(&1.kind == "curated_carousel"))
    assert carousel
    assert carousel.metadata["slide_count"] >= 4

    assert List.last(carousel.metadata["slides"])["title"] == "Continue on RationalGrid.ai"
  end

  test "creates video and image outputs together from one design", %{conn: conn} do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "guided-bundle")

    {:ok, view, _html} = live(conn, ~p"/campaigns/#{campaign.id}/studio")

    select_recommended_question(view, campaign)
    view |> element("#select-aspect-highlight-123") |> render_click()
    view |> element("#continue-to-design") |> render_click()

    assert has_element?(view, "#content-mode-bundle", "Video + carousel")
    view |> element("#content-mode-bundle") |> render_click()

    assert has_element?(view, "#design-platform-summary", "Text cards will be posted")
    assert has_element?(view, "#create-story-package", "Create both")

    view |> element("#create-story-package") |> render_click()
    await_generation(view)

    assets = Campaigns.list_media_assets(campaign)
    carousel = Enum.find(assets, &(&1.kind == "curated_carousel"))
    video = Enum.find(assets, &(&1.kind == "curated_carousel_video"))
    assert carousel
    assert video
    assert has_element?(view, "#guided-output-assets article:nth-child(2)")
    assert has_element?(view, "#curated-carousel-slides-#{carousel.id}[data-auto-save='true']")
    assert has_element?(view, "#curated-carousel-slides-#{video.id}[data-auto-save='true']")
    assert has_element?(view, "#guided-bulk-schedule-form", "Publish text and video posts")
    assert has_element?(view, "#guided-platform-summary", "Text cards will be posted")
    refute has_element?(view, "#create-companion-carousel")

    drafts = Campaigns.list_post_drafts(campaign)

    assert Enum.all?(
             Enum.filter(drafts, &(&1.platform in ["x", "linkedin", "facebook"])),
             &(&1.media_asset_id == carousel.id)
           )

    assert Enum.all?(
             Enum.filter(drafts, &(&1.platform in ["tiktok", "instagram", "youtube"])),
             &(&1.media_asset_id == video.id)
           )
  end

  test "creates an image carousel directly from video review", %{conn: conn} do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "guided-companion")

    {:ok, view, _html} = live(conn, ~p"/campaigns/#{campaign.id}/studio")

    select_recommended_question(view, campaign)
    view |> element("#continue-to-design") |> render_click()
    view |> element("#content-mode-video") |> render_click()
    view |> element("#create-story-package") |> render_click()
    await_generation(view)

    hidden_carousel =
      Campaigns.list_media_assets(campaign) |> Enum.find(&(&1.kind == "curated_carousel"))

    assert hidden_carousel

    refute Enum.any?(
             Campaigns.list_post_drafts(campaign),
             &(&1.media_asset_id == hidden_carousel.id)
           )

    assert has_element?(view, "#create-companion-carousel", "Create image carousel")
    view |> element("#create-companion-carousel") |> render_click()
    render_async(view, 30_000)

    carousel =
      Campaigns.list_media_assets(campaign) |> Enum.find(&(&1.kind == "curated_carousel"))

    assert carousel

    assert Enum.any?(
             Campaigns.list_post_drafts(campaign),
             &(&1.media_asset_id == carousel.id and &1.platform in ["x", "linkedin", "facebook"])
           )

    assert has_element?(view, "#guided-output-#{carousel.id}")
    refute has_element?(view, "#create-companion-carousel")
  end

  test "restores the current generated post screen after a refresh", %{conn: conn} do
    assert {:ok, campaign} =
             Campaigns.import_payload(simplified_payload(), "guided-resume-review")

    {:ok, view, _html} = live(conn, ~p"/campaigns/#{campaign.id}/studio")

    select_recommended_question(view, campaign)
    view |> element("#continue-to-design") |> render_click()
    view |> element("#content-mode-text") |> render_click()
    view |> element("#create-story-package") |> render_click()
    await_generation(view)

    [asset] = Campaigns.list_media_assets(campaign)

    resume_path =
      ~p"/campaigns/#{campaign.id}/studio?#{[step: "review", assets: Integer.to_string(asset.id), platform: "x,linkedin,facebook", asset: "all"]}"

    assert_patch(view, resume_path)

    {:ok, resumed_view, _html} = live(conn, resume_path)

    assert has_element?(resumed_view, "#stage-review")
    assert has_element?(resumed_view, "#guided-output-#{asset.id}")
    assert has_element?(resumed_view, "#guided-review-drafts article")
    resumed_view |> element("#revise-package") |> render_click()
    assert has_element?(resumed_view, "#stage-design")
    assert has_element?(resumed_view, "#package-brief", "story moment")

    resumed_view |> element("#progress-step-review") |> render_click()
    assert has_element?(resumed_view, "#guided-output-#{asset.id}")
    assert has_element?(resumed_view, "#guided-review-drafts article")
  end

  test "review restores scheduling channels from its assets instead of stale design state", %{
    conn: conn
  } do
    assert {:ok, campaign} =
             Campaigns.import_payload(simplified_payload(), "guided-review-platforms")

    {:ok, view, _html} = live(conn, ~p"/campaigns/#{campaign.id}/studio")

    select_recommended_question(view, campaign)
    view |> element("#continue-to-design") |> render_click()
    view |> element("#content-mode-video") |> render_click()
    view |> element("#create-story-package") |> render_click()
    await_generation(view)

    video = Campaigns.list_media_assets(campaign) |> Enum.find(&(&1.mime_type == "video/mp4"))
    assert video

    assert {:ok, _campaign} =
             Campaigns.save_guided_studio_state(campaign, %{
               "content_mode" => "long_form",
               "selected_format" => "long_form",
               "selected_platforms" => ["linkedin", "facebook"]
             })

    review_path =
      ~p"/campaigns/#{campaign.id}/studio?#{[step: "review", assets: Integer.to_string(video.id), platform: "tiktok,youtube,instagram", asset: "all"]}"

    {:ok, resumed_view, _html} = live(conn, review_path)

    assert has_element?(
             resumed_view,
             "#guided-platform-summary",
             "The video will be posted to TikTok, Instagram, and YouTube"
           )

    assert has_element?(
             resumed_view,
             "#guided-bulk-schedule-form",
             "Publish TikTok, Instagram, and YouTube posts at (UTC)"
           )

    assert has_element?(resumed_view, "#guided-review-drafts article")
    refute has_element?(resumed_view, "#empty-guided-review-drafts:only-child")
  end

  test "edits and approves associated copy during review", %{conn: conn} do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "guided-review")

    {:ok, view, _html} = live(conn, ~p"/campaigns/#{campaign.id}/studio")

    select_recommended_question(view, campaign)
    view |> element("#continue-to-design") |> render_click()
    view |> element("#content-mode-text") |> render_click()
    view |> element("#create-story-package") |> render_click()
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

  defp cognitive_order_payload do
    %{
      "metadata" => %{
        "title" => "How does a line of reasoning develop?",
        "slug" => "line-of-reasoning-guided",
        "url" => "https://rationalgrid.ai/g/line-of-reasoning-guided",
        "node_count" => 4,
        "tags" => ["Reasoning"]
      },
      "graph" => %{
        "nodes" => [
          %{
            "id" => "4",
            "class" => "answer",
            "content" => "# A second answer\n\nThe evidence changes the conclusion."
          },
          %{
            "id" => "1",
            "class" => "origin",
            "content" => "How does a line of reasoning develop?"
          },
          %{
            "id" => "3",
            "class" => "question",
            "content" => "What evidence would change the conclusion?"
          },
          %{
            "id" => "2",
            "class" => "answer",
            "content" =>
              "# A first answer\n\nStart with the assumptions. What evidence would change the conclusion?"
          }
        ],
        "edges" => [
          %{"data" => %{"id" => "34", "source" => "3", "target" => "4"}},
          %{"data" => %{"id" => "23", "source" => "2", "target" => "3"}},
          %{"data" => %{"id" => "12", "source" => "1", "target" => "2"}}
        ]
      },
      "highlights" => [
        %{
          "id" => 41,
          "node_id" => "4",
          "text" => "The evidence changes the conclusion.",
          "note" => "The key turn in the reasoning."
        }
      ]
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

  defp select_recommended_question(view, campaign) do
    candidate = Enum.find(Workflow.candidates(campaign), & &1.recommended?)
    view |> element("#select-aspect-#{candidate.dom_id}") |> render_click()
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
