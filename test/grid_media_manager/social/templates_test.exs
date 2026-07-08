defmodule GridMediaManager.Social.TemplatesTest do
  use ExUnit.Case, async: true

  alias GridMediaManager.Campaigns.Campaign
  alias GridMediaManager.Campaigns.MediaAsset
  alias GridMediaManager.Social.Templates

  test "builds platform-specific highlight copy from campaign and asset fields" do
    campaign = %Campaign{
      title: "What is the collective subconscious?",
      grid_url: "https://rationalgrid.ai/g/collective",
      tags: ["Psychology", "Philosophy"],
      raw_payload: %{
        "raw" => %{
          "highlights" => [
            %{"id" => 121, "share_url" => "https://rationalgrid.ai/g/collective?highlight=121"}
          ]
        }
      }
    }

    asset = %MediaAsset{
      id: 1,
      title: "Highlighted quote",
      kind: "highlight_card",
      text: "collective unconscious is an inherited structure",
      highlight_id: 121,
      recommended_platforms: ["x"]
    }

    body = Templates.body(campaign, asset, "x", "highlight")

    assert body =~ "collective unconscious is an inherited structure"
    assert body =~ "https://rationalgrid.ai/g/collective?highlight=121"
  end
end
