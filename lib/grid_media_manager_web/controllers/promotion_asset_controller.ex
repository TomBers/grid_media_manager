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
          ShareCard.question_image_svg(campaign, question, Map.get(params, "style"))
        )
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
          ShareCard.highlight_image_svg(campaign, highlight, Map.get(params, "style"))
        )
    end
  end

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
