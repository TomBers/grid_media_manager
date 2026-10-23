defmodule GridMediaManager.Articles.Source do
  @moduledoc "Builds an article by selecting original passages, never accepting replacement prose."
  alias GridMediaManager.Articles
  alias GridMediaManager.Promotion.Markdown

  def prepare(graph, highlights, title) do
    passages = Enum.flat_map(graph["nodes"], &passages/1)
    highlights = Enum.map(highlights, &normalize_highlight(&1, passages))

    passages =
      Enum.map(passages, fn passage ->
        ids =
          highlights |> Enum.filter(&(passage["id"] in &1["passage_ids"])) |> Enum.map(& &1["id"])

        Map.put(passage, "highlight_ids", ids)
      end)

    Map.merge(graph, %{"title" => title, "passages" => passages, "highlights" => highlights})
  end

  def assemble(%{"sections" => sections} = plan, graph)
      when is_list(sections) and sections != [] do
    with :ok <- Articles.validate_routes(plan, graph),
         true <- valid_selection?(sections, graph) do
      sections = Enum.map(sections, &assemble_section(&1, graph))

      {:ok,
       %{
         "mode" => "source_passages",
         "title" => graph["title"],
         "subtitle" =>
           "A reading path through the original grid, guided by its highlights and branches.",
         "introduction" => "",
         "conclusion" => "",
         "sections" => sections
       }}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_selection}
    end
  end

  def assemble(_, _), do: {:error, :invalid_selection}

  def title(node) do
    node["content"]
    |> String.split(~r/\r?\n/, parts: 2)
    |> hd()
    |> String.trim_leading("#")
    |> String.trim()
  end

  defp passages(node) do
    node["content"]
    |> String.split(~r/\r?\n[ \t]*\r?\n/, trim: true)
    |> Enum.reduce({[], nil}, fn chunk, {passages, heading} ->
      case Regex.run(~r/^\s*\#{1,6} +([^\r\n]+)(?:\r?\n([\s\S]*))?$/, chunk) do
        [_, title] -> {passages, title}
        [_, title, rest] -> {append_passage(passages, rest, title, node), title}
        _ -> {append_passage(passages, chunk, heading, node), heading}
      end
    end)
    |> elem(0)
  end

  defp append_passage(passages, text, heading, node) do
    text = String.trim(text)

    if text == "" do
      passages
    else
      index = length(passages)

      passages ++
        [
          %{
            "id" => "#{node["id"]}:#{index + 1}",
            "node_id" => node["id"],
            "position" => index,
            "heading" => heading,
            "text" => text
          }
        ]
    end
  end

  defp normalize_highlight(highlight, passages) do
    highlight =
      Map.take(highlight, [
        "id",
        "node_id",
        "text_source_type",
        "text_source_id",
        "selection_start",
        "selection_end",
        "text",
        "note"
      ])

    highlight =
      highlight |> Map.update("id", "", &to_string/1) |> Map.update("node_id", "", &to_string/1)

    type = highlight["text_source_type"]

    matches =
      if type in [nil, "node"] and is_binary(highlight["text"]) and
           String.trim(highlight["text"]) != "" do
        matching_passages(highlight, passages)
      else
        []
      end

    Map.put(highlight, "passage_ids", matches)
  end

  # Highlight offsets refer to rendered selections, not necessarily raw Markdown bytes.
  # Match the snapshot text against readable passages and keep the original Markdown for export.
  defp matching_passages(highlight, passages) do
    {ranges, _} =
      passages
      |> Enum.filter(&(&1["node_id"] == highlight["node_id"]))
      |> Enum.map_reduce(0, fn passage, offset ->
        text = comparable(passage["text"])

        {%{id: passage["id"], text: text, start: offset, stop: offset + byte_size(text)},
         offset + byte_size(text) + 1}
      end)

    text = Enum.map_join(ranges, " ", & &1.text)
    needle = comparable(highlight["text"])

    if needle == "" do
      []
    else
      case :binary.match(text, needle) do
        {start, size} ->
          ranges
          |> Enum.filter(&(&1.start < start + size and &1.stop > start))
          |> Enum.map(& &1.id)

        :nomatch ->
          []
      end
    end
  end

  defp comparable(text) do
    text
    |> Markdown.blocks()
    |> Enum.map_join(" ", & &1.text)
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  defp valid_selection?(sections, graph) do
    passages = Map.new(graph["passages"], &{&1["id"], &1})
    all_ids = Enum.flat_map(sections, &List.wrap(&1["passage_ids"]))

    Enum.uniq(all_ids) == all_ids and
      Enum.all?(sections, fn section ->
        ids = section["passage_ids"]

        is_list(ids) and ids != [] and
          Enum.all?(ids, fn id ->
            case passages[id] do
              nil -> false
              passage -> passage["node_id"] in section["node_ids"]
            end
          end)
      end)
  end

  defp assemble_section(section, graph) do
    by_id = Map.new(graph["passages"], &{&1["id"], &1})
    path = section["node_ids"]

    passages =
      section["passage_ids"]
      |> Enum.map(&by_id[&1])
      |> Enum.sort_by(fn passage ->
        {Enum.find_index(path, fn id -> id == passage["node_id"] end), passage["position"]}
      end)

    {passages, _} =
      Enum.map_reduce(passages, nil, fn passage, previous ->
        omitted? =
          if previous && previous["node_id"] == passage["node_id"],
            do: passage["position"] > previous["position"] + 1,
            else: passage["position"] > 0

        {Map.put(passage, "omitted_before", omitted?), passage}
      end)

    last_node = Enum.find(graph["nodes"], &(&1["id"] == List.last(passages)["node_id"]))

    relationship =
      case last_node["class"] do
        "antithesis" -> "Objection"
        "thesis" -> "Defence"
        "question" -> "Question"
        "origin" -> "Opening"
        _ -> if length(path) <= 2, do: "Opening", else: "Follow-up"
      end

    %{
      "title" => title(last_node),
      "summary" => "",
      "relationship" => relationship,
      "node_ids" => path,
      "passages" => passages,
      "body" => Enum.map_join(passages, "\n\n", & &1["text"])
    }
  end
end
