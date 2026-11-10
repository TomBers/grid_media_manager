defmodule GridMediaManager.RationalGridMCPHelpers do
  alias GridMediaManager.Repo
  alias GridMediaManager.RationalGrid.Connection
  alias GridMediaManagerWeb.Endpoint

  def connected(expires_in \\ 3600) do
    Repo.insert!(%Connection{
      key: "studio",
      client_id: "client-1",
      status: "connected",
      expires_at: DateTime.add(DateTime.utc_now(), expires_in) |> DateTime.truncate(:second),
      credentials:
        Phoenix.Token.encrypt(Endpoint, "rg-credentials", %{
          "access_token" => "access-1",
          "refresh_token" => "refresh-1",
          "expires_in" => 3600
        })
    })
  end

  def setup_http do
    previous = Application.get_env(:grid_media_manager, :rational_grid_mcp, [])

    Application.put_env(:grid_media_manager, :rational_grid_mcp,
      req_options: [plug: {Req.Test, __MODULE__}]
    )

    ExUnit.Callbacks.on_exit(fn ->
      Application.put_env(:grid_media_manager, :rational_grid_mcp, previous)
    end)
  end

  def stub(fun), do: Req.Test.stub(__MODULE__, fun)

  def rpc(conn, fun) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)
    request = Jason.decode!(body)
    result = fun.(request["params"]["name"], request["params"]["arguments"])

    Req.Test.json(conn, %{jsonrpc: "2.0", id: request["id"], result: %{structuredContent: result}})
  end

  def grid do
    %{
      "id" => "private-grid",
      "title" => "Can evidence change minds?",
      "url" => "https://rationalgrid.ai/g/private-grid",
      "tags" => [],
      "visibility" => "private"
    }
  end

  def page(offset \\ 0) do
    %{
      "grid" => grid(),
      "nodes" => [
        %{
          "id" => "node-#{offset}",
          "class" => if(offset == 0, do: "origin", else: "answer"),
          "content" =>
            if(offset == 0,
              do: "Can evidence change minds?",
              else: "Evidence can help, but context matters."
            )
        }
      ],
      "edges" => [%{"from" => "node-0", "to" => "node-1"}],
      "total_nodes" => 2,
      "next_offset" => if(offset == 0, do: 1, else: nil)
    }
  end
end
