defmodule GridMediaManagerWeb.PromotionAssetController do
  use GridMediaManagerWeb, :controller

  alias GridMediaManager.Campaigns
  alias GridMediaManager.Promotion.ArtifactStore
  alias GridMediaManager.Promotion.CarouselVideo

  def artifact(conn, %{"id" => id, "index" => index}) do
    with asset when not is_nil(asset) <- Campaigns.get_media_asset(id),
         {index, ""} when index > 0 <- Integer.parse(index),
         {:ok, body} <- ArtifactStore.read(asset, index) do
      conn
      |> put_resp_content_type("image/png")
      |> put_resp_header("cache-control", "private, no-cache")
      |> send_resp(200, body)
    else
      _error -> send_resp(conn, 404, "Media artifact not found")
    end
  end

  def video_artifact(conn, %{"id" => id}) do
    with asset when not is_nil(asset) <- Campaigns.get_media_asset(id),
         true <- asset.mime_type == "video/mp4",
         indexes <- Campaigns.media_asset_slide_indexes(asset),
         {:ok, path} <- CarouselVideo.render_artifacts(asset, indexes) do
      conn
      |> put_resp_content_type("video/mp4")
      |> put_resp_header("cache-control", "private, max-age=3600")
      |> put_resp_header(
        "content-disposition",
        ~s(inline; filename="rationalgrid-#{asset.id}.mp4")
      )
      |> send_file(200, path)
    else
      false -> send_resp(conn, 404, "Video artifact not found")
      {:error, :ffmpeg_not_found} -> send_resp(conn, 503, "Video encoding is unavailable")
      _error -> send_resp(conn, 409, "Save every browser-rendered frame first")
    end
  end

  def client_artifact(
        conn,
        %{"id" => id, "index" => index, "artifact" => %Plug.Upload{} = upload}
      ) do
    renderer_version = conn |> get_req_header("x-canvas-renderer-version") |> List.first()

    with asset when not is_nil(asset) <- Campaigns.get_media_asset(id),
         true <- upload.content_type == "image/png",
         {:ok, body} <- File.read(upload.path),
         {:ok, asset} <-
           Campaigns.store_client_artifact(asset, index, body, renderer_version) do
      conn
      |> put_status(:created)
      |> json(%{
        saved: true,
        index: index,
        url: Campaigns.media_asset_artifact_url(asset, index)
      })
    else
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Media asset not found"})

      false ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "A PNG is required"})

      {:error, :invalid_slide} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "Invalid slide"})

      {:error, :stale_renderer} ->
        conn
        |> put_status(:conflict)
        |> json(%{error: "Refresh the page before saving this media"})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Could not save artifact", reason: inspect(reason)})
    end
  end

  def client_artifact(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "A PNG artifact is required"})
  end
end
