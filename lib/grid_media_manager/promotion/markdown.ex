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
    |> sections_from_blocks()
  end

  @doc """
  Returns sections that are suitable for public-facing slides and previews.

  The source Markdown remains untouched, but terminal bibliographies and search-grounding
  scaffolding are excluded from generated media.
  """
  @spec presentation_sections(term()) :: [
          %{title: String.t(), blocks: [block()], text: String.t()}
        ]
  def presentation_sections(markdown) do
    markdown
    |> blocks()
    |> drop_reference_sections()
    |> presentation_blocks()
    |> sections_from_blocks()
  end

  @doc "Returns public-facing answer text without bibliography or grounding scaffolding."
  @spec presentation_text(term()) :: String.t()
  def presentation_text(markdown) do
    markdown
    |> presentation_sections()
    |> Enum.map_join("\n\n", fn section ->
      if section.title == "The argument" do
        section.text
      else
        [section.title, section.text]
        |> Enum.reject(&(&1 == ""))
        |> Enum.join("\n\n")
      end
    end)
  end

  defp sections_from_blocks(blocks) do
    blocks
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
  Builds concise pages without splitting a sentence or list item.

  Complete thoughts may exceed the preferred page size up to the hard limit. Thoughts beyond
  the hard limit are omitted instead of being published as misleading fragments.
  """
  @spec complete_thought_pages([block()], pos_integer(), pos_integer()) :: [[block()]]
  def complete_thought_pages(blocks, preferred_characters, hard_limit)
      when is_list(blocks) and is_integer(preferred_characters) and preferred_characters > 0 and
             is_integer(hard_limit) and hard_limit >= preferred_characters do
    blocks
    |> Enum.flat_map(&sentence_blocks/1)
    |> Enum.filter(&(String.length(&1.text) <= hard_limit))
    |> Enum.reduce([], fn block, pages ->
      append_block_to_pages(pages, block, preferred_characters)
    end)
  end

  def complete_thought_pages(_blocks, _preferred_characters, _hard_limit), do: []

  @doc """
  Removes authoring scaffolding that is useful in Markdown but distracting on a slide.

  Semantic lists remain lists. Editorial labels such as `Category` are removed,
  while labelled explanation and question items become clean prose blocks.
  """
  @spec presentation_blocks([block()]) :: [block()]
  def presentation_blocks(blocks) when is_list(blocks) do
    Enum.flat_map(blocks, fn
      %{type: :list_item, text: text} = block ->
        if grounding_scaffolding?(text), do: [], else: presentation_list_item(block, text)

      %{text: text} = block when is_binary(text) ->
        if grounding_scaffolding?(text), do: [], else: [block]

      block ->
        [block]
    end)
  end

  def presentation_blocks(_blocks), do: []

  @doc "Returns a clean node title, recovering it from the answer when metadata is a reference."
  @spec presentation_title(term(), term()) :: String.t()
  def presentation_title(title, markdown) do
    title = title |> to_string() |> plain_inline()

    case split_reference_material(title) do
      {:reference, _public_text} -> title_from_markdown(markdown)
      :content -> title
    end
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
    |> String.replace(~r/cite[^]+/u, "")
    |> String.replace(~r/【[^】]*(?:turn\d+(?:search|fetch)\d+|†)[^】]*】/u, "")
    |> String.replace(~r/(?<!\w)\[(?:\d+\s*[,;]?\s*)+\](?!\()/u, "")
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
    |> String.replace(~r/\s+([,.;:!?])/u, "\\1")
    |> String.trim()
  end

  def plain_inline(text), do: text |> to_string() |> plain_inline()

  @doc """
  Converts authored Markdown into plain text suitable for social feed posts.

  Block structure becomes whitespace, Unicode bullets, and typographic quotation
  marks. Unlike slide-oriented text, link destinations remain visible because
  Facebook and LinkedIn only make pasted URLs clickable.
  """
  @spec social_text(term()) :: String.t()
  def social_text(markdown) when is_binary(markdown) do
    markdown
    |> social_sections()
    |> Enum.join("\n\n")
  end

  def social_text(markdown), do: markdown |> to_string() |> social_text()

  @doc """
  Returns the same social-safe text grouped into complete authored sections.

  These boundaries let character-limited platforms omit a complete trailing
  section rather than cutting through one of its paragraphs or lists.
  """
  @spec social_sections(term()) :: [String.t()]
  def social_sections(markdown) when is_binary(markdown) do
    markdown
    |> preserve_link_destinations()
    |> prepare_social_blocks()
    |> blocks()
    |> group_social_sections()
    |> Enum.map(&readable_text/1)
    |> Enum.reject(&(&1 == ""))
  end

  def social_sections(markdown), do: markdown |> to_string() |> social_sections()

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

  defp sentence_blocks(%{text: text} = block) when is_binary(text) do
    text
    |> complete_sentences()
    |> Enum.map(&%{block | text: &1})
  end

  defp sentence_blocks(_block), do: []

  defp preserve_link_destinations(markdown) do
    markdown =
      Regex.replace(
        ~r/!?\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)/u,
        markdown,
        fn
          _match, "", url -> url
          _match, label, url when label == url -> url
          _match, label, url -> "#{label} — #{url}"
        end
      )

    Regex.replace(~r/<((?:https?:\/\/|mailto:)[^>]+)>/u, markdown, "\\1")
  end

  defp prepare_social_blocks(markdown) do
    markdown
    |> String.replace("\r\n", "\n")
    |> String.split("\n")
    |> Enum.reject(&Regex.match?(~r/^\s*```/u, &1))
    |> social_table_lines()
    |> Enum.join("\n")
  end

  defp social_table_lines([header, separator | rest]) do
    if table_row?(header) and table_separator?(separator) do
      {rows, remaining} = Enum.split_while(rest, &table_row?/1)
      headers = table_cells(header)

      ["" | Enum.map(rows, &social_table_row(headers, &1))] ++
        ["" | social_table_lines(remaining)]
    else
      [header | social_table_lines([separator | rest])]
    end
  end

  defp social_table_lines(lines), do: lines

  defp table_row?(line) do
    line = String.trim(line)
    String.starts_with?(line, "|") and String.ends_with?(line, "|")
  end

  defp table_separator?(line) do
    line
    |> table_cells()
    |> case do
      [] -> false
      cells -> Enum.all?(cells, &Regex.match?(~r/^:?-{3,}:?$/u, &1))
    end
  end

  defp table_cells(line) do
    line
    |> String.trim()
    |> String.trim("|")
    |> String.split("|")
    |> Enum.map(&String.trim/1)
  end

  defp social_table_row(headers, row) do
    text =
      headers
      |> Enum.zip(table_cells(row))
      |> Enum.reject(fn {_header, value} -> value == "" end)
      |> Enum.map_join(" · ", fn
        {"", value} -> value
        {header, value} -> "#{header}: #{value}"
      end)

    "- #{text}"
  end

  defp group_social_sections(blocks) do
    {sections, current, _heading_seen?} =
      Enum.reduce(blocks, {[], [], false}, fn
        %{type: :heading} = heading, {sections, current, false} ->
          {sections, current ++ [heading], true}

        %{type: :heading} = heading, {sections, current, true} ->
          {append_social_section(sections, current), [heading], true}

        block, {sections, current, heading_seen?} ->
          {sections, current ++ [block], heading_seen?}
      end)

    append_social_section(sections, current)
  end

  defp append_social_section(sections, []), do: sections
  defp append_social_section(sections, blocks), do: sections ++ [blocks]

  defp drop_reference_sections(blocks) do
    {kept, _dropping?} =
      Enum.reduce(blocks, {[], false}, fn
        %{type: :heading, text: title} = heading, {kept, _dropping?} ->
          if reference_heading?(title), do: {kept, true}, else: {kept ++ [heading], false}

        _block, {kept, true} ->
          {kept, true}

        %{text: text} = block, {kept, false} ->
          case split_reference_material(text) do
            {:reference, ""} -> {kept, true}
            {:reference, public_text} -> {kept ++ [%{block | text: public_text}], true}
            :content -> {kept ++ [block], false}
          end
      end)

    kept
  end

  defp reference_heading?(title) do
    title = normalize(title)

    Regex.match?(
      ~r/^(?:references?|key references|bibliography|works cited|reading list|references for further reading|further reading(?: references)?|further references|recommended (?:reading|sources)|sources?(?: and further reading)?)$/u,
      title
    )
  end

  defp split_reference_material(text) do
    colon_pattern =
      ~r/^(.*?)(?:references for further reading|further reading\s*\/\s*references|key references|references?(?:\s*\([^)]*\))?)\s*:\s*.*$/iu

    label_pattern =
      ~r/^(.*?)(?:references for further reading|further reading\s*\/\s*references|key references|references?(?:\s*\([^)]*\))?)\s*$/iu

    case Regex.run(colon_pattern, text, capture: :all_but_first) ||
           Regex.run(label_pattern, text, capture: :all_but_first) do
      [public_text] -> {:reference, String.trim(public_text)}
      _match -> :content
    end
  end

  defp grounding_scaffolding?(text) do
    normalized = String.trim(text)

    Regex.match?(~r/^(?:search query|suggested search|source query|web search)\b/iu, normalized) or
      Regex.match?(~r/^https?:\/\/\S+$/iu, normalized) or
      Regex.match?(~r/\bsearch query\s*(?:if you want[^:]*|\([^)]*\))?\s*:/iu, normalized) or
      Regex.match?(~r/\(\s*(?:textbook\s+)?search query\s*:/iu, normalized)
  end

  defp title_from_markdown(markdown) do
    markdown
    |> blocks()
    |> drop_reference_sections()
    |> Enum.find_value("", fn
      %{type: type, text: text} when type in [:heading, :paragraph] ->
        text
        |> String.replace(~r/^title\s*:\s*/iu, "")
        |> String.trim()
        |> case do
          "" -> nil
          title -> title
        end

      _block ->
        nil
    end)
  end

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
