defmodule GridMediaManager.Promotion.ShareCard do
  @moduledoc """
  Plans editable social content without rendering it.

  Visual composition belongs to the browser canvas. This module deliberately
  returns only styles, normalized slide content, and media-asset metadata so it
  can move into RationalGrid without bringing a server-side graphics engine.
  """

  alias GridMediaManager.Campaigns.Campaign
  alias GridMediaManager.Promotion.Markdown
  alias GridMediaManager.RationalGrid.MediaPayload
  alias GridMediaManager.Social.Platforms

  @default_style "editorial_dark"
  @carousel_reading_max_characters 360

  @styles [
    %{
      id: "minimal_light",
      label: "Minimal light",
      description: "Black on white · quiet and universal",
      category: "Foundation"
    },
    %{
      id: "minimal_dark",
      label: "Minimal dark",
      description: "White on black · focused and high contrast",
      category: "Foundation"
    },
    %{
      id: "editorial_dark",
      label: "Editorial dark",
      description: "Premium dark · quotes and explainers",
      category: "Social"
    },
    %{
      id: "gradient_poster",
      label: "Gradient poster",
      description: "High-energy color · hooks and launches",
      category: "Social"
    },
    %{
      id: "minimal_academic",
      label: "Academic slate",
      description: "Cool light editorial · thoughtful explainers",
      category: "Social"
    },
    %{
      id: "warm_paper",
      label: "Warm editorial",
      description: "Amber cinematic · reflective excerpts",
      category: "Social"
    },
    %{
      id: "signal_red",
      label: "Signal red",
      description: "High urgency · debate prompts and bold hooks",
      category: "Social"
    },
    %{
      id: "deep_ocean",
      label: "Deep ocean",
      description: "Analytical dark · complex explainers",
      category: "Social"
    },
    %{
      id: "newsprint",
      label: "Newsprint",
      description: "Tactile print · quotes and cultural topics",
      category: "Social"
    }
  ]

  def styles, do: @styles
  def default_style, do: @default_style

  def normalize_style(style) when is_binary(style) do
    if Enum.any?(@styles, &(&1.id == style)), do: style, else: @default_style
  end

  def normalize_style(_style), do: @default_style

  def asset_attrs(%Campaign{}), do: []

  def grid_asset_attr(%Campaign{} = campaign, style \\ @default_style) do
    style = normalize_style(style)

    %{
      title: campaign.title,
      kind: "grid_card",
      url: asset_identity(campaign, "grid", campaign.id, style, "portrait"),
      mime_type: "image/png",
      text: campaign.title,
      node_id: nil,
      highlight_id: nil,
      recommended_platforms: Platforms.text_ids(),
      style: style,
      source_type: "grid",
      source_id: to_string(campaign.id),
      metadata:
        image_metadata("portrait", [%{"kind" => "cover", "title" => campaign.title, "body" => ""}])
    }
  end

  def curated_carousel_image_path(%Campaign{} = campaign, token, slide, style \\ @default_style) do
    asset_identity(campaign, "curated-carousel", "#{token}-#{slide}", style, "portrait")
  end

  def question_id(question_text, node_id \\ nil) do
    :crypto.hash(:sha256, "#{node_id || ""}|#{question_text}")
    |> Base.url_encode64(padding: false)
    |> binary_part(0, 16)
  end

  def questions(%Campaign{} = campaign) do
    user_questions =
      campaign.raw_payload
      |> MediaPayload.user_questions()
      |> Enum.map(&question_from_map(&1, "user_question"))

    answer_questions =
      campaign.raw_payload
      |> MediaPayload.answer_questions()
      |> Enum.map(&question_from_map(&1, "answer_question"))

    follow_up_questions =
      campaign.raw_payload
      |> MediaPayload.follow_up_questions()
      |> Enum.map(&question_from_value(&1, "follow_up_question"))

    (user_questions ++ answer_questions ++ follow_up_questions)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1["id"])
  end

  def find_question(%Campaign{} = campaign, question_id) do
    Enum.find(questions(campaign), &(&1["id"] == to_string(question_id)))
  end

  def find_key_node(%Campaign{} = campaign, node_id) do
    campaign.raw_payload
    |> MediaPayload.key_nodes()
    |> Enum.find(&(to_string(value(&1, "id")) == to_string(node_id)))
    |> enrich_origin_node(campaign)
  end

  def find_highlight(%Campaign{} = campaign, highlight_id) do
    expected_id = integer_value(highlight_id)

    campaign.raw_payload
    |> MediaPayload.highlights()
    |> Enum.find(&(integer_value(value(&1, "id")) == expected_id))
  end

  def carousel_slides(%Campaign{} = campaign, node) when is_map(node) do
    node_title = node |> value("title") |> present_string() |> fallback("Key idea")

    content_slides =
      campaign
      |> node_content(node)
      |> Markdown.sections()
      |> Enum.flat_map(fn section ->
        section.blocks
        |> Markdown.paginate_blocks(420)
        |> Enum.with_index()
        |> Enum.map(fn {blocks, page_index} ->
          title = if page_index == 0, do: section.title, else: "#{section.title} · continued"

          %{
            "kind" => "node_text",
            "label" => "Argument",
            "title" => title,
            "body" => Markdown.readable_text(blocks),
            "blocks" => stringify_blocks(blocks)
          }
        end)
      end)

    [
      %{
        "kind" => "cover",
        "label" => "Thesis",
        "title" => node_title,
        "body" => "Follow the reasoning, test the assumptions, and decide where you stand."
      }
      | content_slides
    ] ++ [cta_slide()]
  end

  def node_reading_slides(%Campaign{} = campaign, node) when is_map(node) do
    node_title = node |> value("title") |> present_string() |> fallback("Key idea")

    content_slides =
      campaign
      |> node_content(node)
      |> Markdown.sections()
      |> Enum.flat_map(fn section ->
        section.blocks
        |> Markdown.paginate_blocks(@carousel_reading_max_characters)
        |> Enum.map(fn blocks ->
          %{
            "kind" => "node_text",
            "label" => "",
            "title" => "",
            "body" => Markdown.readable_text(blocks),
            "blocks" => stringify_blocks(blocks)
          }
        end)
      end)

    [%{"kind" => "node_title", "label" => "", "title" => node_title, "body" => ""}] ++
      content_slides ++ [cta_slide()]
  end

  def node_short_video_slides(%Campaign{} = campaign, node),
    do: node_reading_slides(campaign, node)

  def curated_carousel_selected_slide_indexes(slides, selection \\ nil) when is_list(slides) do
    slide_count = length(slides)
    content_count = max(slide_count - 1, 0)

    indexes =
      case selection do
        nil -> if(content_count > 0, do: Enum.to_list(1..content_count), else: [])
        values when is_list(values) -> values
        _other -> []
      end
      |> Enum.map(&integer_value/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.filter(&(&1 >= 1 and &1 <= content_count))

    if slide_count == 0, do: [], else: indexes ++ [slide_count]
  end

  def curated_carousel_selected_slides(slides, selection \\ nil) when is_list(slides) do
    slides
    |> curated_carousel_selected_slide_indexes(selection)
    |> Enum.map(&Enum.at(slides, &1 - 1))
    |> Enum.reject(&is_nil/1)
  end

  def key_node_carousel_asset_attrs(%Campaign{} = campaign, node, style \\ @default_style) do
    style = normalize_style(style)
    node_id = node |> value("id") |> to_string()
    node_title = node |> value("title") |> present_string() |> fallback("Key idea")
    slides = carousel_slides(campaign, node)

    slides
    |> Enum.with_index(1)
    |> Enum.map(fn {slide, index} ->
      %{
        title: "#{node_title} · Slide #{index}",
        kind: "key_node_carousel_slide",
        url: asset_identity(campaign, "node-carousel", "#{node_id}-#{index}", style, "portrait"),
        mime_type: "image/png",
        text: slide["body"],
        node_id: node_id,
        highlight_id: nil,
        recommended_platforms: if(index == 1, do: Platforms.text_ids(), else: []),
        style: style,
        source_type: "key_node_carousel",
        source_id: "#{node_id}|#{index}",
        metadata:
          image_metadata("portrait", [slide])
          |> Map.merge(%{"slide_index" => index, "slide_count" => length(slides)}),
        carousel_cover?: index == 1
      }
    end)
  end

  def key_node_asset_attr(
        %Campaign{} = campaign,
        node,
        style \\ @default_style,
        format \\ "landscape"
      ) do
    style = normalize_style(style)
    format = normalize_image_format(format)
    node_id = node |> value("id") |> to_string()
    title = node |> value("title") |> present_string() |> fallback("Key idea")
    body = node |> value("excerpt") |> present_string() |> fallback(node_content(campaign, node))
    slide = %{"kind" => "node_text", "label" => "Key idea", "title" => title, "body" => body}

    %{
      title: title,
      kind: "key_node_card",
      url: asset_identity(campaign, "node", node_id, style, format),
      mime_type: "image/png",
      text: body,
      node_id: node_id,
      highlight_id: nil,
      recommended_platforms: Platforms.text_ids(),
      style: style,
      source_type: "key_node",
      source_id: node_id,
      metadata: image_metadata(format, [slide])
    }
  end

  def key_node_long_form_asset_attr(%Campaign{} = campaign, node, style \\ @default_style) do
    attrs = key_node_asset_attr(campaign, node, style, "portrait")
    title = node |> value("title") |> present_string() |> fallback("Key idea")
    body = node_content(campaign, node)
    slide = %{"kind" => "cover", "label" => "", "title" => title, "body" => ""}

    %{
      attrs
      | kind: "long_form_post",
        title: "#{title} · Longer post",
        text: body,
        url: asset_identity(campaign, "long-form", attrs.source_id, attrs.style, "portrait"),
        source_type: "long_form_post",
        metadata:
          attrs.metadata
          |> Map.put("content_type", "long_form")
          |> Map.put("slides", [slide])
          |> Map.put("slide_count", 1)
    }
  end

  def question_asset_attr(
        %Campaign{} = campaign,
        question,
        style \\ @default_style,
        format \\ "landscape"
      ) do
    style = normalize_style(style)
    format = normalize_image_format(format)

    id =
      value(question, "id") ||
        question_id(value(question, "question"), value(question, "node_id"))

    text = question |> value("question") |> present_string()

    if text do
      slide = %{"kind" => "quote", "label" => "Question", "title" => text, "body" => ""}

      %{
        title: "Question",
        kind: "question_quote_card",
        url: asset_identity(campaign, "question", id, style, format),
        mime_type: "image/png",
        text: text,
        node_id: value(question, "node_id") |> nullable_string(),
        highlight_id: nil,
        recommended_platforms: Platforms.text_ids(),
        style: style,
        source_type: "question",
        source_id: to_string(id),
        metadata: image_metadata(format, [slide])
      }
    end
  end

  def highlight_asset_attr(
        %Campaign{} = campaign,
        highlight,
        style \\ @default_style,
        format \\ "landscape"
      ) do
    style = normalize_style(style)
    format = normalize_image_format(format)
    id = integer_value(value(highlight, "id"))
    text = highlight_text(highlight)

    if id && text do
      slide = %{"kind" => "highlight", "label" => "Highlight", "title" => text, "body" => ""}

      %{
        title: "Highlighted quote",
        kind: "highlight_card",
        url: asset_identity(campaign, "highlight", id, style, format),
        mime_type: "image/png",
        text: text,
        node_id: value(highlight, "node_id") |> nullable_string(),
        highlight_id: id,
        recommended_platforms: Platforms.text_ids(),
        style: style,
        source_type: "highlight",
        source_id: to_string(id),
        metadata: image_metadata(format, [slide])
      }
    end
  end

  def question_short_video_asset_attr(%Campaign{} = campaign, question, style) do
    question_asset_attr(campaign, question, style, "short")
    |> Map.merge(%{
      title: "Question · Short video",
      kind: "question_video",
      mime_type: "video/mp4",
      recommended_platforms: Platforms.video_ids(),
      source_type: "question_video"
    })
  end

  def highlight_short_video_asset_attr(%Campaign{} = campaign, highlight, style) do
    highlight_asset_attr(campaign, highlight, style, "short")
    |> Map.merge(%{
      title: "Highlight · Short video",
      kind: "highlight_video",
      mime_type: "video/mp4",
      recommended_platforms: Platforms.video_ids(),
      source_type: "highlight_video"
    })
  end

  def page_title(%Campaign{} = campaign, highlight),
    do: highlight_text(highlight) |> fallback(campaign.title)

  def page_description(%Campaign{} = campaign, highlight),
    do: highlight_text(highlight) |> fallback(campaign.title)

  def node_title(%Campaign{} = campaign, node_id) do
    case find_key_node(campaign, node_id) do
      node when is_map(node) ->
        value(node, "title") |> present_string() |> fallback(campaign.title)

      _node ->
        campaign.title
    end
  end

  defp question_from_map(question, kind) when is_map(question) do
    text = value(question, "question") |> present_string()
    node_id = value(question, "node_id") |> nullable_string()

    if text do
      %{
        "id" => question_id(text, node_id),
        "question" => text,
        "node_id" => node_id,
        "kind" => kind,
        "answer_title" => value(question, "answer_title")
      }
    end
  end

  defp question_from_map(_question, _kind), do: nil

  defp question_from_value(question, kind) when is_binary(question),
    do: question_from_map(%{"question" => question}, kind)

  defp question_from_value(question, kind) when is_map(question),
    do: question_from_map(question, kind)

  defp question_from_value(_question, _kind), do: nil

  defp enrich_origin_node(nil, _campaign), do: nil

  defp enrich_origin_node(node, campaign) do
    if value(node, "class") == "origin" and is_nil(value(node, "content")) do
      case get_in(campaign.raw_payload || %{}, ["content", "first_answer", "content"]) do
        content when is_binary(content) and content != "" -> Map.put(node, "content", content)
        _content -> node
      end
    else
      node
    end
  end

  defp node_content(%Campaign{} = campaign, node) do
    direct = value(node, "content") || value(node, "body") || value(node, "text")

    direct
    |> fallback(get_in(campaign.raw_payload || %{}, ["content", "first_answer", "content"]))
    |> fallback(value(node, "excerpt"))
    |> fallback("")
    |> to_string()
  end

  defp stringify_blocks(blocks) do
    Enum.map(blocks, fn block ->
      block
      |> Map.new(fn {key, value} -> {to_string(key), value} end)
    end)
  end

  defp cta_slide do
    %{
      "kind" => "cta",
      "label" => "Learn more",
      "title" => "Continue on RationalGrid.ai",
      "body" => ""
    }
  end

  defp highlight_text(highlight) when is_map(highlight) do
    value(highlight, "text") || value(highlight, "content") || value(highlight, "quote") ||
      value(highlight, "highlight")
      |> present_string()
  end

  defp highlight_text(_highlight), do: nil

  defp image_metadata(format, slides) do
    {width, height} = dimensions(format)

    %{
      "format" => format,
      "width" => width,
      "height" => height,
      "slide_count" => length(slides),
      "slides" => slides
    }
  end

  defp dimensions("short"), do: {1080, 1920}
  defp dimensions(_format), do: {1080, 1350}

  defp normalize_image_format("short"), do: "short"
  defp normalize_image_format(_format), do: "portrait"

  defp asset_identity(%Campaign{id: id}, kind, source_id, style, format) do
    encoded_source = URI.encode(to_string(source_id), &URI.char_unreserved?/1)
    query = URI.encode_query(%{style: normalize_style(style), format: format})
    "/client-assets/campaigns/#{id}/#{kind}/#{encoded_source}?#{query}"
  end

  defp value(map, key) when is_map(map) do
    Map.get(map, key) ||
      Enum.find_value(map, fn
        {candidate, value} when is_atom(candidate) ->
          if Atom.to_string(candidate) == key, do: value

        _entry ->
          nil
      end)
  end

  defp value(_map, _key), do: nil

  defp present_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      present -> present
    end
  end

  defp present_string(_value), do: nil

  defp nullable_string(nil), do: nil
  defp nullable_string(value), do: to_string(value)

  defp integer_value(value) when is_integer(value), do: value

  defp integer_value(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _result -> nil
    end
  end

  defp integer_value(_value), do: nil

  defp fallback(nil, fallback), do: fallback
  defp fallback("", fallback), do: fallback
  defp fallback(value, _fallback), do: value
end
