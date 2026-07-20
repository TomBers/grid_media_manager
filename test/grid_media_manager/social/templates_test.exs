defmodule GridMediaManager.Social.TemplatesTest do
  use ExUnit.Case, async: true

  alias GridMediaManager.Campaigns.Campaign
  alias GridMediaManager.Campaigns.MediaAsset
  alias GridMediaManager.Social.Platforms
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

  test "keeps source titles and quotes intact when they fit" do
    campaign = campaign()
    quote = "A complete quote that should never end with an ellipsis."
    asset = %MediaAsset{title: "A complete node title", text: quote, kind: "highlight_card"}

    body = Templates.body(campaign, asset, "linkedin", "highlight")

    assert body =~ quote
    assert body =~ campaign.title
    refute body =~ "…"
  end

  test "all generated suggestions stay within their platform limit without truncating source text" do
    campaign = %{campaign() | title: String.duplicate("A very long campaign title ", 180)}

    asset = %MediaAsset{
      id: 1,
      title: String.duplicate("A complete node title ", 180),
      kind: "key_node_card",
      text: String.duplicate("A complete source quote. ", 300),
      recommended_platforms: Platforms.ids()
    }

    campaign
    |> Templates.draft_attrs([asset])
    |> Enum.each(fn draft ->
      assert Platforms.within_limit?(draft.body, draft.platform)
      assert draft.body =~ "Learn more at RationalGrid.ai"
      refute String.ends_with?(draft.body, "…")
    end)
  end

  test "video assets receive distinct copy from their companion image" do
    campaign = campaign()

    image = %MediaAsset{
      id: 1,
      title: "Question quote",
      kind: "question_quote_card",
      text: "What should we value?"
    }

    video = %{image | id: 2, kind: "question_video"}

    image_copy = Templates.body(campaign, image, "instagram", "question_quote")
    video_copy = Templates.body(campaign, video, "instagram", "question_quote")

    refute image_copy == video_copy
    assert video_copy =~ "Pause on this question"
  end

  test "key-node copy keeps the full source text and ends with one clear CTA" do
    campaign = %{
      campaign()
      | raw_payload: %{
          "content" => %{
            "key_nodes" => [
              %{
                "id" => "node-1",
                "title" => "Why comfort can become a cage",
                "content" =>
                  "Comfort solves an immediate problem.\n\nIt can also make the cost of losing agency harder to notice."
              }
            ]
          }
        }
    }

    asset = %MediaAsset{
      id: 1,
      title: "Why comfort can become a cage",
      text: "Short excerpt",
      node_id: "node-1",
      kind: "key_node_card"
    }

    body = Templates.body(campaign, asset, "linkedin", "key_node")

    assert body =~ "Comfort solves an immediate problem."
    assert body =~ "It can also make the cost of losing agency harder to notice."
    assert body =~ "Learn more at RationalGrid.ai:"
    refute body =~ "Key node from"
    refute body =~ "The full grid shows"
  end

  defp campaign do
    %Campaign{
      id: 1,
      title: "What is the collective subconscious?",
      grid_url: "https://rationalgrid.ai/g/collective",
      tags: ["Psychology", "Philosophy"],
      raw_payload: %{}
    }
  end
end
