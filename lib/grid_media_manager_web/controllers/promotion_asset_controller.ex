defmodule GridMediaManagerWeb.PromotionAssetController do
  use GridMediaManagerWeb, :controller

  alias GridMediaManager.Campaigns
  alias GridMediaManager.Promotion.CarouselVideo
  alias GridMediaManager.Promotion.ShareCard

  def grid_card(conn, %{"id" => id} = params) do
    campaign = Campaigns.get_campaign!(id)

    conn
    |> put_svg_cache_headers()
    |> send_resp(200, ShareCard.graph_image_svg(campaign, Map.get(params, "style")))
  end

  def node_card(conn, %{"id" => id, "node_id" => node_id} = params) do
    campaign = Campaigns.get_campaign!(id)

    case ShareCard.find_key_node(campaign, node_id) do
      nil ->
        send_resp(conn, 404, "Key node not found")

      node ->
        conn
        |> put_svg_cache_headers()
        |> send_resp(200, node_svg(campaign, node, params))
    end
  end

  def node_carousel(conn, %{"id" => id, "node_id" => node_id} = params) do
    campaign = Campaigns.get_campaign!(id)

    case ShareCard.find_key_node(campaign, node_id) do
      nil ->
        send_resp(conn, 404, "Key node not found")

      node ->
        conn
        |> put_svg_cache_headers()
        |> send_resp(
          200,
          ShareCard.node_carousel_image_svg(
            campaign,
            node,
            Map.get(params, "style"),
            Map.get(params, "slide", "1")
          )
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

  def node_carousel_video(conn, %{"id" => id, "node_id" => node_id} = params) do
    campaign = Campaigns.get_campaign!(id)

    case ShareCard.find_key_node(campaign, node_id) do
      nil ->
        send_resp(conn, 404, "Key node not found")

      node ->
        case CarouselVideo.render(campaign, node, Map.get(params, "style")) do
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
        |> put_svg_cache_headers()
        |> send_resp(
          200,
          ShareCard.question_platform_image_svg(
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
        |> put_svg_cache_headers()
        |> send_resp(
          200,
          ShareCard.highlight_platform_image_svg(
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

  defp put_svg_cache_headers(conn) do
    conn
    |> put_resp_content_type("image/svg+xml")
    |> put_resp_header("cache-control", "public, max-age=300")
  end

  defp put_png_cache_headers(conn) do
    conn
    |> put_resp_content_type("image/png")
    |> put_resp_header("cache-control", "public, max-age=300")
  end

  defp node_svg(campaign, node, %{"format" => "portrait"} = params) do
    ShareCard.node_reading_image_svg(campaign, node, Map.get(params, "style"))
  end

  defp node_svg(campaign, node, %{"format" => "linkedin"} = params) do
    ShareCard.node_linkedin_image_svg(campaign, node, Map.get(params, "style"))
  end

  defp node_svg(campaign, node, params) do
    ShareCard.node_image_svg(campaign, node, Map.get(params, "style"))
  end
end
