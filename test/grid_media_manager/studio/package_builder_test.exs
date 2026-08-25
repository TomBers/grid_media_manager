defmodule GridMediaManager.Studio.PackageBuilderTest do
  use GridMediaManager.DataCase

  alias GridMediaManager.Campaigns
  alias GridMediaManager.Studio.PackageBuilder
  alias GridMediaManager.Studio.Workflow
  alias GridMediaManager.Social.Platforms

  test "an autonomous plan and guided generation use the same package builder" do
    assert {:ok, campaign} =
             Campaigns.import_payload(
               %{
                 "metadata" => %{
                   "title" => "Shared package workflow",
                   "slug" => "shared-package-workflow",
                   "url" => "https://rationalgrid.ai/g/shared-package-workflow"
                 },
                 "graph" => %{
                   "nodes" => [
                     %{
                       "id" => "1",
                       "class" => "origin",
                       "content" => "What should the audience notice?"
                     },
                     %{
                       "id" => "2",
                       "class" => "answer",
                       "title" => "A grounded answer",
                       "content" => "A concise explanation with a useful implication."
                     }
                   ],
                   "edges" => [%{"data" => %{"source" => "1", "target" => "2"}}]
                 },
                 "highlights" => []
               },
               "shared-package-workflow"
             )

    candidates = Workflow.candidates(campaign)
    standalone_candidate = List.last(candidates)
    other_candidate = Enum.find(candidates, &(&1.key != standalone_candidate.key))
    selected_candidates = [other_candidate, standalone_candidate]
    selected_keys = Enum.map(selected_candidates, & &1.key)

    plan = %{
      recommended_format: "portrait",
      selected_keys: selected_keys,
      selection_details: %{
        "visual_style" => "deep_ocean",
        "text_visual_key" => List.last(selected_keys),
        "cover" => %{
          "mode" => "photo",
          "status" => "selected",
          "photo" => %{
            "id" => 42,
            "alt" => "A thoughtful figure beside an ocean horizon",
            "portrait_url" => "https://images.example/portrait.jpg",
            "original_url" => "https://images.example/original.jpg"
          }
        }
      }
    }

    assert %{assets: [asset], errors: []} =
             PackageBuilder.generate_plan(campaign, plan, candidates)

    assert asset.style == "deep_ocean"
    assert asset.kind == "curated_carousel"
    assert Enum.at(asset.metadata["slides"], 1)["title"] == List.last(selected_candidates).title

    campaign = Campaigns.get_campaign!(campaign.id)
    assert Campaigns.title_card_mode(campaign) == "pexels"
    assert Campaigns.pexels_background(campaign)["id"] == 42

    assert %{assets: complete_assets, errors: []} =
             PackageBuilder.generate_complete_plan(campaign, plan, candidates)

    assert Enum.map(complete_assets, & &1.kind) |> Enum.sort() ==
             Enum.sort(["long_form_post", "curated_carousel", "curated_carousel_video"])

    long_form = Enum.find(complete_assets, &(&1.kind == "long_form_post"))
    assert long_form.recommended_platforms == Platforms.long_form_ids()
    assert Enum.map(long_form.metadata["slides"], & &1["kind"]) == ["cover", "cta"]

    x_post = Enum.find(complete_assets, &(&1.kind == "curated_carousel"))
    assert x_post.recommended_platforms == ["x"]
    assert Enum.map(x_post.metadata["slides"], & &1["kind"]) == ["node_text", "cta"]
    assert List.first(x_post.metadata["slides"])["title"] == standalone_candidate.title

    video = Enum.find(complete_assets, &(&1.kind == "curated_carousel_video"))
    assert video.recommended_platforms == Platforms.video_ids()
    assert List.first(video.metadata["slides"])["kind"] == "cover"
    assert List.last(video.metadata["slides"])["kind"] == "cta"

    content_titles = video.metadata["slides"] |> Enum.drop(1) |> Enum.map(& &1["title"])
    refute List.first(content_titles) == standalone_candidate.title
    assert standalone_candidate.title in content_titles
  end
end
