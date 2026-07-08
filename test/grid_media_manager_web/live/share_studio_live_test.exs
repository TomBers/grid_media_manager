defmodule GridMediaManagerWeb.ShareStudioLiveTest do
  use GridMediaManagerWeb.ConnCase

  import Phoenix.LiveViewTest

  alias GridMediaManager.Campaigns

  test "renders grid summary, media assets, and draft composer", %{conn: conn} do
    assert {:ok, campaign} = Campaigns.import_payload(sample_payload(), "res.json")

    {:ok, view, _html} = live(conn, ~p"/campaigns/#{campaign.id}")

    assert has_element?(view, "#grid-summary-panel")
    assert has_element?(view, "#asset-gallery-panel")
    assert has_element?(view, "#draft-composer-panel")
    assert has_element?(view, "#platform-tab-linkedin")
    assert has_element?(view, "#post-drafts")
  end

  test "saves edited draft copy", %{conn: conn} do
    assert {:ok, campaign} = Campaigns.import_payload(sample_payload(), "res.json")
    [draft | _] = Campaigns.list_post_drafts(campaign, platform: "x", media_asset_id: "campaign")

    {:ok, view, _html} = live(conn, ~p"/campaigns/#{campaign.id}")

    view
    |> form("#draft-form-#{draft.id}", post_draft: %{body: "Updated copy from the editor"})
    |> render_change()

    assert Campaigns.get_post_draft!(draft.id).body == "Updated copy from the editor"
  end

  defp sample_payload do
    "res.json"
    |> File.read!()
    |> Jason.decode!()
  end
end
