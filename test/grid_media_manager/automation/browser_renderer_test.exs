defmodule GridMediaManager.Automation.BrowserRendererTest do
  use GridMediaManager.DataCase

  alias GridMediaManager.Automation.BrowserRenderer
  alias GridMediaManager.Campaigns

  @png <<137, 80, 78, 71, 13, 10, 26, 10, 0, 1, 2, 3>>

  setup do
    previous_root = Application.get_env(:grid_media_manager, :artifact_store_path)

    root =
      Path.join(
        System.tmp_dir!(),
        "grid-media-manager-browser-renderer-test-#{System.unique_integer([:positive])}"
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

  test "reports missing canvas frames and finalizes them in order once uploaded" do
    assert {:ok, campaign} =
             Campaigns.import_payload(
               %{
                 "metadata" => %{
                   "title" => "Browser rendering",
                   "slug" => "browser-rendering",
                   "url" => "https://rationalgrid.ai/g/browser-rendering"
                 },
                 "graph" => %{"nodes" => [], "edges" => []},
                 "highlights" => []
               },
               "browser-rendering"
             )

    assert {:ok, asset} = Campaigns.generate_grid_asset(campaign)
    indexes = Campaigns.media_asset_slide_indexes(asset)

    assert {:pending, pending} = BrowserRenderer.render(campaign, asset, [])
    assert pending.required_indexes == indexes
    assert pending.missing_indexes == indexes
    assert pending.render_path =~ "assets=#{asset.id}"

    rendered_asset =
      Enum.reduce(indexes, asset, fn index, current_asset ->
        assert {:ok, updated_asset} =
                 Campaigns.store_client_artifact(current_asset, index, @png)

        updated_asset
      end)

    assert {:ok, completed} = BrowserRenderer.render(campaign, rendered_asset, [])
    assert completed.output_type == :images
    assert completed.indexes == indexes
    assert Enum.map(completed.artifacts, & &1.index) == indexes
    assert Enum.all?(completed.artifacts, &File.regular?(&1.path))
  end
end
