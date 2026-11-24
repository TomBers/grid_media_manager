defmodule GridMediaManager.RationalGrid.ImportAdapter do
  @moduledoc "Converts authenticated MCP reads into the studio's canonical media payload."

  def payload(read, operation \\ %{})

  def payload(%{"grid" => grid, "nodes" => nodes, "edges" => edges}, operation) do
    nodes = complete_node_content(nodes, grid, operation)

    %{
      "metadata" => %{
        "id" => grid["id"],
        "graph_name" => grid["id"],
        "title" => grid["title"],
        "url" => grid["url"],
        "tags" => grid["tags"] || [],
        "visibility" => grid["visibility"],
        "node_count" => length(nodes),
        "source" => "mcp"
      },
      "graph" => %{"nodes" => nodes, "edges" => edges},
      "highlights" => []
    }
  end

  # The grid-read projection can omit synthesis content. Only supplement an existing,
  # accessible node from the same completed operation; never invent or revive nodes.
  defp complete_node_content(nodes, %{"id" => id}, %{
         "status" => "completed",
         "grid" => %{"id" => id},
         "nodes" => generated
       })
       when is_list(generated) do
    completed = Map.new(generated, &{&1["id"], &1})

    Enum.map(nodes, fn node ->
      candidate = completed[node["id"]]

      if blank?(node["content"]) and is_map(candidate) and
           candidate["class"] == node["class"] and not blank?(candidate["content"]) do
        Map.put(node, "content", candidate["content"])
      else
        node
      end
    end)
  end

  defp complete_node_content(nodes, _grid, _operation), do: nodes
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_value), do: true
end
