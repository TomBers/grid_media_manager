defmodule GridMediaManagerWeb.PromotionAssetControllerTest do
  use GridMediaManagerWeb.ConnCase

  alias GridMediaManager.Campaigns

  @png <<137, 80, 78, 71, 13, 10, 26, 10, 0, 1, 2, 3>>

  setup do
    previous_root = Application.get_env(:grid_media_manager, :artifact_store_path)

    root =
      Path.join(
        System.tmp_dir!(),
        "grid-media-manager-artifact-test-#{System.unique_integer([:positive])}"
      )

    Application.put_env(:grid_media_manager, :artifact_store_path, root)

    on_exit(fn ->
      File.rm_rf!(root)

      if previous_root do
        Application.put_env(:grid_media_manager, :artifact_store_path, previous_root)
      else
        Application.delete_env(:grid_media_manager, :artifact_store_path)
      end
    end)

    :ok
  end

  test "stores and serves a browser-rendered PNG", %{conn: conn} do
    assert {:ok, campaign} = Campaigns.import_payload(payload(), "client-artifact")
    assert {:ok, asset} = Campaigns.generate_grid_asset(campaign)

    upload_path = Path.join(System.tmp_dir!(), "client-artifact-#{asset.id}.png")
    File.write!(upload_path, @png)
    on_exit(fn -> File.rm(upload_path) end)

    upload = %Plug.Upload{path: upload_path, filename: "slide.png", content_type: "image/png"}

    conn =
      post(conn, ~p"/api/media-assets/#{asset.id}/artifacts/1", %{"artifact" => upload})

    assert %{"saved" => true, "index" => "1"} = json_response(conn, 201)

    conn = get(recycle(conn), ~p"/media-assets/#{asset.id}/artifacts/1")
    assert response_content_type(conn, :png) == "image/png; charset=utf-8"
    assert response(conn, 200) == @png
    assert get_resp_header(conn, "cache-control") == ["private, no-cache"]
  end

  test "rejects invalid and missing artifacts", %{conn: conn} do
    assert {:ok, campaign} = Campaigns.import_payload(payload(), "missing-client-artifact")
    assert {:ok, asset} = Campaigns.generate_grid_asset(campaign)

    assert response(get(conn, ~p"/media-assets/#{asset.id}/artifacts/1"), 404) ==
             "Media artifact not found"

    assert response(get(recycle(conn), ~p"/media-assets/not-an-id/artifacts/1"), 404) ==
             "Media artifact not found"
  end

  defp payload do
    %{
      "metadata" => %{
        "title" => "Client-rendered media",
        "slug" => "client-rendered-media",
        "url" => "https://rationalgrid.ai/g/client-rendered-media",
        "tags" => []
      },
      "graph" => %{"nodes" => [], "edges" => []},
      "highlights" => []
    }
  end
end
