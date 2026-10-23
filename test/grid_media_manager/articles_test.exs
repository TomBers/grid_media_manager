defmodule GridMediaManager.ArticlesTest do
  use ExUnit.Case, async: true
  alias GridMediaManager.Articles

  test "normalizes Cytoscape edges and excludes deleted nodes and their links" do
    payload = %{
      "graph" => %{
        "nodes" => [
          %{"id" => 1, "content" => "Opening", "class" => "origin", "user" => "private"},
          %{"data" => %{"id" => 2, "content" => "An objection"}},
          %{"id" => 3, "content" => "Deleted", "deleted" => true}
        ],
        "edges" => [
          %{"data" => %{"source" => "1", "target" => "2"}},
          %{"source" => "1", "target" => "3"}
        ]
      }
    }

    assert {:ok, graph} = Articles.prepare_graph(payload)
    assert Enum.map(graph["nodes"], & &1["id"]) == ["1", "2"]
    refute Enum.any?(graph["nodes"], &Map.has_key?(&1, "user"))
    assert graph["edges"] == [%{"source" => "1", "target" => "2"}]
  end

  test "accepts real directed paths and rejects invented links, reversed edges, and missing IDs" do
    graph = %{
      "nodes" => Enum.map(["1", "2", "3"], &%{"id" => &1}),
      "edges" => [%{"source" => "1", "target" => "2"}, %{"source" => "1", "target" => "3"}]
    }

    assert :ok = Articles.validate_routes(article(["1", "2"]), graph)
    assert :ok = Articles.validate_routes(article(["3"]), graph)

    for path <- [["2", "3"], ["2", "1"], ["1", "999"], [], ["1", "1"]] do
      assert {:error, :invalid_routes} = Articles.validate_routes(article(path), graph)
    end
  end

  test "empty and oversized graphs fail explicitly instead of generating from partial source" do
    assert {:error, :empty_graph} = Articles.prepare_graph(%{})

    assert {:error, :graph_too_large} =
             Articles.prepare_graph(%{
               "graph" => %{
                 "nodes" => [%{"id" => "1", "content" => String.duplicate("a", 150_001)}]
               }
             })
  end

  defp article(path), do: %{"sections" => [%{"node_ids" => path}]}
end
