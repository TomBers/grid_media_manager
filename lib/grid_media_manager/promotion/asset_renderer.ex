defmodule GridMediaManager.Promotion.AssetRenderer do
  @moduledoc """
  Reads finished browser-rendered artifacts for publishing.

  Visual composition deliberately does not happen on the server. PNGs are
  produced by the studio canvas, persisted by `ArtifactStore`, and read here
  when they need to be uploaded to object storage. Video encoding only packages
  those finished frames; it never lays out text or recreates a card.
  """

  alias GridMediaManager.Campaigns
  alias GridMediaManager.Campaigns.Campaign
  alias GridMediaManager.Campaigns.MediaAsset
  alias GridMediaManager.Promotion.ArtifactStore
  alias GridMediaManager.Promotion.CarouselVideo

  def render(%Campaign{}, %MediaAsset{mime_type: "video/mp4"} = asset) do
    indexes = Campaigns.media_asset_slide_indexes(asset)

    with {:ok, path} <- CarouselVideo.render_artifacts(asset, indexes) do
      File.read(path)
    end
  end

  def render(%Campaign{}, %MediaAsset{} = asset) do
    asset
    |> Campaigns.media_asset_slide_indexes()
    |> List.first()
    |> then(&ArtifactStore.read(asset, &1 || 1))
  end

  def render_all(%Campaign{} = campaign, %MediaAsset{mime_type: "video/mp4"} = asset) do
    with {:ok, body} <- render(campaign, asset), do: {:ok, [body]}
  end

  def render_all(%Campaign{}, %MediaAsset{} = asset) do
    ArtifactStore.read_all(asset, Campaigns.media_asset_slide_indexes(asset))
  end
end
