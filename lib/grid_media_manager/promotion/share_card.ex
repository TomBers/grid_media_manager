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
  @carousel_reading_max_characters 220
  @short_video_max_characters 220

  @styles [
    %{
      id: "minimal_light",
      label: "Minimal light",
      description: "Black on white · quiet and universal",
      category: "Clean"
    },
    %{
      id: "minimal_dark",
      label: "Minimal dark",
      description: "White on black · focused and high contrast",
      category: "Monochrome"
    },
    %{
      id: "editorial_dark",
      label: "Editorial dark",
      description: "Indigo and rose · premium editorial depth",
      category: "Editorial"
    },
    %{
      id: "warm_paper",
      label: "Warm editorial",
      description: "Amber cinematic · reflective excerpts",
      category: "Warm"
    },
    %{
      id: "newsprint",
      label: "Newsprint",
      description: "Cream paper and ink · essays and considered ideas",
      category: "Classic"
    },
    %{
      id: "deep_ocean",
      label: "Deep ocean",
      description: "Analytical dark · complex explainers",
      category: "Analytical"
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
      |> Enum.with_index()
      |> Enum.flat_map(fn {section, section_index} ->
        section
        |> reading_section_blocks(node_title, section_index)
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

  def node_short_video_slides(%Campaign{} = campaign, node) when is_map(node) do
    node_title = node |> value("title") |> present_string() |> fallback("Key idea")

    content_slides =
      campaign
      |> node_content(node)
      |> Markdown.sections()
      |> Enum.with_index()
      |> Enum.flat_map(fn {section, section_index} ->
        section
        |> short_video_section_pages(node_title, section_index)
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

  defp short_video_section_pages(section, node_title, section_index) do
    blocks = Markdown.presentation_blocks(section.blocks)

    heading_pages =
      if section_heading?(section.title, node_title, section_index) do
        [[%{type: :heading, level: 2, text: presentation_heading(section.title)}]]
      else
        []
      end

    selected_pages =
      if section_index == 0 do
        blocks
        |> Markdown.paginate_blocks(@short_video_max_characters)
        |> Enum.take(1)
      else
        general_blocks = Enum.reject(blocks, &Map.has_key?(&1, :role))
        connection_blocks = Enum.filter(blocks, &(&1[:role] == :connection))
        question_blocks = Enum.filter(blocks, &(&1[:role] == :question))

        take_pages(general_blocks, 1) ++
          take_pages(connection_blocks, 2) ++ take_pages(question_blocks, 1)
      end

    heading_pages ++ selected_pages
  end

  defp take_pages(blocks, count) do
    blocks
    |> Markdown.paginate_blocks(@short_video_max_characters)
    |> Enum.take(count)
  end

  defp reading_section_blocks(section, node_title, section_index) do
    heading_blocks =
      if section_heading?(section.title, node_title, section_index) do
        [%{type: :heading, level: 2, text: presentation_heading(section.title)}]
      else
        []
      end

    heading_blocks ++ Markdown.presentation_blocks(section.blocks)
  end

  defp section_heading?("The argument", _node_title, _section_index), do: false

  defp section_heading?(section_title, node_title, 0) do
    normalize_heading(section_title) != normalize_heading(node_title)
  end

  defp section_heading?(_section_title, _node_title, _section_index), do: true

  defp normalize_heading(value) do
    value
    |> Markdown.plain_inline()
    |> String.downcase()
    |> String.replace(~r/[^\p{L}\p{N}]+/u, " ")
    |> String.trim()
  end

  defp presentation_heading(value) do
    heading =
      value
      |> Markdown.plain_inline()
      |> String.replace(~r/^\d+[.)]\s*/u, "")
      |> String.replace(~r/[“”\"]/u, "")
      |> String.trim()

    case String.split(heading, ~r/\s*:\s*/u, parts: 2) do
      [_category, subject] ->
        if String.length(subject) >= 12, do: subject, else: heading

      _parts ->
        heading
    end
  end

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

  def long_form_asset_attr(%Campaign{} = campaign, candidates, style \\ @default_style)
      when is_list(candidates) do
    style = normalize_style(style)

    entries =
      candidates
      |> Enum.map(&long_form_entry(campaign, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq_by(&normalize_long_form_text(&1.text))

    case entries do
      [] ->
        nil

      entries ->
        cover_title = long_form_cover_title(campaign, entries)
        text = entries |> Enum.map(& &1.text) |> Enum.join("\n\n")
        source_id = long_form_source_id(entries)
        slide = %{"kind" => "cover", "label" => "", "title" => cover_title, "body" => ""}

        %{
          title: "#{cover_title} · Long-form post",
          kind: "long_form_post",
          url: asset_identity(campaign, "long-form", source_id, style, "portrait"),
          mime_type: "image/png",
          text: text,
          node_id: shared_long_form_value(entries, :node_id),
          highlight_id: shared_long_form_value(entries, :highlight_id),
          recommended_platforms: Platforms.long_form_ids(),
          style: style,
          source_type: "long_form_post",
          source_id: source_id,
          metadata:
            image_metadata("portrait", [slide])
            |> Map.put("content_type", "long_form")
            |> Map.put("sources", Enum.map(entries, &long_form_source_metadata/1))
        }
    end
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

  defp long_form_entry(%Campaign{} = campaign, candidate) do
    case value(candidate, "type") do
      "key_node" ->
        long_form_node_entry(campaign, candidate)

      "question" ->
        long_form_question_entry(campaign, candidate)

      "highlight" ->
        long_form_highlight_entry(campaign, candidate)

      "grid" ->
        long_form_entry_map(
          "grid",
          to_string(campaign.id),
          campaign.title,
          campaign.title,
          nil,
          nil
        )

      _type ->
        nil
    end
  end

  defp long_form_node_entry(campaign, candidate) do
    source_id = value(candidate, "source_id")

    case find_key_node(campaign, source_id) do
      node when is_map(node) ->
        title = node |> value("title") |> present_string() |> fallback(campaign.title)
        text = node_content(campaign, node) |> present_string() |> fallback(title)
        node_id = node |> value("id") |> nullable_string()
        long_form_entry_map("key_node", source_id, title, text, node_id, nil)

      _node ->
        nil
    end
  end

  defp long_form_question_entry(campaign, candidate) do
    source_id = value(candidate, "source_id")

    case find_question(campaign, source_id) do
      question when is_map(question) ->
        text = question |> value("question") |> present_string()

        if text do
          cover_title = if String.length(text) <= 140, do: text, else: campaign.title

          long_form_entry_map(
            "question",
            source_id,
            cover_title,
            text,
            value(question, "node_id") |> nullable_string(),
            nil
          )
        end

      _question ->
        nil
    end
  end

  defp long_form_highlight_entry(campaign, candidate) do
    source_id = value(candidate, "source_id")

    case find_highlight(campaign, source_id) do
      highlight when is_map(highlight) ->
        text = highlight_text(highlight)
        node_id = value(highlight, "node_id") |> nullable_string()
        cover_title = related_node_title(campaign, node_id) || campaign.title

        if text do
          long_form_entry_map(
            "highlight",
            source_id,
            cover_title,
            text,
            node_id,
            integer_value(value(highlight, "id"))
          )
        end

      _highlight ->
        nil
    end
  end

  defp long_form_entry_map(type, source_id, cover_title, text, node_id, highlight_id) do
    %{
      type: type,
      source_id: to_string(source_id),
      cover_title: cover_title,
      text: text |> to_string() |> String.trim(),
      node_id: node_id,
      highlight_id: highlight_id
    }
  end

  defp long_form_cover_title(campaign, [entry]), do: entry.cover_title |> fallback(campaign.title)
  defp long_form_cover_title(campaign, _entries), do: campaign.title

  defp related_node_title(_campaign, nil), do: nil

  defp related_node_title(campaign, node_id) do
    case find_key_node(campaign, node_id) do
      node when is_map(node) -> node |> value("title") |> present_string()
      _node -> nil
    end
  end

  defp shared_long_form_value(entries, field) do
    case entries |> Enum.map(&Map.get(&1, field)) |> Enum.reject(&is_nil/1) |> Enum.uniq() do
      [value] -> value
      _values -> nil
    end
  end

  defp long_form_source_metadata(entry) do
    %{
      "type" => entry.type,
      "source_id" => entry.source_id,
      "node_id" => entry.node_id,
      "highlight_id" => entry.highlight_id
    }
  end

  defp long_form_source_id(entries) do
    entries
    |> Enum.map(&long_form_source_metadata/1)
    |> then(&{&1, Enum.map(entries, fn entry -> entry.text end)})
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.url_encode64(padding: false)
    |> binary_part(0, 20)
  end

  defp normalize_long_form_text(text) do
    text
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
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
