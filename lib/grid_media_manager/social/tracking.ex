defmodule GridMediaManager.Social.Tracking do
  @moduledoc "Adds campaign attribution while preserving RationalGrid deep links."

  def url(url, platform, campaign_id, content) when is_binary(url) do
    uri = URI.parse(url)

    if uri.scheme in ["http", "https"] and uri.host in ["rationalgrid.ai", "www.rationalgrid.ai"] do
      query =
        URI.decode_query(uri.query || "")
        |> Map.merge(%{
          "utm_source" => platform,
          "utm_medium" => "social",
          "utm_campaign" => "grid-#{campaign_id}",
          "utm_content" => to_string(content)
        })

      URI.to_string(%{uri | query: URI.encode_query(query)})
    else
      url
    end
  end

  def url(url, _platform, _campaign_id, _content), do: url
end
