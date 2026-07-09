defmodule GridMediaManagerWeb.PromotionAssetController do
  use GridMediaManagerWeb, :controller

  alias GridMediaManager.Campaigns
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
        |> send_resp(200, ShareCard.node_image_svg(campaign, node, Map.get(params, "style")))
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
end
