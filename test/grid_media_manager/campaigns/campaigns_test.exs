defmodule GridMediaManager.CampaignsTest do
  use GridMediaManager.DataCase, async: true

  alias GridMediaManager.Campaigns
  alias GridMediaManager.Promotion.ShareCard

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
      assert grid_asset.url == "/campaigns/#{campaign.id}/share-card.svg?style=gradient_poster"

      assert {:ok, highlight_asset} =
               Campaigns.generate_highlight_asset(campaign, 123, "warm_paper")

      assert highlight_asset.kind == "highlight_card"
      assert highlight_asset.style == "warm_paper"

      assert highlight_asset.url ==
               "/campaigns/#{campaign.id}/highlights/123/share-card.svg?style=warm_paper"

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
      assert asset.url == "/campaigns/#{campaign.id}/questions/#{question_id}/share-card.svg"

      assert {:ok, styled_asset} =
               Campaigns.generate_question_asset(campaign, question_id, "minimal_academic")

      assert styled_asset.style == "minimal_academic"

      assert styled_asset.url ==
               "/campaigns/#{campaign.id}/questions/#{question_id}/share-card.svg?style=minimal_academic"

      question_assets =
        Campaigns.list_media_assets(campaign) |> Enum.filter(&(&1.kind == "question_quote_card"))

      assert length(question_assets) == 2

      drafts = Campaigns.list_post_drafts(campaign)

      assert Enum.any?(
               drafts,
               &(&1.platform == "linkedin" and &1.angle == "question_quote" and
                   String.contains?(&1.body, long_question))
             )
    end

    test "generates a key-node image asset on demand" do
      payload = simplified_payload()

      assert {:ok, campaign} =
               Campaigns.import_payload(payload, "what-can-a-brave-new-world-teach-us-1964bc")

      assert {:ok, asset} = Campaigns.generate_key_node_asset(campaign, "1")
      assert asset.kind == "key_node_card"
      assert asset.style == "editorial_dark"
      assert asset.url == "/campaigns/#{campaign.id}/nodes/1/share-card.svg"
      assert asset.node_id == "1"

      assert {:ok, styled_asset} = Campaigns.generate_key_node_asset(campaign, "1", "warm_paper")
      assert styled_asset.style == "warm_paper"

      assert styled_asset.url ==
               "/campaigns/#{campaign.id}/nodes/1/share-card.svg?style=warm_paper"

      assets = Campaigns.list_media_assets(campaign)
      assert length(Enum.filter(assets, &(&1.kind == "key_node_card"))) == 2

      drafts = Campaigns.list_post_drafts(campaign)
      assert Enum.any?(drafts, &(&1.platform == "linkedin" and &1.angle == "key_node"))

      assert {:ok, _asset} = Campaigns.generate_key_node_asset(campaign, "1")
      assets = Campaigns.list_media_assets(campaign)
      assert length(Enum.filter(assets, &(&1.kind == "key_node_card"))) == 2
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
