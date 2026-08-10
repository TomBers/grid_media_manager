defmodule GridMediaManager.Promotion.Markdown do
  @moduledoc """
  Extracts presentation-oriented block structure from RationalGrid Markdown.

  The browser canvas consumes these semantic blocks so editable text retains
  headings, quotes, and list structure without depending on server rendering.
  """

  @protected_period "\uE000"

  @type block :: %{
          required(:type) => :heading | :paragraph | :blockquote | :list_item,
          required(:text) => String.t(),
          optional(:level) => pos_integer(),
          optional(:marker) => String.t(),
          optional(:role) => :connection | :question
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

  @spec paginate_blocks([block()], pos_integer()) :: [[block()]]
  def paginate_blocks(blocks, max_characters \\ 1_100)

  def paginate_blocks(blocks, max_characters)
      when is_list(blocks) and is_integer(max_characters) and max_characters > 0 do
    blocks
    |> Enum.flat_map(&split_block(&1, max_characters))
    |> Enum.reduce([], fn block, pages -> append_block_to_pages(pages, block, max_characters) end)
  end

  def paginate_blocks(_blocks, _max_characters), do: []

  @doc """
  Removes authoring scaffolding that is useful in Markdown but distracting on a slide.

  Semantic lists remain lists. Editorial labels such as `Category` are removed,
  while labelled explanation and question items become clean prose blocks.
  """
  @spec presentation_blocks([block()]) :: [block()]
  def presentation_blocks(blocks) when is_list(blocks) do
    Enum.flat_map(blocks, fn
      %{type: :list_item, text: text} = block -> presentation_list_item(block, text)
      block -> [block]
    end)
  end

  def presentation_blocks(_blocks), do: []

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

  defp split_block(%{text: text} = block, max_characters) do
    text
    |> complete_sentences()
    |> Enum.flat_map(&split_long_text(&1, max_characters))
    |> Enum.reduce([], fn sentence, chunks ->
      append_sentence(chunks, sentence, max_characters)
    end)
    |> Enum.map(&%{block | text: &1})
  end

  defp split_block(_block, _max_characters), do: []

  defp presentation_list_item(_block, text) do
    cond do
      Regex.match?(~r/^category\s*:/iu, text) ->
        []

      match =
          Regex.run(
            ~r/^(?:the\s+)?(?:non-obvious\s+connection|question\/insight\s+opened|key\s+insight|connection)\s*:\s*(.+)$/iu,
            text,
            capture: :all_but_first
          ) ->
        role = if Regex.match?(~r/question\/insight/iu, text), do: :question, else: :connection

        [
          %{
            type: :paragraph,
            role: role,
            text: match |> List.first() |> String.trim()
          }
        ]

      true ->
        [%{type: :list_item, marker: "•", text: text}]
    end
  end

  defp split_long_text(text, max_characters) do
    text
    |> String.split(~r/\s+/u, trim: true)
    |> Enum.reduce([], fn word, chunks ->
      case List.pop_at(chunks, -1) do
        {nil, []} ->
          [word]

        {current, previous} ->
          combined = current <> " " <> word

          if String.length(combined) <= max_characters do
            previous ++ [combined]
          else
            chunks ++ [word]
          end
      end
    end)
  end

  defp complete_sentences(text) do
    text
    |> protect_abbreviation_periods()
    |> then(&Regex.scan(~r/.+?(?:[.!?]+(?=\s|$)|$)/u, &1))
    |> List.flatten()
    |> Enum.map(&String.replace(&1, @protected_period, "."))
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> case do
      [] -> [String.trim(text)]
      sentences -> sentences
    end
  end

  defp protect_abbreviation_periods(text) do
    text
    |> String.replace(
      ~r/\b(Dr|Mr|Mrs|Ms|Prof|Sr|Jr|St)\./u,
      "\\1" <> @protected_period
    )
    |> String.replace(
      ~r/\b(e)\.(g)\./iu,
      "\\1" <> @protected_period <> "\\2" <> @protected_period
    )
    |> String.replace(
      ~r/\b(i)\.(e)\./iu,
      "\\1" <> @protected_period <> "\\2" <> @protected_period
    )
  end

  defp append_sentence([], sentence, _max_characters), do: [sentence]

  defp append_sentence(chunks, sentence, max_characters) do
    current = List.last(chunks)
    combined = current <> " " <> sentence

    if String.length(combined) <= max_characters do
      List.replace_at(chunks, length(chunks) - 1, combined)
    else
      chunks ++ [sentence]
    end
  end

  defp append_block_to_pages([], block, _max_characters), do: [[block]]

  defp append_block_to_pages(pages, block, max_characters) do
    current_page = List.last(pages)
    current_size = Enum.reduce(current_page, 0, &(String.length(&1.text) + 24 + &2))
    block_size = String.length(block.text) + 24

    if current_size + block_size <= max_characters do
      List.replace_at(pages, length(pages) - 1, current_page ++ [block])
    else
      pages ++ [[block]]
    end
  end

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
