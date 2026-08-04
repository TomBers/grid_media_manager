defmodule GridMediaManagerWeb.PromotionAssetController do
  use GridMediaManagerWeb, :controller

  alias GridMediaManager.Campaigns
  alias GridMediaManager.Promotion.CarouselVideo
  alias GridMediaManager.Promotion.ShareCard

  def grid_card(conn, %{"id" => id} = params) do
    campaign = Campaigns.get_campaign!(id)

    conn
    |> put_png_cache_headers()
    |> send_resp(200, ShareCard.graph_image_png(campaign, Map.get(params, "style")))
  end

  def node_card(conn, %{"id" => id, "node_id" => node_id} = params) do
    campaign = Campaigns.get_campaign!(id)

    case ShareCard.find_key_node(campaign, node_id) do
      nil ->
        send_resp(conn, 404, "Key node not found")

      node ->
        conn
        |> put_png_cache_headers()
        |> send_resp(
          200,
          if params["cover"] == "title" do
            ShareCard.node_title_card_image_png(campaign, node, Map.get(params, "style"))
          else
            ShareCard.node_image_png(
              campaign,
              node,
              Map.get(params, "style"),
              Map.get(params, "format", "landscape")
            )
          end
        )
    end
  end

  def node_carousel_png(conn, %{"id" => id, "node_id" => node_id} = params) do
    campaign = Campaigns.get_campaign!(id)

    case ShareCard.find_key_node(campaign, node_id) do
      nil ->
        send_resp(conn, 404, "Key node not found")

      node ->
        conn
        |> put_png_cache_headers()
        |> send_resp(
          200,
          ShareCard.node_carousel_image_png(
            campaign,
            node,
            Map.get(params, "style"),
            Map.get(params, "slide", "1")
          )
        )
    end
  end

  def curated_carousel_slide(
        conn,
        %{"id" => id, "token" => token, "slide" => slide} = params
      ) do
    campaign = Campaigns.get_campaign!(id)

    case Campaigns.get_curated_carousel_asset(campaign, token) do
      nil ->
        send_resp(conn, 404, "Curated carousel not found")

      asset ->
        slides = Map.get(asset.metadata || %{}, "slides", [])

        conn
        |> put_png_cache_headers()
        |> send_resp(
          200,
          ShareCard.curated_carousel_image_png(
            campaign,
            slides,
            Map.get(params, "style") || asset.style,
            slide
          )
        )
    end
  end

  def curated_carousel_video(conn, %{"id" => id, "token" => token} = params) do
    campaign = Campaigns.get_campaign!(id)

    asset =
      Campaigns.get_curated_carousel_asset(campaign, token) ||
        Campaigns.get_curated_carousel_video_asset(campaign, token)

    case asset do
      nil ->
        send_resp(conn, 404, "Curated carousel not found")

      asset ->
        metadata = asset.metadata || %{}
        slides = Map.get(metadata, "slides", [])
        style = Map.get(params, "style") || asset.style
        frame_paths = Map.get(metadata, "browser_frame_paths", %{})

        CarouselVideo.render_curated(campaign, token, slides, style, frame_paths: frame_paths)
        |> send_short_video(conn, "rationalgrid-story-#{token}.mp4")
    end
  end

  def browser_frame(
        conn,
        %{"id" => id, "token" => token, "slide" => slide, "frame" => %Plug.Upload{} = upload}
      ) do
    case Campaigns.get_campaign(id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Campaign not found"})

      campaign ->
        with {:ok, body} <- File.read(upload.path),
             true <- upload.content_type == "image/png",
             true <- png_body?(body),
             true <- byte_size(body) <= 12_000_000,
             {:ok, _asset} <-
               Campaigns.store_curated_carousel_browser_frame(campaign, token, slide, body) do
          json(conn, %{saved: true, slide: slide})
        else
          false ->
            conn |> put_status(:unprocessable_entity) |> json(%{error: "Invalid PNG frame"})

          {:error, :not_found} ->
            conn |> put_status(:not_found) |> json(%{error: "Carousel not found"})

          {:error, :invalid_slide} ->
            conn |> put_status(:unprocessable_entity) |> json(%{error: "Invalid slide"})

          {:error, _reason} ->
            conn |> put_status(:unprocessable_entity) |> json(%{error: "Could not save frame"})
        end
    end
  end

  def browser_frame(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "A PNG frame is required"})
  end

  def node_browser_frame(
        conn,
        %{
          "id" => id,
          "node_id" => node_id,
          "slide" => slide,
          "frame" => %Plug.Upload{} = upload
        } = params
      ) do
    case Campaigns.get_campaign(id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Campaign not found"})

      campaign ->
        with {:ok, body} <- File.read(upload.path),
             true <- upload.content_type == "image/png",
             true <- png_body?(body),
             true <- byte_size(body) <= 12_000_000,
             {:ok, _asset} <-
               Campaigns.store_key_node_video_browser_frame(
                 campaign,
                 node_id,
                 slide,
                 body,
                 asset_id: Map.get(params, "asset_id")
               ) do
          json(conn, %{saved: true, slide: slide})
        else
          false ->
            conn |> put_status(:unprocessable_entity) |> json(%{error: "Invalid PNG frame"})

          {:error, :not_found} ->
            conn |> put_status(:not_found) |> json(%{error: "Node video not found"})

          {:error, :invalid_slide} ->
            conn |> put_status(:unprocessable_entity) |> json(%{error: "Invalid slide"})

          {:error, _reason} ->
            conn |> put_status(:unprocessable_entity) |> json(%{error: "Could not save frame"})
        end
    end
  end

  def node_browser_frame(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "A PNG frame is required"})
  end

  def node_carousel_video_frame(
        conn,
        %{"id" => id, "node_id" => node_id, "slide" => slide} = params
      ) do
    campaign = Campaigns.get_campaign!(id)

    case ShareCard.find_key_node(campaign, node_id) do
      nil ->
        send_resp(conn, 404, "Key node not found")

      node ->
        conn
        |> put_png_cache_headers()
        |> send_resp(
          200,
          ShareCard.node_short_video_frame_png(
            campaign,
            node,
            Map.get(params, "style"),
            slide
          )
        )
    end
  end

  def node_carousel_video(conn, %{"id" => id, "node_id" => node_id} = params) do
    campaign = Campaigns.get_campaign!(id)

    case ShareCard.find_key_node(campaign, node_id) do
      nil ->
        send_resp(conn, 404, "Key node not found")

      node ->
        asset = Campaigns.get_key_node_video_asset(campaign, node_id, Map.get(params, "style"))
        frame_paths = get_in((asset && asset.metadata) || %{}, ["browser_frame_paths"]) || %{}

        case CarouselVideo.render(campaign, node, Map.get(params, "style"),
               frame_paths: frame_paths
             ) do
          {:ok, path} ->
            conn
            |> put_resp_content_type("video/mp4")
            |> put_resp_header("cache-control", "public, max-age=3600")
            |> put_resp_header(
              "content-disposition",
              ~s(inline; filename="rationalgrid-#{campaign.id}-#{node_id}.mp4")
            )
            |> send_file(200, path)

          {:error, :ffmpeg_not_found} ->
            send_resp(conn, 503, "Video rendering requires FFmpeg")

          {:error, _reason} ->
            send_resp(conn, 500, "Could not render carousel video")
        end
    end
  end

  def question_card(conn, %{"id" => id, "question_id" => question_id} = params) do
    campaign = Campaigns.get_campaign!(id)

    case ShareCard.find_question(campaign, question_id) do
      nil ->
        send_resp(conn, 404, "Question not found")

      question ->
        conn
        |> put_png_cache_headers()
        |> send_resp(
          200,
          ShareCard.question_platform_image_png(
            campaign,
            question,
            Map.get(params, "style"),
            Map.get(params, "format", "landscape")
          )
        )
    end
  end

  def question_short_video(conn, %{"id" => id, "question_id" => question_id} = params) do
    campaign = Campaigns.get_campaign!(id)
    style = ShareCard.normalize_style(Map.get(params, "style"))

    case ShareCard.find_question(campaign, question_id) do
      nil ->
        send_resp(conn, 404, "Question not found")

      question ->
        CarouselVideo.render_static(
          {:question, campaign.id, question_id, style, question},
          fn -> ShareCard.question_platform_image_png(campaign, question, style, "short") end
        )
        |> send_short_video(conn, "rationalgrid-question-#{question_id}.mp4")
    end
  end

  def highlight_card(conn, %{"id" => id, "highlight_id" => highlight_id} = params) do
    campaign = Campaigns.get_campaign!(id)

    case ShareCard.find_highlight(campaign, highlight_id) do
      nil ->
        send_resp(conn, 404, "Highlight not found")

      highlight ->
        conn
        |> put_png_cache_headers()
        |> send_resp(
          200,
          ShareCard.highlight_platform_image_png(
            campaign,
            highlight,
            Map.get(params, "style"),
            Map.get(params, "format", "landscape")
          )
        )
    end
  end

  def highlight_short_video(conn, %{"id" => id, "highlight_id" => highlight_id} = params) do
    campaign = Campaigns.get_campaign!(id)
    style = ShareCard.normalize_style(Map.get(params, "style"))

    case ShareCard.find_highlight(campaign, highlight_id) do
      nil ->
        send_resp(conn, 404, "Highlight not found")

      highlight ->
        CarouselVideo.render_static(
          {:highlight, campaign.id, highlight_id, style, highlight},
          fn -> ShareCard.highlight_platform_image_png(campaign, highlight, style, "short") end
        )
        |> send_short_video(conn, "rationalgrid-highlight-#{highlight_id}.mp4")
    end
  end

  defp send_short_video({:ok, path}, conn, filename) do
    conn
    |> put_resp_content_type("video/mp4")
    |> put_resp_header("cache-control", "public, max-age=3600")
    |> put_resp_header("content-disposition", ~s(inline; filename="#{filename}"))
    |> send_file(200, path)
  end

  defp send_short_video({:error, :ffmpeg_not_found}, conn, _filename),
    do: send_resp(conn, 503, "Video rendering requires FFmpeg")

  defp send_short_video({:error, _reason}, conn, _filename),
    do: send_resp(conn, 500, "Could not render short video")

  defp png_body?(<<137, 80, 78, 71, _rest::binary>>), do: true
  defp png_body?(_body), do: false

  defp put_png_cache_headers(conn) do
    conn
    |> put_resp_content_type("image/png")
    |> put_resp_header("cache-control", "public, max-age=300")
  end
end
