defmodule GridMediaManager.CampaignsTest do
  use GridMediaManager.DataCase

  alias GridMediaManager.Campaigns
  alias GridMediaManager.Campaigns.MediaAsset
  alias GridMediaManager.Promotion.ArtifactStore
  alias GridMediaManager.Promotion.CarouselVideo
  alias GridMediaManager.Promotion.ShareCard
  alias GridMediaManager.Repo
  alias GridMediaManager.Social.Platforms
  alias GridMediaManager.Studio.Workflow

  @png <<137, 80, 78, 71, 13, 10, 26, 10, 0, 1, 2, 3>>

  setup do
    previous_root = Application.get_env(:grid_media_manager, :artifact_store_path)

    root =
      Path.join(
        System.tmp_dir!(),
        "grid-media-manager-campaign-test-#{System.unique_integer([:positive])}"
      )

    Application.put_env(:grid_media_manager, :artifact_store_path, root)

    on_exit(fn ->
      File.rm_rf!(root)

      if previous_root do
        Application.put_env(:grid_media_manager, :artifact_store_path, previous_root)
      else
        Application.delete_env(:grid_media_manager, :artifact_store_path)
      end
    end)

    :ok
  end

  test "exposes distinct editorial styles while keeping content renderer-agnostic" do
    styles = ShareCard.styles()

    assert length(styles) == 6
    assert Enum.map(styles, & &1.id) |> Enum.uniq() |> length() == length(styles)
    assert Enum.any?(styles, &(&1.id == "minimal_light"))
    assert Enum.any?(styles, &(&1.id == "editorial_dark"))
    assert Enum.any?(styles, &(&1.id == "newsprint"))
    refute Enum.any?(styles, &(&1.id == "signal_red"))
    assert ShareCard.normalize_style("not-a-style") == ShareCard.default_style()
  end

  test "imports source content without generating visual assets or base drafts" do
    assert {:ok, campaign} = Campaigns.import_payload(payload(), "client-only-import")

    assert campaign.title == "How should we reason under uncertainty?"
    assert Campaigns.list_media_assets(campaign) == []
    assert Campaigns.list_post_drafts(campaign) == []
    assert Campaigns.recommended_question(campaign) =~ "What evidence"
  end

  test "generates editable client media metadata and deterministic post drafts" do
    campaign = import_campaign("grid-asset")
    assert {:ok, asset} = Campaigns.generate_grid_asset(campaign, "gradient_poster")

    assert asset.url =~ "/client-assets/campaigns/#{campaign.id}/grid/"

    assert asset.metadata["slides"] == [
             %{"body" => "", "kind" => "cover", "title" => campaign.title}
           ]

    drafts = Campaigns.list_post_drafts(campaign, media_asset_id: asset.id)
    assert Enum.map(drafts, & &1.platform) |> Enum.sort() == Enum.sort(Platforms.text_ids())
    assert Enum.all?(drafts, &(&1.status == "draft"))
  end

  test "plans complete Markdown content as editable slide blocks" do
    campaign = import_campaign("markdown-slides")
    node = ShareCard.find_key_node(campaign, "answer-1")
    slides = ShareCard.node_reading_slides(campaign, node)

    assert Enum.all?(slides, &(&1["kind"] == "node_text"))
    refute Enum.any?(slides, &(&1["kind"] == "cta"))

    content = Enum.filter(slides, &(&1["kind"] == "node_text"))
    assert Enum.any?(content, &String.contains?(&1["body"], "First claim"))

    block_types = content |> Enum.flat_map(& &1["blocks"]) |> Enum.map(& &1["type"])
    assert :list_item in block_types
    assert :blockquote in block_types
  end

  test "creates question and longer-answer assets from source text" do
    campaign = import_campaign("source-assets")
    [question | _rest] = ShareCard.questions(campaign)

    assert {:ok, question_asset} =
             Campaigns.generate_question_asset(campaign, question["id"], "warm_paper", "portrait")

    assert question_asset.text == question["question"]

    assert question_asset.metadata["slides"] |> hd() |> Map.fetch!("title") ==
             question["question"]

    assert {:ok, long_form} =
             Campaigns.generate_long_form_post(campaign, "answer-1", "minimal_light")

    assert long_form.kind == "long_form_post"
    assert long_form.text =~ "First claim"
    assert Enum.map(long_form.metadata["slides"], & &1["kind"]) == ["cover", "cta"]
    assert List.last(long_form.metadata["slides"])["title"] == "Where do you stand?"

    assert Campaigns.list_post_drafts(campaign, media_asset_id: long_form.id)
           |> Enum.map(& &1.platform)
           |> Enum.sort() == Enum.sort(Platforms.long_form_ids())
  end

  test "creates one ordered long-form text post from questions, answers, and highlights" do
    campaign = import_campaign("multi-source-long-form")
    candidates = Workflow.candidates(campaign)

    question = Enum.find(candidates, &(&1.type == "question"))
    answer = Enum.find(candidates, &(&1.type == "key_node" and &1.node_class == "answer"))
    highlight = Enum.find(candidates, &(&1.type == "highlight"))

    assert {:ok, asset} =
             Campaigns.generate_long_form_post(
               campaign,
               [question, answer, highlight],
               "minimal_light"
             )

    assert asset.kind == "long_form_post"
    assert asset.text =~ question.title
    assert asset.text =~ "First claim: confidence should follow evidence."
    assert asset.text =~ highlight.title
    assert asset.metadata["slide_count"] == 2
    assert List.last(asset.metadata["slides"])["body"] =~ "contribute your perspective"

    assert Enum.map(asset.metadata["sources"], & &1["type"]) == [
             "question",
             "key_node",
             "highlight"
           ]

    drafts = Campaigns.list_post_drafts(campaign, media_asset_id: asset.id)

    assert drafts |> Enum.map(& &1.platform) |> Enum.sort() ==
             Enum.sort(Platforms.long_form_ids())

    assert Enum.all?(drafts, &String.contains?(&1.body, "• Look for disconfirming evidence."))
    assert Enum.all?(drafts, &String.contains?(&1.body, campaign.grid_url))
    refute Enum.any?(drafts, &String.contains?(&1.body, "# A structured answer"))
    refute Enum.any?(drafts, &String.contains?(&1.body, "> Good reasoning"))
  end

  test "builds one ordered carousel sequence for image and video outputs" do
    campaign = import_campaign("story-sequence")
    candidates = Workflow.candidates(campaign) |> Enum.take(2)

    result =
      Workflow.generate(campaign, candidates, style: "deep_ocean", format: "combined_carousel")

    assert result.errors == []
    assert [carousel, video] = Enum.sort_by(result.assets, & &1.mime_type)
    assert carousel.mime_type == "image/png"
    assert video.mime_type == "video/mp4"
    assert carousel.metadata["slides"] == video.metadata["slides"]
    assert List.first(carousel.metadata["slides"])["kind"] == "cover"
    assert List.last(carousel.metadata["slides"])["kind"] == "cta"
    assert List.last(carousel.metadata["slides"])["body"] =~ "contribute your perspective"

    assert video.metadata["selected_slide_indexes"] ==
             carousel.metadata["selected_slide_indexes"]

    assert video.metadata["frame_durations"] ==
             CarouselVideo.slide_durations(video.metadata["slides"])

    refute Map.has_key?(video.metadata, "background_audio")

    assert video.metadata["duration_seconds"] ==
             video.metadata["slides"]
             |> CarouselVideo.slide_durations(video.metadata["selected_slide_indexes"])
             |> CarouselVideo.duration_seconds()
  end

  test "video-only generation creates one canonical asset without an intermediate carousel" do
    campaign = import_campaign("single-video-path")
    candidates = Workflow.candidates(campaign) |> Enum.take(2)

    assert %{assets: [video], errors: []} =
             Workflow.generate(campaign, candidates,
               style: "deep_ocean",
               format: "story_video"
             )

    assert video.kind == "curated_carousel_video"
    assert List.first(video.metadata["slides"])["kind"] == "cover"
    assert List.last(video.metadata["slides"])["kind"] == "cta"
    refute Enum.any?(Campaigns.list_media_assets(campaign), &(&1.kind == "curated_carousel"))
  end

  test "stores selected browser artifacts and rejects unselected frames" do
    campaign = import_campaign("artifact-selection")
    candidates = Workflow.candidates(campaign) |> Enum.take(2)
    assert {:ok, asset} = Campaigns.generate_curated_carousel(campaign, candidates, "warm_paper")

    last_index = asset.metadata["slide_count"]
    assert {:ok, asset} = Campaigns.update_curated_carousel_selection(asset, [2])
    assert Campaigns.media_asset_slide_indexes(asset) == [2, last_index]

    assert {:error, :invalid_slide} = Campaigns.store_client_artifact(asset, 1, @png)
    assert {:ok, asset} = Campaigns.store_client_artifact(asset, 2, @png)

    assert ArtifactStore.artifact(asset, 2)["renderer_version"] ==
             ArtifactStore.renderer_version()

    stale_metadata = put_in(asset.metadata, ["artifacts", "2", "renderer_version"], 1)
    refute ArtifactStore.ready?(%{asset | metadata: stale_metadata}, [2])

    refute ArtifactStore.ready?(asset, Campaigns.media_asset_slide_indexes(asset))
    assert {:ok, asset} = Campaigns.store_client_artifact(asset, last_index, @png)
    assert ArtifactStore.ready?(asset, Campaigns.media_asset_slide_indexes(asset))
  end

  test "regenerating an identical asset preserves completed browser artifacts" do
    campaign = import_campaign("artifact-resume")
    assert {:ok, asset} = Campaigns.generate_grid_asset(campaign)
    assert {:ok, asset} = Campaigns.store_client_artifact(asset, 1, @png)

    assert {:ok, regenerated} = Campaigns.generate_grid_asset(campaign)
    assert regenerated.id == asset.id
    assert ArtifactStore.ready?(regenerated, [1])
    assert ArtifactStore.artifact(regenerated, 1) == ArtifactStore.artifact(asset, 1)

    assert {:ok, campaign} =
             Campaigns.set_pexels_background(campaign, %{
               id: 42,
               portrait_url: "https://images.example/new-cover.jpg"
             })

    assert {:ok, changed_cover} = Campaigns.generate_grid_asset(campaign)
    refute ArtifactStore.ready?(changed_cover, [1])
    refute Map.has_key?(changed_cover.metadata, "artifacts")
  end

  test "editing slide text invalidates rendered and published media" do
    campaign = import_campaign("edit-slide")
    assert {:ok, asset} = Campaigns.generate_grid_asset(campaign)
    assert {:ok, asset} = Campaigns.store_client_artifact(asset, 1, @png)

    metadata =
      asset.metadata
      |> Map.put("published_url", "https://media.example/old.png")
      |> Map.update!("slides", fn [slide] ->
        [Map.put(slide, "blocks", [%{"type" => "paragraph"}])]
      end)

    asset = asset |> MediaAsset.changeset(%{metadata: metadata}) |> Repo.update!()

    assert {:ok, updated} =
             Campaigns.update_media_asset_slide(asset, 1, %{
               "title" => "A clearer headline",
               "body" => "Supporting text that can keep changing."
             })

    assert updated.metadata["slides"] == [
             %{
               "body" => "Supporting text that can keep changing.",
               "kind" => "cover",
               "title" => "A clearer headline"
             }
           ]

    refute Map.has_key?(updated.metadata, "artifacts")
    refute Map.has_key?(updated.metadata, "published_url")
  end

  test "locks approved copy while allowing draft and failed copy to be corrected" do
    campaign = import_campaign("draft-lifecycle")
    assert {:ok, asset} = Campaigns.generate_grid_asset(campaign)
    [draft | _rest] = Campaigns.list_post_drafts(campaign, media_asset_id: asset.id)

    assert {:ok, draft} = Campaigns.update_post_draft_body(draft, "A better post body")
    assert {:ok, approved} = Campaigns.approve_post_draft(draft.id)
    assert approved.status == "approved"
    assert {:error, :invalid_transition} = Campaigns.update_post_draft_body(approved, "Too late")
    assert {:error, :invalid_transition} = Campaigns.approve_post_draft(approved.id)
  end

  test "keeps studio choices separate when source content is re-imported" do
    campaign = import_campaign("state-separation")

    assert {:ok, campaign} =
             Campaigns.save_guided_studio_state(campaign, %{
               "stage" => "review",
               "platforms" => ["x", "linkedin"]
             })

    assert {:ok, campaign} = Campaigns.set_title_card_mode(campaign, "text")
    assert {:ok, reimported} = Campaigns.import_payload(payload(), "state-separation")

    assert Campaigns.guided_studio_state(reimported)["stage"] == "review"
    assert Campaigns.title_card_mode(reimported) == "text"
    assert reimported.studio_state == campaign.studio_state
  end

  test "returns a workflow error instead of crashing after campaign deletion" do
    campaign = import_campaign("deleted-campaign")
    candidate = Workflow.candidates(campaign) |> List.first()
    Repo.delete!(campaign)

    assert %{assets: [], errors: [%{reason: :campaign_not_found}]} =
             Workflow.generate(campaign, [candidate])
  end

  defp import_campaign(source) do
    assert {:ok, campaign} = Campaigns.import_payload(payload(), source)
    campaign
  end

  defp payload do
    %{
      "metadata" => %{
        "title" => "How should we reason under uncertainty?",
        "slug" => "reason-under-uncertainty",
        "url" => "https://rationalgrid.ai/g/reason-under-uncertainty",
        "tags" => ["Reasoning", "Evidence"],
        "node_count" => 3
      },
      "graph" => %{
        "nodes" => [
          %{
            "id" => "origin",
            "class" => "origin",
            "title" => "How should we reason under uncertainty?",
            "content" => "How should we reason under uncertainty?"
          },
          %{
            "id" => "answer-1",
            "class" => "answer",
            "title" => "A structured answer",
            "content" => """
            # A structured answer

            First claim: confidence should follow evidence.

            ## A practical test

            - Look for disconfirming evidence.
            - Separate confidence from certainty.

            > Good reasoning stays revisable.

            What evidence would change your mind?
            """,
            "excerpt" => "Confidence should follow evidence."
          },
          %{
            "id" => "question-1",
            "class" => "question",
            "content" => "What evidence would change your mind?"
          }
        ],
        "edges" => []
      },
      "highlights" => [
        %{
          "id" => 101,
          "node_id" => "answer-1",
          "text" => "Good reasoning stays revisable."
        }
      ]
    }
  end
end
