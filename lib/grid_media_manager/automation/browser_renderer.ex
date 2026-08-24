defmodule GridMediaManager.Automation.BrowserRenderer do
  @moduledoc """
  Finalizes assets composed by the canonical Studio browser canvas.

  Missing frames are returned as resumable work rather than being recreated by a
  second server-side renderer. Once all PNGs exist, image artifacts are exposed in
  order and video artifacts are assembled with ffmpeg.
  """

  @behaviour GridMediaManager.Automation.Renderer

  alias GridMediaManager.Campaigns
  alias GridMediaManager.Campaigns.Campaign
  alias GridMediaManager.Campaigns.MediaAsset
  alias GridMediaManager.Promotion.ArtifactStore
  alias GridMediaManager.Promotion.CarouselVideo

  @impl true
  def render(%Campaign{} = campaign, %MediaAsset{id: asset_id}, _opts) do
    asset = Campaigns.get_media_asset!(asset_id)
    indexes = Campaigns.media_asset_slide_indexes(asset)
    missing_indexes = Enum.reject(indexes, &ArtifactStore.ready?(asset, [&1]))

    case missing_indexes do
      [] -> finalize(asset, indexes)
      missing -> {:pending, pending_details(campaign, asset, indexes, missing)}
    end
  end

  defp finalize(%MediaAsset{mime_type: "video/mp4"} = asset, indexes) do
    case CarouselVideo.render_artifacts(asset, indexes) do
      {:ok, path} ->
        {:ok,
         %{
           output_type: :video,
           mime_type: "video/mp4",
           path: path,
           indexes: indexes
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp finalize(%MediaAsset{} = asset, indexes) do
    artifacts =
      Enum.map(indexes, fn index ->
        artifact = ArtifactStore.artifact(asset, index)

        %{
          index: index,
          path: artifact["path"],
          mime_type: artifact["mime_type"],
          sha256: artifact["sha256"]
        }
      end)

    {:ok,
     %{
       output_type: :images,
       mime_type: "image/png",
       artifacts: artifacts,
       indexes: indexes
     }}
  end

  defp pending_details(campaign, asset, indexes, missing_indexes) do
    %{
      required_indexes: indexes,
      missing_indexes: missing_indexes,
      render_path: "/campaigns/#{campaign.id}/studio?step=review&assets=#{asset.id}&asset=all"
    }
  end
end
