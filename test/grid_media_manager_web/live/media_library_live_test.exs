defmodule GridMediaManagerWeb.MediaLibraryLiveTest do
  use GridMediaManagerWeb.ConnCase

  import Phoenix.LiveViewTest

  alias GridMediaManager.Campaigns
  alias GridMediaManager.Campaigns.Campaign
  alias GridMediaManager.Campaigns.MediaAsset
  alias GridMediaManager.Repo

  test "lists every saved frame, including frames from an older renderer", %{conn: conn} do
    {campaign, asset, _body} = uploaded_asset_fixture(8)
    insert_asset(campaign, "Unsaved source", %{})

    {:ok, view, _html} = live(conn, ~p"/media-library")

    assert has_element?(view, "#media-library")
    assert has_element?(view, "#media-library-summary", "1")
    assert has_element?(view, "#asset-#{asset.id}-frame-1")

    assert has_element?(
             view,
             "#asset-#{asset.id}-frame-1 img[src='/media-library/assets/#{asset.id}/frames/1']"
           )

    assert has_element?(view, "#asset-#{asset.id}-frame-1", "Renderer 8")

    assert has_element?(
             view,
             "#inspect-campaign-#{asset.id}[href='/campaigns/#{campaign.id}/studio']"
           )

    refute has_element?(view, "#uploaded-assets", "Unsaved source")
  end

  test "serves an archived frame even when its renderer is no longer current", %{conn: conn} do
    {_campaign, asset, body} = uploaded_asset_fixture(7)

    conn = get(conn, ~p"/media-library/assets/#{asset.id}/frames/1")

    assert response(conn, 200) == body
    assert get_resp_header(conn, "content-type") == ["image/png; charset=utf-8"]
    assert get_resp_header(conn, "cache-control") == ["private, no-cache"]
  end

  defp uploaded_asset_fixture(renderer_version) do
    campaign =
      %Campaign{}
      |> Campaign.changeset(%{
        slug: "media-library-#{System.unique_integer([:positive])}",
        title: "Inspectable campaign",
        raw_payload: %{},
        fetched_at: DateTime.utc_now()
      })
      |> Repo.insert!()

    asset =
      insert_asset(campaign, "Inspectable video", %{
        "duration_seconds" => 12.5,
        "slides" => [
          %{"kind" => "node_text", "title" => "A complete title", "body" => "Frame copy"}
        ]
      })

    body = <<137, 80, 78, 71, 13, 10, 26, 10, 1, 2, 3, 4>>
    assert {:ok, asset} = Campaigns.store_client_artifact(asset, 1, body)
    path = get_in(asset.metadata, ["artifacts", "1", "path"])

    on_exit(fn -> File.rm(path) end)

    metadata = put_in(asset.metadata, ["artifacts", "1", "renderer_version"], renderer_version)

    asset =
      asset
      |> MediaAsset.changeset(%{metadata: metadata})
      |> Repo.update!()

    {campaign, asset, body}
  end

  defp insert_asset(campaign, title, metadata) do
    %MediaAsset{}
    |> MediaAsset.changeset(%{
      campaign_id: campaign.id,
      title: title,
      kind: "curated_carousel_video",
      url: "diagnostic://#{System.unique_integer([:positive])}",
      mime_type: "video/mp4",
      metadata: metadata
    })
    |> Repo.insert!()
  end
end
