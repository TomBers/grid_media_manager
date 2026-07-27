defmodule GridMediaManager.CampaignsTest do
  use GridMediaManager.DataCase, async: true

  alias GridMediaManager.Campaigns
  alias GridMediaManager.Promotion.CarouselVideo
  alias GridMediaManager.Promotion.ShareCard
  alias GridMediaManager.Promotion.SlideSequence
  alias GridMediaManager.RationalGrid.MediaPayload
  alias GridMediaManager.Social.Platforms
  alias GridMediaManager.Studio.Workflow

  test "exposes distinct style presets for different editorial moods" do
    styles = ShareCard.styles()
    ids = Enum.map(styles, & &1.id)

    assert Enum.all?(
             ["minimal_light", "minimal_dark", "signal_red", "deep_ocean", "newsprint"],
             &(&1 in ids)
           )

    assert length(ids) == length(Enum.uniq(ids))
    assert ShareCard.normalize_style("newsprint") == "newsprint"

    assert Enum.count(styles, &(&1.category == "Foundation")) == 2
    assert Enum.count(styles, &(&1.category == "Social")) == 7
  end

  test "returns a generation error instead of crashing for a deleted campaign" do
    campaign = %GridMediaManager.Campaigns.Campaign{id: -1}
    candidate = %{title: "A stale selection"}

    assert %{assets: [], errors: [%{candidate: ^candidate, reason: :campaign_not_found}]} =
             Workflow.generate(campaign, [candidate], format: "story_video")
  end

  test "keeps the source carousel when generating a story video" do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "kept-story-carousel")

    candidates =
      campaign
      |> Workflow.candidates()
      |> Enum.filter(&(&1.type in ["question", "highlight", "key_node"]))
      |> Enum.take(2)

    _result = Workflow.generate(campaign, candidates, format: "story_video")

    assets = Campaigns.list_media_assets(campaign)
    assert [%{id: carousel_id}] = Enum.filter(assets, &(&1.kind == "curated_carousel"))
    assert Campaigns.list_post_drafts(campaign, media_asset_id: carousel_id) == []
  end

  test "keeps previous generated carousel variants" do
    assert {:ok, campaign} =
             Campaigns.import_payload(simplified_payload(), "kept-carousel-variants")

    candidates =
      campaign
      |> Workflow.candidates()
      |> Enum.filter(&(&1.type in ["question", "highlight", "key_node"]))
      |> Enum.take(2)

    assert {:ok, first} =
             Campaigns.generate_curated_carousel(campaign, candidates, "editorial_dark")

    assert {:ok, second} =
             Campaigns.generate_curated_carousel(
               campaign,
               Enum.reverse(candidates),
               "editorial_dark"
             )

    assert first.id != second.id

    assert Enum.all?(
             [first.id, second.id],
             &Enum.any?(Campaigns.list_media_assets(campaign), fn asset -> asset.id == &1 end)
           )
  end

  test "generates text mode as an ordered carousel with a final CTA" do
    assert {:ok, campaign} =
             Campaigns.import_payload(simplified_payload(), "text-carousel-package")

    candidate =
      campaign
      |> Workflow.candidates()
      |> Enum.find(&(&1.type == "key_node"))

    result =
      Workflow.generate(campaign, [candidate],
        style: "editorial_dark",
        format: "portrait"
      )

    assert result.errors == []
    assert [%{kind: "curated_carousel"} = carousel] = result.assets
    assert carousel.metadata["slide_count"] >= 3

    assert List.last(carousel.metadata["slides"]) == %{
             "body" => "",
             "kind" => "cta",
             "label" => "Learn more",
             "title" => "Continue on RationalGrid.ai"
           }

    text_slide = %{"body" => "Readable body copy", "label" => "", "title" => ""}
    text_svg = ShareCard.curated_carousel_image_svg(campaign, [text_slide], "editorial_dark", 1)

    assert text_svg =~ "Readable"
    assert text_svg =~ "body copy"
    refute text_svg =~ "data:image/png;base64"
  end

  test "scales node text to the available reading area" do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "adaptive-node-text")

    short_slide = %{"kind" => "node_text", "title" => "", "body" => "A short, clear explanation."}

    long_slide = %{
      "kind" => "node_text",
      "title" => "",
      "body" =>
        String.duplicate(
          "A meaningful sentence explains the claim clearly and gives the reader useful context. ",
          8
        )
    }

    short_svg =
      ShareCard.curated_carousel_image_svg(campaign, [short_slide], "editorial_dark", 1)

    long_svg =
      ShareCard.curated_carousel_image_svg(campaign, [long_slide], "editorial_dark", 1)

    assert short_svg =~ ~s(font-size="136")
    refute long_svg =~ ~s(font-size="136")
  end

  test "limits carousel publishing to three ordered images with the CTA last" do
    slides = [
      %{"title" => "Opening", "body" => ""},
      %{"title" => "Second", "body" => ""},
      %{"title" => "Third", "body" => ""},
      %{"title" => "Fourth", "body" => ""},
      %{"label" => "Learn more", "title" => "Continue on RationalGrid.ai", "body" => ""}
    ]

    assert ShareCard.curated_carousel_selected_slide_indexes(slides) == [1, 2, 5]
    assert ShareCard.curated_carousel_selected_slide_indexes(slides, [4, 2, 1, 5]) == [4, 2, 5]

    assert ShareCard.curated_carousel_selected_slides(slides, [3, 1, 5]) ==
             [Enum.at(slides, 2), Enum.at(slides, 0), Enum.at(slides, 4)]
  end

  test "keeps every carousel frame in video metadata by default" do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "video-selection")

    slides = [
      %{"title" => "Opening", "body" => ""},
      %{"title" => "Second", "body" => ""},
      %{"title" => "Third", "body" => ""},
      %{"title" => "Fourth", "body" => ""},
      %{"label" => "Learn more", "title" => "Continue on RationalGrid.ai", "body" => ""}
    ]

    attrs = CarouselVideo.curated_asset_attr(campaign, "video-token", slides, "editorial_dark")

    assert attrs.metadata["slide_count"] == 5
    assert attrs.metadata["duration_seconds"] > 0
    refute Map.has_key?(attrs.metadata, "selected_slide_indexes")
    assert attrs.url =~ "v=18"
  end

  test "stores browser-rendered carousel frames for the selected slide" do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "browser-frame-store")

    candidates = Workflow.candidates(campaign) |> Enum.take(1)

    assert {:ok, asset} =
             Campaigns.generate_curated_carousel(campaign, candidates, "editorial_dark")

    png = <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 0>>

    assert {:ok, _updated_asset} =
             Campaigns.store_curated_carousel_browser_frame(
               campaign,
               asset.source_id,
               2,
               png
             )

    stored_asset = Campaigns.get_media_asset!(asset.id)
    path = get_in(stored_asset.metadata, ["browser_frame_paths", "2"])

    assert is_binary(path)
    assert File.read!(path) == png
    on_exit(fn -> File.rm(path) end)
  end

  test "combines persisted browser frames into the curated video" do
    if CarouselVideo.available?() do
      assert {:ok, campaign} =
               Campaigns.import_payload(simplified_payload(), "video-browser-frames")

      slides = [
        %{"kind" => "cover", "title" => "Opening", "body" => ""},
        %{"kind" => "node_text", "title" => "Frame two", "body" => ""},
        %{"kind" => "cta", "label" => "Learn more", "title" => "Continue", "body" => ""}
      ]

      frame =
        Base.decode64!(
          "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        )

      frame_directory =
        Path.join(
          System.tmp_dir!(),
          "grid-media-manager-test-frames-#{System.unique_integer([:positive])}"
        )

      File.mkdir_p!(frame_directory)

      frame_paths =
        for index <- 1..length(slides), into: %{} do
          path = Path.join(frame_directory, "#{campaign.id}-#{index}.png")
          File.write!(path, frame)
          {Integer.to_string(index), path}
        end

      on_exit(fn -> File.rm_rf(frame_directory) end)

      assert {:ok, video_path} =
               CarouselVideo.render_curated(
                 campaign,
                 "browser-frame-video",
                 slides,
                 "editorial_dark",
                 frame_paths: frame_paths,
                 force: true
               )

      assert File.stat!(video_path).size > 0
    end
  end

  test "builds one typed sequence for highlights and full nodes" do
    assert {:ok, campaign} =
             Campaigns.import_payload(simplified_payload(), "typed-slide-sequence")

    candidates =
      Workflow.candidates(campaign)
      |> Enum.filter(&(&1.type in ["highlight", "key_node"]))
      |> Enum.take(2)

    slides = SlideSequence.build(campaign, candidates)

    assert hd(slides)["kind"] == "cover"
    assert List.last(slides)["kind"] == "cta"
    assert Enum.any?(slides, &(&1["kind"] == "highlight"))
    assert Enum.any?(slides, &(&1["kind"] == "node_text"))
    assert Enum.all?(slides, &is_binary(&1["body"]))
  end

  test "renders full titles and quotes without top-right format labels" do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "full-card-copy")

    long_question =
      "How should a society preserve freedom when comfort, safety, convenience, and certainty all make surrendering agency feel reasonable?"

    question = %{"question" => long_question, "kind" => "follow_up_question"}

    question_svg =
      ShareCard.question_platform_image_svg(campaign, question, "minimal_dark", "linkedin")

    assert question_svg =~ "surrendering agency feel reasonable?"
    refute question_svg =~ "…"
    refute question_svg =~ "LINKEDIN ·"

    long_title =
      "A complete node title about freedom, comfort, responsibility, technology, and the difficult work of retaining human agency"

    node = %{"id" => "long-node", "title" => long_title, "content" => "A complete explanation."}
    node_svg = ShareCard.node_linkedin_image_svg(campaign, node, "minimal_dark")

    assert node_svg =~ "difficult work of retaining"
    assert node_svg =~ "human agency"
    refute node_svg =~ "LINKEDIN ·"

    carousel_svg = ShareCard.node_carousel_image_svg(campaign, node, "minimal_dark", 1)
    refute carousel_svg =~ ">Thesis</text>"
  end

  test "persists and clears a Pexels background with attribution" do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "pexels-background")

    photo = %{
      id: 42,
      alt: "A mountain view",
      photographer: "Ada Example",
      photographer_url: "https://www.pexels.com/@ada-example",
      pexels_url: "https://www.pexels.com/photo/42",
      avg_color: "#334155",
      landscape_url: "https://images.pexels.com/photos/42/landscape.jpeg",
      portrait_url: "https://images.pexels.com/photos/42/portrait.jpeg",
      original_url: "https://images.pexels.com/photos/42/original.jpeg",
      preview_url: "https://images.pexels.com/photos/42/preview.jpeg"
    }

    assert {:ok, campaign} = Campaigns.set_pexels_background(campaign, photo)
    background = Campaigns.pexels_background(campaign)

    assert background["id"] == 42
    assert background["photographer"] == "Ada Example"
    assert background["pexels_url"] == "https://www.pexels.com/photo/42"
    refute Map.has_key?(background, "preview_url")

    assert {:ok, campaign} = Campaigns.clear_pexels_background(campaign)
    assert Campaigns.pexels_background(campaign) == nil
  end

  test "renders Markdown structure in key-node media" do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "markdown-media")

    node = %{
      "id" => "markdown-node",
      "class" => "answer",
      "title" => "A structured answer",
      "content" => """
      # A structured answer

      An opening paragraph with **important language** and a [useful source](https://example.com).

      ## The Shared Blueprint

      > A claim worth examining closely.

      - **The Hero:** A recurring pattern.
      - The Shadow: what remains hidden.
      """
    }

    svg = ShareCard.node_linkedin_image_svg(campaign, node, "minimal_light")

    assert svg =~ "The Shared Blueprint"
    assert svg =~ "font-style=\"italic\""
    assert svg =~ "•  The Hero:"
    assert svg =~ "important language"
    assert svg =~ "useful source"
    refute svg =~ "**"
    refute svg =~ "https://example.com"

    slides = ShareCard.carousel_slides(campaign, node)
    assert Enum.any?(slides, &(&1.title == "The Shared Blueprint"))
    assert Enum.any?(slides, &String.contains?(&1.body, "• The Hero:"))
  end

  describe "import_payload/2" do
    test "repairs invalid Windows-1252 bytes before scoring questions" do
      malformed_question = "What should we protect" <> <<0x94>> <> "?"

      payload = %{
        "metadata" => %{
          "title" => "A malformed legacy grid",
          "slug" => "malformed-legacy-grid",
          "url" => "https://rationalgrid.ai/g/malformed-legacy-grid"
        },
        "content" => %{"follow_up_questions" => [malformed_question]}
      }

      assert {:ok, campaign} = Campaigns.import_payload(payload, "malformed-legacy-grid")
      assert Campaigns.recommended_question(campaign) == "What should we protect”?"
      assert String.valid?(campaign.raw_payload["content"]["follow_up_questions"] |> List.first())
    end

    test "rejects URL fragments when extracting follow-up questions" do
      payload = %{
        "content" => %{
          "follow_up_questions" => [
            "com/search?",
            "Would comfort make freedom less valuable?"
          ]
        }
      }

      assert MediaPayload.follow_up_questions(payload) == [
               "Would comfort make freedom less valuable?"
             ]
    end

    test "creates a campaign, media assets, and deterministic drafts" do
      payload = sample_payload()

      assert {:ok, campaign} = Campaigns.import_payload(payload, "res.json")
      assert campaign.slug == "what-is-the-collective-subconscious-637e9a"
      assert campaign.title == "What is the collective subconscious?"

      assets = Campaigns.list_media_assets(campaign)
      drafts = Campaigns.list_post_drafts(campaign)

      assert length(assets) == 7
      assert length(drafts) > 20
      assert Enum.any?(drafts, &(&1.platform == "linkedin" and &1.angle == "explainer"))

      assert Enum.any?(
               assets,
               &(&1.kind == "highlight_card" and &1.text == "collective unconscious")
             )
    end

    test "approves a draft for the publishing queue" do
      assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "approval-test")

      [draft | _] =
        Campaigns.list_post_drafts(campaign, platform: "x", media_asset_id: "campaign")

      assert {:ok, approved} = Campaigns.approve_post_draft(draft.id)
      assert approved.status == "approved"
    end

    test "imports the simplified content payload without pre-rendered assets" do
      payload = simplified_payload()

      assert {:ok, campaign} =
               Campaigns.import_payload(payload, "what-can-a-brave-new-world-teach-us-1964bc")

      assert campaign.slug == "what-can-a-brave-new-world-teach-us-1964bc"
      assert campaign.title == "What can a brave new world teach us?"

      assets = Campaigns.list_media_assets(campaign)
      assert assets == []

      drafts = Campaigns.list_post_drafts(campaign)
      assert Enum.any?(drafts, &(&1.platform == "linkedin" and &1.angle == "explainer"))
      refute Enum.any?(drafts, &(&1.platform == "linkedin" and &1.angle == "key_node"))
      refute Enum.any?(drafts, &(&1.platform == "linkedin" and &1.angle == "highlight"))

      assert Campaigns.origin_question(campaign) == "What can a brave new world teach us?"
      assert Campaigns.first_answer_excerpt(campaign) == "A dystopian lesson about comfort."

      assert Campaigns.follow_up_questions(campaign) == [
               "If a drug like soma existed today...",
               "How do modern social media algorithms mimic..."
             ]

      assert Campaigns.recommended_question(campaign) ==
               "If a drug like soma existed today..."

      assert [%{"question" => "If a drug like soma existed today..."}] =
               Campaigns.user_questions(campaign)

      assert [%{"text" => "Perfect comfort can become a cage."}] = Campaigns.highlights(campaign)
    end

    test "imports the metadata graph payload and extracts questions from node content" do
      payload = metadata_graph_payload()

      assert {:ok, campaign} =
               Campaigns.import_payload(payload, "what-can-a-brave-new-world-teach-us-1964bc")

      assert campaign.slug == "what-can-a-brave-new-world-teach-us-1964bc"
      assert campaign.title == "What can a brave new world teach us?"

      assert campaign.grid_url ==
               "https://rationalgrid.com/g/what-can-a-brave-new-world-teach-us-1964bc"

      assert campaign.tags == ["Dystopian Literature", "Social Philosophy"]
      assert campaign.node_count == 3

      assert Campaigns.origin_question(campaign) == "What can a brave new world teach us?"
      assert Campaigns.first_answer_excerpt(campaign) == "A dystopian lesson about comfort."

      assert Campaigns.follow_up_questions(campaign) == [
               "If a drug like soma existed today, would we choose comfort over freedom?",
               "How do modern social media algorithms mimic soma?",
               "Is it possible for a society to achieve perfect safety without losing freedom?"
             ]

      assert Campaigns.answer_questions(campaign) == [
               %{
                 "question" =>
                   "If a drug like soma existed today, would we choose comfort over freedom?",
                 "node_id" => "2",
                 "answer_title" => "What Can a Brave New World Teach Us?"
               },
               %{
                 "question" => "How do modern social media algorithms mimic soma?",
                 "node_id" => "2",
                 "answer_title" => "What Can a Brave New World Teach Us?"
               }
             ]

      assert Enum.any?(ShareCard.questions(campaign), fn question ->
               question["kind"] == "answer_question" and question["node_id"] == "2" and
                 question["id"] ==
                   ShareCard.question_id(
                     "If a drug like soma existed today, would we choose comfort over freedom?",
                     "2"
                   )
             end)

      assert [
               %{
                 "node_id" => "4",
                 "question" =>
                   "Is it possible for a society to achieve perfect safety without losing freedom?"
               }
             ] =
               Campaigns.user_questions(campaign)

      assert [%{"text" => "Perfect comfort can become a cage."}] = Campaigns.highlights(campaign)

      key_nodes = Campaigns.key_nodes(campaign)
      assert length(key_nodes) == 3

      assert Enum.any?(
               key_nodes,
               &(Map.get(&1, "id") == "2" and Map.get(&1, "class") == "answer")
             )
    end

    test "generates title and highlight assets on demand" do
      payload = simplified_payload()

      assert {:ok, campaign} =
               Campaigns.import_payload(payload, "what-can-a-brave-new-world-teach-us-1964bc")

      assert {:ok, grid_asset} = Campaigns.generate_grid_asset(campaign, "gradient_poster")
      assert grid_asset.kind == "grid_card"
      assert grid_asset.style == "gradient_poster"
      assert grid_asset.url == "/campaigns/#{campaign.id}/share-card.png?style=gradient_poster"
      assert grid_asset.mime_type == "image/png"

      assert {:ok, highlight_asset} =
               Campaigns.generate_highlight_asset(campaign, 123, "warm_paper")

      assert highlight_asset.kind == "highlight_card"
      assert highlight_asset.style == "warm_paper"

      assert highlight_asset.url ==
               "/campaigns/#{campaign.id}/highlights/123/share-card.png?style=warm_paper"

      assert highlight_asset.mime_type == "image/png"

      highlight = %{"id" => 123, "text" => "Perfect comfort can become a cage."}
      warm_svg = ShareCard.highlight_image_svg(campaign, highlight, "warm_paper")
      assert warm_svg =~ "#451a03"
      refute warm_svg =~ "#120f16"

      assets = Campaigns.list_media_assets(campaign)
      assert length(assets) == 2

      drafts = Campaigns.list_post_drafts(campaign)
      assert Enum.any?(drafts, &(&1.platform == "linkedin" and &1.angle == "visual"))
      assert Enum.any?(drafts, &(&1.platform == "linkedin" and &1.angle == "highlight"))
    end

    test "generates a question quote asset on demand without truncating the question" do
      long_question =
        "If a public culture could engineer endless comfort, frictionless entertainment, algorithmic reassurance, chemically stabilized mood, and institutional protection from every sharp edge of existence, would people still retain enough agency to recognize that they had traded away the difficult conditions required for freedom?"

      payload = metadata_graph_payload_with_question(long_question)

      assert {:ok, campaign} =
               Campaigns.import_payload(payload, "what-can-a-brave-new-world-teach-us-1964bc")

      assert long_question in Campaigns.follow_up_questions(campaign)

      question_id = ShareCard.question_id(long_question)
      assert {:ok, asset} = Campaigns.generate_question_asset(campaign, question_id)
      assert asset.kind == "question_quote_card"
      assert asset.text == long_question
      assert asset.style == "editorial_dark"
      assert asset.url == "/campaigns/#{campaign.id}/questions/#{question_id}/share-card.png"
      assert asset.mime_type == "image/png"

      assert {:ok, styled_asset} =
               Campaigns.generate_question_asset(campaign, question_id, "minimal_academic")

      assert styled_asset.style == "minimal_academic"

      assert styled_asset.url ==
               "/campaigns/#{campaign.id}/questions/#{question_id}/share-card.png?style=minimal_academic"

      question_assets =
        Campaigns.list_media_assets(campaign) |> Enum.filter(&(&1.kind == "question_quote_card"))

      assert length(question_assets) == 2

      drafts = Campaigns.list_post_drafts(campaign)

      question_asset_ids = MapSet.new(question_assets, & &1.id)

      question_drafts =
        Enum.filter(
          drafts,
          &(MapSet.member?(question_asset_ids, &1.media_asset_id) and &1.angle == "question_quote")
        )

      assert Enum.sort(Enum.map(question_drafts, & &1.platform)) ==
               Enum.sort(Platforms.text_ids() ++ Platforms.text_ids())

      assert Enum.uniq_by(question_drafts, & &1.body) |> length() == 1
    end

    test "generates platform-specific question and highlight cards" do
      assert {:ok, campaign} =
               Campaigns.import_payload(simplified_payload(), "platform-quotes-test")

      question = "If a drug like soma existed today..."
      question_id = ShareCard.question_id(question)

      assert {:ok, question_asset} =
               Campaigns.generate_question_asset(
                 campaign,
                 question_id,
                 "minimal_light",
                 "linkedin"
               )

      assert question_asset.metadata["format"] == "linkedin"
      assert question_asset.metadata["width"] == 1200
      assert question_asset.recommended_platforms == Platforms.text_ids()
      assert question_asset.url =~ "format=linkedin"

      assert {:ok, highlight_asset} =
               Campaigns.generate_highlight_asset(campaign, 123, "minimal_dark", "portrait")

      assert highlight_asset.metadata["format"] == "portrait"
      assert highlight_asset.metadata["height"] == 1350
      assert highlight_asset.recommended_platforms == Platforms.text_ids()
      assert highlight_asset.url =~ "format=portrait"
    end

    test "generates a question portrait and uploadable Short package" do
      assert {:ok, campaign} =
               Campaigns.import_payload(simplified_payload(), "question-short-package")

      question_candidate =
        campaign
        |> Workflow.candidates()
        |> Enum.find(&(&1.type == "question"))

      if CarouselVideo.available?() do
        result =
          Workflow.generate(campaign, [question_candidate],
            style: "gradient_poster",
            format: "carousel"
          )

        assert result.errors == []
        assert Enum.any?(result.assets, &(&1.kind == "question_quote_card"))
        assert Enum.any?(result.assets, &(&1.kind == "question_video"))

        video = Enum.find(result.assets, &(&1.kind == "question_video"))
        assert video.mime_type == "video/mp4"
        assert video.metadata["width"] == 1080
        assert video.metadata["height"] == 1920
        assert video.recommended_platforms == Platforms.video_ids()
      else
        result =
          Workflow.generate(campaign, [question_candidate],
            style: "gradient_poster",
            format: "carousel"
          )

        assert Enum.any?(result.assets, &(&1.kind == "question_quote_card"))
        assert result.errors != []
      end
    end

    test "generates a key-node image asset on demand" do
      payload = simplified_payload()

      assert {:ok, campaign} =
               Campaigns.import_payload(payload, "what-can-a-brave-new-world-teach-us-1964bc")

      assert {:ok, asset} = Campaigns.generate_key_node_asset(campaign, "1")
      assert asset.kind == "key_node_card"
      assert asset.style == "editorial_dark"
      assert asset.url == "/campaigns/#{campaign.id}/nodes/1/share-card.png"
      assert asset.mime_type == "image/png"
      assert asset.node_id == "1"

      assert {:ok, styled_asset} = Campaigns.generate_key_node_asset(campaign, "1", "warm_paper")
      assert styled_asset.style == "warm_paper"

      assert styled_asset.url ==
               "/campaigns/#{campaign.id}/nodes/1/share-card.png?style=warm_paper"

      assert {:ok, portrait_asset} =
               Campaigns.generate_key_node_asset(campaign, "1", "warm_paper", "portrait")

      assert portrait_asset.url ==
               "/campaigns/#{campaign.id}/nodes/1/share-card.png?style=warm_paper&format=portrait"

      assert portrait_asset.metadata["format"] == "portrait"
      assert portrait_asset.recommended_platforms == Platforms.text_ids()

      assert {:ok, linkedin_asset} =
               Campaigns.generate_key_node_asset(campaign, "1", "warm_paper", "linkedin")

      assert linkedin_asset.url ==
               "/campaigns/#{campaign.id}/nodes/1/share-card.png?style=warm_paper&format=linkedin"

      assert linkedin_asset.metadata["format"] == "linkedin"
      assert linkedin_asset.metadata["width"] == 1200
      assert linkedin_asset.metadata["height"] == 1200
      assert linkedin_asset.recommended_platforms == Platforms.text_ids()

      node = ShareCard.find_key_node(campaign, "1")
      assert ShareCard.node_reading_image_svg(campaign, node, "warm_paper") =~ "width=\"1080\""
      assert ShareCard.node_linkedin_image_svg(campaign, node, "warm_paper") =~ "height=\"1200\""

      assets = Campaigns.list_media_assets(campaign)
      assert length(Enum.filter(assets, &(&1.kind == "key_node_card"))) == 4

      drafts = Campaigns.list_post_drafts(campaign)
      assert Enum.any?(drafts, &(&1.platform == "linkedin" and &1.angle == "key_node"))

      assert {:ok, _asset} = Campaigns.generate_key_node_asset(campaign, "1")
      assets = Campaigns.list_media_assets(campaign)
      assert length(Enum.filter(assets, &(&1.kind == "key_node_card"))) == 4
    end

    test "combines selected mixed candidates into one story carousel" do
      assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "combined-carousel")

      candidates =
        campaign
        |> Workflow.candidates()
        |> Enum.filter(&(&1.type in ["question", "highlight", "key_node"]))
        |> Enum.take(3)

      result =
        Workflow.generate(campaign, candidates,
          style: "gradient_poster",
          format: "combined_carousel"
        )

      carousel = Enum.find(result.assets, &(&1.kind == "curated_carousel"))
      assert carousel

      batch_ids =
        result.assets
        |> Enum.map(& &1.metadata["generation_batch_id"])
        |> Enum.uniq()

      assert [batch_id] = batch_ids
      assert is_binary(batch_id)
      assert Enum.all?(result.assets, &is_binary(&1.metadata["generated_at"]))
      assert carousel.metadata["format"] == "curated_carousel"
      assert carousel.metadata["slide_count"] == length(carousel.metadata["slides"])
      assert carousel.metadata["slide_count"] >= length(candidates) + 2
      assert carousel.recommended_platforms == Platforms.text_ids()

      if CarouselVideo.available?() do
        assert result.errors == []
        video = Enum.find(result.assets, &(&1.kind == "curated_carousel_video"))
        assert video
        assert video.metadata["slide_count"] == carousel.metadata["slide_count"]
        refute Map.has_key?(video.metadata, "selected_slide_indexes")
        assert video.metadata["background_audio"]
      else
        assert result.errors != []
      end

      png =
        ShareCard.curated_carousel_image_png(
          campaign,
          carousel.metadata["slides"],
          carousel.style,
          2
        )

      assert binary_part(png, 0, 8) == <<137, 80, 78, 71, 13, 10, 26, 10>>

      assert Enum.any?(
               Campaigns.list_post_drafts(campaign, platform: "x"),
               &(&1.media_asset_id == carousel.id)
             )
    end

    test "generates an ordered carousel of key-node slides" do
      assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "carousel-test")

      assert {:ok, assets} =
               Campaigns.generate_key_node_carousel(campaign, "1", "gradient_poster")

      assert length(assets) >= 2
      assert Enum.all?(assets, &(&1.kind == "key_node_carousel_slide"))
      assert Enum.at(assets, 0).metadata["slide_index"] == 1
      assert Enum.at(assets, 0).recommended_platforms == Platforms.text_ids()
      assert Enum.at(assets, 0).mime_type == "image/png"

      assert Enum.at(assets, 0).text ==
               "Follow the reasoning, test the assumptions, and decide where you stand."

      assert Enum.at(assets, 0).url =~ "/carousel.png?"
      assert Enum.all?(Enum.drop(assets, 1), &(&1.recommended_platforms == []))

      assert Enum.any?(
               Campaigns.list_post_drafts(campaign),
               &(&1.media_asset_id == Enum.at(assets, 0).id)
             )
    end

    test "renders a carousel as a vertical short-form MP4" do
      assert {:ok, campaign} =
               Campaigns.import_payload(simplified_payload(), "carousel-video-test")

      if CarouselVideo.available?() do
        assert {:ok, asset} =
                 Campaigns.generate_key_node_video(campaign, "1", "gradient_poster")

        assert asset.kind == "key_node_video"
        assert asset.mime_type == "video/mp4"
        assert asset.metadata["width"] == 1080
        assert asset.metadata["height"] == 1920
        assert asset.metadata["duration_seconds"] > 0
        assert asset.metadata["background_audio"]
        assert CarouselVideo.background_audio_available?()
        assert "youtube" in asset.recommended_platforms

        node = ShareCard.find_key_node(campaign, "1")
        assert {:ok, path} = CarouselVideo.render(campaign, node, "gradient_poster")
        video = File.read!(path)
        assert binary_part(video, 4, 4) == "ftyp"

        assert Enum.any?(
                 Campaigns.list_post_drafts(campaign, platform: "youtube"),
                 &(&1.media_asset_id == asset.id and &1.angle == "key_node")
               )

        key_node_candidate =
          campaign
          |> Workflow.candidates()
          |> Enum.find(&(&1.type == "key_node" and &1.source_id == "1"))

        result =
          Workflow.generate(campaign, [key_node_candidate],
            style: "gradient_poster",
            format: "carousel"
          )

        assert result.errors == []
        assert Enum.any?(result.assets, &(&1.kind == "key_node_video"))
        assert Enum.any?(result.assets, &(&1.kind == "key_node_carousel_slide"))
      else
        assert {:error, :ffmpeg_not_found} =
                 Campaigns.generate_key_node_video(campaign, "1", "gradient_poster")
      end
    end

    test "deletes a generated image asset and its generated drafts" do
      payload = simplified_payload()

      assert {:ok, campaign} =
               Campaigns.import_payload(payload, "what-can-a-brave-new-world-teach-us-1964bc")

      assert {:ok, asset} = Campaigns.generate_grid_asset(campaign)
      drafts = Campaigns.list_post_drafts(campaign)
      assert Enum.any?(drafts, &(&1.media_asset_id == asset.id))

      assert {:ok, deleted_asset} = Campaigns.delete_generated_media_asset(asset.id)
      assert deleted_asset.id == asset.id

      assets = Campaigns.list_media_assets(campaign)
      refute Enum.any?(assets, &(&1.id == asset.id))

      drafts = Campaigns.list_post_drafts(campaign)
      refute Enum.any?(drafts, &(&1.media_asset_id == asset.id))
    end

    test "does not overwrite an edited draft when the payload is imported again" do
      payload = sample_payload()
      assert {:ok, campaign} = Campaigns.import_payload(payload, "res.json")

      [draft | _] =
        Campaigns.list_post_drafts(campaign, platform: "x", media_asset_id: "campaign")

      assert {:ok, _draft} = Campaigns.update_post_draft(draft, %{body: "Edited internal copy"})

      assert {:ok, campaign} = Campaigns.import_payload(payload, "res.json")
      drafts = Campaigns.list_post_drafts(campaign, platform: "x", media_asset_id: "campaign")

      assert Enum.any?(drafts, &(&1.body == "Edited internal copy"))
    end
  end

  defp sample_payload do
    "res.json"
    |> File.read!()
    |> Jason.decode!()
  end

  defp metadata_graph_payload_with_question(question) do
    payload = metadata_graph_payload()

    update_in(payload, ["graph", "nodes"], fn nodes ->
      nodes ++
        [
          %{
            "id" => "9",
            "class" => "answer",
            "title" => "Long question source",
            "content" => question
          }
        ]
    end)
  end

  defp metadata_graph_payload do
    %{
      "metadata" => %{
        "title" => "What can a brave new world teach us?",
        "slug" => "what-can-a-brave-new-world-teach-us-1964bc",
        "url" => "https://rationalgrid.com/g/what-can-a-brave-new-world-teach-us-1964bc",
        "api_url" =>
          "https://rationalgrid.com/api/promotion/grids/what-can-a-brave-new-world-teach-us-1964bc",
        "tags" => ["Dystopian Literature", "Social Philosophy"],
        "node_count" => 3,
        "inserted_at" => "2026-07-01T00:00:00Z",
        "updated_at" => "2026-07-02T00:00:00Z"
      },
      "graph" => %{
        "nodes" => [
          %{
            "id" => "1",
            "class" => "origin",
            "title" => "What can a brave new world teach us?",
            "content" => "What can a brave new world teach us?"
          },
          %{
            "id" => "2",
            "class" => "answer",
            "title" => "What Can a Brave New World Teach Us?",
            "content" =>
              "# What Can a Brave New World Teach Us?\n\nA dystopian lesson about comfort. If a drug like soma existed today, would we choose comfort over freedom? How do modern social media algorithms mimic soma? This sentence is not a question.",
            "excerpt" => "A dystopian lesson about comfort."
          },
          %{
            "id" => "4",
            "class" => "question",
            "content" =>
              "Is it possible for a society to achieve perfect safety without losing freedom?"
          }
        ],
        "edges" => []
      },
      "highlights" => [
        %{
          "id" => 123,
          "node_id" => "2",
          "text" => "Perfect comfort can become a cage.",
          "note" => nil
        }
      ]
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
        "follow_up_questions" => [
          "If a drug like soma existed today...",
          "How do modern social media algorithms mimic..."
        ],
        "user_questions" => [
          %{
            "node_id" => "4",
            "question" => "If a drug like soma existed today..."
          }
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
