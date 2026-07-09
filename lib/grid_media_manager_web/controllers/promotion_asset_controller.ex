defmodule GridMediaManagerWeb.PromotionAssetController do
  use GridMediaManagerWeb, :controller

  alias GridMediaManager.Campaigns
  alias GridMediaManager.Promotion.ShareCard

  def grid_card(conn, %{"id" => id}) do
    campaign = Campaigns.get_campaign!(id)

    conn
    |> put_svg_cache_headers()
    |> send_resp(200, ShareCard.graph_image_svg(campaign))
  end

  def highlight_card(conn, %{"id" => id, "highlight_id" => highlight_id}) do
    campaign = Campaigns.get_campaign!(id)

    case ShareCard.find_highlight(campaign, highlight_id) do
      nil ->
        send_resp(conn, 404, "Highlight not found")

      highlight ->
        conn
        |> put_svg_cache_headers()
        |> send_resp(200, ShareCard.highlight_image_svg(campaign, highlight))
    end
  end

  defp put_svg_cache_headers(conn) do
    conn
    |> put_resp_content_type("image/svg+xml")
    |> put_resp_header("cache-control", "public, max-age=300")
  end
end
