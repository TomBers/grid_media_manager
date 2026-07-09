defmodule GridMediaManager.RationalGrid.ClientTest do
  use ExUnit.Case, async: false

  alias GridMediaManager.RationalGrid.Client

  setup do
    previous_config = Application.get_env(:grid_media_manager, :rational_grid)

    on_exit(fn ->
      Application.put_env(:grid_media_manager, :rational_grid, previous_config)
    end)

    :ok
  end

  test "defaults to the /api promotion endpoints" do
    Application.put_env(:grid_media_manager, :rational_grid, base_url: "https://rationalgrid.ai")

    assert Client.index_url() == {:ok, "https://rationalgrid.ai/api/promotion/grids"}

    assert Client.media_url("what-is-the-collective-subconscious-637e9a") ==
             {:ok,
              "https://rationalgrid.ai/api/promotion/grids/what-is-the-collective-subconscious-637e9a"}
  end

  test "builds the configured promotion show URL for a slug" do
    Application.put_env(:grid_media_manager, :rational_grid,
      base_url: "http://localhost:4000",
      index_path: "/api/promotion/grids",
      media_path_template: "/api/promotion/grids/:graph_name"
    )

    assert Client.media_url("what-is-the-collective-subconscious-637e9a") ==
             {:ok,
              "http://localhost:4000/api/promotion/grids/what-is-the-collective-subconscious-637e9a"}
  end

  test "builds the configured promotion index URL" do
    Application.put_env(:grid_media_manager, :rational_grid,
      base_url: "http://localhost:4000",
      index_path: "/api/promotion/grids",
      media_path_template: "/api/promotion/grids/:graph_name"
    )

    assert Client.index_url() == {:ok, "http://localhost:4000/api/promotion/grids"}
  end

  test "normalizes flexible grid index payloads" do
    payload = %{
      "grids" => [
        %{
          "graph_name" => "what-is-the-collective-subconscious-637e9a",
          "title" => "What is the collective subconscious?",
          "node_count" => 14,
          "tags" => ["Psychology", "Philosophy"]
        }
      ]
    }

    assert [grid] = Client.normalize_grid_index(payload)
    assert grid.slug == "what-is-the-collective-subconscious-637e9a"
    assert grid.title == "What is the collective subconscious?"
    assert grid.node_count == 14
    assert grid.tags == ["Psychology", "Philosophy"]
    assert grid.source == "what-is-the-collective-subconscious-637e9a"
  end
end
