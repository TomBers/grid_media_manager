defmodule GridMediaManager.Studio.PackageBuilderTest do
  use GridMediaManager.DataCase

  alias GridMediaManager.Campaigns
  alias GridMediaManager.Studio.PackageBuilder
  alias GridMediaManager.Studio.Workflow

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
    selected_keys = candidates |> Enum.take(2) |> Enum.map(& &1.key)

    plan = %{
      recommended_format: "portrait",
      selected_keys: selected_keys,
      selection_details: %{
        "visual_style" => "deep_ocean",
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

    campaign = Campaigns.get_campaign!(campaign.id)
    assert Campaigns.title_card_mode(campaign) == "pexels"
    assert Campaigns.pexels_background(campaign)["id"] == 42
  end
end
