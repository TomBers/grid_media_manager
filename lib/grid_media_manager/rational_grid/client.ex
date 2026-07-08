defmodule GridMediaManager.RationalGrid.Client do
  @moduledoc """
  Fetches RationalGrid media payloads with Req.

  Configure the endpoint with environment variables when needed:

    * `RATIONAL_GRID_BASE_URL` - defaults to `https://rationalgrid.ai`
    * `RATIONAL_GRID_MEDIA_PATH_TEMPLATE` - defaults to `/g/:slug/media.json`

  Internal users may also paste a direct media endpoint URL, in which case it is
  fetched as-is.
  """

  alias GridMediaManager.RationalGrid.Slug

  @default_base_url "https://rationalgrid.ai"
  @default_media_path_template "/g/:slug/media.json"

  def fetch_media(input) when is_binary(input) do
    with {:ok, url} <- media_url(input),
         {:ok, response} <- request(url) do
      decode_response(response)
    end
  end

  def media_url(input) when is_binary(input) do
    input = String.trim(input)

    cond do
      input == "" ->
        {:error, :blank}

      Slug.direct_media_url?(input) ->
        {:ok, input}

      true ->
        with {:ok, slug} <- Slug.normalize(input) do
          {:ok, build_media_url(slug)}
        end
    end
  end

  defp build_media_url(slug) do
    base_url =
      System.get_env("RATIONAL_GRID_BASE_URL") ||
        get_in(Application.get_env(:grid_media_manager, :rational_grid, []), [:base_url]) ||
        @default_base_url

    path_template =
      System.get_env("RATIONAL_GRID_MEDIA_PATH_TEMPLATE") ||
        get_in(Application.get_env(:grid_media_manager, :rational_grid, []), [
          :media_path_template
        ]) ||
        @default_media_path_template

    base_url = String.trim_trailing(base_url, "/")
    path = String.replace(path_template, ":slug", URI.encode(slug))

    base_url <> ensure_leading_slash(path)
  end

  defp ensure_leading_slash("/" <> _rest = path), do: path
  defp ensure_leading_slash(path), do: "/" <> path

  defp request(url) do
    case Req.get(url: url, receive_timeout: 15_000, retry: :transient) do
      {:ok, %{status: status} = response} when status in 200..299 ->
        {:ok, response}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  defp decode_response(%{body: body}) when is_map(body), do: {:ok, body}

  defp decode_response(%{body: body}) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} when is_map(decoded) -> {:ok, decoded}
      {:ok, _decoded} -> {:error, :invalid_payload}
      {:error, reason} -> {:error, {:invalid_json, reason}}
    end
  end

  defp decode_response(_response), do: {:error, :invalid_payload}
end
