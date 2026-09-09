defmodule GridMediaManager.Studio.EditorialHookTest do
  use GridMediaManager.DataCase

  alias GridMediaManager.Campaigns
  alias GridMediaManager.Promotion.CarouselVideo
  alias GridMediaManager.Studio.{PackageBuilder, Workflow}

  setup do
    {:ok, campaign} =
      Campaigns.import_payload(
        %{
          "metadata" => %{
            "title" => "Evidence and belief",
            "url" => "https://rationalgrid.ai/g/evidence"
          },
          "graph" => %{
            "nodes" => [
              %{"id" => "1", "class" => "origin", "content" => "What could change your mind?"},
              %{
                "id" => "2",
                "class" => "answer",
                "title" => "Revising a belief",
                "content" => "New evidence can challenge an old assumption."
              }
            ],
            "edges" => [%{"data" => %{"source" => "1", "target" => "2"}}]
          },
          "highlights" => []
        },
        "editorial-hook"
      )

    candidates = Workflow.candidates(campaign)
    selected = Enum.filter(candidates, &(&1.type == "key_node"))

    plan = %{
      hook: "What if a better question changes your mind?",
      selected_keys: Enum.map(selected, & &1.key),
      recommended_format: "combined_carousel",
      selection_details: %{"cover" => %{"mode" => "text"}}
    }

    %{campaign: campaign, candidates: candidates, plan: plan}
  end

  test "every destination uses the planned opening while retaining source material", context do
    %{campaign: campaign, candidates: candidates, plan: plan} = context

    assert %{assets: assets, errors: []} =
             PackageBuilder.generate_complete_plan(campaign, plan, candidates)

    assert length(assets) == 3

    for asset <- assets do
      assert asset.title == plan.hook
      assert List.first(asset.metadata["slides"])["title"] == plan.hook
      assert asset.metadata["editorial_hook"] == plan.hook

      for draft <- Campaigns.list_post_drafts(campaign, media_asset_id: asset.id) do
        assert String.starts_with?(draft.body, plan.hook)
      end
    end

    long_form = Enum.find(assets, &(&1.kind == "long_form_post"))
    assert long_form.text =~ "New evidence can challenge an old assumption."
    assert Campaigns.get_campaign!(campaign.id).title == campaign.title
    assert Campaigns.get_campaign!(campaign.id).raw_payload == campaign.raw_payload

    video = Enum.find(assets, &(&1.mime_type == "video/mp4"))

    assert video.metadata["duration_seconds"] ==
             CarouselVideo.asset_duration_seconds(
               video,
               Campaigns.media_asset_slide_indexes(video)
             )
  end

  test "regeneration is stable and another hook does not replace approved output", context do
    %{campaign: campaign, candidates: candidates, plan: plan} = context

    assert %{assets: assets, errors: []} =
             PackageBuilder.generate_complete_plan(campaign, plan, candidates)

    draft = Campaigns.list_post_drafts(campaign) |> List.first()
    {:ok, draft} = Campaigns.update_post_draft_body(draft, "An editor-approved caption.")
    {:ok, _draft} = Campaigns.approve_post_draft(draft.id)

    assert %{assets: regenerated, errors: []} =
             PackageBuilder.generate_complete_plan(campaign, plan, candidates)

    assert Enum.map(regenerated, & &1.id) == Enum.map(assets, & &1.id)
    assert Campaigns.get_post_draft!(draft.id).body == "An editor-approved caption."

    other_plan = %{plan | hook: "Which assumption would you question first?"}

    assert %{assets: other_assets, errors: []} =
             PackageBuilder.generate_complete_plan(campaign, other_plan, candidates)

    refute Enum.any?(other_assets, fn asset -> asset.id in Enum.map(assets, & &1.id) end)

    for asset <- assets do
      saved = Campaigns.get_media_asset!(asset.id)
      assert List.first(saved.metadata["slides"])["title"] == plan.hook
    end

    assert Campaigns.get_post_draft!(draft.id).status == "approved"
  end

  test "blank hooks retain the ordinary source-based cover", context do
    %{campaign: campaign, candidates: candidates, plan: plan} = context

    assert %{assets: [asset], errors: []} =
             PackageBuilder.generate_plan(campaign, %{plan | hook: "  "}, candidates,
               format: "story_video"
             )

    assert List.first(asset.metadata["slides"])["title"] == campaign.title
    refute Map.has_key?(asset.metadata, "editorial_hook")
  end
end
