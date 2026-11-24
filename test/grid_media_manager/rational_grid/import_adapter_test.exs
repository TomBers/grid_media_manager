defmodule GridMediaManager.RationalGrid.ImportAdapterTest do
  use ExUnit.Case, async: true
  alias GridMediaManager.RationalGrid.ImportAdapter

  test "retains completed synthesis content when the accessible grid projection omits it" do
    synthesis = %{
      "id" => "5",
      "class" => "synthesis",
      "content" => "Comfort can enable autonomy while dependence can constrain it."
    }

    read = %{
      "grid" => %{"id" => "private-grid"},
      "nodes" => [%{synthesis | "content" => ""}],
      "edges" => []
    }

    operation = %{"status" => "completed", "grid" => read["grid"], "nodes" => [synthesis]}
    assert ImportAdapter.payload(read, operation)["graph"]["nodes"] == [synthesis]

    for unsafe_operation <- [
          %{operation | "status" => "generating"},
          %{operation | "grid" => %{"id" => "other-grid"}},
          %{operation | "nodes" => [%{synthesis | "class" => "answer"}]}
        ] do
      assert ImportAdapter.payload(read, unsafe_operation)["graph"]["nodes"] == read["nodes"]
    end

    persisted = %{synthesis | "content" => "The current persisted text."}

    assert ImportAdapter.payload(%{read | "nodes" => [persisted]}, operation)["graph"]["nodes"] ==
             [persisted]

    assert ImportAdapter.payload(%{read | "nodes" => []}, operation)["graph"]["nodes"] == []
  end
end
