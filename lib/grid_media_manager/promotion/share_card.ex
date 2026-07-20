defmodule GridMediaManager.Promotion.ShareCard do
  @moduledoc """
  Generates RationalGrid promotion share cards from imported campaign content.

  Most cards remain SVG-first; carousels are rasterized to PNG for social
  publishing after their layout is rendered.

  This is adapted from Dialectic's `DialecticWeb.HighlightShare`, but it is
  intentionally decoupled from Dialectic schemas/routes. It works from the
  persisted campaign payload in this app.
  """

  alias GridMediaManager.Campaigns.Campaign
  alias GridMediaManager.Promotion.Markdown
  alias GridMediaManager.RationalGrid.MediaPayload

  @image_width 1200
  @image_height 630
  @portrait_width 1080
  @portrait_height 1350
  @square_size 1200
  @short_width 1080
  @short_height 1920
  @short_body_x 110
  @short_body_width 860
  @short_body_area_top 260
  @short_body_area_bottom 1_690
  @short_body_max_y 1_650
  @short_body_font_size 58
  @short_body_max_lines 9
  @short_min_duration 4.5
  @short_words_per_second 3.0
  @short_pause_duration 1.5

  @quote_area_left 112
  @quote_area_top 146
  @quote_area_width 920
  @quote_area_height 350

  @sanitize_slice_multiplier 4
  @quote_font_family "Georgia, 'Times New Roman', serif"
  @ui_font_family "Arial, Helvetica, sans-serif"
  @default_style "editorial_dark"

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

  def asset_attrs(%Campaign{} = _campaign), do: []

  def grid_asset_attr(campaign, style \\ @default_style)

  def grid_asset_attr(%Campaign{} = campaign, style) do
    style = normalize_style(style)

    %{
      title: campaign.title,
      kind: "grid_card",
      url: graph_image_path(campaign, style),
      mime_type: "image/png",
      text: nil,
      node_id: nil,
      highlight_id: nil,
      recommended_platforms: ["x", "linkedin", "substack", "bluesky"],
      style: style,
      source_type: "grid",
      source_id: to_string(campaign.id),
      metadata: %{}
    }
  end

  def graph_image_path(campaign, style \\ @default_style)

  def graph_image_path(%Campaign{id: id}, style) do
    "/campaigns/#{id}/share-card.png"
    |> maybe_add_style_query(style)
  end

  def highlight_image_path(campaign, highlight_id, style \\ @default_style),
    do: highlight_image_path(campaign, highlight_id, style, "landscape")

  def highlight_image_path(%Campaign{id: id}, highlight_id, style, format) do
    "/campaigns/#{id}/highlights/#{highlight_id}/share-card.png"
    |> maybe_add_style_query(style)
    |> maybe_add_quote_format_query(format)
  end

  def highlight_short_video_path(%Campaign{id: id}, highlight_id, style) do
    query = URI.encode_query(%{style: normalize_style(style)})
    "/campaigns/#{id}/highlights/#{highlight_id}/short.mp4?#{query}"
  end

  def node_image_path(campaign, node_id, style \\ @default_style, format \\ "landscape")

  def node_image_path(%Campaign{id: id}, node_id, style, format) do
    encoded_node_id = URI.encode(to_string(node_id), &URI.char_unreserved?/1)

    "/campaigns/#{id}/nodes/#{encoded_node_id}/share-card.png"
    |> maybe_add_style_query(style)
    |> maybe_add_format_query(format)
  end

  def curated_carousel_image_path(campaign, token, slide, style \\ @default_style)

  def curated_carousel_image_path(%Campaign{id: id}, token, slide, style) do
    encoded_token = URI.encode(to_string(token), &URI.char_unreserved?/1)

    "/campaigns/#{id}/curated-carousels/#{encoded_token}/slides/#{slide}/image.png"
    |> maybe_add_style_query(style)
  end

  def node_carousel_image_path(campaign, node_id, slide, style \\ @default_style)

  def node_carousel_image_path(%Campaign{id: id}, node_id, slide, style) do
    encoded_node_id = URI.encode(to_string(node_id), &URI.char_unreserved?/1)

    "/campaigns/#{id}/nodes/#{encoded_node_id}/carousel.png"
    |> then(&(&1 <> "?" <> URI.encode_query(%{style: normalize_style(style), slide: slide})))
  end

  def question_image_path(campaign, question_id, style \\ @default_style),
    do: question_image_path(campaign, question_id, style, "landscape")

  def question_image_path(%Campaign{id: id}, question_id, style, format) do
    "/campaigns/#{id}/questions/#{URI.encode(to_string(question_id), &URI.char_unreserved?/1)}/share-card.png"
    |> maybe_add_style_query(style)
    |> maybe_add_quote_format_query(format)
  end

  def question_short_video_path(%Campaign{id: id}, question_id, style) do
    encoded_id = URI.encode(to_string(question_id), &URI.char_unreserved?/1)
    query = URI.encode_query(%{style: normalize_style(style)})
    "/campaigns/#{id}/questions/#{encoded_id}/short.mp4?#{query}"
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
      |> Enum.map(fn question ->
        text = question |> get("question") |> sanitize_text(nil)
        node_id = question |> get("node_id") |> string_value()

        question_map(text, node_id, "user_question")
      end)

    answer_questions =
      campaign.raw_payload
      |> MediaPayload.answer_questions()
      |> Enum.map(&answer_question_map/1)

    follow_up_questions =
      campaign.raw_payload
      |> MediaPayload.follow_up_questions()
      |> Enum.map(&question_map(&1, nil, "follow_up_question"))

    (user_questions ++ answer_questions ++ follow_up_questions)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1["id"])
  end

  def find_question(%Campaign{} = campaign, question_id) do
    campaign
    |> questions()
    |> Enum.find(&(Map.get(&1, "id") == to_string(question_id)))
  end

  def find_key_node(%Campaign{} = campaign, node_id) do
    campaign.raw_payload
    |> MediaPayload.key_nodes()
    |> Enum.find(fn node -> to_string(get(node, "id")) == to_string(node_id) end)
    |> enrich_key_node_content(campaign)
  end

  defp enrich_key_node_content(nil, _campaign), do: nil

  defp enrich_key_node_content(node, %Campaign{} = campaign) do
    content_map = Map.get(campaign.raw_payload, "content")
    first_answer = if is_map(content_map), do: Map.get(content_map, "first_answer"), else: nil

    case {Map.get(node, "class"), Map.get(node, "content"), first_answer} do
      {"origin", nil, %{"content" => content}} when is_binary(content) and content != "" ->
        Map.put(node, "content", content)

      _ ->
        node
    end
  end

  def find_highlight(%Campaign{} = campaign, highlight_id) do
    with {:ok, parsed_id} <- parse_integer(highlight_id) do
      campaign.raw_payload
      |> MediaPayload.highlights()
      |> Enum.find(fn highlight -> parse_highlight_id(highlight) == parsed_id end)
    end
  end

  def graph_image_svg(campaign, style \\ @default_style)

  def graph_image_svg(%Campaign{} = campaign, style) do
    style = normalize_style(style)
    palette = quote_palette(style)
    title = sanitize_text(campaign.title, nil)
    title_layout = grid_title_layout(title)

    title_markup =
      title_layout.lines
      |> Enum.with_index()
      |> Enum.map_join("", fn {line, index} ->
        y = title_layout.start_y + index * title_layout.line_gap
        ~s(<tspan x="#{@quote_area_left}" y="#{y}">#{escape_xml(line)}</tspan>)
      end)

    tags = campaign.tags |> Enum.take(3) |> Enum.join(" · ")
    label = if tags == "", do: "Grid on RationalGrid", else: tags

    """
    <svg xmlns="http://www.w3.org/2000/svg" width="#{@image_width}" height="#{@image_height}" viewBox="0 0 #{@image_width} #{@image_height}" role="img" aria-labelledby="title desc">
      <title id="title">#{escape_xml(title)} · RationalGrid</title>
      <desc id="desc">Share card for #{escape_xml(title)} on RationalGrid</desc>
      <defs>
        <linearGradient id="canvas" x1="0%" y1="0%" x2="100%" y2="100%">
          <stop offset="0%" stop-color="#{palette.canvas_a}" />
          <stop offset="52%" stop-color="#{palette.canvas_b}" />
          <stop offset="100%" stop-color="#{palette.canvas_c}" />
        </linearGradient>
        <radialGradient id="violetHalo" cx="18%" cy="12%" r="72%">
          <stop offset="0%" stop-color="#{palette.bloom_a}" stop-opacity="#{palette.bloom_opacity}" />
          <stop offset="100%" stop-color="#{palette.bloom_a}" stop-opacity="0" />
        </radialGradient>
        <radialGradient id="blueHalo" cx="86%" cy="18%" r="68%">
          <stop offset="0%" stop-color="#{palette.bloom_b}" stop-opacity="#{palette.bloom_opacity}" />
          <stop offset="100%" stop-color="#{palette.bloom_b}" stop-opacity="0" />
        </radialGradient>
        <linearGradient id="accent" x1="0%" y1="0%" x2="100%" y2="0%">
          <stop offset="0%" stop-color="#{palette.accent_a}" />
          <stop offset="52%" stop-color="#{palette.accent_b}" />
          <stop offset="100%" stop-color="#{palette.accent_c}" />
        </linearGradient>
        <filter id="cardShadow" x="-8%" y="-10%" width="116%" height="124%">
          <feDropShadow dx="0" dy="22" stdDeviation="22" flood-color="#{palette.shadow}" flood-opacity="#{palette.shadow_opacity}" />
        </filter>
      </defs>

      <rect width="1200" height="630" fill="url(#canvas)" />
      #{pexels_background_markup(campaign, 1200, 630)}
      <rect width="1200" height="630" fill="url(#violetHalo)" />
      <rect width="1200" height="630" fill="url(#blueHalo)" />
      <circle cx="1040" cy="126" r="132" fill="#{palette.bloom_b}" fill-opacity="#{palette.decoration_opacity}" />
      <circle cx="160" cy="538" r="118" fill="#{palette.bloom_a}" fill-opacity="#{palette.decoration_opacity}" />

      <rect x="52" y="44" width="1096" height="542" rx="44" fill="#{palette.card}" fill-opacity="#{palette.card_opacity}" filter="url(#cardShadow)" />
      <rect x="52.5" y="44.5" width="1095" height="541" rx="43.5" fill="none" stroke="#{palette.border}" stroke-opacity="#{palette.border_opacity}" />
      <rect x="52" y="44" width="1096" height="542" rx="44" fill="#{palette.panel}" fill-opacity="#{palette.panel_opacity}" />

      <text x="96" y="98" fill="#{palette.label}" fill-opacity="0.86" font-size="17" font-weight="700" font-family="#{@ui_font_family}" letter-spacing="0.15">RationalGrid.ai</text>
      <line x1="96" y1="134" x2="1104" y2="134" stroke="#{palette.border}" stroke-width="1" stroke-opacity="#{palette.border_opacity}" />
      <rect x="96" y="478" width="230" height="6" rx="3" fill="url(#accent)" opacity="0.92" />
      <text x="96" y="510" fill="#{palette.muted}" font-size="17" font-weight="700" font-family="#{@ui_font_family}" letter-spacing="0.35">#{escape_xml(label)}</text>
      <text fill="#{palette.text}" font-size="#{title_layout.font_size}" font-weight="800" font-family="#{@ui_font_family}" letter-spacing="-0.55" paint-order="stroke" stroke="#{palette.text_stroke}" stroke-width="2" stroke-opacity="#{palette.text_stroke_opacity}">
        #{title_markup}
      </text>
    </svg>
    """
  end

  def graph_image_png(campaign, style \\ @default_style) do
    campaign
    |> graph_image_svg(style)
    |> rasterize_svg()
  end

  def node_image_png(campaign, node, style \\ @default_style, format \\ "landscape") do
    svg =
      case normalize_node_format(format) do
        "linkedin" -> node_linkedin_image_svg(campaign, node, style)
        "portrait" -> node_reading_image_svg(campaign, node, style)
        "landscape" -> node_image_svg(campaign, node, style)
      end

    rasterize_svg(svg)
  end

  def node_image_svg(campaign, node, style \\ @default_style)

  def node_image_svg(%Campaign{} = campaign, node, style) when is_map(node) do
    style = normalize_style(style)
    palette = quote_palette(style)
    node_title = node |> get("title") |> sanitize_text(nil) |> fallback("Key node")

    node_excerpt =
      node
      |> get("excerpt")
      |> fallback(get(node, "content"))
      |> sanitize_text(nil)

    layout = node_card_layout(node_title, node_excerpt)
    footer = "Key node from #{sanitize_text(campaign.title, nil)}"
    footer_font_size = single_line_font_size(footer, 976, 16, 8)

    title_markup =
      layout.title_lines
      |> Enum.with_index()
      |> Enum.map_join("", fn {line, index} ->
        y = layout.title_start_y + index * layout.title_line_gap
        ~s(<tspan x="112" y="#{y}">#{escape_xml(line)}</tspan>)
      end)

    excerpt_markup =
      layout.body_lines
      |> Enum.with_index()
      |> Enum.map_join("", fn {line, index} ->
        y = layout.body_start_y + index * layout.body_line_gap
        ~s(<tspan x="112" y="#{y}">#{escape_xml(line)}</tspan>)
      end)

    """
    <svg xmlns="http://www.w3.org/2000/svg" width="#{@image_width}" height="#{@image_height}" viewBox="0 0 #{@image_width} #{@image_height}" role="img" aria-labelledby="title desc">
      <title id="title">#{escape_xml(node_title)} · #{escape_xml(campaign.title)} · RationalGrid</title>
      <desc id="desc">Key node card from #{escape_xml(campaign.title)} on RationalGrid</desc>
      <defs>
        <linearGradient id="nodeCanvas" x1="0%" y1="0%" x2="100%" y2="100%">
          <stop offset="0%" stop-color="#{palette.canvas_a}" />
          <stop offset="46%" stop-color="#{palette.canvas_b}" />
          <stop offset="100%" stop-color="#{palette.canvas_c}" />
        </linearGradient>
        <radialGradient id="nodeViolet" cx="16%" cy="12%" r="72%">
          <stop offset="0%" stop-color="#{palette.bloom_a}" stop-opacity="#{palette.bloom_opacity}" />
          <stop offset="100%" stop-color="#{palette.bloom_a}" stop-opacity="0" />
        </radialGradient>
        <radialGradient id="nodeSky" cx="88%" cy="16%" r="66%">
          <stop offset="0%" stop-color="#{palette.bloom_b}" stop-opacity="#{palette.bloom_opacity}" />
          <stop offset="100%" stop-color="#{palette.bloom_b}" stop-opacity="0" />
        </radialGradient>
        <linearGradient id="nodeAccent" x1="0%" y1="0%" x2="100%" y2="0%">
          <stop offset="0%" stop-color="#{palette.accent_a}" />
          <stop offset="54%" stop-color="#{palette.accent_b}" />
          <stop offset="100%" stop-color="#{palette.accent_c}" />
        </linearGradient>
        <filter id="nodeShadow" x="-8%" y="-10%" width="116%" height="124%">
          <feDropShadow dx="0" dy="28" stdDeviation="24" flood-color="#{palette.shadow}" flood-opacity="#{palette.shadow_opacity}" />
        </filter>
      </defs>

      <rect width="1200" height="630" fill="url(#nodeCanvas)" />
      #{pexels_background_markup(campaign, 1200, 630)}
      <rect width="1200" height="630" fill="url(#nodeViolet)" />
      <rect width="1200" height="630" fill="url(#nodeSky)" />
      <path d="M-44 470 C186 382 364 598 602 474 C790 376 966 408 1252 250" fill="none" stroke="#{palette.accent_a}" stroke-opacity="#{palette.decoration_opacity}" stroke-width="2" />
      <path d="M-22 166 C198 246 318 38 552 150 C802 270 942 92 1224 122" fill="none" stroke="#{palette.accent_c}" stroke-opacity="#{palette.decoration_opacity}" stroke-width="2" />

      <rect x="48" y="42" width="1104" height="546" rx="42" fill="#{palette.card}" fill-opacity="#{palette.card_opacity}" filter="url(#nodeShadow)" />
      <rect x="48.5" y="42.5" width="1103" height="545" rx="41.5" fill="none" stroke="#{palette.border}" stroke-opacity="#{palette.border_opacity}" />
      <rect x="76" y="70" width="1048" height="490" rx="30" fill="#{palette.panel}" fill-opacity="#{palette.panel_opacity}" stroke="#{palette.border}" stroke-opacity="#{palette.border_opacity}" />

      <text x="112" y="118" fill="#{palette.label}" font-size="17" font-weight="800" font-family="#{@ui_font_family}" letter-spacing="0.35">RationalGrid.ai</text>

      <line x1="112" y1="144" x2="1088" y2="144" stroke="#{palette.border}" stroke-width="1" stroke-opacity="#{palette.border_opacity}" />
      <rect x="112" y="516" width="344" height="6" rx="3" fill="url(#nodeAccent)" opacity="0.96" />

      <text fill="#{palette.text}" font-size="#{layout.title_font_size}" font-weight="800" font-family="#{@ui_font_family}" letter-spacing="-0.5" paint-order="stroke" stroke="#{palette.text_stroke}" stroke-width="2.2" stroke-opacity="#{palette.text_stroke_opacity}">
        #{title_markup}
      </text>
      <text fill="#{palette.secondary_text}" font-size="#{layout.body_font_size}" font-weight="500" font-family="#{@ui_font_family}" letter-spacing="0" opacity="0.92">
        #{excerpt_markup}
      </text>
      <text x="112" y="548" fill="#{palette.muted}" font-size="#{footer_font_size}" font-weight="700" font-family="#{@ui_font_family}" letter-spacing="0.2">#{escape_xml(footer)}</text>
    </svg>
    """
  end

  def node_linkedin_image_svg(campaign, node, style \\ @default_style)

  def node_linkedin_image_svg(%Campaign{} = campaign, node, style) when is_map(node) do
    style = normalize_style(style)
    palette = quote_palette(style)
    node_title = node |> get("title") |> sanitize_text(nil) |> fallback("Key node")

    node_markdown =
      node
      |> get("content")
      |> fallback(get(node, "excerpt"))
      |> fallback("")
      |> to_string()

    title_layout =
      bounded_text_layout(node_title, 950, 210, [62, 58, 54, 50, 46, 42, 38, 34, 30, 26, 22, 18])

    title_font_size = title_layout.font_size
    title_line_gap = title_layout.line_gap
    title_lines = title_layout.lines
    title_start_y = 242
    title_last_y = title_start_y + (length(title_lines) - 1) * title_line_gap
    body_font_size = 30
    body_start_y = title_last_y + 106
    footer = "A key idea from #{sanitize_text(campaign.title, nil)}"
    footer_font_size = single_line_font_size(footer, 952, 18, 8)

    title_markup =
      title_lines
      |> Enum.with_index()
      |> Enum.map_join("", fn {line, index} ->
        ~s(<tspan x="124" y="#{title_start_y + index * title_line_gap}">#{escape_xml(line)}</tspan>)
      end)

    body_markup =
      markdown_body_markup(node_markdown, node_title, %{
        x: 124,
        start_y: body_start_y,
        max_y: 1_045,
        width: 950,
        font_size: body_font_size,
        palette: palette
      })

    """
    <svg xmlns="http://www.w3.org/2000/svg" width="#{@square_size}" height="#{@square_size}" viewBox="0 0 #{@square_size} #{@square_size}" role="img" aria-labelledby="title desc">
      <title id="title">#{escape_xml(node_title)} · #{escape_xml(campaign.title)} · RationalGrid</title>
      <desc id="desc">LinkedIn explainer card for #{escape_xml(node_title)} from #{escape_xml(campaign.title)}</desc>
      <defs>
        <linearGradient id="linkedinCanvas" x1="0%" y1="0%" x2="100%" y2="100%">
          <stop offset="0%" stop-color="#{palette.canvas_a}" />
          <stop offset="48%" stop-color="#{palette.canvas_b}" />
          <stop offset="100%" stop-color="#{palette.canvas_c}" />
        </linearGradient>
        <radialGradient id="linkedinBloomA" cx="12%" cy="10%" r="72%">
          <stop offset="0%" stop-color="#{palette.bloom_a}" stop-opacity="#{palette.bloom_opacity}" />
          <stop offset="100%" stop-color="#{palette.bloom_a}" stop-opacity="0" />
        </radialGradient>
        <radialGradient id="linkedinBloomB" cx="90%" cy="24%" r="70%">
          <stop offset="0%" stop-color="#{palette.bloom_b}" stop-opacity="#{palette.bloom_opacity}" />
          <stop offset="100%" stop-color="#{palette.bloom_b}" stop-opacity="0" />
        </radialGradient>
        <linearGradient id="linkedinAccent" x1="0%" y1="0%" x2="100%" y2="0%">
          <stop offset="0%" stop-color="#{palette.accent_a}" />
          <stop offset="52%" stop-color="#{palette.accent_b}" />
          <stop offset="100%" stop-color="#{palette.accent_c}" />
        </linearGradient>
        <filter id="linkedinShadow" x="-8%" y="-6%" width="116%" height="114%">
          <feDropShadow dx="0" dy="28" stdDeviation="26" flood-color="#{palette.shadow}" flood-opacity="#{palette.shadow_opacity}" />
        </filter>
      </defs>

      <rect width="1200" height="1200" fill="url(#linkedinCanvas)" />
      #{pexels_background_markup(campaign, 1200, 1200)}
      <rect width="1200" height="1200" fill="url(#linkedinBloomA)" />
      <rect width="1200" height="1200" fill="url(#linkedinBloomB)" />
      <path d="M-60 970 C240 820 430 1110 760 910 C920 812 1040 790 1270 650" fill="none" stroke="#{palette.accent_b}" stroke-opacity="#{palette.decoration_opacity}" stroke-width="3" />

      <rect x="48" y="48" width="1104" height="1104" rx="44" fill="#{palette.card}" fill-opacity="#{palette.card_opacity}" filter="url(#linkedinShadow)" />
      <rect x="48.5" y="48.5" width="1103" height="1103" rx="43.5" fill="none" stroke="#{palette.border}" stroke-opacity="#{palette.border_opacity}" />
      <rect x="76" y="76" width="1048" height="1048" rx="32" fill="#{palette.panel}" fill-opacity="#{palette.panel_opacity}" stroke="#{palette.border}" stroke-opacity="#{palette.border_opacity}" />

      <text x="124" y="140" fill="#{palette.label}" font-size="20" font-weight="800" font-family="#{@ui_font_family}">RationalGrid.ai</text>

      <line x1="124" y1="176" x2="1076" y2="176" stroke="#{palette.border}" stroke-width="1" stroke-opacity="#{palette.border_opacity}" />

      <text fill="#{palette.text}" font-size="#{title_font_size}" font-weight="800" font-family="#{@ui_font_family}" letter-spacing="-0.7" paint-order="stroke" stroke="#{palette.text_stroke}" stroke-width="2.2" stroke-opacity="#{palette.text_stroke_opacity}">
        #{title_markup}
      </text>
      <rect x="124" y="#{body_start_y - 58}" width="240" height="7" rx="3.5" fill="url(#linkedinAccent)" opacity="0.96" />
      #{body_markup}

      <line x1="124" y1="1070" x2="1076" y2="1070" stroke="#{palette.border}" stroke-width="1" stroke-opacity="#{palette.border_opacity}" />
      <text x="124" y="1108" fill="#{palette.muted}" font-size="#{footer_font_size}" font-weight="700" font-family="#{@ui_font_family}">#{escape_xml(footer)}</text>
    </svg>
    """
  end

  def node_reading_image_svg(campaign, node, style \\ @default_style)

  def node_reading_image_svg(%Campaign{} = campaign, node, style) when is_map(node) do
    style = normalize_style(style)
    palette = quote_palette(style)
    node_title = node |> get("title") |> sanitize_text(nil) |> fallback("Key node")

    node_markdown =
      node
      |> get("content")
      |> fallback(get(node, "excerpt"))
      |> fallback("")
      |> to_string()

    title_layout =
      bounded_text_layout(node_title, 820, 280, [58, 54, 50, 46, 42, 38, 34, 30, 26, 22, 18])

    title_font_size = title_layout.font_size
    title_line_gap = title_layout.line_gap
    title_lines = title_layout.lines
    title_start_y = 232
    body_font_size = 29
    body_start_y = title_start_y + (length(title_lines) - 1) * title_line_gap + 92

    title_markup =
      title_lines
      |> Enum.with_index()
      |> Enum.map_join("", fn {line, index} ->
        y = title_start_y + index * title_line_gap
        ~s(<tspan x="130" y="#{y}">#{escape_xml(line)}</tspan>)
      end)

    body_markup =
      markdown_body_markup(node_markdown, node_title, %{
        x: 130,
        start_y: body_start_y,
        max_y: 1_160,
        width: 820,
        font_size: body_font_size,
        palette: palette
      })

    """
    <svg xmlns="http://www.w3.org/2000/svg" width="#{@portrait_width}" height="#{@portrait_height}" viewBox="0 0 #{@portrait_width} #{@portrait_height}" role="img" aria-labelledby="title desc">
      <title id="title">#{escape_xml(node_title)} · #{escape_xml(campaign.title)} · RationalGrid</title>
      <desc id="desc">Portrait reading card for #{escape_xml(node_title)} from #{escape_xml(campaign.title)} on RationalGrid</desc>
      <defs>
        <linearGradient id="portraitCanvas" x1="0%" y1="0%" x2="100%" y2="100%">
          <stop offset="0%" stop-color="#{palette.canvas_a}" />
          <stop offset="48%" stop-color="#{palette.canvas_b}" />
          <stop offset="100%" stop-color="#{palette.canvas_c}" />
        </linearGradient>
        <radialGradient id="portraitBloomA" cx="12%" cy="10%" r="72%">
          <stop offset="0%" stop-color="#{palette.bloom_a}" stop-opacity="#{palette.bloom_opacity}" />
          <stop offset="100%" stop-color="#{palette.bloom_a}" stop-opacity="0" />
        </radialGradient>
        <radialGradient id="portraitBloomB" cx="90%" cy="24%" r="70%">
          <stop offset="0%" stop-color="#{palette.bloom_b}" stop-opacity="#{palette.bloom_opacity}" />
          <stop offset="100%" stop-color="#{palette.bloom_b}" stop-opacity="0" />
        </radialGradient>
        <linearGradient id="portraitAccent" x1="0%" y1="0%" x2="100%" y2="0%">
          <stop offset="0%" stop-color="#{palette.accent_a}" />
          <stop offset="52%" stop-color="#{palette.accent_b}" />
          <stop offset="100%" stop-color="#{palette.accent_c}" />
        </linearGradient>
        <filter id="portraitShadow" x="-8%" y="-6%" width="116%" height="114%">
          <feDropShadow dx="0" dy="28" stdDeviation="26" flood-color="#{palette.shadow}" flood-opacity="#{palette.shadow_opacity}" />
        </filter>
      </defs>

      <rect width="1080" height="1350" fill="url(#portraitCanvas)" />
      #{pexels_background_markup(campaign, 1080, 1350)}
      <rect width="1080" height="1350" fill="url(#portraitBloomA)" />
      <rect width="1080" height="1350" fill="url(#portraitBloomB)" />
      <path d="M-80 1040 C220 890 420 1200 730 1010 C870 924 986 878 1160 760" fill="none" stroke="#{palette.accent_b}" stroke-opacity="#{palette.decoration_opacity}" stroke-width="3" />

      <rect x="54" y="54" width="972" height="1242" rx="44" fill="#{palette.card}" fill-opacity="#{palette.card_opacity}" filter="url(#portraitShadow)" />
      <rect x="54.5" y="54.5" width="971" height="1241" rx="43.5" fill="none" stroke="#{palette.border}" stroke-opacity="#{palette.border_opacity}" />
      <rect x="82" y="82" width="916" height="1186" rx="32" fill="#{palette.panel}" fill-opacity="#{palette.panel_opacity}" stroke="#{palette.border}" stroke-opacity="#{palette.border_opacity}" />

      <text x="130" y="142" fill="#{palette.label}" fill-opacity="0.92" font-size="20" font-weight="800" font-family="#{@ui_font_family}" letter-spacing="0.4">RationalGrid.ai</text>

      <line x1="130" y1="176" x2="950" y2="176" stroke="#{palette.border}" stroke-width="1" stroke-opacity="#{palette.border_opacity}" />

      <text fill="#{palette.text}" font-size="#{title_font_size}" font-weight="800" font-family="#{@ui_font_family}" letter-spacing="-0.7" paint-order="stroke" stroke="#{palette.text_stroke}" stroke-width="2.2" stroke-opacity="#{palette.text_stroke_opacity}">
        #{title_markup}
      </text>
      <rect x="130" y="#{body_start_y - 54}" width="210" height="7" rx="3.5" fill="url(#portraitAccent)" opacity="0.96" />
      #{body_markup}

      <line x1="130" y1="1210" x2="950" y2="1210" stroke="#{palette.border}" stroke-width="1" stroke-opacity="#{palette.border_opacity}" />
      <text x="130" y="1248" fill="#{palette.muted}" font-size="18" font-weight="700" font-family="#{@ui_font_family}" letter-spacing="0.2">Explore the full argument on RationalGrid</text>
    </svg>
    """
  end

  def carousel_slides(%Campaign{} = campaign, node) when is_map(node) do
    node_title = node |> get("title") |> sanitize_text(320) |> fallback("Key node")

    content = node_content(campaign, node)

    content_slides =
      content
      |> Markdown.sections()
      |> Enum.flat_map(fn section ->
        base_title =
          if same_markdown_title?(section.title, node_title),
            do: "Opening idea",
            else: section.title

        section.blocks
        |> Markdown.paginate_blocks(420)
        |> Enum.with_index()
        |> Enum.map(fn {blocks, page_index} ->
          title = if page_index == 0, do: base_title, else: "#{base_title} · continued"

          %{
            label: "Argument",
            title: title,
            body: Markdown.readable_text(blocks),
            blocks: blocks
          }
        end)
      end)

    slides =
      [
        %{
          label: "Thesis",
          title: node_title,
          body: "Follow the reasoning, test the assumptions, and decide where you stand."
        }
      ] ++
        content_slides ++
        [
          %{
            label: "Learn more",
            title: "Continue on RationalGrid.ai",
            body: ""
          }
        ]

    slides
  end

  def node_short_video_slides(%Campaign{} = campaign, node) when is_map(node) do
    node_title = node |> get("title") |> sanitize_text(320) |> fallback("Key node")

    content_slides =
      node_content(campaign, node)
      |> Markdown.sections()
      |> Enum.flat_map(fn section ->
        section.blocks
        |> paginate_short_video_blocks()
        |> Enum.map(fn blocks ->
          %{
            label: "",
            title: "",
            body: Markdown.readable_text(blocks),
            blocks: blocks
          }
        end)
      end)

    opening = %{label: "", title: node_title, body: ""}
    closing = %{label: "Learn more", title: "Continue on RationalGrid.ai", body: ""}

    [opening] ++ content_slides ++ [closing]
  end

  def node_short_video_durations(%Campaign{} = campaign, node) when is_map(node) do
    campaign
    |> node_short_video_slides(node)
    |> short_video_slide_durations()
  end

  def curated_carousel_short_video_durations(slides) when is_list(slides) do
    short_video_slide_durations(slides)
  end

  defp short_video_slide_durations(slides) do
    Enum.map(slides, &short_video_slide_duration/1)
  end

  defp short_video_slide_duration(slide) do
    label = slide |> get("label") |> to_string()
    title = slide |> get("title") |> sanitize_text(nil)
    body = slide |> get("body") |> sanitize_text(nil)

    cond do
      label == "Learn more" -> @short_min_duration
      title != "" and body == "" -> readable_duration(title)
      true -> readable_duration(Enum.join([title, body], " "))
    end
  end

  defp readable_duration(text) do
    word_count = text |> String.split(~r/\s+/, trim: true) |> length()

    max(
      @short_min_duration,
      Float.round(word_count / @short_words_per_second + @short_pause_duration, 2)
    )
  end

  defp paginate_short_video_blocks(blocks) do
    blocks
    |> Enum.flat_map(&short_video_block_chunks/1)
    |> Enum.reduce([], &append_short_video_block(&2, &1))
  end

  defp short_video_block_chunks(block) do
    lines = short_video_block_lines(block)

    lines
    |> Enum.chunk_every(@short_body_max_lines)
    |> Enum.map(fn chunk -> %{block | text: Enum.join(chunk, " ")} end)
  end

  defp short_video_block_lines(block) do
    style =
      markdown_block_style(block, %{
        font_size: @short_body_font_size,
        palette: %{text: "", secondary_text: ""}
      })

    max_units = (@short_body_width - style.indent) / style.font_size * 0.9
    wrap_all_lines_by_width(block.text, max_units)
  end

  defp short_video_body_start_y(content) do
    blocks = if is_list(content), do: content, else: Markdown.blocks(content)

    {last_y, last_line_gap, rendered?} =
      Enum.reduce(blocks, {0, @short_body_font_size, false}, fn block,
                                                                {last_y, _last_line_gap,
                                                                 rendered?} ->
        style =
          markdown_block_style(block, %{
            font_size: @short_body_font_size,
            palette: %{text: "", secondary_text: ""}
          })

        lines = short_video_block_lines(block)
        first_y = if rendered?, do: last_y + style.line_gap + style.gap, else: 0
        block_last_y = first_y + max(length(lines) - 1, 0) * style.line_gap
        {block_last_y, style.line_gap, true}
      end)

    content_height = if rendered?, do: last_y + last_line_gap, else: 0
    available_height = @short_body_area_bottom - @short_body_area_top
    centered_offset = div(max(available_height - content_height, 0), 2)

    @short_body_area_top + centered_offset + @short_body_font_size
  end

  defp append_short_video_block([], block), do: [[block]]

  defp append_short_video_block(pages, block) do
    current_page = List.last(pages)
    current_lines = Enum.reduce(current_page, 0, &(length(short_video_block_lines(&1)) + &2))
    block_lines = length(short_video_block_lines(block))

    if current_lines + block_lines <= @short_body_max_lines do
      List.replace_at(pages, length(pages) - 1, current_page ++ [block])
    else
      pages ++ [[block]]
    end
  end

  defp node_content(%Campaign{} = campaign, node) do
    direct_content = get(node, "content") || get(node, "body") || get(node, "text")

    content =
      if direct_content || get(node, "class") != "origin" do
        direct_content
      else
        first_answer_content(campaign.raw_payload)
      end

    content |> fallback(get(node, "excerpt")) |> fallback("") |> to_string()
  end

  defp first_answer_content(payload) when is_map(payload) do
    with content_map when is_map(content_map) <- Map.get(payload, "content"),
         first_answer when is_map(first_answer) <- Map.get(content_map, "first_answer") do
      Map.get(first_answer, "content")
    else
      _ -> nil
    end
  end

  defp first_answer_content(_payload), do: nil

  def key_node_carousel_asset_attrs(%Campaign{} = campaign, node, style \\ @default_style) do
    style = normalize_style(style)
    node_id = node |> get("id") |> string_value()
    node_title = node |> get("title") |> sanitize_text(180) |> fallback("Key node")
    slides = carousel_slides(campaign, node)
    total = length(slides)

    slides
    |> Enum.with_index(1)
    |> Enum.map(fn {slide, index} ->
      %{
        title: "#{node_title} · Slide #{index}",
        kind: "key_node_carousel_slide",
        url: node_carousel_image_path(campaign, node_id, index, style),
        mime_type: "image/png",
        text: slide.body,
        node_id: node_id,
        highlight_id: nil,
        recommended_platforms: if(index == 1, do: ["instagram", "linkedin"], else: []),
        style: style,
        source_type: "key_node_carousel",
        source_id: "#{node_id}|#{index}",
        metadata: %{
          "format" => "carousel",
          "slide_index" => index,
          "slide_count" => total,
          "slide_label" => slide.label
        },
        carousel_cover?: index == 1
      }
    end)
  end

  def node_carousel_image_svg(campaign, node, style, slide) when is_map(node) do
    style = normalize_style(style)
    slide_index = normalize_slide_index(slide)
    slides = carousel_slides(campaign, node)
    selected_slide = Enum.at(slides, slide_index - 1) || List.first(slides)

    carousel_slide_image_svg(campaign, selected_slide, style, slide_index, length(slides))
  end

  def curated_carousel_image_svg(campaign, slides, style, slide) when is_list(slides) do
    style = normalize_style(style)
    slide_index = normalize_slide_index(slide)
    slides = Enum.map(slides, &normalize_curated_slide/1)
    selected_slide = Enum.at(slides, slide_index - 1) || List.first(slides)

    carousel_slide_image_svg(campaign, selected_slide, style, slide_index, length(slides))
  end

  def curated_carousel_image_png(campaign, slides, style, slide) when is_list(slides) do
    campaign
    |> curated_carousel_image_svg(slides, style, slide)
    |> Image.from_svg!()
    |> Image.write!(:memory, suffix: ".png")
  end

  defp carousel_slide_image_svg(campaign, slide, style, slide_index, slide_count) do
    palette = quote_palette(style)
    body_start_y = 480
    title_image_data_uri = carousel_title_image_data_uri(slide.title, palette.text)
    footer = "#{slide_index} / #{slide_count} · Learn more at rationalgrid.ai"
    footer_font_size = single_line_font_size(footer, 820, 18, 8)

    body_markup =
      fitted_markdown_body_markup(
        Map.get(slide, :blocks, slide.body),
        nil,
        %{
          x: 130,
          start_y: body_start_y,
          max_y: 1_160,
          width: 820,
          font_size: 31,
          palette: palette
        },
        [31, 28, 26, 24, 22, 20, 18, 16, 14, 12]
      )

    """
    <svg xmlns="http://www.w3.org/2000/svg" width="#{@portrait_width}" height="#{@portrait_height}" viewBox="0 0 #{@portrait_width} #{@portrait_height}" role="img" aria-labelledby="title desc">
      <title id="title">#{escape_xml(slide.title)} · #{escape_xml(campaign.title)} · RationalGrid</title>
      <desc id="desc">Carousel slide #{slide_index} of #{slide_count} from #{escape_xml(campaign.title)} on RationalGrid</desc>
      <defs>
        <linearGradient id="carouselCanvas" x1="0%" y1="0%" x2="100%" y2="100%">
          <stop offset="0%" stop-color="#{palette.canvas_a}" />
          <stop offset="48%" stop-color="#{palette.canvas_b}" />
          <stop offset="100%" stop-color="#{palette.canvas_c}" />
        </linearGradient>
        <radialGradient id="carouselBloomA" cx="12%" cy="10%" r="72%">
          <stop offset="0%" stop-color="#{palette.bloom_a}" stop-opacity="#{palette.bloom_opacity}" />
          <stop offset="100%" stop-color="#{palette.bloom_a}" stop-opacity="0" />
        </radialGradient>
        <radialGradient id="carouselBloomB" cx="90%" cy="24%" r="70%">
          <stop offset="0%" stop-color="#{palette.bloom_b}" stop-opacity="#{palette.bloom_opacity}" />
          <stop offset="100%" stop-color="#{palette.bloom_b}" stop-opacity="0" />
        </radialGradient>
        <linearGradient id="carouselAccent" x1="0%" y1="0%" x2="100%" y2="0%">
          <stop offset="0%" stop-color="#{palette.accent_a}" />
          <stop offset="52%" stop-color="#{palette.accent_b}" />
          <stop offset="100%" stop-color="#{palette.accent_c}" />
        </linearGradient>
        <filter id="carouselShadow" x="-8%" y="-6%" width="116%" height="114%">
          <feDropShadow dx="0" dy="28" stdDeviation="26" flood-color="#{palette.shadow}" flood-opacity="#{palette.shadow_opacity}" />
        </filter>
      </defs>

      <rect width="1080" height="1350" fill="url(#carouselCanvas)" />
      #{pexels_background_markup(campaign, 1080, 1350)}
      <rect width="1080" height="1350" fill="url(#carouselBloomA)" />
      <rect width="1080" height="1350" fill="url(#carouselBloomB)" />
      <rect x="54" y="54" width="972" height="1242" rx="44" fill="#{palette.card}" fill-opacity="#{palette.card_opacity}" filter="url(#carouselShadow)" />
      <rect x="54.5" y="54.5" width="971" height="1241" rx="43.5" fill="none" stroke="#{palette.border}" stroke-opacity="#{palette.border_opacity}" />
      <rect x="82" y="82" width="916" height="1186" rx="32" fill="#{palette.panel}" fill-opacity="#{palette.panel_opacity}" stroke="#{palette.border}" stroke-opacity="#{palette.border_opacity}" />

      <text x="130" y="142" fill="#{palette.label}" fill-opacity="0.92" font-size="20" font-weight="800" font-family="#{@ui_font_family}" letter-spacing="0.4">RationalGrid.ai</text>

      <line x1="130" y1="176" x2="950" y2="176" stroke="#{palette.border}" stroke-width="1" stroke-opacity="#{palette.border_opacity}" />
      <image x="130" y="205" width="820" height="190" href="#{title_image_data_uri}" preserveAspectRatio="none" />
      <rect x="130" y="430" width="210" height="7" rx="3.5" fill="url(#carouselAccent)" opacity="0.96" />
      #{body_markup}
      <line x1="130" y1="1210" x2="950" y2="1210" stroke="#{palette.border}" stroke-width="1" stroke-opacity="#{palette.border_opacity}" />
      <text x="130" y="1248" fill="#{palette.muted}" font-size="#{footer_font_size}" font-weight="700" font-family="#{@ui_font_family}">#{escape_xml(footer)}</text>
    </svg>
    """
  end

  @doc """
  Rasterizes a carousel SVG to a social-ready PNG using libvips.

  The SVG remains the layout source so existing styles stay consistent, while
  Image.Text handles the bounded title layout and libvips produces the final
  bitmap that social platforms expect.
  """
  def node_carousel_image_png(campaign, node, style, slide) when is_map(node) do
    campaign
    |> node_carousel_image_svg(node, style, slide)
    |> Image.from_svg!()
    |> Image.write!(:memory, suffix: ".png")
  end

  def node_short_video_frame_svg(campaign, node, style, slide) when is_map(node) do
    style = normalize_style(style)
    slide_index = normalize_slide_index(slide)
    slides = node_short_video_slides(campaign, node)
    selected_slide = Enum.at(slides, slide_index - 1) || List.first(slides)

    short_video_frame_svg(campaign, selected_slide, style, slide_index, length(slides))
  end

  def curated_carousel_short_video_frame_svg(campaign, slides, style, slide)
      when is_list(slides) do
    style = normalize_style(style)
    slide_index = normalize_slide_index(slide)
    slides = Enum.map(slides, &normalize_curated_slide/1)
    selected_slide = Enum.at(slides, slide_index - 1) || List.first(slides)

    short_video_frame_svg(campaign, selected_slide, style, slide_index, length(slides))
  end

  def curated_carousel_short_video_frame_png(campaign, slides, style, slide)
      when is_list(slides) do
    campaign
    |> curated_carousel_short_video_frame_svg(slides, style, slide)
    |> Image.from_svg!()
    |> Image.write!(:memory, suffix: ".png")
  end

  defp short_video_frame_svg(campaign, slide, style, slide_index, slide_count) do
    palette = quote_palette(style)
    cover? = slide_index == 1
    cta? = slide.label in ["Explore", "Learn more"]
    text_only? = slide.title == "" and not cta?
    minimal? = cover? or text_only? or cta?
    logo_markup = if cta?, do: rg_logo_markup(), else: ""

    brand_header =
      if minimal? do
        ""
      else
        ~s(<text x="130" y="170" fill="#{palette.label}" font-size="23" font-weight="800" font-family="#{@ui_font_family}">RationalGrid.ai</text>)
      end

    footer_markup =
      if minimal? do
        ""
      else
        ~s(<line x1="130" y1="1738" x2="950" y2="1738" stroke="#{palette.border}" stroke-width="1" stroke-opacity="#{palette.border_opacity}" />) <>
          ~s(<text x="130" y="1790" fill="#{palette.muted}" font-size="22" font-weight="700" font-family="#{@ui_font_family}">Learn more at rationalgrid.ai</text>)
      end

    top_rule =
      if minimal? do
        ""
      else
        ~s(<line x1="130" y1="210" x2="950" y2="210" stroke="#{palette.border}" stroke-width="1" stroke-opacity="#{palette.border_opacity}" />)
      end

    title_layout =
      bounded_text_layout(
        slide.title,
        820,
        390,
        if(cover?,
          do: [68, 64, 60, 56, 52, 48, 44, 40, 36, 32, 28, 24, 20, 18],
          else: [56, 52, 48, 44, 40, 36, 32, 28, 24, 20, 18]
        )
      )

    title_font_size = title_layout.font_size
    title_line_gap = title_layout.line_gap
    title_lines = title_layout.lines

    title_start_y =
      cond do
        cta? -> 930
        cover? -> 760
        true -> 350
      end

    title_x = if cta?, do: 540, else: 130
    title_anchor = if cta?, do: "middle", else: "start"
    title_last_y = title_start_y + (length(title_lines) - 1) * title_line_gap

    body_start_y =
      cond do
        cta? or cover? -> 610
        text_only? -> short_video_body_start_y(Map.get(slide, :blocks, slide.body))
        true -> max(title_last_y + 92, 610)
      end

    body_font_size =
      cond do
        text_only? -> @short_body_font_size
        cover? -> 48
        true -> 46
      end

    body_font_sizes =
      if text_only? do
        [@short_body_font_size]
      else
        Enum.filter(
          [body_font_size, 44, 42, 40, 38, 36, 34, 32, 30, 28, 26, 24, 22, 20],
          &(&1 <= body_font_size)
        )
      end

    title_markup =
      title_lines
      |> Enum.with_index()
      |> Enum.map_join("", fn {line, index} ->
        ~s(<tspan x="#{title_x}" y="#{title_start_y + index * title_line_gap}">#{escape_xml(line)}</tspan>)
      end)

    body_markup =
      if cta? do
        ""
      else
        fitted_markdown_body_markup(
          Map.get(slide, :blocks, slide.body),
          nil,
          %{
            x: if(text_only?, do: @short_body_x, else: 130),
            start_y: body_start_y,
            max_y: if(text_only?, do: @short_body_max_y, else: 1_620),
            width: if(text_only?, do: @short_body_width, else: 820),
            font_size: body_font_size,
            palette: palette
          },
          body_font_sizes
        )
      end

    accent_markup =
      if minimal? do
        ""
      else
        ~s|<rect x="130" y="#{body_start_y - 72}" width="260" height="9" rx="4.5" fill="url(#shortAccent)" opacity="0.98" />|
      end

    """
    <svg xmlns="http://www.w3.org/2000/svg" width="#{@short_width}" height="#{@short_height}" viewBox="0 0 #{@short_width} #{@short_height}" role="img" aria-labelledby="title desc">
      <title id="title">#{escape_xml(slide.title)} · #{escape_xml(campaign.title)} · RationalGrid Short</title>
      <desc id="desc">Vertical short-video frame #{slide_index} of #{slide_count}</desc>
      <defs>
        <linearGradient id="shortCanvas" x1="0%" y1="0%" x2="100%" y2="100%">
          <stop offset="0%" stop-color="#{palette.canvas_a}" />
          <stop offset="48%" stop-color="#{palette.canvas_b}" />
          <stop offset="100%" stop-color="#{palette.canvas_c}" />
        </linearGradient>
        <radialGradient id="shortBloomA" cx="12%" cy="10%" r="72%">
          <stop offset="0%" stop-color="#{palette.bloom_a}" stop-opacity="#{palette.bloom_opacity}" />
          <stop offset="100%" stop-color="#{palette.bloom_a}" stop-opacity="0" />
        </radialGradient>
        <radialGradient id="shortBloomB" cx="90%" cy="28%" r="70%">
          <stop offset="0%" stop-color="#{palette.bloom_b}" stop-opacity="#{palette.bloom_opacity}" />
          <stop offset="100%" stop-color="#{palette.bloom_b}" stop-opacity="0" />
        </radialGradient>
        <linearGradient id="shortAccent" x1="0%" y1="0%" x2="100%" y2="0%">
          <stop offset="0%" stop-color="#{palette.accent_a}" />
          <stop offset="52%" stop-color="#{palette.accent_b}" />
          <stop offset="100%" stop-color="#{palette.accent_c}" />
        </linearGradient>
        <filter id="shortShadow" x="-8%" y="-6%" width="116%" height="114%">
          <feDropShadow dx="0" dy="32" stdDeviation="28" flood-color="#{palette.shadow}" flood-opacity="#{palette.shadow_opacity}" />
        </filter>
      </defs>

      <rect width="1080" height="1920" fill="url(#shortCanvas)" />
      #{pexels_background_markup(campaign, 1080, 1920)}
      <rect width="1080" height="1920" fill="url(#shortBloomA)" />
      <rect width="1080" height="1920" fill="url(#shortBloomB)" />
      <circle cx="950" cy="230" r="220" fill="#{palette.bloom_b}" fill-opacity="#{palette.decoration_opacity}" />
      <circle cx="120" cy="1690" r="240" fill="#{palette.bloom_a}" fill-opacity="#{palette.decoration_opacity}" />

      <rect x="54" y="64" width="972" height="1792" rx="48" fill="#{palette.card}" fill-opacity="#{palette.card_opacity}" filter="url(#shortShadow)" />
      <rect x="54.5" y="64.5" width="971" height="1791" rx="47.5" fill="none" stroke="#{palette.border}" stroke-opacity="#{palette.border_opacity}" />
      <rect x="82" y="92" width="916" height="1736" rx="34" fill="#{palette.panel}" fill-opacity="#{palette.panel_opacity}" stroke="#{palette.border}" stroke-opacity="#{palette.border_opacity}" />

      #{brand_header}

      #{top_rule}
      #{logo_markup}

      <text x="#{title_x}" text-anchor="#{title_anchor}" fill="#{palette.text}" font-size="#{title_font_size}" font-weight="900" font-family="#{@ui_font_family}" letter-spacing="-1.2" paint-order="stroke" stroke="#{palette.text_stroke}" stroke-width="2.4" stroke-opacity="#{palette.text_stroke_opacity}">
        #{title_markup}
      </text>
      #{accent_markup}
      #{body_markup}

      #{footer_markup}
    </svg>
    """
  end

  def node_short_video_frame_png(campaign, node, style, slide) when is_map(node) do
    campaign
    |> node_short_video_frame_svg(node, style, slide)
    |> Image.from_svg!()
    |> Image.write!(:memory, suffix: ".png")
  end

  defp rg_logo_markup do
    path = Path.join(to_string(:code.priv_dir(:grid_media_manager)), "static/images/rg_logo.webp")

    case File.read(path) do
      {:ok, logo} ->
        png = logo |> Image.from_binary!() |> Image.write!(:memory, suffix: ".png")
        encoded = Base.encode64(png)

        ~s(<image x="420" y="520" width="240" height="240" href="data:image/png;base64,#{encoded}" preserveAspectRatio="xMidYMid meet" />)

      _ ->
        ""
    end
  end

  defp carousel_title_image_data_uri(title, text_color) do
    title
    |> Image.Text.text!(
      font: "Arial",
      font_size: 0,
      font_weight: :heavy,
      text_fill_color: text_color,
      background_fill_color: :transparent,
      width: 820,
      height: 190,
      x: :left,
      y: :top
    )
    |> Image.write!(:memory, suffix: ".png")
    |> Base.encode64()
    |> then(&"data:image/png;base64,#{&1}")
  end

  def question_image_svg(campaign, question, style \\ @default_style)

  def question_image_svg(%Campaign{} = campaign, question, style) when is_map(question) do
    style = normalize_style(style)
    palette = quote_palette(style)
    question_text = question |> get("question") |> sanitize_text(nil)

    layout = full_quote_layout(question_text)
    campaign_title = sanitize_text(campaign.title, nil)
    campaign_title_size = single_line_font_size(campaign_title, 1_028, 22, 10)

    quote_markup =
      layout.lines
      |> Enum.with_index()
      |> Enum.map_join("", fn {line, index} ->
        y = layout.start_y + index * layout.line_gap
        ~s(<tspan x="#{@quote_area_left}" y="#{y}">#{escape_xml(line)}</tspan>)
      end)

    """
    <svg xmlns="http://www.w3.org/2000/svg" width="#{@image_width}" height="#{@image_height}" viewBox="0 0 #{@image_width} #{@image_height}" role="img" aria-labelledby="title desc">
      <title id="title">#{escape_xml(question_text)} · #{escape_xml(campaign.title)} · RationalGrid</title>
      <desc id="desc">Question quote card from #{escape_xml(campaign.title)} on RationalGrid</desc>
      <defs>
        <linearGradient id="questionCanvas" x1="0%" y1="0%" x2="100%" y2="100%">
          <stop offset="0%" stop-color="#{palette.canvas_a}" />
          <stop offset="42%" stop-color="#{palette.canvas_b}" />
          <stop offset="100%" stop-color="#{palette.canvas_c}" />
        </linearGradient>
        <radialGradient id="questionRose" cx="14%" cy="14%" r="70%">
          <stop offset="0%" stop-color="#{palette.bloom_a}" stop-opacity="#{palette.bloom_opacity}" />
          <stop offset="100%" stop-color="#{palette.bloom_a}" stop-opacity="0" />
        </radialGradient>
        <radialGradient id="questionCyan" cx="88%" cy="18%" r="68%">
          <stop offset="0%" stop-color="#{palette.bloom_b}" stop-opacity="#{palette.bloom_opacity}" />
          <stop offset="100%" stop-color="#{palette.bloom_b}" stop-opacity="0" />
        </radialGradient>
        <linearGradient id="questionAccent" x1="0%" y1="0%" x2="100%" y2="0%">
          <stop offset="0%" stop-color="#{palette.accent_a}" />
          <stop offset="50%" stop-color="#{palette.accent_b}" />
          <stop offset="100%" stop-color="#{palette.accent_c}" />
        </linearGradient>
        <filter id="questionShadow" x="-8%" y="-10%" width="116%" height="124%">
          <feDropShadow dx="0" dy="28" stdDeviation="24" flood-color="#{palette.shadow}" flood-opacity="#{palette.shadow_opacity}" />
        </filter>
      </defs>

      <rect width="1200" height="630" fill="url(#questionCanvas)" />
      #{pexels_background_markup(campaign, 1200, 630)}
      <rect width="1200" height="630" fill="url(#questionRose)" />
      <rect width="1200" height="630" fill="url(#questionCyan)" />
      <path d="M-40 488 C212 390 356 622 604 496 C820 386 948 434 1240 284" fill="none" stroke="#{palette.accent_a}" stroke-opacity="#{palette.decoration_opacity}" stroke-width="2" />
      <path d="M-30 158 C186 250 312 24 548 142 C806 270 944 76 1232 118" fill="none" stroke="#{palette.accent_c}" stroke-opacity="#{palette.decoration_opacity}" stroke-width="2" />

      <rect x="38" y="34" width="1124" height="562" rx="40" fill="#{palette.card}" fill-opacity="#{palette.card_opacity}" filter="url(#questionShadow)" />
      <rect x="38.5" y="34.5" width="1123" height="561" rx="39.5" fill="none" stroke="#{palette.border}" stroke-opacity="#{palette.border_opacity}" />
      <rect x="58" y="54" width="1084" height="522" rx="30" fill="#{palette.panel}" fill-opacity="#{palette.panel_opacity}" stroke="#{palette.border}" stroke-opacity="#{palette.border_opacity}" />

      <text x="86" y="98" fill="#{palette.label}" fill-opacity="0.9" font-size="17" font-weight="800" font-family="#{@ui_font_family}" letter-spacing="0">RationalGrid.ai</text>

      <rect x="86" y="126" width="1028" height="1" fill="#{palette.border}" fill-opacity="#{palette.border_opacity}" />
      <rect x="86" y="514" width="344" height="6" rx="3" fill="url(#questionAccent)" opacity="0.96" />

      <text x="58" y="286" fill="#{palette.accent_a}" fill-opacity="0.10" font-size="198" font-weight="700" font-family="#{@quote_font_family}">“</text>
      <text x="1142" y="500" text-anchor="end" fill="#{palette.accent_c}" fill-opacity="0.08" font-size="154" font-weight="700" font-family="#{@quote_font_family}">”</text>
      <text fill="#{palette.text}" font-size="#{layout.font_size}" font-weight="700" font-family="#{@quote_font_family}" letter-spacing="0" paint-order="stroke" stroke="#{palette.text_stroke}" stroke-width="2.2" stroke-opacity="#{palette.text_stroke_opacity}">
        #{quote_markup}
      </text>

      <text x="86" y="552" fill="#{palette.label}" fill-opacity="0.9" font-size="#{campaign_title_size}" font-weight="800" font-family="#{@ui_font_family}" letter-spacing="0">#{escape_xml(campaign_title)}</text>
    </svg>
    """
  end

  def highlight_image_svg(campaign, highlight, style \\ @default_style)

  def highlight_image_svg(%Campaign{} = campaign, highlight, style) when is_map(highlight) do
    style = normalize_style(style)
    palette = quote_palette(style)

    quote_text =
      highlight
      |> highlight_text()
      |> sanitize_text(nil)

    quote_layout = quote_layout(quote_text)

    source_label =
      campaign
      |> node_title(highlight_node_id(highlight))
      |> sanitize_text(nil)

    source_font_size = single_line_font_size(source_label, 1_028, 24, 10)

    quote_markup =
      quote_layout.lines
      |> Enum.with_index()
      |> Enum.map_join("", fn {line, index} ->
        y = quote_layout.start_y + index * quote_layout.line_gap
        ~s(<tspan x="#{@quote_area_left}" y="#{y}">#{escape_xml(line)}</tspan>)
      end)

    """
    <svg xmlns="http://www.w3.org/2000/svg" width="#{@image_width}" height="#{@image_height}" viewBox="0 0 #{@image_width} #{@image_height}" role="img" aria-labelledby="title desc">
      <title id="title">#{escape_xml(page_title(campaign, highlight))}</title>
      <desc id="desc">#{escape_xml(page_description(campaign, highlight))}</desc>
      <defs>
        <linearGradient id="quoteCanvas" x1="0%" y1="0%" x2="100%" y2="100%">
          <stop offset="0%" stop-color="#{palette.canvas_a}" />
          <stop offset="45%" stop-color="#{palette.canvas_b}" />
          <stop offset="100%" stop-color="#{palette.canvas_c}" />
        </linearGradient>
        <radialGradient id="amberBloom" cx="12%" cy="12%" r="68%">
          <stop offset="0%" stop-color="#{palette.bloom_a}" stop-opacity="#{palette.bloom_opacity}" />
          <stop offset="100%" stop-color="#{palette.bloom_a}" stop-opacity="0" />
        </radialGradient>
        <radialGradient id="tealBloom" cx="88%" cy="18%" r="72%">
          <stop offset="0%" stop-color="#{palette.bloom_b}" stop-opacity="#{palette.bloom_opacity}" />
          <stop offset="100%" stop-color="#{palette.bloom_b}" stop-opacity="0" />
        </radialGradient>
        <radialGradient id="violetBloom" cx="66%" cy="88%" r="62%">
          <stop offset="0%" stop-color="#{palette.accent_c}" stop-opacity="#{palette.decoration_opacity}" />
          <stop offset="100%" stop-color="#{palette.accent_c}" stop-opacity="0" />
        </radialGradient>
        <linearGradient id="quotePanel" x1="0%" y1="0%" x2="100%" y2="100%">
          <stop offset="0%" stop-color="#{palette.panel}" stop-opacity="#{palette.panel_opacity}" />
          <stop offset="42%" stop-color="#{palette.panel}" stop-opacity="#{palette.panel_soft_opacity}" />
          <stop offset="100%" stop-color="#{palette.panel_end}" stop-opacity="#{palette.panel_accent_opacity}" />
        </linearGradient>
        <linearGradient id="highlightAccent" x1="0%" y1="0%" x2="100%" y2="0%">
          <stop offset="0%" stop-color="#{palette.accent_a}" />
          <stop offset="48%" stop-color="#{palette.accent_b}" />
          <stop offset="100%" stop-color="#{palette.accent_c}" />
        </linearGradient>
        <linearGradient id="brandMark" x1="0%" y1="0%" x2="100%" y2="100%">
          <stop offset="0%" stop-color="#{palette.accent_b}" />
          <stop offset="100%" stop-color="#{palette.accent_c}" />
        </linearGradient>
        <filter id="cardShadow" x="-8%" y="-10%" width="116%" height="124%">
          <feDropShadow dx="0" dy="28" stdDeviation="24" flood-color="#{palette.shadow}" flood-opacity="#{palette.shadow_opacity}" />
        </filter>
        <filter id="softGlow" x="-35%" y="-35%" width="170%" height="170%">
          <feGaussianBlur stdDeviation="18" result="blur" />
          <feColorMatrix in="blur" type="matrix" values="1 0 0 0 0.96 0 1 0 0 0.65 0 0 1 0 0.20 0 0 0 #{palette.glow_opacity} 0" />
          <feMerge>
            <feMergeNode />
            <feMergeNode in="SourceGraphic" />
          </feMerge>
        </filter>
      </defs>

      <rect width="1200" height="630" fill="url(#quoteCanvas)" />
      #{pexels_background_markup(campaign, 1200, 630)}
      <rect width="1200" height="630" fill="url(#amberBloom)" />
      <rect width="1200" height="630" fill="url(#tealBloom)" />
      <rect width="1200" height="630" fill="url(#violetBloom)" />
      <path d="M-40 492 C220 402 356 638 606 500 C820 382 948 438 1240 284" fill="none" stroke="#{palette.accent_b}" stroke-opacity="#{palette.decoration_opacity}" stroke-width="2" />
      <path d="M-30 158 C186 250 312 24 548 142 C806 270 944 76 1232 118" fill="none" stroke="#{palette.accent_c}" stroke-opacity="#{palette.decoration_opacity}" stroke-width="2" />
      <circle cx="1032" cy="112" r="168" fill="#{palette.bloom_b}" fill-opacity="#{palette.decoration_opacity}" />
      <circle cx="158" cy="516" r="152" fill="#{palette.bloom_a}" fill-opacity="#{palette.decoration_opacity}" />

      <rect x="38" y="34" width="1124" height="562" rx="40" fill="#{palette.card}" fill-opacity="#{palette.card_opacity}" filter="url(#cardShadow)" />
      <rect x="38.5" y="34.5" width="1123" height="561" rx="39.5" fill="none" stroke="#{palette.border}" stroke-opacity="#{palette.border_opacity}" />
      <rect x="58" y="54" width="1084" height="522" rx="30" fill="url(#quotePanel)" stroke="#{palette.border}" stroke-opacity="#{palette.border_opacity}" />

      <circle cx="92" cy="92" r="16" fill="url(#brandMark)" filter="url(#softGlow)" />
      <path d="M92 83 L100 92 L92 101 L84 92 Z" fill="#{palette.card}" fill-opacity="0.88" />
      <text x="121" y="98" fill="#{palette.label}" fill-opacity="0.9" font-size="17" font-weight="800" font-family="#{@ui_font_family}" letter-spacing="0">RationalGrid.ai</text>

      <rect x="86" y="126" width="1028" height="1" fill="#{palette.border}" fill-opacity="#{palette.border_opacity}" />
      <rect x="86" y="514" width="344" height="6" rx="3" fill="url(#highlightAccent)" opacity="0.96" />

      <text x="58" y="286" fill="#{palette.accent_a}" fill-opacity="0.10" font-size="198" font-weight="700" font-family="#{@quote_font_family}">“</text>
      <text x="1142" y="500" text-anchor="end" fill="#{palette.accent_c}" fill-opacity="0.08" font-size="154" font-weight="700" font-family="#{@quote_font_family}">”</text>
      <text fill="#{palette.text}" font-size="#{quote_layout.font_size}" font-weight="700" font-family="#{@quote_font_family}" letter-spacing="0" paint-order="stroke" stroke="#{palette.text_stroke}" stroke-width="2.2" stroke-opacity="#{palette.text_stroke_opacity}">
        #{quote_markup}
      </text>

      <text x="86" y="552" fill="#{palette.label}" fill-opacity="0.9" font-size="#{source_font_size}" font-weight="800" font-family="#{@ui_font_family}" letter-spacing="0">#{escape_xml(source_label)}</text>
    </svg>
    """
  end

  def question_platform_image_svg(campaign, question, style, format)

  def question_platform_image_svg(%Campaign{} = campaign, question, style, format)
      when is_map(question) do
    format = normalize_quote_format(format)

    if format == "landscape" do
      question_image_svg(campaign, question, style)
    else
      text = question |> get("question") |> sanitize_text(nil)
      kind = question |> get("kind") |> sanitize_text(48) |> fallback("question")

      platform_quote_image_svg(
        campaign,
        text,
        campaign.title,
        kind,
        style,
        format
      )
    end
  end

  def highlight_platform_image_svg(campaign, highlight, style, format)

  def highlight_platform_image_svg(%Campaign{} = campaign, highlight, style, format)
      when is_map(highlight) do
    format = normalize_quote_format(format)

    if format == "landscape" do
      highlight_image_svg(campaign, highlight, style)
    else
      text = highlight |> highlight_text() |> sanitize_text(nil)
      source = campaign |> node_title(highlight_node_id(highlight)) |> sanitize_text(nil)
      platform_quote_image_svg(campaign, text, source, "highlight", style, format)
    end
  end

  def question_platform_image_png(campaign, question, style, format) do
    campaign
    |> question_platform_image_svg(question, style, format)
    |> rasterize_svg()
  end

  def highlight_platform_image_png(campaign, highlight, style, format) do
    campaign
    |> highlight_platform_image_svg(highlight, style, format)
    |> rasterize_svg()
  end

  defp platform_quote_image_svg(campaign, text, source, kind, style, format) do
    style = normalize_style(style)
    palette = quote_palette(style)
    spec = platform_quote_spec(format)
    layout = platform_quote_layout(text, spec)
    platform_label = platform_quote_label(format)

    quote_markup =
      layout.lines
      |> Enum.with_index()
      |> Enum.map_join("", fn {line, index} ->
        ~s(<tspan x="#{spec.text_x}" y="#{layout.start_y + index * layout.line_gap}">#{escape_xml(line)}</tspan>)
      end)

    """
    <svg xmlns="http://www.w3.org/2000/svg" width="#{spec.width}" height="#{spec.height}" viewBox="0 0 #{spec.width} #{spec.height}" role="img" aria-labelledby="title desc">
      <title id="title">#{escape_xml(text)} · #{escape_xml(campaign.title)} · RationalGrid</title>
      <desc id="desc">#{escape_xml(platform_label)} #{escape_xml(kind)} card from #{escape_xml(campaign.title)}</desc>
      <defs>
        <linearGradient id="platformCanvas" x1="0%" y1="0%" x2="100%" y2="100%">
          <stop offset="0%" stop-color="#{palette.canvas_a}" />
          <stop offset="48%" stop-color="#{palette.canvas_b}" />
          <stop offset="100%" stop-color="#{palette.canvas_c}" />
        </linearGradient>
        <radialGradient id="platformBloomA" cx="12%" cy="10%" r="72%">
          <stop offset="0%" stop-color="#{palette.bloom_a}" stop-opacity="#{palette.bloom_opacity}" />
          <stop offset="100%" stop-color="#{palette.bloom_a}" stop-opacity="0" />
        </radialGradient>
        <radialGradient id="platformBloomB" cx="90%" cy="24%" r="70%">
          <stop offset="0%" stop-color="#{palette.bloom_b}" stop-opacity="#{palette.bloom_opacity}" />
          <stop offset="100%" stop-color="#{palette.bloom_b}" stop-opacity="0" />
        </radialGradient>
        <linearGradient id="platformAccent" x1="0%" y1="0%" x2="100%" y2="0%">
          <stop offset="0%" stop-color="#{palette.accent_a}" />
          <stop offset="52%" stop-color="#{palette.accent_b}" />
          <stop offset="100%" stop-color="#{palette.accent_c}" />
        </linearGradient>
        <filter id="platformShadow" x="-8%" y="-6%" width="116%" height="114%">
          <feDropShadow dx="0" dy="28" stdDeviation="26" flood-color="#{palette.shadow}" flood-opacity="#{palette.shadow_opacity}" />
        </filter>
      </defs>

      <rect width="#{spec.width}" height="#{spec.height}" fill="url(#platformCanvas)" />
      #{pexels_background_markup(campaign, spec.width, spec.height)}
      <rect width="#{spec.width}" height="#{spec.height}" fill="url(#platformBloomA)" />
      <rect width="#{spec.width}" height="#{spec.height}" fill="url(#platformBloomB)" />
      <circle cx="#{spec.width - 120}" cy="170" r="190" fill="#{palette.bloom_b}" fill-opacity="#{palette.decoration_opacity}" />
      <circle cx="110" cy="#{spec.height - 170}" r="210" fill="#{palette.bloom_a}" fill-opacity="#{palette.decoration_opacity}" />

      <rect x="54" y="54" width="#{spec.width - 108}" height="#{spec.height - 108}" rx="46" fill="#{palette.card}" fill-opacity="#{palette.card_opacity}" filter="url(#platformShadow)" />
      <rect x="54.5" y="54.5" width="#{spec.width - 109}" height="#{spec.height - 109}" rx="45.5" fill="none" stroke="#{palette.border}" stroke-opacity="#{palette.border_opacity}" />
      <rect x="82" y="82" width="#{spec.width - 164}" height="#{spec.height - 164}" rx="34" fill="#{palette.panel}" fill-opacity="#{palette.panel_opacity}" stroke="#{palette.border}" stroke-opacity="#{palette.border_opacity}" />

      <text x="#{spec.text_x}" y="#{spec.brand_y}" fill="#{palette.label}" font-size="#{spec.brand_size}" font-weight="800" font-family="#{@ui_font_family}">RationalGrid.ai</text>

      <line x1="#{spec.text_x}" y1="#{spec.rule_y}" x2="#{spec.text_right}" y2="#{spec.rule_y}" stroke="#{palette.border}" stroke-width="1" stroke-opacity="#{palette.border_opacity}" />

      <text x="#{spec.text_x - 48}" y="#{spec.quote_top + 52}" fill="#{palette.accent_a}" fill-opacity="0.10" font-size="#{spec.quote_mark_size}" font-weight="700" font-family="#{@quote_font_family}">“</text>
      <text x="#{spec.text_right + 34}" y="#{spec.quote_bottom}" text-anchor="end" fill="#{palette.accent_c}" fill-opacity="0.08" font-size="#{round(spec.quote_mark_size * 0.78)}" font-weight="700" font-family="#{@quote_font_family}">”</text>
      <text fill="#{palette.text}" font-size="#{layout.font_size}" font-weight="700" font-family="#{@quote_font_family}" paint-order="stroke" stroke="#{palette.text_stroke}" stroke-width="2.2" stroke-opacity="#{palette.text_stroke_opacity}">
        #{quote_markup}
      </text>

      <rect x="#{spec.text_x}" y="#{spec.accent_y}" width="#{spec.accent_width}" height="8" rx="4" fill="url(#platformAccent)" opacity="0.96" />
      <text x="#{spec.text_x}" y="#{spec.footer_y}" fill="#{palette.label}" font-size="#{single_line_font_size(source, spec.text_right - spec.text_x, spec.footer_size, 10)}" font-weight="800" font-family="#{@ui_font_family}">#{escape_xml(sanitize_text(source, nil))}</text>
      <text x="#{spec.text_x}" y="#{spec.cta_y}" fill="#{palette.muted}" font-size="#{spec.cta_size}" font-weight="700" font-family="#{@ui_font_family}">Explore and contribute on RationalGrid</text>
    </svg>
    """
  end

  defp platform_quote_layout(text, spec) do
    text = sanitize_text(text, nil)

    Enum.find_value(spec.font_sizes, fn font_size ->
      max_units = spec.text_width / font_size * spec.wrap_factor
      lines = wrap_all_lines_by_width(text, max_units)
      line_gap = round(font_size * 1.16)
      block_height = quote_block_height(lines, line_gap)
      fits_width? = Enum.all?(lines, &(text_units(&1) <= max_units))

      if fits_width? and block_height <= spec.quote_bottom - spec.quote_top do
        extra_space = spec.quote_bottom - spec.quote_top - block_height

        %{
          font_size: font_size,
          line_gap: line_gap,
          start_y: spec.quote_top + div(extra_space, 2) + font_size,
          lines: lines
        }
      end
    end) ||
      %{
        font_size: List.last(spec.font_sizes),
        line_gap: round(List.last(spec.font_sizes) * 1.16),
        start_y: spec.quote_top + List.last(spec.font_sizes),
        lines:
          wrap_all_lines_by_width(
            text,
            spec.text_width / List.last(spec.font_sizes) * spec.wrap_factor
          )
      }
  end

  defp platform_quote_spec("linkedin") do
    %{
      width: 1200,
      height: 1200,
      text_x: 124,
      text_right: 1076,
      text_width: 880,
      brand_y: 140,
      brand_size: 20,
      kicker_size: 16,
      rule_y: 176,
      quote_top: 250,
      quote_bottom: 850,
      quote_mark_size: 170,
      accent_y: 920,
      accent_width: 260,
      footer_y: 982,
      footer_size: 24,
      cta_y: 1092,
      cta_size: 18,
      source_limit: 90,
      font_sizes: [78, 74, 70, 66, 62, 58, 54, 50, 46, 42, 38, 34, 30, 26, 22, 18, 14, 12, 10, 8],
      max_lines: 10,
      wrap_factor: 0.92
    }
  end

  defp platform_quote_spec("portrait") do
    %{
      width: 1080,
      height: 1350,
      text_x: 130,
      text_right: 950,
      text_width: 760,
      brand_y: 142,
      brand_size: 20,
      kicker_size: 16,
      rule_y: 178,
      quote_top: 290,
      quote_bottom: 1_010,
      quote_mark_size: 176,
      accent_y: 1_080,
      accent_width: 240,
      footer_y: 1_142,
      footer_size: 23,
      cta_y: 1_262,
      cta_size: 18,
      source_limit: 76,
      font_sizes: [
        80,
        76,
        72,
        68,
        64,
        60,
        56,
        52,
        48,
        44,
        40,
        36,
        32,
        28,
        24,
        20,
        16,
        14,
        12,
        10,
        8
      ],
      max_lines: 12,
      wrap_factor: 0.88
    }
  end

  defp platform_quote_spec("short") do
    %{
      width: 1080,
      height: 1920,
      text_x: 130,
      text_right: 950,
      text_width: 740,
      brand_y: 170,
      brand_size: 23,
      kicker_size: 17,
      rule_y: 210,
      quote_top: 360,
      quote_bottom: 1_440,
      quote_mark_size: 210,
      accent_y: 1_560,
      accent_width: 280,
      footer_y: 1_638,
      footer_size: 25,
      cta_y: 1_790,
      cta_size: 22,
      source_limit: 68,
      font_sizes: [
        104,
        98,
        92,
        86,
        80,
        74,
        68,
        62,
        56,
        50,
        44,
        38,
        34,
        30,
        26,
        22,
        18,
        14,
        12,
        10,
        8
      ],
      max_lines: 14,
      wrap_factor: 0.85
    }
  end

  defp platform_quote_label("linkedin"), do: "LinkedIn"
  defp platform_quote_label("portrait"), do: "Instagram"
  defp platform_quote_label("short"), do: "Short"

  def page_title(%Campaign{} = campaign, highlight) when is_map(highlight) do
    quote = highlight |> highlight_text() |> sanitize_text(nil)
    "“#{quote}” · #{campaign.title}"
  end

  def page_description(%Campaign{} = campaign, highlight) when is_map(highlight) do
    title = node_title(campaign, highlight_node_id(highlight))
    quote = highlight |> highlight_text() |> sanitize_text(nil)

    "Highlighted quote from #{title} in \"#{campaign.title}\" on RationalGrid: “#{quote}”"
  end

  def node_title(%Campaign{} = campaign, node_id) do
    campaign.raw_payload
    |> MediaPayload.key_nodes()
    |> Enum.find_value("Node #{node_id}", fn node ->
      if to_string(get(node, "id")) == to_string(node_id) do
        node
        |> get("title")
        |> sanitize_text(nil)
        |> case do
          "" -> "Node #{node_id}"
          "Untitled" -> "Node #{node_id}"
          title -> title
        end
      end
    end)
  end

  def question_asset_attr(
        campaign,
        question,
        style \\ @default_style,
        format \\ "landscape"
      )

  def question_asset_attr(%Campaign{} = campaign, question, style, format)
      when is_map(question) do
    style = normalize_style(style)
    format = normalize_quote_format(format)

    with text when is_binary(text) and text != "" <-
           question |> get("question") |> sanitize_text(nil),
         id when is_binary(id) and id != "" <- question |> get("id") |> string_value() do
      %{
        title: "Question quote",
        kind: "question_quote_card",
        url: question_image_path(campaign, id, style, format),
        mime_type: "image/png",
        text: text,
        node_id: question |> get("node_id") |> string_value(),
        highlight_id: nil,
        recommended_platforms: quote_platforms(format),
        style: style,
        source_type: "question",
        source_id: id,
        metadata:
          Map.merge(
            %{"question_kind" => get(question, "kind")},
            quote_format_metadata(format)
          )
      }
    else
      _ -> nil
    end
  end

  def key_node_asset_attr(campaign, node, style \\ @default_style, format \\ "landscape")

  def key_node_asset_attr(%Campaign{} = campaign, node, style, format) do
    style = normalize_style(style)
    format = normalize_node_format(format)

    with node_id when is_binary(node_id) and node_id != "" <- node |> get("id") |> string_value(),
         title when is_binary(title) and title != "" <- node |> get("title") |> sanitize_text(nil) do
      %{
        title: title,
        kind: "key_node_card",
        url: node_image_path(campaign, node_id, style, format),
        mime_type: "image/png",
        text: node |> get("excerpt") |> sanitize_text(nil) |> fallback(title),
        node_id: node_id,
        highlight_id: nil,
        recommended_platforms: key_node_platforms(format),
        style: style,
        source_type: "key_node",
        source_id: node_id,
        metadata:
          Map.merge(%{"node_class" => get(node, "class")}, key_node_format_metadata(format))
      }
    else
      _ -> nil
    end
  end

  def highlight_asset_attr(
        campaign,
        highlight,
        style \\ @default_style,
        format \\ "landscape"
      )

  def highlight_asset_attr(%Campaign{} = campaign, highlight, style, format) do
    style = normalize_style(style)
    format = normalize_quote_format(format)

    with highlight_id when not is_nil(highlight_id) <- parse_highlight_id(highlight),
         text when is_binary(text) and text != "" <- highlight_text(highlight) do
      %{
        title: "Highlighted quote",
        kind: "highlight_card",
        url: highlight_image_path(campaign, highlight_id, style, format),
        mime_type: "image/png",
        text: text,
        node_id: highlight_node_id(highlight),
        highlight_id: highlight_id,
        recommended_platforms: quote_platforms(format),
        style: style,
        source_type: "highlight",
        source_id: Integer.to_string(highlight_id),
        metadata: quote_format_metadata(format)
      }
    else
      _ -> nil
    end
  end

  def question_short_video_asset_attr(%Campaign{} = campaign, question, style)
      when is_map(question) do
    style = normalize_style(style)
    id = question |> get("id") |> string_value()
    text = question |> get("question") |> sanitize_text(nil)

    %{
      title: "Question · Short video",
      kind: "question_video",
      url: question_short_video_path(campaign, id, style),
      mime_type: "video/mp4",
      text: text,
      node_id: question |> get("node_id") |> string_value(),
      highlight_id: nil,
      recommended_platforms: ["youtube", "instagram"],
      style: style,
      source_type: "question_video",
      source_id: id,
      metadata: %{
        "format" => "short_video",
        "platform" => "shorts",
        "width" => 1080,
        "height" => 1920,
        "duration_seconds" => 6.0,
        "question_kind" => get(question, "kind")
      }
    }
  end

  def highlight_short_video_asset_attr(%Campaign{} = campaign, highlight, style) do
    style = normalize_style(style)
    highlight_id = parse_highlight_id(highlight)

    %{
      title: "Highlight · Short video",
      kind: "highlight_video",
      url: highlight_short_video_path(campaign, highlight_id, style),
      mime_type: "video/mp4",
      text: highlight_text(highlight),
      node_id: highlight_node_id(highlight),
      highlight_id: highlight_id,
      recommended_platforms: ["youtube", "instagram"],
      style: style,
      source_type: "highlight_video",
      source_id: Integer.to_string(highlight_id),
      metadata: %{
        "format" => "short_video",
        "platform" => "shorts",
        "width" => 1080,
        "height" => 1920,
        "duration_seconds" => 6.0
      }
    }
  end

  defp answer_question_map(question) do
    text = question |> get("question") |> sanitize_text(nil)
    node_id = question |> get("node_id") |> string_value()

    case question_map(text, node_id, "answer_question") do
      nil -> nil
      question_map -> Map.put(question_map, "answer_title", get(question, "answer_title"))
    end
  end

  defp question_map(text, node_id, kind) do
    text = sanitize_text(text, nil)

    if text != "" do
      %{
        "id" => question_id(text, node_id),
        "question" => text,
        "node_id" => node_id,
        "kind" => kind
      }
    end
  end

  defp quote_layout(text), do: full_quote_layout(text)

  defp full_quote_layout(text) do
    text = sanitize_text(text, nil)

    Enum.find_value(
      [72, 68, 64, 60, 56, 52, 48, 44, 40, 36, 32, 28, 24, 22, 20, 18, 16, 14, 12, 10, 8, 6],
      fn font_size ->
        lines = wrap_all_lines_by_width(text, max_line_units(font_size))
        line_gap = quote_line_gap(font_size)
        block_height = quote_block_height(lines, line_gap)

        if block_height <= @quote_area_height do
          %{
            font_size: font_size,
            line_gap: line_gap,
            start_y: quote_start_y(block_height, font_size),
            lines: lines
          }
        end
      end
    ) || fallback_full_quote_layout(text)
  end

  defp fallback_full_quote_layout(text) do
    font_size = 6
    line_gap = quote_line_gap(font_size)
    lines = wrap_all_lines_by_width(text, max_line_units(font_size))
    block_height = quote_block_height(lines, line_gap)

    %{
      font_size: font_size,
      line_gap: line_gap,
      start_y: quote_start_y(block_height, font_size),
      lines: lines
    }
  end

  defp node_card_layout(title, excerpt) do
    title_text = sanitize_text(title, nil)
    body_text = sanitize_text(excerpt, nil)
    body_present? = body_text != "" and body_text != title_text

    node_card_layout_candidates(title_text, body_text, body_present?)
    |> Enum.max_by(&node_card_layout_score/1, fn -> nil end)
    |> case do
      nil -> fallback_node_card_layout(title_text, body_text, body_present?)
      layout -> layout
    end
  end

  defp node_card_layout_candidates(title_text, body_text, body_present?) do
    for title_font <- [62, 58, 54, 50, 46, 42, 38, 34, 30, 26, 22, 18, 14, 12],
        body_font <- [26, 24, 22, 20, 18, 16, 14, 12, 10, 8],
        reduce: [] do
      acc ->
        case build_node_card_layout(title_text, body_text, body_present?, title_font, body_font) do
          nil -> acc
          layout -> [layout | acc]
        end
    end
  end

  defp build_node_card_layout(title_text, body_text, body_present?, title_font, body_font) do
    title_line_gap = round(title_font * 1.12)
    title_lines = wrap_all_lines_by_width(title_text, 910 / title_font)
    title_start_y = 200
    title_last_y = title_start_y + (length(title_lines) - 1) * title_line_gap
    body_start_y = title_last_y + round(title_font * 0.82) + 28
    body_line_gap = round(body_font * 1.42)

    body_lines =
      if body_present? do
        max_body_lines = max(div(494 - body_start_y, body_line_gap) + 1, 0)
        max_units = 910 / body_font
        all_body_lines = wrap_all_lines_by_width(body_text, max_units)
        visible_body_lines = Enum.take(all_body_lines, max_body_lines)

        maybe_mark_markdown_truncated(
          visible_body_lines,
          max_units,
          length(visible_body_lines) < length(all_body_lines)
        )
      else
        []
      end

    cond do
      title_last_y > 360 ->
        nil

      body_present? and length(body_lines) < 2 ->
        nil

      true ->
        %{
          title_font_size: title_font,
          title_line_gap: title_line_gap,
          title_start_y: title_start_y,
          title_lines: title_lines,
          body_font_size: body_font,
          body_line_gap: body_line_gap,
          body_start_y: body_start_y,
          body_lines: body_lines,
          body_present?: body_present?
        }
    end
  end

  defp node_card_layout_score(layout) do
    title_score = layout.title_font_size / 62
    body_score = if layout.body_present?, do: layout.body_font_size / 26, else: 1
    body_lines_score = if layout.body_present?, do: min(length(layout.body_lines), 8) / 8, else: 1
    title_lines_penalty = max(length(layout.title_lines) - 2, 0) * 0.08

    title_score * 0.38 + body_score * 0.2 + body_lines_score * 0.42 - title_lines_penalty
  end

  defp fallback_node_card_layout(title_text, body_text, body_present?) do
    build_node_card_layout(title_text, body_text, body_present?, 34, 18) ||
      %{
        title_font_size: 12,
        title_line_gap: 14,
        title_start_y: 200,
        title_lines: wrap_all_lines_by_width(title_text, 910 / 12),
        body_font_size: 8,
        body_line_gap: 11,
        body_start_y: 336,
        body_lines: if(body_present?, do: wrap_all_lines_by_width(body_text, 910 / 8), else: []),
        body_present?: body_present?
      }
  end

  defp grid_title_layout(text) do
    title_text = sanitize_text(text, nil)

    layout =
      bounded_text_layout(
        title_text,
        @quote_area_width,
        @quote_area_height,
        [76, 72, 68, 64, 60, 56, 52, 48, 44, 40, 36, 32, 28, 24, 20, 16, 12]
      )

    block_height = quote_block_height(layout.lines, layout.line_gap)
    Map.put(layout, :start_y, quote_start_y(block_height, layout.font_size))
  end

  defp bounded_text_layout(text, width, max_height, font_sizes) do
    Enum.find_value(font_sizes, fn font_size ->
      line_gap = round(font_size * 1.12)
      lines = wrap_all_lines_by_width(text, width / font_size)

      if quote_block_height(lines, line_gap) <= max_height do
        %{font_size: font_size, line_gap: line_gap, lines: lines}
      end
    end) ||
      then(List.last(font_sizes), fn font_size ->
        %{
          font_size: font_size,
          line_gap: round(font_size * 1.12),
          lines: wrap_all_lines_by_width(text, width / font_size)
        }
      end)
  end

  defp single_line_font_size(text, max_width, preferred_size, minimum_size) do
    fitted_size = floor(max_width / max(text_units(text), 1))
    fitted_size |> min(preferred_size) |> max(minimum_size)
  end

  defp quote_line_gap(font_size), do: round(font_size * 1.18)

  defp quote_block_height(lines, line_gap) do
    case length(lines) do
      0 -> 0
      1 -> line_gap
      count -> (count - 1) * line_gap + round(line_gap * 0.92)
    end
  end

  defp quote_start_y(block_height, font_size) do
    extra_space = max(@quote_area_height - block_height, 0)
    @quote_area_top + div(extra_space, 2) + font_size
  end

  defp max_line_units(font_size), do: @quote_area_width / font_size

  defp wrap_all_lines_by_width(text, max_units) do
    text
    |> String.split(" ", trim: true)
    |> Enum.reduce([], fn word, acc -> append_word_to_lines(acc, word, max_units) end)
  end

  defp append_word_to_lines([], word, _max_units), do: [word]

  defp append_word_to_lines(lines, word, max_units) do
    current_line = List.last(lines)
    candidate = current_line <> " " <> word

    if text_units(candidate) <= max_units do
      List.replace_at(lines, length(lines) - 1, candidate)
    else
      lines ++ [word]
    end
  end

  defp truncate_line_to_units(text, max_units) do
    trimmed = String.trim(text)

    if text_units(trimmed) <= max_units do
      trimmed
    else
      trimmed
      |> String.graphemes()
      |> Enum.reduce_while({"", 0.0}, fn grapheme, {acc, units} ->
        next_units = units + char_units(grapheme)

        if next_units + char_units("…") <= max_units do
          {:cont, {acc <> grapheme, next_units}}
        else
          {:halt, {String.trim_trailing(acc) <> "…", next_units}}
        end
      end)
      |> elem(0)
    end
  end

  defp text_units(text) do
    text
    |> String.graphemes()
    |> Enum.reduce(0.0, fn grapheme, total -> total + char_units(grapheme) end)
  end

  defp char_units(" "), do: 0.32
  defp char_units("…"), do: 0.55

  defp char_units(grapheme)
       when grapheme in ["i", "l", "I", "j", "t", "'", "\"", ".", ",", ":", ";", "!"] do
    0.28
  end

  defp char_units(grapheme) when grapheme in ["m", "w", "M", "W", "Q", "G", "@", "%", "&"] do
    0.9
  end

  defp char_units(grapheme) do
    if grapheme =~ ~r/[A-Z]/, do: 0.72, else: 0.56
  end

  defp sanitize_text(nil, _max_length), do: ""

  defp sanitize_text(text, nil) do
    text
    |> to_string()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp sanitize_text(text, max_length) when is_integer(max_length) and max_length > 0 do
    text
    |> to_string()
    |> String.slice(0, max_length * @sanitize_slice_multiplier)
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> truncate(max_length)
  end

  defp truncate(text, max_length) when is_binary(text) do
    if String.length(text) > max_length do
      text
      |> String.slice(0, max_length - 1)
      |> String.trim_trailing()
      |> Kernel.<>("…")
    else
      text
    end
  end

  defp parse_highlight_id(highlight), do: highlight |> get("id") |> integer_value()

  defp parse_integer(value) do
    case integer_value(value) do
      nil -> :error
      integer -> {:ok, integer}
    end
  end

  defp integer_value(value) when is_integer(value), do: value

  defp integer_value(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _ -> nil
    end
  end

  defp integer_value(_value), do: nil

  defp highlight_text(highlight), do: highlight |> get("text") |> sanitize_text(nil)
  defp highlight_node_id(highlight), do: highlight |> get("node_id") |> string_value()

  defp get(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) || Map.get(map, String.to_existing_atom(key))
  rescue
    ArgumentError -> Map.get(map, key)
  end

  defp maybe_add_style_query(path, style) do
    style = normalize_style(style)

    if style == @default_style do
      path
    else
      path <> "?" <> URI.encode_query(%{style: style})
    end
  end

  defp maybe_add_quote_format_query(path, format) do
    case normalize_quote_format(format) do
      "landscape" -> path
      normalized_format -> append_query(path, %{format: normalized_format})
    end
  end

  defp maybe_add_format_query(path, "landscape"), do: path

  defp maybe_add_format_query(path, format) do
    append_query(path, %{format: normalize_node_format(format)})
  end

  defp append_query(path, query) do
    separator = if String.contains?(path, "?"), do: "&", else: "?"
    path <> separator <> URI.encode_query(query)
  end

  defp normalize_node_format(format) when format in ["portrait", "linkedin"], do: format
  defp normalize_node_format(_format), do: "landscape"

  defp key_node_platforms("portrait"), do: ["instagram"]
  defp key_node_platforms("linkedin"), do: ["linkedin"]
  defp key_node_platforms(_format), do: ["x", "bluesky", "linkedin"]

  defp key_node_format_metadata("portrait") do
    %{"format" => "portrait", "platform" => "instagram", "width" => 1080, "height" => 1350}
  end

  defp key_node_format_metadata("linkedin") do
    %{"format" => "linkedin", "platform" => "linkedin", "width" => 1200, "height" => 1200}
  end

  defp key_node_format_metadata(_format) do
    %{"format" => "landscape", "platform" => "cross_platform", "width" => 1200, "height" => 630}
  end

  defp normalize_quote_format(format) when format in ["linkedin", "portrait", "short"],
    do: format

  defp normalize_quote_format(_format), do: "landscape"

  defp quote_platforms("linkedin"), do: ["linkedin"]
  defp quote_platforms("portrait"), do: ["instagram"]
  defp quote_platforms("short"), do: ["youtube", "instagram"]
  defp quote_platforms(_format), do: ["x", "bluesky", "linkedin"]

  defp quote_format_metadata("linkedin") do
    %{"format" => "linkedin", "platform" => "linkedin", "width" => 1200, "height" => 1200}
  end

  defp quote_format_metadata("portrait") do
    %{"format" => "portrait", "platform" => "instagram", "width" => 1080, "height" => 1350}
  end

  defp quote_format_metadata("short") do
    %{"format" => "short", "platform" => "shorts", "width" => 1080, "height" => 1920}
  end

  defp quote_format_metadata(_format) do
    %{"format" => "landscape", "platform" => "cross_platform", "width" => 1200, "height" => 630}
  end

  defp normalize_curated_slide(slide) when is_map(slide) do
    %{
      label: slide |> get("label") |> sanitize_text(nil) |> fallback(""),
      title: slide |> get("title") |> sanitize_text(nil) |> fallback(""),
      body: slide |> get("body") |> sanitize_text(nil)
    }
  end

  defp normalize_slide_index(slide) when is_integer(slide), do: max(slide, 1)

  defp normalize_slide_index(slide) do
    case Integer.parse(to_string(slide)) do
      {index, ""} -> max(index, 1)
      _ -> 1
    end
  end

  defp markdown_body_markup(content, title, opts) do
    content
    |> render_markdown_body(title, opts)
    |> Map.fetch!(:markup)
  end

  defp fitted_markdown_body_markup(content, title, opts, font_sizes) do
    Enum.find_value(font_sizes, fn font_size ->
      result = render_markdown_body(content, title, %{opts | font_size: font_size})
      if result.truncated?, do: nil, else: result.markup
    end) || complete_body_fallback_markup(opts)
  end

  defp render_markdown_body(content, title, opts) do
    blocks =
      case content do
        blocks when is_list(blocks) -> blocks
        markdown -> Markdown.blocks(markdown)
      end
      |> Markdown.drop_leading_title(title)

    {markup, _last_y, _rendered?, truncated?} =
      Enum.reduce_while(blocks, {[], opts.start_y, false, false}, fn block,
                                                                     {markup, last_y, rendered?,
                                                                      _truncated?} ->
        style = markdown_block_style(block, opts)
        first_y = if rendered?, do: last_y + style.line_gap + style.gap, else: opts.start_y
        max_units = (opts.width - style.indent) / style.font_size * 0.9
        lines = wrap_all_lines_by_width(block.text, max_units)
        available_lines = max(div(opts.max_y - first_y, style.line_gap) + 1, 0)

        if available_lines == 0 do
          {:halt, {markup, last_y, rendered?, true}}
        else
          visible_lines = Enum.take(lines, available_lines)
          block_truncated? = length(visible_lines) < length(lines)

          display_lines =
            maybe_mark_markdown_truncated(visible_lines, max_units, block_truncated?)

          block_markup = markdown_block_markup(block, display_lines, first_y, style, opts)
          block_last_y = first_y + max(length(display_lines) - 1, 0) * style.line_gap
          result = {markup ++ [block_markup], block_last_y, true, block_truncated?}

          if block_truncated?, do: {:halt, result}, else: {:cont, result}
        end
      end)

    %{markup: Enum.join(markup, ""), truncated?: truncated?}
  end

  defp complete_body_fallback_markup(opts) do
    block = %{
      type: :paragraph,
      text: "Explore the complete argument and supporting context on RationalGrid."
    }

    style = markdown_block_style(block, %{opts | font_size: max(opts.font_size, 24)})
    markdown_block_markup(block, [block.text], opts.start_y, style, opts)
  end

  defp markdown_block_style(%{type: :heading}, opts) do
    font_size = opts.font_size + 5

    %{
      font_size: font_size,
      line_gap: round(font_size * 1.28),
      gap: 18,
      indent: 0,
      weight: 800,
      style: "normal",
      family: @ui_font_family,
      color: opts.palette.text,
      opacity: "1"
    }
  end

  defp markdown_block_style(%{type: :blockquote}, opts) do
    %{
      font_size: opts.font_size,
      line_gap: round(opts.font_size * 1.42),
      gap: 18,
      indent: 30,
      weight: 600,
      style: "italic",
      family: @quote_font_family,
      color: opts.palette.secondary_text,
      opacity: "0.96"
    }
  end

  defp markdown_block_style(%{type: :list_item}, opts) do
    font_size = max(opts.font_size - 1, 16)

    %{
      font_size: font_size,
      line_gap: round(font_size * 1.38),
      gap: 7,
      indent: 38,
      weight: 550,
      style: "normal",
      family: @ui_font_family,
      color: opts.palette.secondary_text,
      opacity: "0.95"
    }
  end

  defp markdown_block_style(_block, opts) do
    %{
      font_size: opts.font_size,
      line_gap: round(opts.font_size * 1.42),
      gap: 14,
      indent: 0,
      weight: 500,
      style: "normal",
      family: @ui_font_family,
      color: opts.palette.secondary_text,
      opacity: "0.94"
    }
  end

  defp markdown_block_markup(block, lines, first_y, style, opts) do
    text_markup =
      lines
      |> Enum.with_index()
      |> Enum.map_join("", fn {line, index} ->
        {x, text} = markdown_line(block, line, index, opts.x, style.indent)
        text = decorate_markdown_quote(block, text, index, length(lines))
        y = first_y + index * style.line_gap

        ~s(<text x="#{x}" y="#{y}" fill="#{style.color}" font-size="#{style.font_size}" font-weight="#{style.weight}" font-style="#{style.style}" font-family="#{style.family}" opacity="#{style.opacity}">#{escape_xml(text)}</text>)
      end)

    case block do
      %{type: :blockquote} ->
        last_y = first_y + max(length(lines) - 1, 0) * style.line_gap

        ~s(<rect x="#{opts.x}" y="#{first_y - style.font_size}" width="5" height="#{last_y - first_y + style.line_gap}" rx="2.5" fill="#{opts.palette.accent_a}" opacity="0.72" />) <>
          text_markup

      _ ->
        text_markup
    end
  end

  defp markdown_line(%{type: :list_item, marker: marker}, line, 0, x, _indent),
    do: {x, "#{marker}  #{line}"}

  defp markdown_line(%{type: :list_item}, line, _index, x, indent),
    do: {x + indent, line}

  defp markdown_line(%{type: :blockquote}, line, _index, x, indent),
    do: {x + indent, line}

  defp markdown_line(_block, line, _index, x, _indent), do: {x, line}

  defp decorate_markdown_quote(%{type: :blockquote}, text, 0, 1), do: "“#{text}”"
  defp decorate_markdown_quote(%{type: :blockquote}, text, 0, _count), do: "“#{text}"

  defp decorate_markdown_quote(%{type: :blockquote}, text, index, count)
       when index == count - 1,
       do: "#{text}”"

  defp decorate_markdown_quote(_block, text, _index, _count), do: text

  defp maybe_mark_markdown_truncated([], _max_units, _truncated?), do: []
  defp maybe_mark_markdown_truncated(lines, _max_units, false), do: lines

  defp maybe_mark_markdown_truncated(lines, max_units, true) do
    List.update_at(lines, -1, fn line ->
      line
      |> String.trim_trailing("…")
      |> Kernel.<>("…")
      |> truncate_line_to_units(max_units)
    end)
  end

  defp same_markdown_title?(left, right) do
    normalize_markdown_title(left) == normalize_markdown_title(right)
  end

  defp normalize_markdown_title(title) do
    title
    |> Markdown.plain_inline()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, " ")
    |> String.trim()
  end

  defp pexels_background_markup(%Campaign{} = campaign, width, height) do
    background = get_in(campaign.raw_payload || %{}, ["share_studio", "pexels_background"])
    url = pexels_background_url(background, width, height)

    with %URI{scheme: "https", host: "images.pexels.com"} <- URI.parse(url || ""),
         {:ok, %{status: status, body: body}} when status in 200..299 and is_binary(body) <-
           Req.get(url, receive_timeout: 10_000, retry: :transient) do
      encoded = Base.encode64(body)

      """
      <image x="0" y="0" width="#{width}" height="#{height}" href="data:image/jpeg;base64,#{encoded}" preserveAspectRatio="xMidYMid slice" />
      <rect width="#{width}" height="#{height}" fill="#020617" fill-opacity="0.58" />
      """
    else
      _error -> ""
    end
  end

  defp pexels_background_url(background, width, height) when is_map(background) do
    preferred_key = if height > width, do: "portrait_url", else: "landscape_url"
    Map.get(background, preferred_key) || Map.get(background, "original_url")
  end

  defp pexels_background_url(_background, _width, _height), do: nil

  defp rasterize_svg(svg) do
    svg
    |> Image.from_svg!()
    |> Image.write!(:memory, suffix: ".png")
  end

  defp quote_palette(style) do
    colors = palette_colors(style)

    colors
    |> Map.merge(palette_effects(style))
    |> Map.put(:panel_end, panel_end_color(colors, style))
  end

  defp panel_end_color(colors, style) when style in ["minimal_light", "minimal_dark"],
    do: colors.panel

  defp panel_end_color(colors, _style), do: colors.accent_c

  defp palette_effects(style) when style in ["minimal_light", "minimal_dark"] do
    %{
      decoration_opacity: "0",
      panel_soft_opacity: "1",
      panel_accent_opacity: "0",
      glow_opacity: "0"
    }
  end

  defp palette_effects(_style) do
    %{
      decoration_opacity: "0.18",
      panel_soft_opacity: "0.07",
      panel_accent_opacity: "0.13",
      glow_opacity: "0.55"
    }
  end

  defp palette_colors("minimal_light") do
    %{
      canvas_a: "#ffffff",
      canvas_b: "#ffffff",
      canvas_c: "#ffffff",
      bloom_a: "#ffffff",
      bloom_b: "#ffffff",
      bloom_opacity: "0",
      accent_a: "#111111",
      accent_b: "#737373",
      accent_c: "#000000",
      shadow: "#000000",
      shadow_opacity: "0",
      card: "#ffffff",
      card_opacity: "1",
      panel: "#ffffff",
      panel_opacity: "1",
      border: "#000000",
      border_opacity: "0.14",
      label: "#111111",
      kicker: "#525252",
      text: "#000000",
      secondary_text: "#262626",
      muted: "#525252",
      text_stroke: "#ffffff",
      text_stroke_opacity: "0"
    }
  end

  defp palette_colors("minimal_dark") do
    %{
      canvas_a: "#000000",
      canvas_b: "#000000",
      canvas_c: "#000000",
      bloom_a: "#000000",
      bloom_b: "#000000",
      bloom_opacity: "0",
      accent_a: "#ffffff",
      accent_b: "#a3a3a3",
      accent_c: "#ffffff",
      shadow: "#000000",
      shadow_opacity: "0",
      card: "#000000",
      card_opacity: "1",
      panel: "#000000",
      panel_opacity: "1",
      border: "#ffffff",
      border_opacity: "0.2",
      label: "#ffffff",
      kicker: "#d4d4d4",
      text: "#ffffff",
      secondary_text: "#e5e5e5",
      muted: "#a3a3a3",
      text_stroke: "#000000",
      text_stroke_opacity: "0"
    }
  end

  defp palette_colors("gradient_poster") do
    %{
      canvas_a: "#2e1065",
      canvas_b: "#7e22ce",
      canvas_c: "#0f766e",
      bloom_a: "#f0abfc",
      bloom_b: "#67e8f9",
      bloom_opacity: "0.48",
      accent_a: "#f0abfc",
      accent_b: "#fde68a",
      accent_c: "#67e8f9",
      shadow: "#000000",
      shadow_opacity: "0.32",
      card: "#111827",
      card_opacity: "0.68",
      panel: "#ffffff",
      panel_opacity: "0.08",
      border: "#ffffff",
      border_opacity: "0.16",
      label: "#ffffff",
      kicker: "#f5d0fe",
      text: "#fff7ed",
      secondary_text: "#e0f2fe",
      muted: "#c4b5fd",
      text_stroke: "#111827",
      text_stroke_opacity: "0.28"
    }
  end

  defp palette_colors("minimal_academic") do
    %{
      canvas_a: "#f8fafc",
      canvas_b: "#f1f5f9",
      canvas_c: "#e2e8f0",
      bloom_a: "#cbd5e1",
      bloom_b: "#bfdbfe",
      bloom_opacity: "0.46",
      accent_a: "#334155",
      accent_b: "#64748b",
      accent_c: "#0f172a",
      shadow: "#64748b",
      shadow_opacity: "0.16",
      card: "#ffffff",
      card_opacity: "0.94",
      panel: "#f8fafc",
      panel_opacity: "0.94",
      border: "#cbd5e1",
      border_opacity: "0.88",
      label: "#334155",
      kicker: "#475569",
      text: "#0f172a",
      secondary_text: "#334155",
      muted: "#64748b",
      text_stroke: "#ffffff",
      text_stroke_opacity: "0.45"
    }
  end

  defp palette_colors("warm_paper") do
    %{
      canvas_a: "#451a03",
      canvas_b: "#78350f",
      canvas_c: "#1c1917",
      bloom_a: "#f59e0b",
      bloom_b: "#fdba74",
      bloom_opacity: "0.44",
      accent_a: "#f59e0b",
      accent_b: "#fef3c7",
      accent_c: "#fdba74",
      shadow: "#000000",
      shadow_opacity: "0.30",
      card: "#1c1917",
      card_opacity: "0.78",
      panel: "#fff7ed",
      panel_opacity: "0.09",
      border: "#fed7aa",
      border_opacity: "0.18",
      label: "#ffedd5",
      kicker: "#fed7aa",
      text: "#fff7ed",
      secondary_text: "#fed7aa",
      muted: "#fdba74",
      text_stroke: "#1c1917",
      text_stroke_opacity: "0.28"
    }
  end

  defp palette_colors("signal_red") do
    %{
      canvas_a: "#2b0709",
      canvas_b: "#7f1d1d",
      canvas_c: "#111827",
      bloom_a: "#fb7185",
      bloom_b: "#f59e0b",
      bloom_opacity: "0.46",
      accent_a: "#fb7185",
      accent_b: "#facc15",
      accent_c: "#f97316",
      shadow: "#190204",
      shadow_opacity: "0.38",
      card: "#180a0b",
      card_opacity: "0.82",
      panel: "#fff1f2",
      panel_opacity: "0.08",
      border: "#fecdd3",
      border_opacity: "0.2",
      label: "#ffe4e6",
      kicker: "#fda4af",
      text: "#fff7ed",
      secondary_text: "#fecaca",
      muted: "#fda4af",
      text_stroke: "#3f0b0b",
      text_stroke_opacity: "0.3"
    }
  end

  defp palette_colors("deep_ocean") do
    %{
      canvas_a: "#082f49",
      canvas_b: "#0f172a",
      canvas_c: "#164e63",
      bloom_a: "#38bdf8",
      bloom_b: "#2dd4bf",
      bloom_opacity: "0.42",
      accent_a: "#67e8f9",
      accent_b: "#bef264",
      accent_c: "#22d3ee",
      shadow: "#020617",
      shadow_opacity: "0.4",
      card: "#06111f",
      card_opacity: "0.84",
      panel: "#ecfeff",
      panel_opacity: "0.07",
      border: "#a5f3fc",
      border_opacity: "0.18",
      label: "#cffafe",
      kicker: "#99f6e4",
      text: "#ecfeff",
      secondary_text: "#bae6fd",
      muted: "#67e8f9",
      text_stroke: "#082f49",
      text_stroke_opacity: "0.3"
    }
  end

  defp palette_colors("newsprint") do
    %{
      canvas_a: "#f5f0e6",
      canvas_b: "#e7dfd0",
      canvas_c: "#d6c8b6",
      bloom_a: "#fecaca",
      bloom_b: "#bfdbfe",
      bloom_opacity: "0.38",
      accent_a: "#991b1b",
      accent_b: "#44403c",
      accent_c: "#1d4ed8",
      shadow: "#57534e",
      shadow_opacity: "0.2",
      card: "#faf7f0",
      card_opacity: "0.94",
      panel: "#fffdf8",
      panel_opacity: "0.84",
      border: "#a8a29e",
      border_opacity: "0.62",
      label: "#292524",
      kicker: "#991b1b",
      text: "#1c1917",
      secondary_text: "#44403c",
      muted: "#78716c",
      text_stroke: "#fffdf8",
      text_stroke_opacity: "0.5"
    }
  end

  defp palette_colors(_style) do
    %{
      canvas_a: "#111827",
      canvas_b: "#1e1b4b",
      canvas_c: "#0f172a",
      bloom_a: "#fb7185",
      bloom_b: "#22d3ee",
      bloom_opacity: "0.40",
      accent_a: "#fb7185",
      accent_b: "#fef3c7",
      accent_c: "#22d3ee",
      shadow: "#000000",
      shadow_opacity: "0.36",
      card: "#020617",
      card_opacity: "0.78",
      panel: "#ffffff",
      panel_opacity: "0.07",
      border: "#ffffff",
      border_opacity: "0.13",
      label: "#f8fafc",
      kicker: "#fecdd3",
      text: "#fff7ed",
      secondary_text: "#cbd5e1",
      muted: "#94a3b8",
      text_stroke: "#020617",
      text_stroke_opacity: "0.24"
    }
  end

  defp fallback(nil, fallback), do: fallback
  defp fallback("", fallback), do: fallback
  defp fallback(value, _fallback), do: value

  defp string_value(nil), do: nil
  defp string_value(value) when is_binary(value), do: value
  defp string_value(value), do: to_string(value)

  defp escape_xml(text) do
    text
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end
end
