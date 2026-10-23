defmodule GridMediaManager.Articles.HTML do
  @moduledoc "Portable article HTML for rich-text pasting and standalone reading."
  alias GridMediaManager.Articles

  # Generate only basic editor elements. All source text is escaped; raw source HTML
  # is never trusted, and links are restricted to web URLs and email addresses.
  def body(draft) do
    content = draft.content

    sections =
      Enum.map_join(Articles.reading_sections(draft), "\n", fn section ->
        prose =
          if content["mode"] == "source_passages" do
            Enum.map_join(section.reading_passages, "\n", &passage/1)
          else
            markdown(section["body"])
          end

        links =
          Enum.map_join(
            section.reading_links,
            " · ",
            &link(&1.label, Articles.node_url(draft, &1.id))
          )

        source = if links == "", do: "", else: "<p>#{links}</p>"
        "<h2>#{escape(section["title"])}</h2>\n#{prose}\n#{source}"
      end)

    conclusion =
      if content["mode"] == "source_passages",
        do: "",
        else: "<h2>Where the paths meet</h2>" <> markdown(content["conclusion"] || "")

    note =
      if content["mode"] == "source_passages",
        do: "Original passages have been selected and arranged for this article.",
        else: "An AI-assisted draft interpreting the grid."

    "<p><em>#{escape(content["subtitle"] || "")}</em></p>\n" <>
      markdown(content["introduction"] || "") <>
      sections <>
      conclusion <>
      "<hr><p>Based on #{link(draft.source_title, draft.source_url)}. #{note}</p>"
  end

  def document(draft) do
    """
    <!doctype html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>#{escape(draft.content["title"])}</title>
    <style>
      body { margin: 64px auto; padding: 0 24px; max-width: 700px; color: #242424; background: #fff; font: 19px/1.75 Georgia, serif; }
      h1 { font-size: 2.4em; line-height: 1.12; letter-spacing: -.03em; margin: 0 0 .6em; }
      h2 { font-size: 1.65em; line-height: 1.25; margin: 2em 0 .8em; padding-top: 1em; border-top: 1px solid #e5e5e5; }
      h3 { font-size: 1.2em; line-height: 1.4; margin: 1.7em 0 .65em; }
      p { margin: 0 0 1.15em; } article > h1 + p { color: #666; font-size: 1.1em; }
      a { color: #9a3412; text-underline-offset: 3px; }
      blockquote { border-left: 3px solid #c97645; margin: 1.6em 0; padding: .2em 0 .2em 1.3em; color: #555; font-style: italic; }
      blockquote p:last-child { margin-bottom: 0; }
      ul, ol { padding-left: 1.5em; margin: 1em 0 1.5em; }
      li { padding-left: .25em; margin-bottom: .65em; } hr { border: 0; border-top: 1px solid #ddd; margin: 2em 0; }
      @media (max-width: 600px) { body { margin: 32px auto; font-size: 17px; } h1 { font-size: 2em; } }
      @media print { body { margin: 0 auto; } }
    </style>
    </head>
    <body><article><h1>#{escape(draft.content["title"])}</h1>#{body(draft)}</article></body>
    </html>
    """
  end

  @doc "Renders an original passage with its restored source subheading."
  def passage(passage, heading_level \\ 3) when heading_level in [3, 4] do
    heading =
      if passage.reading_heading,
        do: "<h#{heading_level}>#{inline(passage.reading_heading)}</h#{heading_level}>\n",
        else: ""

    heading <> markdown(passage["text"])
  end

  @doc "Renders the Markdown subset used by grid passages, without accepting raw HTML."
  def markdown(text) do
    text |> String.replace("\r\n", "\n") |> String.split("\n") |> blocks() |> Enum.join("\n")
  end

  defp blocks([]), do: []

  defp blocks([line | rest]) do
    trimmed = String.trim(line)

    cond do
      trimmed == "" ->
        blocks(rest)

      heading = Regex.run(~r/^(\#{1,6})\s+(.+)$/, trimmed) ->
        [_, marks, title] = heading
        level = min(String.length(marks), 3)
        ["<h#{level}>#{inline(title)}</h#{level}>" | blocks(rest)]

      Regex.match?(~r/^([-*_])(?:\s*\1){2,}$/, trimmed) ->
        ["<hr>" | blocks(rest)]

      String.starts_with?(trimmed, ">") ->
        {quotes, remaining} =
          Enum.split_while([line | rest], &String.starts_with?(String.trim(&1), ">"))

        quote = Enum.map_join(quotes, "\n", &String.replace(&1, ~r/^\s*>\s?/, ""))
        ["<blockquote>#{markdown(quote)}</blockquote>" | blocks(remaining)]

      list_item(trimmed) != nil ->
        {kind, number, _} = list_item(trimmed)

        {items, remaining} =
          Enum.split_while([line | rest], fn item ->
            case list_item(String.trim(item)) do
              {^kind, _, _} -> true
              _ -> false
            end
          end)

        start = if kind == "ol" and number != "1", do: " start=\"#{number}\"", else: ""

        contents =
          Enum.map_join(items, "", fn item ->
            {_, _, text} = list_item(String.trim(item))
            "<li>#{inline(text)}</li>"
          end)

        ["<#{kind}#{start}>#{contents}</#{kind}>" | blocks(remaining)]

      true ->
        {lines, remaining} = Enum.split_while(rest, &(not block_start?(&1)))
        ["<p>#{inline(Enum.join([line | lines], " "))}</p>" | blocks(remaining)]
    end
  end

  defp block_start?(line) do
    text = String.trim(line)

    text == "" or String.starts_with?(text, ">") or list_item(text) != nil or
      Regex.match?(~r/^(?:\#{1,6}\s|([-*_])(?:\s*\1){2,}$)/, text)
  end

  defp list_item(text) do
    cond do
      match = Regex.run(~r/^[-+*]\s+(.+)$/, text) ->
        {"ul", nil, Enum.at(match, 1)}

      match = Regex.run(~r/^(\d+)[.)]\s+(.+)$/, text) ->
        {"ol", Enum.at(match, 1), Enum.at(match, 2)}

      true ->
        nil
    end
  end

  # Tokenize before escaping, so replacement text cannot introduce executable tags.
  defp inline(text) do
    pattern =
      ~r/(`[^`\n]+`|\[[^\]\n]+\]\([^\s)]+\)|\*\*[^*\n]+\*\*|__[^_\n]+__|(?<!\w)\*[^*\n]+\*|(?<!\w)_[^_\n]+_)/u

    Regex.split(pattern, text, include_captures: true, trim: false)
    |> Enum.map_join("", &inline_token/1)
  end

  defp inline_token(token) do
    cond do
      match = Regex.run(~r/^`([^`\n]+)`$/, token) ->
        "<code>#{escape(Enum.at(match, 1))}</code>"

      match = Regex.run(~r/^\*\*([^*\n]+)\*\*$/, token) ->
        "<strong>#{inline(Enum.at(match, 1))}</strong>"

      match = Regex.run(~r/^__([^_\n]+)__$/, token) ->
        "<strong>#{inline(Enum.at(match, 1))}</strong>"

      match = Regex.run(~r/^\*([^*\n]+)\*$/, token) ->
        "<em>#{escape(Enum.at(match, 1))}</em>"

      match = Regex.run(~r/^_([^_\n]+)_$/, token) ->
        "<em>#{escape(Enum.at(match, 1))}</em>"

      match = Regex.run(~r/^\[([^\]]+)\]\(([^\s)]+)\)$/, token) ->
        link(Enum.at(match, 1), Enum.at(match, 2))

      true ->
        escape(token)
    end
  end

  defp link(label, url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) ->
        "<a href=\"#{escape(url)}\">#{escape(label)}</a>"

      %URI{scheme: "mailto", path: address} when is_binary(address) ->
        "<a href=\"#{escape(url)}\">#{escape(label)}</a>"

      _ ->
        escape(label)
    end
  end

  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
