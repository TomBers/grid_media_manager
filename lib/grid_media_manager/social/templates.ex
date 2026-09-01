defmodule GridMediaManager.Social.Templates do
  @moduledoc """
  Deterministic social draft templates.

  These intentionally avoid LLMs. They only reuse fields provided by the
  RationalGrid media endpoint so internal users can get predictable copy quickly.
  """

  alias GridMediaManager.Campaigns.Campaign
  alias GridMediaManager.Campaigns.MediaAsset
  alias GridMediaManager.Promotion.Markdown
  alias GridMediaManager.Promotion.ShareCard
  alias GridMediaManager.RationalGrid.MediaPayload
  alias GridMediaManager.Social.Platforms

  def body(%Campaign{} = campaign, asset, platform, angle) do
    body_for_platform(campaign, asset, platform, angle)
  end

  def draft_attrs(%Campaign{} = campaign, media_assets) when is_list(media_assets) do
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
  end

  def draft_attrs_for_platforms(%Campaign{} = campaign, media_assets, platforms)
      when is_list(media_assets) and is_list(platforms) do
    media_assets
    |> Enum.flat_map(fn asset ->
      angle = asset_angle(asset)
      asset_platforms = asset_platforms(asset)
      platforms = Enum.filter(platforms, &(&1 in asset_platforms))

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
  end

  def angle_label("question"), do: "Question-first"
  def angle_label("explainer"), do: "Explainer"
  def angle_label("discussion"), do: "Discussion prompt"
  def angle_label("highlight"), do: "Highlight-first"
  def angle_label("key_node"), do: "Key node"
  def angle_label("question_quote"), do: "Question quote"
  def angle_label("visual"), do: "Visual asset"
  def angle_label("long_form"), do: "Long-form post"

  def angle_label(angle) when is_binary(angle) do
    angle |> String.replace("_", " ") |> String.capitalize()
  end

  defp body_for_platform(%Campaign{} = campaign, %MediaAsset{} = asset, platform, "highlight") do
    link = asset_link(campaign, asset)
    title = caption_title(campaign.title)
    quote = asset.text |> fallback(title)

    copy =
      case platform do
        "x" ->
          "“#{quote}”\n\nThis idea sits inside a larger question about #{title}.\n\n#{cta_line(link)}"

        "linkedin" ->
          "“#{quote}”\n\nA strong claim is more useful when its assumptions and consequences are visible. This one sits inside a larger question about #{title}.\n\n#{cta_line(link)}"

        "facebook" ->
          "“#{quote}”\n\nWhat does this change about how we see #{title}?\n\n#{cta_line(link)}"

        "instagram" ->
          "“#{quote}”\n\nA highlight from #{title}.\n\n#{cta_line(link)}\n\n#{hashtags(campaign)}"

        "substack" ->
          "A useful excerpt from #{title}:\n\n“#{quote}”\n\n#{cta_line(link)}"

        _ ->
          "“#{quote}”\n\n#{cta_line(link)}"
      end

    fit_to_platform(copy, platform, link)
  end

  defp body_for_platform(
         %Campaign{} = campaign,
         %MediaAsset{} = asset,
         platform,
         "question_quote"
       ) do
    link = asset_link(campaign, asset)
    title = caption_title(campaign.title)
    question = asset.text |> fallback(title)

    copy =
      case platform do
        "linkedin" ->
          "#{question}\n\nA question worth exploring in #{title}.\n\n#{cta_line(link)}"

        "facebook" ->
          "#{question}\n\nWhere do you stand—and what evidence would change your mind?\n\n#{cta_line(link)}"

        "instagram" ->
          "#{question}\n\nA question worth exploring in #{title}.\n\n#{cta_line(link)}\n\n#{hashtags(campaign)}"

        "substack" ->
          "A question worth exploring from #{title}:\n\n#{question}\n\n#{cta_line(link)}"

        _ ->
          "#{question}\n\n#{cta_line(link)}"
      end

    fit_to_platform(copy, platform, link)
  end

  defp body_for_platform(%Campaign{} = campaign, %MediaAsset{} = asset, platform, "key_node") do
    link = asset_link(campaign, asset)
    node_title = asset.title |> fallback("Key node") |> caption_title()
    node_text = full_node_text(campaign, asset)

    copy =
      case platform do
        "linkedin" ->
          "#{node_title}\n\n#{node_text}\n\n#{cta_line(link)}"

        "facebook" ->
          "#{node_title}\n\n#{node_text}\n\nWhich part of this argument is most convincing?\n\n#{cta_line(link)}"

        "instagram" ->
          "#{node_title}\n\n#{node_text}\n\n#{cta_line(link)}\n\n#{hashtags(campaign)}"

        "youtube" ->
          "#{node_title}\n\n#{node_text}\n\n#{cta_line(link)}\n\n#Shorts #RationalGrid"

        "substack" ->
          "#{node_title}\n\n#{node_text}\n\n#{cta_line(link)}"

        _ ->
          "#{node_title}\n\n#{node_text}\n\n#{cta_line(link)}"
      end

    fit_to_platform(copy, platform, link)
  end

  defp body_for_platform(
         %Campaign{} = campaign,
         %MediaAsset{kind: "long_form_post"} = asset,
         platform,
         "long_form"
       ) do
    source =
      asset.text
      |> fallback(asset.title)
      |> to_string()
      |> fallback(asset.title |> fallback("Long-form answer") |> to_string())

    sections = Markdown.social_sections(source)
    fit_long_form_to_platform(sections, platform, asset_link(campaign, asset))
  end

  defp body_for_platform(%Campaign{} = campaign, %MediaAsset{} = asset, platform, "visual") do
    link = asset_link(campaign, asset)
    title = caption_title(campaign.title)
    hook = visual_hook(asset, title)

    copy =
      case platform do
        "x" ->
          "#{hook}\n\nWhich assumption changes once you see the full argument?\n\n#{cta_line(link)}"

        "linkedin" ->
          "#{title}\n\nOne visual idea, placed inside its wider argument.\n\n#{cta_line(link)}"

        "facebook" ->
          "#{title}\n\nStart with the visual, then follow the evidence and decide where you stand.\n\n#{cta_line(link)}"

        "instagram" ->
          "#{title}\n\n#{hook}\n\nSwipe for the reasoning. Which part would you challenge?\n\n#{cta_line(link)}\n\n#{hashtags(campaign)}"

        "tiktok" ->
          "#{title}\n\n#{hook}\n\nWatch to the final connection, then tell us where the argument breaks.\n\n#{cta_line(link)}\n\n#{hashtags(campaign)}"

        "youtube" ->
          "#{title}\n\n#{hook}\n\nA concise visual argument: the claim, its tension, and the takeaway. What follows if it is right?\n\n#{cta_line(link)}\n\n#Shorts #RationalGrid"

        "substack" ->
          "#{title}\n\nA navigable map of explanations, questions, and related ideas.\n\n#{cta_line(link)}"

        _ ->
          "#{title}\n\n#{cta_line(link)}"
      end

    fit_to_platform(copy, platform, link)
  end

  defp body_for_platform(%Campaign{} = campaign, _asset, platform, "question") do
    question = ensure_question(campaign.title)

    copy =
      case platform do
        "linkedin" ->
          "#{question}\n\nFollow the claims, assumptions, and related lines of inquiry.\n\n#{cta_line(campaign.grid_url)}"

        "instagram" ->
          "#{question}\n\nFollow the related claims and keep learning.\n\n#{cta_line(campaign.grid_url)}\n\n#{hashtags(campaign)}"

        "substack" ->
          "A question worth mapping: #{question}\n\nFollow the explanation, related claims, and unanswered questions.\n\n#{cta_line(campaign.grid_url)}"

        _ ->
          "#{question}\n\n#{cta_line(campaign.grid_url)}"
      end

    fit_to_platform(copy, platform, campaign.grid_url)
  end

  defp body_for_platform(%Campaign{} = campaign, _asset, platform, "explainer") do
    title = caption_title(campaign.title)

    copy =
      case platform do
        "linkedin" ->
          "#{title}\n\nA learning path through the key explanations, connected questions, and structure of the topic.\n\n#{cta_line(campaign.grid_url)}"

        "instagram" ->
          "#{title}\n\nA visual learning path through the connected ideas.\n\n#{cta_line(campaign.grid_url)}\n\n#{hashtags(campaign)}"

        "substack" ->
          "#{title}\n\nExplore the topic as a map of central explanations, related questions, and paths for deeper learning.\n\n#{cta_line(campaign.grid_url)}"

        _ ->
          "#{title}\n\nA map for exploring the ideas, not just reading about them.\n#{cta_line(campaign.grid_url)}"
      end

    fit_to_platform(copy, platform, campaign.grid_url)
  end

  defp body_for_platform(%Campaign{} = campaign, _asset, platform, "discussion") do
    question = lead_question(campaign)

    copy =
      case platform do
        "linkedin" ->
          "#{question}\n\nWhat is claimed, what supports it, and what remains open?\n\n#{cta_line(campaign.grid_url)}"

        "instagram" ->
          "#{question}\n\nFollow the connected questions and decide where you land.\n\n#{cta_line(campaign.grid_url)}\n\n#{hashtags(campaign)}"

        "substack" ->
          "#{question}\n\nTrace what is claimed, what supports it, what follows, and what remains open.\n\n#{cta_line(campaign.grid_url)}"

        _ ->
          "#{question}\n\nWhere do you land?\n\n#{cta_line(campaign.grid_url)}"
      end

    fit_to_platform(copy, platform, campaign.grid_url)
  end

  defp full_node_text(%Campaign{} = campaign, %MediaAsset{} = asset) do
    node_text =
      with node_id when is_binary(node_id) and node_id != "" <- asset.node_id,
           node when is_map(node) <- ShareCard.find_key_node(campaign, node_id) do
        ShareCard.node_short_video_slides(campaign, node)
        |> Enum.map(&Map.get(&1, "body", ""))
        |> Enum.reject(&(String.trim(&1) == ""))
        |> Enum.join("\n\n")
      else
        _ -> ""
      end

    node_text |> fallback(asset.text) |> fallback(caption_title(campaign.title))
  end

  defp cta_line(link) do
    "Read the full argument and follow its connected questions.\nLearn more at RationalGrid.ai:\n#{link || "https://rationalgrid.ai"}"
  end

  defp lead_question(%Campaign{} = campaign) do
    MediaPayload.recommended_question(campaign.raw_payload) || ensure_question(campaign.title)
  end

  defp asset_angle(%MediaAsset{kind: kind})
       when kind in ["curated_carousel", "curated_carousel_video"],
       do: "visual"

  defp asset_angle(%MediaAsset{kind: "key_node_card"}),
    do: "key_node"

  defp asset_angle(%MediaAsset{kind: "long_form_post"}), do: "long_form"

  defp asset_angle(%MediaAsset{kind: "question_quote_card"}),
    do: "question_quote"

  defp asset_angle(%MediaAsset{text: text}) when text in [nil, ""], do: "visual"
  defp asset_angle(%MediaAsset{}), do: "highlight"

  defp asset_platforms(%MediaAsset{mime_type: "video/mp4"}), do: Platforms.video_ids()

  defp asset_platforms(%MediaAsset{kind: "long_form_post"}), do: Platforms.long_form_ids()

  defp asset_platforms(%MediaAsset{}), do: Platforms.text_ids()

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
    title = title |> caption_title() |> String.trim()

    if String.ends_with?(title, "?") do
      title
    else
      "What can we learn from #{title}?"
    end
  end

  defp caption_title(title) when is_binary(title) do
    title
    |> String.trim()
    |> String.split(~r/\s+/, trim: true)
    |> Enum.with_index()
    |> Enum.map_join(" ", fn {word, index} ->
      normalized = String.downcase(word)

      if index > 0 and
           normalized in [
             "a",
             "an",
             "and",
             "as",
             "at",
             "for",
             "in",
             "of",
             "on",
             "or",
             "the",
             "to"
           ] do
        normalized
      else
        String.capitalize(normalized)
      end
    end)
  end

  defp caption_title(title), do: title

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

  defp fit_to_platform(copy, platform, link) do
    if Platforms.within_limit?(copy, platform) do
      copy
    else
      fallback_copy = compact_fallback(link)

      if Platforms.within_limit?(fallback_copy, platform) do
        fallback_copy
      else
        "Learn more at RationalGrid.ai"
      end
    end
  end

  defp fit_long_form_to_platform(sections, platform, link) do
    cta = cta_line(link)

    copy =
      case platform do
        "facebook" ->
          sections
          |> Enum.take(3)
          |> Enum.join("\n\n")
          |> Kernel.<>("\n\nWhich part of this argument would change your mind?")

        _platform ->
          Enum.join(sections, "\n\n")
      end

    full_copy = copy <> "\n\n" <> cta

    if Platforms.within_limit?(full_copy, platform) do
      full_copy
    else
      limit = Platforms.max_chars(platform)
      available = max(limit - String.length(cta) - 5, 0)

      shortened =
        sections
        |> complete_sections_within(available)
        |> fallback(logical_blocks_within(copy, available))

      shortened_copy = shortened <> "\n\n…\n\n" <> cta

      if Platforms.within_limit?(shortened_copy, platform), do: shortened_copy, else: cta
    end
  end

  defp complete_sections_within(sections, limit) do
    sections
    |> Enum.reduce_while([], fn section, selected ->
      candidate = Enum.join(selected ++ [section], "\n\n")

      if String.length(candidate) <= limit do
        {:cont, selected ++ [section]}
      else
        {:halt, selected}
      end
    end)
    |> Enum.join("\n\n")
  end

  defp logical_blocks_within(copy, limit) do
    copy
    |> String.split(~r/\n{2,}/u, trim: true)
    |> group_list_blocks()
    |> Enum.reduce_while([], fn block, selected ->
      candidate = Enum.join(selected ++ [block], "\n\n")

      if String.length(candidate) <= limit do
        {:cont, selected ++ [block]}
      else
        {:halt, selected}
      end
    end)
    |> Enum.join("\n\n")
  end

  defp group_list_blocks(blocks) do
    {groups, list_items} =
      Enum.reduce(blocks, {[], []}, fn block, {groups, list_items} ->
        if list_block?(block) do
          {groups, list_items ++ [block]}
        else
          {append_list_group(groups, list_items) ++ [block], []}
        end
      end)

    append_list_group(groups, list_items)
  end

  defp list_block?(block), do: Regex.match?(~r/^(?:•|\d+[.)])\s+/u, block)

  defp append_list_group(groups, []), do: groups
  defp append_list_group(groups, items), do: groups ++ [Enum.join(items, "\n\n")]

  defp compact_fallback(link) when is_binary(link) and link != "" do
    cta_line(link)
  end

  defp compact_fallback(_link), do: "Learn more at RationalGrid.ai"

  defp visual_hook(%MediaAsset{} = asset, fallback) do
    asset.metadata
    |> Kernel.||(%{})
    |> Map.get("slides", [])
    |> Enum.reject(&(Map.get(&1, "kind") in ["cover", "cta"]))
    |> Enum.find_value(fn slide ->
      [Map.get(slide, "title"), Map.get(slide, "body")]
      |> Enum.find(&(is_binary(&1) and String.trim(&1) != ""))
    end)
    |> fallback(asset.text)
    |> fallback(fallback)
    |> String.trim()
    |> String.slice(0, 220)
  end

  defp fallback(nil, fallback), do: fallback
  defp fallback("", fallback), do: fallback
  defp fallback(value, _fallback), do: value
end
