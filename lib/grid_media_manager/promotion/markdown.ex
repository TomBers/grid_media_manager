defmodule GridMediaManager.Promotion.Markdown do
  @moduledoc """
  Extracts presentation-oriented block structure from RationalGrid Markdown.

  The media pipeline renders SVG rather than browser HTML, so this module keeps
  the semantic parts that improve card readability without depending on a DOM.
  """

  @type block :: %{
          required(:type) => :heading | :paragraph | :blockquote | :list_item,
          required(:text) => String.t(),
          optional(:level) => pos_integer(),
          optional(:marker) => String.t()
        }

  @spec blocks(term()) :: [block()]
  def blocks(markdown) when is_binary(markdown) do
    markdown
    |> String.replace("\r\n", "\n")
    |> String.split("\n")
    |> Enum.reduce({[], []}, &reduce_line/2)
    |> then(fn {blocks, paragraph} -> flush_paragraph(blocks, paragraph) end)
    |> merge_adjacent_blockquotes()
  end

  def blocks(_markdown), do: []

  @spec drop_leading_title([block()], term()) :: [block()]
  def drop_leading_title([%{type: :heading, text: heading} | rest], title)
      when is_binary(title) do
    if normalize(heading) == normalize(title),
      do: rest,
      else: [%{type: :heading, text: heading} | rest]
  end

  def drop_leading_title(blocks, _title), do: blocks

  @spec sections(term()) :: [%{title: String.t(), blocks: [block()], text: String.t()}]
  def sections(markdown) do
    markdown
    |> blocks()
    |> Enum.reduce([], fn
      %{type: :heading, text: title}, sections ->
        sections ++ [%{title: title, blocks: []}]

      block, [] ->
        [%{title: "The argument", blocks: [block]}]

      block, sections ->
        List.update_at(sections, -1, fn section ->
          %{section | blocks: section.blocks ++ [block]}
        end)
    end)
    |> Enum.map(fn section -> Map.put(section, :text, readable_text(section.blocks)) end)
    |> Enum.reject(&(&1.text == ""))
  end

  @spec readable_text([block()]) :: String.t()
  def readable_text(blocks) when is_list(blocks) do
    blocks
    |> Enum.map(fn
      %{type: :heading, text: text} -> text
      %{type: :blockquote, text: text} -> "“#{text}”"
      %{type: :list_item, marker: marker, text: text} -> "#{marker} #{text}"
      %{text: text} -> text
    end)
    |> Enum.join("\n\n")
    |> String.trim()
  end

  @spec plain_inline(term()) :: String.t()
  def plain_inline(text) when is_binary(text) do
    text
    |> String.replace(~r/!\[([^\]]*)\]\([^\)]+\)/u, "\\1")
    |> String.replace(~r/\[([^\]]+)\]\([^\)]+\)/u, "\\1")
    |> String.replace(~r/<(?:https?:\/\/|mailto:)[^>]+>/u, "")
    |> String.replace(~r/<[^>]+>/u, "")
    |> String.replace(~r/\*\*([^*]+)\*\*/u, "\\1")
    |> String.replace(~r/__([^_]+)__/u, "\\1")
    |> String.replace(~r/\*([^*]+)\*/u, "\\1")
    |> String.replace(~r/_([^_]+)_/u, "\\1")
    |> String.replace(~r/`([^`]+)`/u, "\\1")
    |> String.replace(~r/\\([*_`\[\]#>+-])/u, "\\1")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  def plain_inline(text), do: text |> to_string() |> plain_inline()

  defp reduce_line(line, {blocks, paragraph}) do
    trimmed = String.trim(line)

    cond do
      trimmed == "" ->
        {flush_paragraph(blocks, paragraph), []}

      heading = Regex.run(~r/^(\#{1,6})\s+(.+)$/u, trimmed, capture: :all_but_first) ->
        [marks, text] = heading
        blocks = flush_paragraph(blocks, paragraph)
        {blocks ++ [%{type: :heading, level: String.length(marks), text: plain_inline(text)}], []}

      quote = Regex.run(~r/^>\s?(.*)$/u, trimmed, capture: :all_but_first) ->
        [text] = quote
        blocks = flush_paragraph(blocks, paragraph)
        {blocks ++ [%{type: :blockquote, text: plain_inline(text)}], []}

      item = Regex.run(~r/^[-+*]\s+(.+)$/u, trimmed, capture: :all_but_first) ->
        [text] = item
        blocks = flush_paragraph(blocks, paragraph)
        {blocks ++ [%{type: :list_item, marker: "•", text: plain_inline(text)}], []}

      item = Regex.run(~r/^(\d+)[.)]\s+(.+)$/u, trimmed, capture: :all_but_first) ->
        [number, text] = item
        blocks = flush_paragraph(blocks, paragraph)
        {blocks ++ [%{type: :list_item, marker: "#{number}.", text: plain_inline(text)}], []}

      Regex.match?(~r/^([-*_])(?:\s*\1){2,}$/u, trimmed) ->
        {flush_paragraph(blocks, paragraph), []}

      true ->
        {blocks, paragraph ++ [trimmed]}
    end
  end

  defp flush_paragraph(blocks, []), do: blocks

  defp flush_paragraph(blocks, lines) do
    text = lines |> Enum.join(" ") |> plain_inline()
    if text == "", do: blocks, else: blocks ++ [%{type: :paragraph, text: text}]
  end

  defp merge_adjacent_blockquotes(blocks) do
    blocks
    |> Enum.reduce([], fn
      %{type: :blockquote, text: text}, [%{type: :blockquote, text: previous} | rest] ->
        [%{type: :blockquote, text: String.trim(previous <> " " <> text)} | rest]

      block, acc ->
        [block | acc]
    end)
    |> Enum.reverse()
    |> Enum.map(fn
      %{type: :blockquote, text: text} = block ->
        %{block | text: clean_blockquote_delimiters(text)}

      block ->
        block
    end)
  end

  defp clean_blockquote_delimiters(text) do
    text
    |> String.replace(~r/^[\"“”]+/u, "")
    |> String.replace(~r/[\"“”]+(?=\s+—)/u, "")
    |> String.replace(~r/[\"“”]+$/u, "")
    |> String.trim()
  end

  defp normalize(text) do
    text
    |> plain_inline()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, " ")
    |> String.trim()
  end
end
