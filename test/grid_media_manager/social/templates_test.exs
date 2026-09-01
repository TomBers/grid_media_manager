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
    assert body =~ "What Is the Collective Subconscious?"
    refute body =~ "…"
  end

  test "capitalizes grid and node titles in generated captions" do
    campaign = %{campaign() | title: "what can a brave new world teach us?"}

    asset = %MediaAsset{
      title: "why comfort can become a cage",
      kind: "key_node_card",
      text: "A short excerpt"
    }

    body = Templates.body(campaign, asset, "linkedin", "visual")
    node_body = Templates.body(campaign, asset, "linkedin", "key_node")

    assert body =~ "What Can a Brave New World Teach Us?"
    assert node_body =~ "Why Comfort Can Become a Cage"
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

  test "story video copy is adapted for each video platform" do
    campaign = campaign()

    video = %MediaAsset{
      id: 2,
      title: "What should we value?",
      kind: "curated_carousel_video",
      mime_type: "video/mp4"
    }

    instagram_copy = Templates.body(campaign, video, "instagram", "visual")
    youtube_copy = Templates.body(campaign, video, "youtube", "visual")

    refute instagram_copy == youtube_copy
    assert instagram_copy =~ "#"
    assert youtube_copy =~ "RationalGrid.ai"
  end

  test "adapts copy within each supported platform group" do
    campaign = campaign()

    text_asset = %MediaAsset{
      id: 1,
      title: "A useful highlight",
      kind: "highlight_card",
      text: "The important idea is easier to see when the pieces are connected."
    }

    video_asset = %MediaAsset{
      id: 2,
      title: "A useful highlight",
      kind: "curated_carousel_video",
      mime_type: "video/mp4",
      text: "The important idea is easier to see when the pieces are connected."
    }

    text_copies =
      Enum.map(Platforms.text_ids(), &Templates.body(campaign, text_asset, &1, "highlight"))

    video_copies =
      Enum.map(Platforms.video_ids(), &Templates.body(campaign, video_asset, &1, "highlight"))

    assert Enum.uniq(text_copies) |> length() == 3
    assert Enum.uniq(video_copies) |> length() >= 2
  end

  test "creates drafts only for the matching platform group for each asset" do
    campaign = campaign()

    image = %MediaAsset{id: 1, kind: "highlight_card", mime_type: "image/png", text: "A quote"}

    video = %MediaAsset{
      id: 2,
      kind: "curated_carousel_video",
      mime_type: "video/mp4",
      text: "A quote"
    }

    drafts = Templates.draft_attrs_for_platforms(campaign, [image, video], Platforms.ids())

    assert drafts |> Enum.filter(&(&1.media_asset_id == image.id)) |> Enum.map(& &1.platform) ==
             Platforms.text_ids()

    assert drafts |> Enum.filter(&(&1.media_asset_id == video.id)) |> Enum.map(& &1.platform) ==
             Platforms.video_ids()
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

  test "long-form posts keep the answer together and target LinkedIn and Facebook" do
    campaign = campaign()

    asset = %MediaAsset{
      id: 1,
      title: "Why comfort can become a cage",
      kind: "long_form_post",
      text: "The complete answer stays together in one post.",
      node_id: "node-1"
    }

    drafts = Templates.draft_attrs_for_platforms(campaign, [asset], Platforms.ids())

    assert Enum.map(drafts, & &1.platform) == Platforms.long_form_ids()
    assert Enum.all?(drafts, &(&1.body =~ "The complete answer stays together in one post."))
    assert Enum.all?(drafts, &(&1.body =~ "https://rationalgrid.ai/g/collective?node=node-1"))
    assert Enum.all?(drafts, fn draft -> Platforms.within_limit?(draft.body, draft.platform) end)
  end

  test "long-form drafts use social-safe plain text and retain RationalGrid links" do
    campaign = campaign()

    asset = %MediaAsset{
      id: 1,
      title: "A formatted answer",
      kind: "long_form_post",
      node_id: "node-1",
      text: """
      # A formatted answer

      This has **strong emphasis** and <em>HTML emphasis</em>.

      > A claim worth quoting

      - First implication
      - [Read the source](https://rationalgrid.ai/g/source-grid)

      | Prediction | Confidence |
      | --- | --- |
      | Better comprehension | High |
      """
    }

    for platform <- Platforms.long_form_ids() do
      body = Templates.body(campaign, asset, platform, "long_form")

      assert body =~ "A formatted answer"
      assert body =~ "This has strong emphasis and HTML emphasis."
      assert body =~ "“A claim worth quoting”"
      assert body =~ "• First implication"
      assert body =~ "Read the source — https://rationalgrid.ai/g/source-grid"
      assert body =~ "• Prediction: Better comprehension · Confidence: High"
      assert body =~ "Learn more at RationalGrid.ai:"
      assert body =~ "https://rationalgrid.ai/g/collective?node=node-1"
      refute body =~ "# A formatted answer"
      refute body =~ "**strong emphasis**"
      refute body =~ "<em>"
      refute body =~ "| --- |"
    end
  end

  test "long-form copy uses LinkedIn and Facebook limits instead of the X limit" do
    campaign = campaign()
    answer = String.duplicate("A complete formatted paragraph.\n\n", 160)
    asset = %MediaAsset{kind: "long_form_post", text: answer, node_id: "node-1"}

    linkedin = Templates.body(campaign, asset, "linkedin", "long_form")
    facebook = Templates.body(campaign, asset, "facebook", "long_form")

    assert String.length(linkedin) > 280
    assert Platforms.within_limit?(linkedin, "linkedin")
    assert Platforms.max_chars("facebook") == 5_000
    assert Platforms.within_limit?(facebook, "facebook")
    assert String.length(facebook) > 3_000
    refute facebook =~ String.trim(answer)
    assert facebook =~ "https://rationalgrid.ai/g/collective?node=node-1"
  end

  test "LinkedIn long-form copy ends at a complete section before a trailing list" do
    campaign = campaign()

    complete_argument =
      Enum.map_join(1..88, " ", fn index ->
        "Complete argument sentence #{index}."
      end)

    follow_up = String.duplicate("This question needs its full context to remain readable. ", 4)

    asset = %MediaAsset{
      kind: "long_form_post",
      node_id: "node-1",
      text: """
      # Main argument

      #{complete_argument}

      ## Follow-up questions

      1. #{follow_up}
      2. #{follow_up}
      3. #{follow_up}
      """
    }

    linkedin = Templates.body(campaign, asset, "linkedin", "long_form")
    facebook = Templates.body(campaign, asset, "facebook", "long_form")

    assert linkedin =~ "Complete argument sentence 88."
    refute linkedin =~ "Follow-up questions"
    refute linkedin =~ "1. This question"

    assert linkedin =~
             "\n\nRead the full argument and follow its connected questions.\nLearn more at RationalGrid.ai:"

    assert linkedin =~ "https://rationalgrid.ai/g/collective?node=node-1"

    assert facebook =~ "Follow-up questions"
    assert facebook =~ "3. This question"
  end

  test "long-form posts never create blank drafts" do
    campaign = campaign()
    asset = %MediaAsset{id: 1, kind: "long_form_post", title: "Fallback answer title", text: ""}

    drafts = Templates.draft_attrs_for_platforms(campaign, [asset], Platforms.long_form_ids())

    assert Enum.all?(drafts, &(&1.body =~ "Fallback answer title"))
    assert Enum.all?(drafts, &(&1.body =~ "https://rationalgrid.ai/g/collective"))
    assert Enum.all?(drafts, &(&1.body != ""))
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
