defmodule GridMediaManager.Pexels.ClientTest do
  use ExUnit.Case, async: false

  alias GridMediaManager.Pexels.Client

  setup do
    previous_config = Application.get_env(:grid_media_manager, :pexels)

    Req.Test.verify_on_exit!()

    Application.put_env(:grid_media_manager, :pexels,
      api_key: "pexels-secret",
      endpoint: "https://pexels.test/v1/search",
      plug: {Req.Test, __MODULE__}
    )

    on_exit(fn ->
      if is_nil(previous_config) do
        Application.delete_env(:grid_media_manager, :pexels)
      else
        Application.put_env(:grid_media_manager, :pexels, previous_config)
      end
    end)

    :ok
  end

  test "configured?/0 requires a non-blank API key" do
    assert Client.configured?()

    Application.put_env(:grid_media_manager, :pexels, api_key: "  ")
    refute Client.configured?()

    Application.delete_env(:grid_media_manager, :pexels)
    refute Client.configured?()
  end

  test "search/2 returns not_configured without making a request" do
    Application.put_env(:grid_media_manager, :pexels,
      endpoint: "https://pexels.test/v1/search",
      plug: {Req.Test, __MODULE__}
    )

    assert Client.search("mountains") == {:error, :not_configured}
  end

  test "uses the default endpoint and sends the API key as the raw Authorization header" do
    Application.put_env(:grid_media_manager, :pexels,
      api_key: "pexels-secret",
      plug: {Req.Test, __MODULE__}
    )

    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.scheme == :https
      assert conn.host == "api.pexels.com"
      assert conn.request_path == "/v1/search"
      assert Plug.Conn.get_req_header(conn, "authorization") == ["pexels-secret"]
      assert Plug.Conn.Query.decode(conn.query_string) == %{"query" => "ocean"}

      Req.Test.json(conn, %{"photos" => []})
    end)

    assert Client.search("ocean") == {:ok, []}
  end

  test "passes search options and normalizes Pexels photos" do
    Req.Test.expect(__MODULE__, fn conn ->
      assert Plug.Conn.get_req_header(conn, "authorization") == ["pexels-secret"]

      assert Plug.Conn.Query.decode(conn.query_string) == %{
               "orientation" => "landscape",
               "per_page" => "8",
               "query" => "city lights"
             }

      Req.Test.json(conn, %{
        "photos" => [
          %{
            "id" => 42,
            "alt" => "A city skyline at night",
            "photographer" => "Ada Example",
            "photographer_url" => "https://www.pexels.com/@ada-example",
            "url" => "https://www.pexels.com/photo/42",
            "avg_color" => "#253047",
            "src" => %{
              "medium" => "https://images.pexels.com/medium.jpg",
              "landscape" => "https://images.pexels.com/landscape.jpg",
              "portrait" => "https://images.pexels.com/portrait.jpg",
              "original" => "https://images.pexels.com/original.jpg"
            }
          }
        ]
      })
    end)

    assert {:ok, [photo]} =
             Client.search("  city lights  ", orientation: "landscape", per_page: 8)

    assert photo == %{
             id: 42,
             alt: "A city skyline at night",
             photographer: "Ada Example",
             photographer_url: "https://www.pexels.com/@ada-example",
             pexels_url: "https://www.pexels.com/photo/42",
             avg_color: "#253047",
             preview_url: "https://images.pexels.com/medium.jpg",
             landscape_url: "https://images.pexels.com/landscape.jpg",
             portrait_url: "https://images.pexels.com/portrait.jpg",
             original_url: "https://images.pexels.com/original.jpg"
           }
  end

  test "returns an API error with the response status and message" do
    Req.Test.expect(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_status(401)
      |> Req.Test.json(%{"error" => "Unauthorized"})
    end)

    assert Client.search("forest") == {:error, {:api_error, 401, "Unauthorized"}}
  end

  test "returns an HTTP error when a failed response has no API message" do
    Req.Test.expect(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_status(503)
      |> Req.Test.json(%{"status" => "unavailable"})
    end)

    assert Client.search("forest") == {:error, {:http_error, 503}}
  end

  test "rejects malformed successful responses" do
    Req.Test.expect(__MODULE__, fn conn ->
      Req.Test.json(conn, %{"photos" => "not-a-list"})
    end)

    assert Client.search("forest") == {:error, :invalid_response}
  end
end
