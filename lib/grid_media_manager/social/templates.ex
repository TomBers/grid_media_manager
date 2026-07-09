defmodule GridMediaManager.Social.Templates do
  @moduledoc """
  Deterministic social draft templates.

  These intentionally avoid LLMs. They only reuse fields provided by the
  RationalGrid media endpoint so internal users can get predictable copy quickly.
  """

  alias GridMediaManager.Campaigns.Campaign
  alias GridMediaManager.Campaigns.MediaAsset
  alias GridMediaManager.Social.Platforms

  @base_angles ~w(question explainer discussion)

  def draft_attrs(%Campaign{} = campaign, media_assets) when is_list(media_assets) do
    base_drafts =
      for platform <- Platforms.ids(),
          angle <- @base_angles do
        %{
          media_asset_id: nil,
          platform: platform,
          angle: angle,
          body: body(campaign, nil, platform, angle),
          status: "draft"
        }
      end

    asset_drafts =
      media_assets
      |> Enum.flat_map(fn asset ->
        platforms = asset_platforms(asset)
        angle = asset_angle(asset)

        Enum.map(platforms, fn platform ->
          %{
            media_asset_id: asset.id,
            platform: platform,
            angle: angle,
            body: body(campaign, asset, platform, angle),
            status: "draft"
          }
        end)
      end)

    base_drafts ++ asset_drafts
  end

  def angle_label("question"), do: "Question-first"
  def angle_label("explainer"), do: "Explainer"
  def angle_label("discussion"), do: "Discussion prompt"
  def angle_label("highlight"), do: "Highlight-first"
  def angle_label("key_node"), do: "Key node"
  def angle_label("visual"), do: "Visual asset"

  def angle_label(angle) when is_binary(angle) do
    angle |> String.replace("_", " ") |> String.capitalize()
  end

  def body(%Campaign{} = campaign, %MediaAsset{} = asset, platform, "highlight") do
    link = asset_link(campaign, asset)
    quote = asset.text |> fallback(campaign.title) |> truncate(platform_quote_limit(platform))

    case platform do
      "linkedin" ->
        "“#{quote}”\n\nThis highlight comes from a RationalGrid exploring #{campaign.title}. The map gives the quote more context by connecting it to related explanations, questions, and critiques.\n\nExplore the grid:\n#{link}"

      "instagram" ->
        "“#{quote}”\n\nA shareable RationalGrid highlight from: #{campaign.title}\n\nExplore the full argument map through the link.\n\n#{hashtags(campaign)}"

      "substack" ->
        "A useful excerpt from #{campaign.title}:\n\n“#{quote}”\n\nThe full RationalGrid maps the surrounding argument, related questions, and context.\n\n#{link}"

      _ ->
        "“#{quote}”\n\nA RationalGrid highlight from #{truncate(campaign.title, 84)}.\n#{link}"
    end
  end

  def body(%Campaign{} = campaign, %MediaAsset{} = asset, platform, "key_node") do
    link = asset_link(campaign, asset)
    node_title = asset.title |> fallback("Key node") |> truncate(120)
    excerpt = asset.text |> fallback(campaign.title) |> truncate(platform_quote_limit(platform))

    case platform do
      "linkedin" ->
        "Key node from #{campaign.title}: #{node_title}\n\n#{excerpt}\n\nExplore the full RationalGrid map:\n#{link}"

      "instagram" ->
        "Key node: #{node_title}\n\n#{excerpt}\n\nFrom the RationalGrid: #{campaign.title}\n\n#{hashtags(campaign)}"

      "substack" ->
        "A key node from #{campaign.title}:\n\n#{node_title}\n\n#{excerpt}\n\nThe full grid shows how this node connects to the surrounding argument.\n\n#{link}"

      _ ->
        "Key node from #{truncate(campaign.title, 88)}:\n#{node_title}\n\n#{link}"
    end
  end

  def body(%Campaign{} = campaign, %MediaAsset{} = asset, platform, "visual") do
    link = asset_link(campaign, asset)

    case platform do
      "linkedin" ->
        "New RationalGrid share card: #{campaign.title}\n\nThe grid maps an argument as a learning object, with key claims, explanations, and follow-up paths in one place.\n\nExplore the map:\n#{link}"

      "instagram" ->
        "New RationalGrid map: #{campaign.title}\n\nA visual entry point into the argument and the questions around it.\n\n#{hashtags(campaign)}"

      "substack" ->
        "I’m sharing a RationalGrid on #{campaign.title}. It turns the topic into a navigable map of explanations, questions, and related ideas.\n\n#{link}"

      _ ->
        "New RationalGrid: #{truncate(campaign.title, 120)}\n\nExplore the map:\n#{link}"
    end
  end

  def body(%Campaign{} = campaign, _asset, platform, "question") do
    question = ensure_question(campaign.title)

    case platform do
      "linkedin" ->
        "#{question}\n\nThis RationalGrid turns the question into an explorable argument map, connecting explanations, assumptions, and related lines of inquiry.\n\nExplore it here:\n#{campaign.grid_url}"

      "instagram" ->
        "#{question}\n\nThis RationalGrid maps the topic visually so people can explore the question, follow related claims, and keep learning.\n\n#{hashtags(campaign)}"

      "substack" ->
        "A question worth mapping: #{question}\n\nThis RationalGrid collects the explanation, related claims, and follow-up questions in a form that is easier to explore than a linear article.\n\n#{campaign.grid_url}"

      _ ->
        "#{question}\n\nA RationalGrid maps the argument and related questions.\n#{campaign.grid_url}"
    end
  end

  def body(%Campaign{} = campaign, _asset, platform, "explainer") do
    tags = campaign.tags |> Enum.take(3) |> Enum.join(", ")
    tag_line = if tags == "", do: "", else: "\n\nTopics: #{tags}"

    case platform do
      "linkedin" ->
        "New RationalGrid: #{campaign.title}\n\nThis grid maps the topic as a learning path: key explanations, connected questions, and the structure of the argument in one place.#{tag_line}\n\nExplore the map:\n#{campaign.grid_url}"

      "instagram" ->
        "New RationalGrid: #{campaign.title}\n\nA visual argument map for learning the topic and following the connected ideas.\n\n#{hashtags(campaign)}"

      "substack" ->
        "New RationalGrid: #{campaign.title}\n\nInstead of reading the topic as a single thread, this grid lets you explore it as a map: central explanations, related questions, and paths for deeper learning.#{tag_line}\n\n#{campaign.grid_url}"

      _ ->
        "New RationalGrid: #{truncate(campaign.title, 112)}\n\nA map for exploring the argument, not just reading about it.\n#{campaign.grid_url}"
    end
  end

  def body(%Campaign{} = campaign, _asset, platform, "discussion") do
    case platform do
      "linkedin" ->
        "What would change if more online discussions were mapped instead of flattened into comment threads?\n\nThis RationalGrid uses #{campaign.title} as an explorable argument map — a way to learn through structure, context, and follow-up questions.\n\nExplore it:\n#{campaign.grid_url}"

      "instagram" ->
        "What if learning a topic felt more like exploring a map than scrolling a feed?\n\nThis RationalGrid is a visual argument map for: #{campaign.title}\n\n#{hashtags(campaign)}"

      "substack" ->
        "Most social posts flatten an idea. A RationalGrid tries to preserve the structure: what is being claimed, what supports it, what follows, and what remains open.\n\nThis one maps: #{campaign.title}\n\n#{campaign.grid_url}"

      _ ->
        "What if online arguments were easier to map, explore, and learn from?\n\nExample RationalGrid: #{truncate(campaign.title, 92)}\n#{campaign.grid_url}"
    end
  end

  defp asset_angle(%MediaAsset{kind: "key_node_card"}), do: "key_node"
  defp asset_angle(%MediaAsset{text: text}) when text in [nil, ""], do: "visual"
  defp asset_angle(%MediaAsset{}), do: "highlight"

  defp asset_platforms(%MediaAsset{recommended_platforms: platforms}) do
    platforms = Enum.filter(platforms || [], &(&1 in Platforms.ids()))
    if platforms == [], do: Platforms.ids(), else: platforms
  end

  defp asset_link(%Campaign{} = campaign, %MediaAsset{} = asset) do
    highlight_link(campaign, asset) || node_link(campaign, asset) || campaign.grid_url ||
      asset.url
  end

  defp highlight_link(%Campaign{} = campaign, %MediaAsset{highlight_id: highlight_id})
       when is_integer(highlight_id) do
    campaign.raw_payload
    |> get_in(["raw", "highlights"])
    |> case do
      highlights when is_list(highlights) ->
        highlights
        |> Enum.find(&(Map.get(&1, "id") == highlight_id))
        |> case do
          %{"share_url" => share_url} when is_binary(share_url) -> share_url
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp highlight_link(_campaign, _asset), do: nil

  defp node_link(%Campaign{grid_url: grid_url}, %MediaAsset{node_id: node_id})
       when is_binary(grid_url) and grid_url != "" and is_binary(node_id) and node_id != "" do
    separator = if String.contains?(grid_url, "?"), do: "&", else: "?"
    grid_url <> separator <> URI.encode_query(%{node: node_id})
  end

  defp node_link(_campaign, _asset), do: nil

  defp ensure_question(title) do
    title = String.trim(title || "")

    if String.ends_with?(title, "?") do
      title
    else
      "What can we learn from #{title}?"
    end
  end

  defp hashtags(%Campaign{tags: tags}) do
    tags
    |> Enum.take(5)
    |> Enum.map(fn tag ->
      tag
      |> String.replace(~r/[^A-Za-z0-9]/, "")
      |> case do
        "" -> nil
        hashtag -> "##{hashtag}"
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
    |> fallback("#RationalGrid #ArgumentMapping")
  end

  defp platform_quote_limit("x"), do: 110
  defp platform_quote_limit("bluesky"), do: 130
  defp platform_quote_limit(_platform), do: 220

  defp truncate(nil, _max), do: ""

  defp truncate(text, max) when is_binary(text) and max > 1 do
    if String.length(text) <= max do
      text
    else
      truncated =
        text
        |> String.slice(0, max - 1)
        |> String.trim()

      truncated <> "…"
    end
  end

  defp fallback(nil, fallback), do: fallback
  defp fallback("", fallback), do: fallback
  defp fallback(value, _fallback), do: value
end
