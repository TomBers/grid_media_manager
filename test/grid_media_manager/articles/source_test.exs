defmodule GridMediaManager.Articles.SourceTest do
  use ExUnit.Case, async: true
  alias GridMediaManager.Articles
  alias GridMediaManager.Articles.Source

  test "matches rendered highlights while preserving raw paragraphs and notes" do
    graph = graph()
    [first, second, _, _] = graph["highlights"]
    assert first["passage_ids"] == ["2:1"]
    assert first["note"] == "An editorial clue, not article text"
    assert second["passage_ids"] == ["2:1", "2:2"]

    assert Enum.find(graph["passages"], &(&1["id"] == "2:1"))["text"] ==
             "A **marked idea** with a qualification."
  end

  test "stale highlights and non-node selections cannot become replacement prose" do
    graph = graph()
    assert Enum.at(graph["highlights"], 2)["passage_ids"] == []
    assert Enum.at(graph["highlights"], 3)["passage_ids"] == []
    {:ok, content} = Source.assemble(plan(["2:1"]), graph)
    refute content["sections"] |> hd() |> Map.fetch!("body") =~ "stale text"
  end

  test "ignores invented prose and restores source order with explicit omissions" do
    graph = graph()

    selection =
      plan(["2:3", "2:1"])
      |> Map.put("title", "Invented hook")
      |> Map.put("conclusion", "Invented agreement")

    {:ok, content} = Source.assemble(selection, graph)
    assert content["title"] == "Original grid title"
    assert content["introduction"] == ""
    assert content["conclusion"] == ""
    assert content["mode"] == "source_passages"
    [section] = content["sections"]
    assert section["title"] == "Original node title"
    assert Enum.map(section["passages"], & &1["id"]) == ["2:1", "2:3"]
    assert Enum.map(section["passages"], & &1["omitted_before"]) == [false, true]
    node = Enum.find(graph["nodes"], &(&1["id"] == "2"))
    assert Enum.all?(section["passages"], &String.contains?(node["content"], &1["text"]))
    refute section["body"] =~ "Invented"
  end

  test "rejects unknown, duplicate, and off-route passages" do
    graph = graph()

    for ids <- [["unknown"], ["2:1", "2:1"], ["3:1"], []] do
      assert {:error, :invalid_selection} = Source.assemble(plan(ids), graph)
    end

    repeated = %{"sections" => plan(["2:1"])["sections"] ++ plan(["2:1"])["sections"]}
    assert {:error, :invalid_selection} = Source.assemble(repeated, graph)
  end

  test "exports original wording with one section link and no editorial markers" do
    graph = graph()
    {:ok, content} = Source.assemble(plan(["2:1", "2:3"]), graph)

    markdown =
      Articles.markdown(%{
        content: content,
        source_title: "Original grid title",
        source_url: "https://rationalgrid.ai/g/example"
      })

    assert markdown =~ "A **marked idea** with a qualification."

    assert markdown =~
             "[Explore this thread in the grid](https://rationalgrid.ai/g/example?node=2)"

    assert length(Regex.scan(~r/\?node=2/, markdown)) == 1
    refute markdown =~ "[…]"
    refute markdown =~ "contains a grid highlight"
    refute markdown =~ "Where the paths meet"
    refute markdown =~ "An editorial clue"
  end

  test "grids without highlights still supply selectable original passages" do
    payload = %{
      "graph" => %{"nodes" => [%{"id" => "a", "content" => "# Heading\n\nOriginal text."}]}
    }

    assert {:ok, graph} = Articles.prepare_graph(payload)
    assert graph["highlights"] == []

    assert {:ok, _} =
             Source.assemble(
               %{"sections" => [%{"node_ids" => ["a"], "passage_ids" => ["a:1"]}]},
               graph
             )
  end

  defp plan(ids),
    do: %{
      "sections" => [%{"node_ids" => ["1", "2"], "passage_ids" => ids, "body" => "Invented body"}]
    }

  defp graph do
    {:ok, graph} =
      Articles.prepare_graph(%{
        "metadata" => %{"title" => "Original grid title"},
        "graph" => %{
          "nodes" => [
            %{"id" => "1", "class" => "origin", "content" => "# Opening"},
            %{
              "id" => "2",
              "class" => "answer",
              "content" =>
                "# Original node title\n\nA **marked idea** with a qualification.\n\nAnother original paragraph.\n\nA final caveat."
            },
            %{
              "id" => "3",
              "class" => "antithesis",
              "content" => "# Objection\n\nAn opposing interpretation."
            }
          ],
          "edges" => [%{"source" => "1", "target" => "2"}, %{"source" => "1", "target" => "3"}]
        },
        "highlights" => [
          %{
            "id" => 1,
            "node_id" => "2",
            "text_source_type" => "node",
            "text" => "marked idea",
            "note" => "An editorial clue, not article text",
            "selection_start" => 999
          },
          %{"id" => 2, "node_id" => "2", "text" => "a qualification. Another original"},
          %{"id" => 3, "node_id" => "2", "text" => "stale text"},
          %{"id" => 4, "node_id" => "2", "text_source_type" => "comment", "text" => "marked idea"}
        ]
      })

    graph
  end
end
