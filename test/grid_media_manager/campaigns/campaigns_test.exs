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
end
