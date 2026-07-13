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
  alias GridMediaManager.RationalGrid.MediaPayload

  @image_width 1200
  @image_height 630
  @portrait_width 1080
  @portrait_height 1350
  @square_size 1200
  @short_width 1080
  @short_height 1920
  @max_quote_lines 6
  @quote_area_left 112
  @quote_area_top 146
  @quote_area_width 920
  @quote_area_height 350
  @max_svg_quote_chars 800
  @max_svg_title_chars 220
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
      mime_type: "image/svg+xml",
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
    "/campaigns/#{id}/share-card.svg"
    |> maybe_add_style_query(style)
  end

  def highlight_image_path(campaign, highlight_id, style \\ @default_style),
    do: highlight_image_path(campaign, highlight_id, style, "landscape")

  def highlight_image_path(%Campaign{id: id}, highlight_id, style, format) do
    "/campaigns/#{id}/highlights/#{highlight_id}/share-card.svg"
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

    "/campaigns/#{id}/nodes/#{encoded_node_id}/share-card.svg"
    |> maybe_add_style_query(style)
    |> maybe_add_format_query(format)
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
    "/campaigns/#{id}/questions/#{URI.encode(to_string(question_id), &URI.char_unreserved?/1)}/share-card.svg"
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
    title = sanitize_text(campaign.title, @max_svg_title_chars)
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
      <rect width="1200" height="630" fill="url(#violetHalo)" />
      <rect width="1200" height="630" fill="url(#blueHalo)" />
      <circle cx="1040" cy="126" r="132" fill="#{palette.bloom_b}" fill-opacity="#{palette.decoration_opacity}" />
      <circle cx="160" cy="538" r="118" fill="#{palette.bloom_a}" fill-opacity="#{palette.decoration_opacity}" />

      <rect x="52" y="44" width="1096" height="542" rx="44" fill="#{palette.card}" fill-opacity="#{palette.card_opacity}" filter="url(#cardShadow)" />
      <rect x="52.5" y="44.5" width="1095" height="541" rx="43.5" fill="none" stroke="#{palette.border}" stroke-opacity="#{palette.border_opacity}" />
      <rect x="52" y="44" width="1096" height="542" rx="44" fill="#{palette.panel}" fill-opacity="#{palette.panel_opacity}" />

      <text x="1092" y="98" text-anchor="end" fill="#{palette.label}" fill-opacity="0.86" font-size="17" font-weight="700" font-family="#{@ui_font_family}" letter-spacing="0.15">RationalGrid.ai</text>
      <line x1="96" y1="134" x2="1104" y2="134" stroke="#{palette.border}" stroke-width="1" stroke-opacity="#{palette.border_opacity}" />
      <rect x="96" y="478" width="230" height="6" rx="3" fill="url(#accent)" opacity="0.92" />
      <text x="96" y="510" fill="#{palette.muted}" font-size="17" font-weight="700" font-family="#{@ui_font_family}" letter-spacing="0.35">#{escape_xml(label)}</text>
      <text fill="#{palette.text}" font-size="#{title_layout.font_size}" font-weight="800" font-family="#{@ui_font_family}" letter-spacing="-0.55" paint-order="stroke" stroke="#{palette.text_stroke}" stroke-width="2" stroke-opacity="#{palette.text_stroke_opacity}">
        #{title_markup}
      </text>
    </svg>
    """
  end

  def node_image_svg(campaign, node, style \\ @default_style)

  def node_image_svg(%Campaign{} = campaign, node, style) when is_map(node) do
    style = normalize_style(style)
    palette = quote_palette(style)
    node_title = node |> get("title") |> sanitize_text(260) |> fallback("Key node")

    node_excerpt =
      node
      |> get("excerpt")
      |> fallback(get(node, "content"))
      |> sanitize_text(920)

    node_class =
      node |> get("class") |> sanitize_text(48) |> fallback("node") |> String.replace("_", " ")

    layout = node_card_layout(node_title, node_excerpt)

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
      <rect width="1200" height="630" fill="url(#nodeViolet)" />
      <rect width="1200" height="630" fill="url(#nodeSky)" />
      <path d="M-44 470 C186 382 364 598 602 474 C790 376 966 408 1252 250" fill="none" stroke="#{palette.accent_a}" stroke-opacity="#{palette.decoration_opacity}" stroke-width="2" />
      <path d="M-22 166 C198 246 318 38 552 150 C802 270 942 92 1224 122" fill="none" stroke="#{palette.accent_c}" stroke-opacity="#{palette.decoration_opacity}" stroke-width="2" />

      <rect x="48" y="42" width="1104" height="546" rx="42" fill="#{palette.card}" fill-opacity="#{palette.card_opacity}" filter="url(#nodeShadow)" />
      <rect x="48.5" y="42.5" width="1103" height="545" rx="41.5" fill="none" stroke="#{palette.border}" stroke-opacity="#{palette.border_opacity}" />
      <rect x="76" y="70" width="1048" height="490" rx="30" fill="#{palette.panel}" fill-opacity="#{palette.panel_opacity}" stroke="#{palette.border}" stroke-opacity="#{palette.border_opacity}" />

      <text x="112" y="118" fill="#{palette.label}" font-size="17" font-weight="800" font-family="#{@ui_font_family}" letter-spacing="0.35">RationalGrid.ai</text>
      <text x="1088" y="118" text-anchor="end" fill="#{palette.kicker}" font-size="15" font-weight="800" font-family="#{@ui_font_family}" letter-spacing="1.2" text-transform="uppercase">#{escape_xml(node_class)}</text>
      <line x1="112" y1="144" x2="1088" y2="144" stroke="#{palette.border}" stroke-width="1" stroke-opacity="#{palette.border_opacity}" />
      <rect x="112" y="516" width="344" height="6" rx="3" fill="url(#nodeAccent)" opacity="0.96" />

      <text fill="#{palette.text}" font-size="#{layout.title_font_size}" font-weight="800" font-family="#{@ui_font_family}" letter-spacing="-0.5" paint-order="stroke" stroke="#{palette.text_stroke}" stroke-width="2.2" stroke-opacity="#{palette.text_stroke_opacity}">
        #{title_markup}
      </text>
      <text fill="#{palette.secondary_text}" font-size="#{layout.body_font_size}" font-weight="500" font-family="#{@ui_font_family}" letter-spacing="0" opacity="0.92">
        #{excerpt_markup}
      </text>
      <text x="112" y="548" fill="#{palette.muted}" font-size="16" font-weight="700" font-family="#{@ui_font_family}" letter-spacing="0.2">Key node from #{escape_xml(sanitize_text(campaign.title, 110))}</text>
    </svg>
    """
  end

  def node_linkedin_image_svg(campaign, node, style \\ @default_style)

  def node_linkedin_image_svg(%Campaign{} = campaign, node, style) when is_map(node) do
    style = normalize_style(style)
    palette = quote_palette(style)
    node_title = node |> get("title") |> sanitize_text(320) |> fallback("Key node")

    node_content =
      node
      |> get("content")
      |> fallback(get(node, "excerpt"))
      |> fallback("")
      |> strip_node_markdown()
      |> sanitize_text(2_400)
      |> strip_leading_title(node_title)

    node_class =
      node |> get("class") |> sanitize_text(48) |> fallback("node") |> String.replace("_", " ")

    title_font_size = 62
    title_line_gap = 68
    title_lines = wrap_lines_by_width(node_title, 950 / title_font_size, 3)
    title_start_y = 242
    title_last_y = title_start_y + (length(title_lines) - 1) * title_line_gap
    body_font_size = 30
    body_line_gap = 43
    body_start_y = title_last_y + 106
    body_max_lines = max(div(1_045 - body_start_y, body_line_gap) + 1, 5) |> min(15)
    body_lines = wrap_lines_by_width(node_content, 950 / body_font_size, body_max_lines)

    title_markup =
      title_lines
      |> Enum.with_index()
      |> Enum.map_join("", fn {line, index} ->
        ~s(<tspan x="124" y="#{title_start_y + index * title_line_gap}">#{escape_xml(line)}</tspan>)
      end)

    body_markup =
      body_lines
      |> Enum.with_index()
      |> Enum.map_join("", fn {line, index} ->
        ~s(<tspan x="124" y="#{body_start_y + index * body_line_gap}">#{escape_xml(line)}</tspan>)
      end)

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
      <rect width="1200" height="1200" fill="url(#linkedinBloomA)" />
      <rect width="1200" height="1200" fill="url(#linkedinBloomB)" />
      <path d="M-60 970 C240 820 430 1110 760 910 C920 812 1040 790 1270 650" fill="none" stroke="#{palette.accent_b}" stroke-opacity="#{palette.decoration_opacity}" stroke-width="3" />

      <rect x="48" y="48" width="1104" height="1104" rx="44" fill="#{palette.card}" fill-opacity="#{palette.card_opacity}" filter="url(#linkedinShadow)" />
      <rect x="48.5" y="48.5" width="1103" height="1103" rx="43.5" fill="none" stroke="#{palette.border}" stroke-opacity="#{palette.border_opacity}" />
      <rect x="76" y="76" width="1048" height="1048" rx="32" fill="#{palette.panel}" fill-opacity="#{palette.panel_opacity}" stroke="#{palette.border}" stroke-opacity="#{palette.border_opacity}" />

      <text x="124" y="140" fill="#{palette.label}" font-size="20" font-weight="800" font-family="#{@ui_font_family}">RationalGrid.ai</text>
      <text x="1076" y="140" text-anchor="end" fill="#{palette.kicker}" font-size="17" font-weight="800" font-family="#{@ui_font_family}" letter-spacing="1.4">LINKEDIN · #{escape_xml(node_class)}</text>
      <line x1="124" y1="176" x2="1076" y2="176" stroke="#{palette.border}" stroke-width="1" stroke-opacity="#{palette.border_opacity}" />

      <text fill="#{palette.text}" font-size="#{title_font_size}" font-weight="800" font-family="#{@ui_font_family}" letter-spacing="-0.7" paint-order="stroke" stroke="#{palette.text_stroke}" stroke-width="2.2" stroke-opacity="#{palette.text_stroke_opacity}">
        #{title_markup}
      </text>
      <rect x="124" y="#{body_start_y - 58}" width="240" height="7" rx="3.5" fill="url(#linkedinAccent)" opacity="0.96" />
      <text fill="#{palette.secondary_text}" font-size="#{body_font_size}" font-weight="500" font-family="#{@ui_font_family}" opacity="0.94">
        #{body_markup}
      </text>

      <line x1="124" y1="1070" x2="1076" y2="1070" stroke="#{palette.border}" stroke-width="1" stroke-opacity="#{palette.border_opacity}" />
      <text x="124" y="1108" fill="#{palette.muted}" font-size="18" font-weight="700" font-family="#{@ui_font_family}">A key idea from #{escape_xml(sanitize_text(campaign.title, 92))}</text>
    </svg>
    """
  end

  def node_reading_image_svg(campaign, node, style \\ @default_style)

  def node_reading_image_svg(%Campaign{} = campaign, node, style) when is_map(node) do
    style = normalize_style(style)
    palette = quote_palette(style)
    node_title = node |> get("title") |> sanitize_text(320) |> fallback("Key node")

    node_content =
      node
      |> get("content")
      |> fallback(get(node, "excerpt"))
      |> fallback("")
      |> strip_node_markdown()
      |> sanitize_text(1500)
      |> strip_leading_title(node_title)

    node_class =
      node |> get("class") |> sanitize_text(48) |> fallback("node") |> String.replace("_", " ")

    title_font_size = 58
    title_line_gap = 66
    title_lines = wrap_lines_by_width(node_title, 820 / title_font_size, 4)
    title_start_y = 232
    body_font_size = 29
    body_line_gap = 42
    body_start_y = title_start_y + (length(title_lines) - 1) * title_line_gap + 92
    body_max_lines = max(min(div(1160 - body_start_y, body_line_gap), 18), 4)
    body_lines = wrap_lines_by_width(node_content, 820 / body_font_size, body_max_lines)

    title_markup =
      title_lines
      |> Enum.with_index()
      |> Enum.map_join("", fn {line, index} ->
        y = title_start_y + index * title_line_gap
        ~s(<tspan x="130" y="#{y}">#{escape_xml(line)}</tspan>)
      end)

    body_markup =
      body_lines
      |> Enum.with_index()
      |> Enum.map_join("", fn {line, index} ->
        y = body_start_y + index * body_line_gap
        ~s(<tspan x="130" y="#{y}">#{escape_xml(line)}</tspan>)
      end)

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
      <rect width="1080" height="1350" fill="url(#portraitBloomA)" />
      <rect width="1080" height="1350" fill="url(#portraitBloomB)" />
      <path d="M-80 1040 C220 890 420 1200 730 1010 C870 924 986 878 1160 760" fill="none" stroke="#{palette.accent_b}" stroke-opacity="#{palette.decoration_opacity}" stroke-width="3" />

      <rect x="54" y="54" width="972" height="1242" rx="44" fill="#{palette.card}" fill-opacity="#{palette.card_opacity}" filter="url(#portraitShadow)" />
      <rect x="54.5" y="54.5" width="971" height="1241" rx="43.5" fill="none" stroke="#{palette.border}" stroke-opacity="#{palette.border_opacity}" />
      <rect x="82" y="82" width="916" height="1186" rx="32" fill="#{palette.panel}" fill-opacity="#{palette.panel_opacity}" stroke="#{palette.border}" stroke-opacity="#{palette.border_opacity}" />

      <text x="130" y="142" fill="#{palette.label}" fill-opacity="0.92" font-size="20" font-weight="800" font-family="#{@ui_font_family}" letter-spacing="0.4">RationalGrid.ai</text>
      <text x="950" y="142" text-anchor="end" fill="#{palette.kicker}" font-size="17" font-weight="800" font-family="#{@ui_font_family}" letter-spacing="1.4" text-transform="uppercase">#{escape_xml(node_class)}</text>
      <line x1="130" y1="176" x2="950" y2="176" stroke="#{palette.border}" stroke-width="1" stroke-opacity="#{palette.border_opacity}" />

      <text fill="#{palette.text}" font-size="#{title_font_size}" font-weight="800" font-family="#{@ui_font_family}" letter-spacing="-0.7" paint-order="stroke" stroke="#{palette.text_stroke}" stroke-width="2.2" stroke-opacity="#{palette.text_stroke_opacity}">
        #{title_markup}
      </text>
      <rect x="130" y="#{body_start_y - 54}" width="210" height="7" rx="3.5" fill="url(#portraitAccent)" opacity="0.96" />
      <text fill="#{palette.secondary_text}" font-size="#{body_font_size}" font-weight="500" font-family="#{@ui_font_family}" letter-spacing="0" opacity="0.94">
        #{body_markup}
      </text>

      <line x1="130" y1="1210" x2="950" y2="1210" stroke="#{palette.border}" stroke-width="1" stroke-opacity="#{palette.border_opacity}" />
      <text x="130" y="1248" fill="#{palette.muted}" font-size="18" font-weight="700" font-family="#{@ui_font_family}" letter-spacing="0.2">Explore the full argument on RationalGrid</text>
    </svg>
    """
  end

  def carousel_slides(%Campaign{} = campaign, node) when is_map(node) do
    node_title = node |> get("title") |> sanitize_text(320) |> fallback("Key node")

    content =
      node
      |> get("content")
      |> fallback(get(node, "excerpt"))
      |> fallback("")
      |> to_string()

    sections =
      Regex.split(~r/(?m)^##+\s+/, content, trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(fn section ->
        case String.split(section, "\n", parts: 2) do
          [heading, body] -> %{title: String.trim(heading), body: String.trim(body)}
          [body] -> %{title: "The argument", body: body}
        end
      end)

    body_sections =
      sections
      |> Enum.map(fn section ->
        %{
          section
          | body: section.body |> strip_node_markdown() |> strip_leading_title(node_title)
        }
      end)
      |> Enum.reject(&(&1.body == ""))

    content_slides =
      body_sections
      |> Enum.take(3)
      |> Enum.map(fn section ->
        %{label: "Argument", title: section.title, body: section.body}
      end)

    question =
      campaign.raw_payload
      |> MediaPayload.follow_up_questions()
      |> List.first()
      |> fallback("What does this node make you question?")

    slides =
      [
        %{
          label: "Thesis",
          title: node_title,
          body: "A key move in the argument mapped by RationalGrid."
        }
      ] ++
        content_slides ++
        [%{label: "Question", title: "Where do you stand?", body: question}]

    Enum.take(slides, 5)
  end

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
    slide = Enum.at(slides, slide_index - 1) || List.first(slides)
    palette = quote_palette(style)
    body_lines = wrap_lines_by_width(slide.body, 820 / 31, 15)
    body_start_y = 480
    title_image_data_uri = carousel_title_image_data_uri(slide.title, palette.text)

    body_markup =
      body_lines
      |> Enum.with_index()
      |> Enum.map_join("", fn {line, index} ->
        ~s(<tspan x="130" y="#{body_start_y + index * 45}">#{escape_xml(line)}</tspan>)
      end)

    """
    <svg xmlns="http://www.w3.org/2000/svg" width="#{@portrait_width}" height="#{@portrait_height}" viewBox="0 0 #{@portrait_width} #{@portrait_height}" role="img" aria-labelledby="title desc">
      <title id="title">#{escape_xml(slide.title)} · #{escape_xml(campaign.title)} · RationalGrid</title>
      <desc id="desc">Carousel slide #{slide_index} from #{escape_xml(node |> get("title") |> sanitize_text(180))} on RationalGrid</desc>
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
      <rect width="1080" height="1350" fill="url(#carouselBloomA)" />
      <rect width="1080" height="1350" fill="url(#carouselBloomB)" />
      <rect x="54" y="54" width="972" height="1242" rx="44" fill="#{palette.card}" fill-opacity="#{palette.card_opacity}" filter="url(#carouselShadow)" />
      <rect x="54.5" y="54.5" width="971" height="1241" rx="43.5" fill="none" stroke="#{palette.border}" stroke-opacity="#{palette.border_opacity}" />
      <rect x="82" y="82" width="916" height="1186" rx="32" fill="#{palette.panel}" fill-opacity="#{palette.panel_opacity}" stroke="#{palette.border}" stroke-opacity="#{palette.border_opacity}" />

      <text x="130" y="142" fill="#{palette.label}" fill-opacity="0.92" font-size="20" font-weight="800" font-family="#{@ui_font_family}" letter-spacing="0.4">RationalGrid.ai</text>
      <text x="950" y="142" text-anchor="end" fill="#{palette.kicker}" font-size="17" font-weight="800" font-family="#{@ui_font_family}" letter-spacing="1.4" text-transform="uppercase">#{escape_xml(slide.label)}</text>
      <line x1="130" y1="176" x2="950" y2="176" stroke="#{palette.border}" stroke-width="1" stroke-opacity="#{palette.border_opacity}" />
      <image x="130" y="205" width="820" height="190" href="#{title_image_data_uri}" preserveAspectRatio="none" />
      <rect x="130" y="430" width="210" height="7" rx="3.5" fill="url(#carouselAccent)" opacity="0.96" />
      <text fill="#{palette.secondary_text}" font-size="31" font-weight="500" font-family="#{@ui_font_family}" letter-spacing="0" opacity="0.94">
        #{body_markup}
      </text>
      <line x1="130" y1="1210" x2="950" y2="1210" stroke="#{palette.border}" stroke-width="1" stroke-opacity="#{palette.border_opacity}" />
      <text x="130" y="1248" fill="#{palette.muted}" font-size="18" font-weight="700" font-family="#{@ui_font_family}">#{slide_index} / #{length(slides)} · #{escape_xml(sanitize_text(campaign.title, 76))}</text>
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
    slides = carousel_slides(campaign, node)
    slide = Enum.at(slides, slide_index - 1) || List.first(slides)
    palette = quote_palette(style)
    cover? = slide_index == 1
    title_font_size = if cover?, do: 90, else: 74
    title_line_gap = round(title_font_size * 1.08)
    title_lines = wrap_lines_by_width(slide.title, 820 / title_font_size, 5)
    title_start_y = 410
    title_last_y = title_start_y + (length(title_lines) - 1) * title_line_gap
    body_start_y = max(title_last_y + 128, 790)
    body_font_size = if cover?, do: 44, else: 40
    body_line_gap = round(body_font_size * 1.42)
    body_max_lines = max(div(1_650 - body_start_y, body_line_gap) + 1, 5) |> min(14)
    body_lines = wrap_lines_by_width(slide.body, 820 / body_font_size, body_max_lines)

    title_markup =
      title_lines
      |> Enum.with_index()
      |> Enum.map_join("", fn {line, index} ->
        ~s(<tspan x="130" y="#{title_start_y + index * title_line_gap}">#{escape_xml(line)}</tspan>)
      end)

    body_markup =
      body_lines
      |> Enum.with_index()
      |> Enum.map_join("", fn {line, index} ->
        ~s(<tspan x="130" y="#{body_start_y + index * body_line_gap}">#{escape_xml(line)}</tspan>)
      end)

    """
    <svg xmlns="http://www.w3.org/2000/svg" width="#{@short_width}" height="#{@short_height}" viewBox="0 0 #{@short_width} #{@short_height}" role="img" aria-labelledby="title desc">
      <title id="title">#{escape_xml(slide.title)} · #{escape_xml(campaign.title)} · RationalGrid Short</title>
      <desc id="desc">Vertical short-video frame #{slide_index} of #{length(slides)}</desc>
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
      <rect width="1080" height="1920" fill="url(#shortBloomA)" />
      <rect width="1080" height="1920" fill="url(#shortBloomB)" />
      <circle cx="950" cy="230" r="220" fill="#{palette.bloom_b}" fill-opacity="#{palette.decoration_opacity}" />
      <circle cx="120" cy="1690" r="240" fill="#{palette.bloom_a}" fill-opacity="#{palette.decoration_opacity}" />

      <rect x="54" y="64" width="972" height="1792" rx="48" fill="#{palette.card}" fill-opacity="#{palette.card_opacity}" filter="url(#shortShadow)" />
      <rect x="54.5" y="64.5" width="971" height="1791" rx="47.5" fill="none" stroke="#{palette.border}" stroke-opacity="#{palette.border_opacity}" />
      <rect x="82" y="92" width="916" height="1736" rx="34" fill="#{palette.panel}" fill-opacity="#{palette.panel_opacity}" stroke="#{palette.border}" stroke-opacity="#{palette.border_opacity}" />

      <text x="130" y="170" fill="#{palette.label}" font-size="23" font-weight="800" font-family="#{@ui_font_family}">RationalGrid.ai</text>
      <text x="950" y="170" text-anchor="end" fill="#{palette.kicker}" font-size="18" font-weight="800" font-family="#{@ui_font_family}" letter-spacing="1.7">SHORT · #{slide_index}/#{length(slides)}</text>
      <line x1="130" y1="210" x2="950" y2="210" stroke="#{palette.border}" stroke-width="1" stroke-opacity="#{palette.border_opacity}" />
      <text x="130" y="302" fill="#{palette.kicker}" font-size="22" font-weight="800" font-family="#{@ui_font_family}" letter-spacing="2.4">#{escape_xml(String.upcase(slide.label))}</text>

      <text fill="#{palette.text}" font-size="#{title_font_size}" font-weight="900" font-family="#{@ui_font_family}" letter-spacing="-1.2" paint-order="stroke" stroke="#{palette.text_stroke}" stroke-width="2.4" stroke-opacity="#{palette.text_stroke_opacity}">
        #{title_markup}
      </text>
      <rect x="130" y="#{body_start_y - 72}" width="260" height="9" rx="4.5" fill="url(#shortAccent)" opacity="0.98" />
      <text fill="#{palette.secondary_text}" font-size="#{body_font_size}" font-weight="550" font-family="#{@ui_font_family}" opacity="0.96">
        #{body_markup}
      </text>

      <line x1="130" y1="1738" x2="950" y2="1738" stroke="#{palette.border}" stroke-width="1" stroke-opacity="#{palette.border_opacity}" />
      <text x="130" y="1790" fill="#{palette.muted}" font-size="22" font-weight="700" font-family="#{@ui_font_family}">Explore the full conversation on RationalGrid</text>
    </svg>
    """
  end

  def node_short_video_frame_png(campaign, node, style, slide) when is_map(node) do
    campaign
    |> node_short_video_frame_svg(node, style, slide)
    |> Image.from_svg!()
    |> Image.write!(:memory, suffix: ".png")
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

    question_type =
      question
      |> get("kind")
      |> sanitize_text(48)
      |> fallback("question")
      |> String.replace("_", " ")

    layout = full_quote_layout(question_text)

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
      <rect width="1200" height="630" fill="url(#questionRose)" />
      <rect width="1200" height="630" fill="url(#questionCyan)" />
      <path d="M-40 488 C212 390 356 622 604 496 C820 386 948 434 1240 284" fill="none" stroke="#{palette.accent_a}" stroke-opacity="#{palette.decoration_opacity}" stroke-width="2" />
      <path d="M-30 158 C186 250 312 24 548 142 C806 270 944 76 1232 118" fill="none" stroke="#{palette.accent_c}" stroke-opacity="#{palette.decoration_opacity}" stroke-width="2" />

      <rect x="38" y="34" width="1124" height="562" rx="40" fill="#{palette.card}" fill-opacity="#{palette.card_opacity}" filter="url(#questionShadow)" />
      <rect x="38.5" y="34.5" width="1123" height="561" rx="39.5" fill="none" stroke="#{palette.border}" stroke-opacity="#{palette.border_opacity}" />
      <rect x="58" y="54" width="1084" height="522" rx="30" fill="#{palette.panel}" fill-opacity="#{palette.panel_opacity}" stroke="#{palette.border}" stroke-opacity="#{palette.border_opacity}" />

      <text x="86" y="98" fill="#{palette.label}" fill-opacity="0.9" font-size="17" font-weight="800" font-family="#{@ui_font_family}" letter-spacing="0">RationalGrid.ai</text>
      <text x="1114" y="98" text-anchor="end" fill="#{palette.kicker}" font-size="15" font-weight="800" font-family="#{@ui_font_family}" letter-spacing="1.2" text-transform="uppercase">#{escape_xml(question_type)}</text>
      <rect x="86" y="126" width="1028" height="1" fill="#{palette.border}" fill-opacity="#{palette.border_opacity}" />
      <rect x="86" y="514" width="344" height="6" rx="3" fill="url(#questionAccent)" opacity="0.96" />

      <text x="58" y="286" fill="#{palette.accent_a}" fill-opacity="0.10" font-size="198" font-weight="700" font-family="#{@quote_font_family}">“</text>
      <text x="1142" y="500" text-anchor="end" fill="#{palette.accent_c}" fill-opacity="0.08" font-size="154" font-weight="700" font-family="#{@quote_font_family}">”</text>
      <text fill="#{palette.text}" font-size="#{layout.font_size}" font-weight="700" font-family="#{@quote_font_family}" letter-spacing="0" paint-order="stroke" stroke="#{palette.text_stroke}" stroke-width="2.2" stroke-opacity="#{palette.text_stroke_opacity}">
        #{quote_markup}
      </text>

      <text x="86" y="552" fill="#{palette.label}" fill-opacity="0.9" font-size="22" font-weight="800" font-family="#{@ui_font_family}" letter-spacing="0">#{escape_xml(sanitize_text(campaign.title, 140))}</text>
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
      |> sanitize_text(@max_svg_quote_chars)

    quote_layout = quote_layout(quote_text)

    source_label =
      campaign
      |> node_title(highlight_node_id(highlight))
      |> sanitize_text(140)
      |> truncate_line_to_units(900 / 24)

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

      <text x="86" y="552" fill="#{palette.label}" fill-opacity="0.9" font-size="24" font-weight="800" font-family="#{@ui_font_family}" letter-spacing="0">#{escape_xml(source_label)}</text>
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
      text = highlight |> highlight_text() |> sanitize_text(@max_svg_quote_chars)
      source = campaign |> node_title(highlight_node_id(highlight)) |> sanitize_text(140)
      platform_quote_image_svg(campaign, text, source, "highlight", style, format)
    end
  end

  def question_platform_image_png(campaign, question, style, format) do
    campaign
    |> question_platform_image_svg(question, style, format)
    |> Image.from_svg!()
    |> Image.write!(:memory, suffix: ".png")
  end

  def highlight_platform_image_png(campaign, highlight, style, format) do
    campaign
    |> highlight_platform_image_svg(highlight, style, format)
    |> Image.from_svg!()
    |> Image.write!(:memory, suffix: ".png")
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
      <rect width="#{spec.width}" height="#{spec.height}" fill="url(#platformBloomA)" />
      <rect width="#{spec.width}" height="#{spec.height}" fill="url(#platformBloomB)" />
      <circle cx="#{spec.width - 120}" cy="170" r="190" fill="#{palette.bloom_b}" fill-opacity="#{palette.decoration_opacity}" />
      <circle cx="110" cy="#{spec.height - 170}" r="210" fill="#{palette.bloom_a}" fill-opacity="#{palette.decoration_opacity}" />

      <rect x="54" y="54" width="#{spec.width - 108}" height="#{spec.height - 108}" rx="46" fill="#{palette.card}" fill-opacity="#{palette.card_opacity}" filter="url(#platformShadow)" />
      <rect x="54.5" y="54.5" width="#{spec.width - 109}" height="#{spec.height - 109}" rx="45.5" fill="none" stroke="#{palette.border}" stroke-opacity="#{palette.border_opacity}" />
      <rect x="82" y="82" width="#{spec.width - 164}" height="#{spec.height - 164}" rx="34" fill="#{palette.panel}" fill-opacity="#{palette.panel_opacity}" stroke="#{palette.border}" stroke-opacity="#{palette.border_opacity}" />

      <text x="#{spec.text_x}" y="#{spec.brand_y}" fill="#{palette.label}" font-size="#{spec.brand_size}" font-weight="800" font-family="#{@ui_font_family}">RationalGrid.ai</text>
      <text x="#{spec.text_right}" y="#{spec.brand_y}" text-anchor="end" fill="#{palette.kicker}" font-size="#{spec.kicker_size}" font-weight="800" font-family="#{@ui_font_family}" letter-spacing="1.6">#{escape_xml(String.upcase(platform_label))} · #{escape_xml(String.upcase(String.replace(kind, "_", " ")))}</text>
      <line x1="#{spec.text_x}" y1="#{spec.rule_y}" x2="#{spec.text_right}" y2="#{spec.rule_y}" stroke="#{palette.border}" stroke-width="1" stroke-opacity="#{palette.border_opacity}" />

      <text x="#{spec.text_x - 48}" y="#{spec.quote_top + 52}" fill="#{palette.accent_a}" fill-opacity="0.10" font-size="#{spec.quote_mark_size}" font-weight="700" font-family="#{@quote_font_family}">“</text>
      <text x="#{spec.text_right + 34}" y="#{spec.quote_bottom}" text-anchor="end" fill="#{palette.accent_c}" fill-opacity="0.08" font-size="#{round(spec.quote_mark_size * 0.78)}" font-weight="700" font-family="#{@quote_font_family}">”</text>
      <text fill="#{palette.text}" font-size="#{layout.font_size}" font-weight="700" font-family="#{@quote_font_family}" paint-order="stroke" stroke="#{palette.text_stroke}" stroke-width="2.2" stroke-opacity="#{palette.text_stroke_opacity}">
        #{quote_markup}
      </text>

      <rect x="#{spec.text_x}" y="#{spec.accent_y}" width="#{spec.accent_width}" height="8" rx="4" fill="url(#platformAccent)" opacity="0.96" />
      <text x="#{spec.text_x}" y="#{spec.footer_y}" fill="#{palette.label}" font-size="#{spec.footer_size}" font-weight="800" font-family="#{@ui_font_family}">#{escape_xml(sanitize_text(source, spec.source_limit))}</text>
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
          wrap_lines_by_width(
            text,
            spec.text_width / List.last(spec.font_sizes) * spec.wrap_factor,
            spec.max_lines
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
      font_sizes: [78, 74, 70, 66, 62, 58, 54, 50, 46, 42, 38, 34, 30, 26],
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
      font_sizes: [80, 76, 72, 68, 64, 60, 56, 52, 48, 44, 40, 36, 32, 28, 24],
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
      font_sizes: [104, 98, 92, 86, 80, 74, 68, 62, 56, 50, 44, 38, 34, 30],
      max_lines: 14,
      wrap_factor: 0.85
    }
  end

  defp platform_quote_label("linkedin"), do: "LinkedIn"
  defp platform_quote_label("portrait"), do: "Instagram"
  defp platform_quote_label("short"), do: "Short"

  def page_title(%Campaign{} = campaign, highlight) when is_map(highlight) do
    quote = highlight |> highlight_text() |> sanitize_text(90)
    truncate("“#{quote}” · #{campaign.title}", 120)
  end

  def page_description(%Campaign{} = campaign, highlight) when is_map(highlight) do
    title = node_title(campaign, highlight_node_id(highlight))
    quote = highlight |> highlight_text() |> sanitize_text(180)

    truncate(
      "Highlighted quote from #{title} in \"#{campaign.title}\" on RationalGrid: “#{quote}”",
      240
    )
  end

  def node_title(%Campaign{} = campaign, node_id) do
    campaign.raw_payload
    |> MediaPayload.key_nodes()
    |> Enum.find_value("Node #{node_id}", fn node ->
      if to_string(get(node, "id")) == to_string(node_id) do
        node
        |> get("title")
        |> sanitize_text(72)
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
        mime_type: "image/svg+xml",
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
        mime_type: "image/svg+xml",
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
        mime_type: "image/svg+xml",
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

  defp quote_layout(text) do
    text
    |> quote_layout_candidates()
    |> Enum.max_by(&quote_layout_score/1, fn -> nil end)
    |> case do
      nil -> fallback_quote_layout(text)
      layout -> layout
    end
  end

  defp quote_layout_candidates(text) do
    candidate_font_sizes()
    |> Enum.map(fn font_size ->
      lines = wrap_lines_by_width(text, max_line_units(font_size), @max_quote_lines)
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
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp quote_layout_score(%{font_size: font_size, lines: lines}) do
    max_units = max_line_units(font_size)
    line_units = Enum.map(lines, &text_units/1)
    longest_line = Enum.max(line_units, fn -> 1 end)
    shortest_line = Enum.min(line_units, fn -> 1 end)
    average_line = Enum.sum(line_units) / max(length(line_units), 1)
    line_count_penalty = max(length(lines) - 3, 0) * 0.18

    fill_score = average_line / max_units
    balance_score = shortest_line / max(longest_line, 1)
    font_score = font_size / 76

    fill_score * 0.45 + balance_score * 0.35 + font_score * 0.2 - line_count_penalty
  end

  defp full_quote_layout(text) do
    text = sanitize_text(text, nil)

    Enum.find_value(
      [72, 68, 64, 60, 56, 52, 48, 44, 40, 36, 32, 28, 24, 22, 20, 18, 16, 14, 12, 10],
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
    font_size = 10
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

  defp fallback_quote_layout(text) do
    font_size = 36
    line_gap = quote_line_gap(font_size)
    lines = wrap_lines_by_width(text, max_line_units(font_size), @max_quote_lines)
    block_height = quote_block_height(lines, line_gap)

    %{
      font_size: font_size,
      line_gap: line_gap,
      start_y: quote_start_y(block_height, font_size),
      lines: lines
    }
  end

  defp node_card_layout(title, excerpt) do
    title_text = sanitize_text(title, @max_svg_title_chars)
    body_text = sanitize_text(excerpt, 920)
    body_present? = body_text != "" and body_text != title_text

    node_card_layout_candidates(title_text, body_text, body_present?)
    |> Enum.max_by(&node_card_layout_score/1, fn -> nil end)
    |> case do
      nil -> fallback_node_card_layout(title_text, body_text, body_present?)
      layout -> layout
    end
  end

  defp node_card_layout_candidates(title_text, body_text, body_present?) do
    for title_font <- [62, 58, 54, 50, 46, 42, 38, 34],
        body_font <- [26, 24, 22, 20, 18],
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
    title_lines = wrap_lines_by_width(title_text, 910 / title_font, 3)
    title_start_y = 200
    title_last_y = title_start_y + (length(title_lines) - 1) * title_line_gap
    body_start_y = title_last_y + round(title_font * 0.82) + 28
    body_line_gap = round(body_font * 1.42)
    max_body_lines = max_body_lines(body_start_y, body_line_gap, body_present?)

    cond do
      title_last_y > 360 ->
        nil

      body_present? and max_body_lines < 3 ->
        nil

      true ->
        body_lines =
          if body_present? do
            wrap_lines_by_width(body_text, 910 / body_font, max_body_lines)
          else
            []
          end

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

  defp max_body_lines(_body_start_y, _body_line_gap, false), do: 0

  defp max_body_lines(body_start_y, body_line_gap, true) do
    max(div(494 - body_start_y, body_line_gap) + 1, 0)
    |> min(8)
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
        title_font_size: 34,
        title_line_gap: 38,
        title_start_y: 200,
        title_lines: wrap_lines_by_width(title_text, 910 / 34, 3),
        body_font_size: 18,
        body_line_gap: 26,
        body_start_y: 336,
        body_lines: if(body_present?, do: wrap_lines_by_width(body_text, 910 / 18, 6), else: []),
        body_present?: body_present?
      }
  end

  defp grid_title_layout(text) do
    title_text = sanitize_text(text, @max_svg_title_chars)

    Enum.find_value([76, 72, 68, 64, 60, 56, 52, 48, 44, 40], fn font_size ->
      lines = wrap_lines_by_width(title_text, @quote_area_width / font_size, 3)
      line_gap = round(font_size * 1.12)
      block_height = quote_block_height(lines, line_gap)

      if block_height <= @quote_area_height do
        %{
          font_size: font_size,
          line_gap: line_gap,
          start_y: quote_start_y(block_height, font_size),
          lines: lines
        }
      end
    end) || fallback_quote_layout(title_text)
  end

  defp candidate_font_sizes, do: [76, 72, 68, 64, 60, 56, 52, 48, 44, 40, 36]

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

  defp wrap_lines_by_width(text, max_units, max_lines) do
    text
    |> wrap_all_lines_by_width(max_units)
    |> limit_lines_by_width(max_units, max_lines)
  end

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

  defp limit_lines_by_width(lines, max_units, max_lines) when length(lines) <= max_lines do
    lines
    |> Enum.map(&truncate_line_to_units(&1, max_units))
    |> balance_line_endings(max_units)
  end

  defp limit_lines_by_width(lines, max_units, max_lines) do
    {visible_lines, overflow_lines} = Enum.split(lines, max_lines)
    overflow_text = Enum.join(overflow_lines, " ")
    merged_last_line = List.last(visible_lines) <> " " <> overflow_text

    visible_lines
    |> Enum.map(&truncate_line_to_units(&1, max_units))
    |> List.replace_at(max_lines - 1, truncate_line_to_units(merged_last_line, max_units))
    |> balance_line_endings(max_units)
  end

  defp balance_line_endings(lines, _max_units) when length(lines) < 2, do: lines

  defp balance_line_endings(lines, max_units) do
    last_line = List.last(lines)

    if String.ends_with?(last_line, "…") or text_units(last_line) >= max_units * 0.42 do
      lines
    else
      previous_index = length(lines) - 2
      previous_line = Enum.at(lines, previous_index)
      previous_words = String.split(previous_line, " ", trim: true)

      maybe_move_word_to_last_line(lines, previous_index, previous_words, last_line, max_units)
    end
  end

  defp maybe_move_word_to_last_line(
         lines,
         _previous_index,
         previous_words,
         _last_line,
         _max_units
       )
       when length(previous_words) < 2 do
    lines
  end

  defp maybe_move_word_to_last_line(lines, previous_index, previous_words, last_line, max_units) do
    word = List.last(previous_words)
    new_previous = previous_words |> Enum.drop(-1) |> Enum.join(" ")
    new_last = word <> " " <> last_line

    if text_units(new_previous) >= max_units * 0.32 and text_units(new_last) <= max_units do
      lines
      |> List.replace_at(previous_index, new_previous)
      |> List.replace_at(length(lines) - 1, new_last)
    else
      lines
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

  defp normalize_slide_index(slide) when is_integer(slide), do: max(slide, 1)

  defp normalize_slide_index(slide) do
    case Integer.parse(to_string(slide)) do
      {index, ""} -> max(index, 1)
      _ -> 1
    end
  end

  defp strip_leading_title(text, title) do
    text = text |> String.trim_leading("#") |> String.trim_leading()

    cond do
      text == title ->
        ""

      String.starts_with?(text, title) ->
        String.trim_leading(String.slice(text, String.length(title)..-1//1), " :—–-\n")

      true ->
        text
    end
  end

  defp strip_node_markdown(text) when is_binary(text) do
    text
    |> String.replace(~r/^[[:space:]]*#+[[:space:]]*/m, "")
    |> String.replace(~r/\*\*([^*]+)\*\*/, "\\1")
    |> String.replace(~r/\*([^*]+)\*/, "\\1")
    |> String.replace(~r/\[([^\]]+)\]\([^\)]+\)/, "\\1")
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
