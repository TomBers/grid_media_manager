defmodule GridMediaManager.CampaignsTest do
  use GridMediaManager.DataCase, async: true

  alias GridMediaManager.Campaigns

  describe "import_payload/2" do
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

    test "imports the simplified content payload without pre-rendered assets" do
      payload = simplified_payload()

      assert {:ok, campaign} =
               Campaigns.import_payload(payload, "what-can-a-brave-new-world-teach-us-1964bc")

      assert campaign.slug == "what-can-a-brave-new-world-teach-us-1964bc"
      assert campaign.title == "What can a brave new world teach us?"

      assets = Campaigns.list_media_assets(campaign)
      assert length(assets) == 2

      assert Enum.any?(
               assets,
               &(&1.kind == "grid_card" and &1.url == "/campaigns/#{campaign.id}/share-card.svg")
             )

      refute Enum.any?(assets, &(&1.kind == "key_node_card"))

      assert Enum.any?(
               assets,
               &(&1.kind == "highlight_card" and
                   &1.url == "/campaigns/#{campaign.id}/highlights/123/share-card.svg")
             )

      drafts = Campaigns.list_post_drafts(campaign)
      assert Enum.any?(drafts, &(&1.platform == "linkedin" and &1.angle == "explainer"))
      refute Enum.any?(drafts, &(&1.platform == "linkedin" and &1.angle == "key_node"))

      assert Campaigns.origin_question(campaign) == "What can a brave new world teach us?"
      assert Campaigns.first_answer_excerpt(campaign) == "A dystopian lesson about comfort."

      assert Campaigns.follow_up_questions(campaign) == [
               "If a drug like soma existed today...",
               "How do modern social media algorithms mimic..."
             ]

      assert [%{"question" => "If a drug like soma existed today..."}] =
               Campaigns.user_questions(campaign)

      assert [%{"text" => "Perfect comfort can become a cage."}] = Campaigns.highlights(campaign)
    end

    test "generates a key-node image asset on demand" do
      payload = simplified_payload()

      assert {:ok, campaign} =
               Campaigns.import_payload(payload, "what-can-a-brave-new-world-teach-us-1964bc")

      assert {:ok, asset} = Campaigns.generate_key_node_asset(campaign, "1")
      assert asset.kind == "key_node_card"
      assert asset.url == "/campaigns/#{campaign.id}/nodes/1/share-card.svg"
      assert asset.node_id == "1"

      assets = Campaigns.list_media_assets(campaign)
      assert length(Enum.filter(assets, &(&1.kind == "key_node_card"))) == 1

      drafts = Campaigns.list_post_drafts(campaign)
      assert Enum.any?(drafts, &(&1.platform == "linkedin" and &1.angle == "key_node"))

      assert {:ok, _asset} = Campaigns.generate_key_node_asset(campaign, "1")
      assets = Campaigns.list_media_assets(campaign)
      assert length(Enum.filter(assets, &(&1.kind == "key_node_card"))) == 1
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
