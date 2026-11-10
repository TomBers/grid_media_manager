defmodule GridMediaManager.RationalGrid.ImportAdapter do
  @moduledoc "Converts authenticated MCP reads into the studio's canonical media payload."

  def payload(%{"grid" => grid, "nodes" => nodes, "edges" => edges}) do
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
end
