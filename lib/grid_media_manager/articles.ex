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

  def markdown(draft) do
    if draft.content["mode"] == "source_passages",
      do: source_markdown(draft),
      else: legacy_markdown(draft)
  end

  defp source_markdown(draft) do
    sections =
      Enum.map_join(draft.content["sections"], "\n\n", fn section ->
        passages =
          Enum.map_join(section["passages"], "\n\n", fn passage ->
            omission = if passage["omitted_before"], do: "[…]\n\n", else: ""
            quote = passage["text"] |> String.split("\n") |> Enum.map_join("\n", &("> " <> &1))

            highlighted =
              if passage["highlight_ids"] != [], do: " · contains a grid highlight", else: ""

            omission <>
              quote <>
              "\n\n[Original passage · Node #{passage["node_id"]}](#{node_url(draft, passage["node_id"])})#{highlighted}"
          end)

        links = Enum.map_join(section["node_ids"], " → ", &"[Node #{&1}](#{node_url(draft, &1)})")
        "## #{section["title"]}\n\n#{passages}\n\nFollow this path: #{links}"
      end)

    "# #{draft.content["title"]}\n\nSelected passages from [#{draft.source_title}](#{draft.source_url}), guided by the grid’s highlights and branches.\n\n#{sections}\n\n---\n\nPassage wording is preserved from the grid. […] marks omitted text before an excerpt.\n"
  end

  defp legacy_markdown(draft) do
    content = draft.content

    sections =
      Enum.map_join(content["sections"], "\n\n", fn section ->
        links = Enum.map_join(section["node_ids"], " → ", &"[Node #{&1}](#{node_url(draft, &1)})")
        "## #{section["title"]}\n\n#{section["body"]}\n\nExplore this direction: #{links}"
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
