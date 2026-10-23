defmodule GridMediaManager.Articles do
  @moduledoc "Assembles saved articles from original grid passages and editorial highlights."
  import Ecto.Query

  alias GridMediaManager.Articles.{Draft, Generator, Source}
  alias GridMediaManager.RationalGrid.{Client, Slug}
  alias GridMediaManager.Repo

  def list_drafts do
    Repo.all(from d in Draft, order_by: [desc: d.inserted_at, desc: d.id], limit: 20)
  end

  def get_draft(id) do
    case Ecto.Type.cast(:id, id) do
      {:ok, id} -> Repo.get(Draft, id)
      :error -> nil
    end
  end

  def generate(source, brief) do
    with {:ok, slug} <- Slug.normalize(source),
         {:ok, payload} <- Client.fetch_media(source),
         {:ok, graph} <- prepare_graph(payload),
         {:ok, selection} <- Generator.generate(graph, brief),
         {:ok, content} <- Source.assemble(selection, graph) do
      %Draft{}
      |> Draft.changeset(%{
        slug: slug,
        source_title: get_in(payload, ["metadata", "title"]) || slug,
        source_url: "https://rationalgrid.ai/g/" <> URI.encode(slug),
        brief: brief,
        content: content,
        graph: graph
      })
      |> Repo.insert()
    end
  end

  def prepare_graph(payload) do
    raw_graph = payload["graph"] || %{}

    nodes =
      (raw_graph["nodes"] || [])
      |> Enum.filter(&is_map/1)
      |> Enum.map(&Map.merge(&1, &1["data"] || %{}))
      |> Enum.reject(&(&1["deleted"] == true or &1["compound"] == true))
      |> Enum.map(fn node ->
        %{
          "id" => to_string(node["id"] || ""),
          "class" => node["class"] || node["type"] || "node",
          "source_text" => node["source_text"],
          "prompt_kind" => node["prompt_kind"],
          "content" => node["content"] || node["text"] || ""
        }
      end)
      |> Enum.filter(&(&1["id"] != "" and is_binary(&1["content"]) and &1["content"] != ""))
      |> Enum.uniq_by(& &1["id"])

    ids = MapSet.new(nodes, & &1["id"])

    edges =
      (raw_graph["edges"] || [])
      |> Enum.filter(&is_map/1)
      |> Enum.map(fn edge ->
        edge = edge["data"] || edge

        %{
          "source" => to_string(edge["source"] || ""),
          "target" => to_string(edge["target"] || "")
        }
      end)
      |> Enum.filter(&(MapSet.member?(ids, &1["source"]) and MapSet.member?(ids, &1["target"])))
      |> Enum.uniq()

    cond do
      nodes == [] ->
        {:error, :empty_graph}

      length(nodes) > 100 or Enum.sum(Enum.map(nodes, &String.length(&1["content"]))) > 150_000 ->
        {:error, :graph_too_large}

      true ->
        highlights = payload |> GridMediaManager.RationalGrid.MediaPayload.highlights()
        title = get_in(payload, ["metadata", "title"]) || Source.title(hd(nodes))
        graph = Source.prepare(%{"nodes" => nodes, "edges" => edges}, highlights, title)
        if graph["passages"] == [], do: {:error, :empty_graph}, else: {:ok, graph}
    end
  end

  def validate_routes(%{"sections" => sections}, graph)
      when is_list(sections) and sections != [] do
    ids = MapSet.new(graph["nodes"], & &1["id"])
    edges = MapSet.new(graph["edges"], &{&1["source"], &1["target"]})

    valid? =
      Enum.all?(sections, fn section ->
        path = section["node_ids"]

        is_list(path) and path != [] and Enum.uniq(path) == path and
          Enum.all?(path, &MapSet.member?(ids, &1)) and
          Enum.all?(Enum.chunk_every(path, 2, 1, :discard), fn [from, to] ->
            MapSet.member?(edges, {from, to})
          end)
      end)

    if valid?, do: :ok, else: {:error, :invalid_routes}
  end

  def validate_routes(_content, _graph), do: {:error, :invalid_routes}

  def node_url(draft, id), do: draft.source_url <> "?" <> URI.encode_query(%{"node" => id})

  @doc "Adds reading links only for new source nodes contributing to each section."
  def reading_sections(draft) do
    draft.content["sections"]
    |> Enum.map_reduce(MapSet.new(), fn section, linked ->
      ids =
        case section["passages"] do
          passages when is_list(passages) -> Enum.map(passages, & &1["node_id"])
          _ -> Enum.take(section["node_ids"], -1)
        end
        |> Enum.uniq()

      new_ids = Enum.reject(ids, &MapSet.member?(linked, &1))

      links =
        Enum.map(new_ids, fn id ->
          %{
            id: id,
            label:
              if(length(new_ids) == 1,
                do: "Explore this thread in the grid",
                else: "Read source node #{id}"
              )
          }
        end)

      section =
        section
        |> Map.put(:reading_links, links)
        |> Map.put(:reading_passages, reading_passages(section))

      {section, Enum.reduce(ids, linked, &MapSet.put(&2, &1))}
    end)
    |> elem(0)
  end

  # Headings are stored separately from the verbatim passage text. Restore each
  # heading at the start of its run, without repeating the section title.
  defp reading_passages(section) do
    (section["passages"] || [])
    |> Enum.map_reduce(nil, fn passage, previous ->
      heading = passage["heading"]
      context = {passage["node_id"], heading}

      show? =
        is_binary(heading) and String.trim(heading) != "" and
          heading != section["title"] and context != previous

      {Map.put(passage, :reading_heading, if(show?, do: heading)), context}
    end)
    |> elem(0)
  end

  def markdown(draft) do
    if draft.content["mode"] == "source_passages",
      do: source_markdown(draft),
      else: legacy_markdown(draft)
  end

  defp source_markdown(draft) do
    sections =
      Enum.map_join(reading_sections(draft), "\n\n", fn section ->
        passages =
          Enum.map_join(section.reading_passages, "\n\n", fn passage ->
            if passage.reading_heading,
              do: "### #{passage.reading_heading}\n\n#{passage["text"]}",
              else: passage["text"]
          end)

        links =
          Enum.map_join(section.reading_links, " · ", &"[#{&1.label}](#{node_url(draft, &1.id)})")

        "## #{section["title"]}\n\n#{passages}\n\n#{links}"
      end)

    "# #{draft.content["title"]}\n\nSelected passages from [#{draft.source_title}](#{draft.source_url}), guided by the grid’s highlights and branches.\n\n#{sections}\n\n---\n\nOriginal passages have been selected and arranged for this article.\n"
  end

  defp legacy_markdown(draft) do
    content = draft.content

    sections =
      Enum.map_join(reading_sections(draft), "\n\n", fn section ->
        links =
          Enum.map_join(section.reading_links, " · ", &"[#{&1.label}](#{node_url(draft, &1.id)})")

        "## #{section["title"]}\n\n#{section["body"]}\n\n#{links}"
      end)

    """
    # #{content["title"]}

    #{content["subtitle"]}

    #{content["introduction"]}

    #{sections}

    ## Where the paths meet

    #{content["conclusion"]}

    ---

    Based on [#{draft.source_title}](#{draft.source_url}). An AI-assisted draft interpreting the grid; node links identify the source discussion.
    """
  end

  def word_count(draft), do: draft |> markdown() |> String.split() |> length()
end
