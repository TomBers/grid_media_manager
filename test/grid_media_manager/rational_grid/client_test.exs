defmodule GridMediaManager.RationalGrid.ClientTest do
  use ExUnit.Case, async: false

  alias GridMediaManager.RationalGrid.Client

  setup do
    previous_config = Application.get_env(:grid_media_manager, :rational_grid)
    previous_token = System.get_env("RATIONALGRID_PROMOTION_API_TOKEN")
    previous_base_url = System.get_env("RATIONAL_GRID_BASE_URL")

    on_exit(fn ->
      Application.put_env(:grid_media_manager, :rational_grid, previous_config)

      if previous_token do
        System.put_env("RATIONALGRID_PROMOTION_API_TOKEN", previous_token)
      else
        System.delete_env("RATIONALGRID_PROMOTION_API_TOKEN")
      end

      if previous_base_url do
        System.put_env("RATIONAL_GRID_BASE_URL", previous_base_url)
      else
        System.delete_env("RATIONAL_GRID_BASE_URL")
      end
    end)

    System.delete_env("RATIONALGRID_PROMOTION_API_TOKEN")
    System.delete_env("RATIONAL_GRID_BASE_URL")

    :ok
  end

  test "rejects direct media URLs on an untrusted origin" do
    Application.put_env(:grid_media_manager, :rational_grid, base_url: "https://rationalgrid.ai")

    assert Client.media_url("https://attacker.example/api/media.json") ==
             {:error, :untrusted_origin}
  end

  test "accepts direct media URLs on the configured origin" do
    Application.put_env(:grid_media_manager, :rational_grid, base_url: "https://rationalgrid.ai")

    assert Client.media_url("https://rationalgrid.ai/api/promotion/grids/example") ==
             {:ok, "https://rationalgrid.ai/api/promotion/grids/example"}
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

  test "adds an authorization bearer header when the promotion token is configured" do
    System.put_env("RATIONALGRID_PROMOTION_API_TOKEN", "dev-secret-token")

    assert Client.request_headers() == [{"authorization", "Bearer dev-secret-token"}]
  end

  test "does not add authorization headers when the promotion token is blank" do
    System.put_env("RATIONALGRID_PROMOTION_API_TOKEN", "   ")

    assert Client.request_headers() == []
  end

  test "uses the configured promotion token when the environment token is absent" do
    Application.put_env(:grid_media_manager, :rational_grid,
      base_url: "http://localhost:4000",
      promotion_api_token: "configured-dev-token"
    )

    assert Client.request_headers() == [{"authorization", "Bearer configured-dev-token"}]
  end

  test "environment token takes precedence over configured promotion token" do
    Application.put_env(:grid_media_manager, :rational_grid,
      base_url: "http://localhost:4000",
      promotion_api_token: "configured-dev-token"
    )

    System.put_env("RATIONALGRID_PROMOTION_API_TOKEN", "env-token")

    assert Client.request_headers() == [{"authorization", "Bearer env-token"}]
  end

  test "sorts grid index entries from newest to oldest" do
    payload = %{
      "grids" => [
        %{
          "slug" => "undated-grid",
          "title" => "Undated"
        },
        %{
          "slug" => "old-grid",
          "title" => "Old",
          "inserted_at" => "2026-01-10T10:00:00Z",
          "updated_at" => "2026-07-10T10:00:00Z"
        },
        %{
          "slug" => "new-grid",
          "title" => "New",
          "inserted_at" => "2026-06-15T09:00:00+02:00"
        },
        %{
          "slug" => "fallback-grid",
          "title" => "Fallback date",
          "updated_at" => "2026-05-01"
        }
      ]
    }

    assert Enum.map(Client.normalize_grid_index(payload), & &1.slug) == [
             "new-grid",
             "fallback-grid",
             "old-grid",
             "undated-grid"
           ]
  end

  test "normalizes flexible grid index payloads" do
    payload = %{
      "grids" => [
        %{
          "metadata" => %{
            "slug" => "what-is-the-collective-subconscious-637e9a",
            "title" => "What is the collective subconscious?",
            "node_count" => 14,
            "tags" => ["Psychology", "Philosophy"]
          }
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
