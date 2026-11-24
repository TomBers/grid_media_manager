defmodule GridMediaManager.RationalGrid.HTTP do
  @moduledoc false

  def base_url do
    Application.get_env(:grid_media_manager, :rational_grid_mcp, [])
    |> Keyword.get(:base_url, "https://rationalgrid.ai")
    |> String.trim_trailing("/")
  end

  def resource, do: base_url() <> "/mcp"

  def request(method, path, opts \\ []) do
    test_opts =
      Application.get_env(:grid_media_manager, :rational_grid_mcp, [])[:req_options] || []

    Req.request(
      Keyword.merge(
        [
          method: method,
          url: base_url() <> path,
          retry: false,
          redirect: false,
          receive_timeout: 20_000
        ],
        opts ++ test_opts
      )
    )
  end
end
