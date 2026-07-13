defmodule GridMediaManager.RationalGrid.Client do
  @moduledoc """
  Fetches RationalGrid promotion payloads with Req.

  Configure the endpoints with environment variables when needed:

    * `RATIONAL_GRID_BASE_URL` - defaults to `https://rationalgrid.ai`
    * `RATIONAL_GRID_INDEX_PATH` - defaults to `/api/promotion/grids`
    * `RATIONAL_GRID_MEDIA_PATH_TEMPLATE` - defaults to `/api/promotion/grids/:slug`
    * `RATIONALGRID_PROMOTION_API_TOKEN` - optional bearer token for authenticated requests
      (or `config :grid_media_manager, :rational_grid, promotion_api_token: ...`)

  Internal users may also paste a direct promotion endpoint URL, in which case it
  is fetched as-is.
  """

  alias GridMediaManager.RationalGrid.Slug

  @default_base_url "https://rationalgrid.ai"
  @default_index_path "/api/promotion/grids"
  @default_media_path_template "/api/promotion/grids/:slug"
  @promotion_api_token_env "RATIONALGRID_PROMOTION_API_TOKEN"

  def fetch_media(input) when is_binary(input) do
    with {:ok, url} <- media_url(input),
         {:ok, response} <- request(url) do
      decode_media_response(response)
    end
  end

  def fetch_grid_index do
    with {:ok, url} <- index_url(),
         {:ok, response} <- request(url),
         {:ok, decoded} <- decode_any_response(response) do
      {:ok, normalize_grid_index(decoded)}
    end
  end

  def index_url do
    {:ok, build_url(index_path())}
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

  def request_headers do
    case promotion_api_token() do
      nil -> []
      token -> [{"authorization", "Bearer #{token}"}]
    end
  end

  def promotion_api_token do
    System.get_env(@promotion_api_token_env)
    |> string_value()
    |> case do
      nil ->
        :grid_media_manager
        |> Application.get_env(:rational_grid, [])
        |> get_in([:promotion_api_token])
        |> string_value()

      token ->
        token
    end
  end

  def normalize_grid_index(decoded) do
    grids =
      cond do
        is_list(decoded) -> decoded
        is_map(decoded) and is_list(decoded["grids"]) -> decoded["grids"]
        is_map(decoded) and is_list(decoded["data"]) -> decoded["data"]
        is_map(decoded) and is_list(decoded[:grids]) -> decoded[:grids]
        is_map(decoded) and is_list(decoded[:data]) -> decoded[:data]
        true -> []
      end

    grids
    |> Enum.filter(&is_map/1)
    |> Enum.map(&normalize_grid_summary/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(&grid_sort_key/1, :desc)
  end

  defp build_media_url(slug) do
    media_path_template()
    |> String.replace(":slug", URI.encode(slug))
    |> String.replace(":graph_name", URI.encode(slug))
    |> build_url()
  end

  defp build_url(path) do
    base_url() <> ensure_leading_slash(path)
  end

  defp base_url do
    (System.get_env("RATIONAL_GRID_BASE_URL") ||
       get_in(Application.get_env(:grid_media_manager, :rational_grid, []), [:base_url]) ||
       @default_base_url)
    |> String.trim_trailing("/")
  end

  defp index_path do
    System.get_env("RATIONAL_GRID_INDEX_PATH") ||
      get_in(Application.get_env(:grid_media_manager, :rational_grid, []), [:index_path]) ||
      @default_index_path
  end

  defp media_path_template do
    System.get_env("RATIONAL_GRID_MEDIA_PATH_TEMPLATE") ||
      get_in(Application.get_env(:grid_media_manager, :rational_grid, []), [
        :media_path_template
      ]) ||
      @default_media_path_template
  end

  defp ensure_leading_slash("/" <> _rest = path), do: path
  defp ensure_leading_slash(path), do: "/" <> path

  defp request(url) do
    case Req.get(url: url, headers: request_headers(), receive_timeout: 15_000, retry: :transient) do
      {:ok, %{status: status} = response} when status in 200..299 ->
        {:ok, response}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  defp decode_media_response(response) do
    case decode_any_response(response) do
      {:ok, decoded} when is_map(decoded) -> {:ok, decoded}
      {:ok, _decoded} -> {:error, :invalid_payload}
      {:error, reason} -> {:error, reason}
    end
  end

  defp decode_any_response(%{body: body}) when is_map(body) or is_list(body), do: {:ok, body}

  defp decode_any_response(%{body: body}) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} when is_map(decoded) or is_list(decoded) -> {:ok, decoded}
      {:ok, _decoded} -> {:error, :invalid_payload}
      {:error, reason} -> {:error, {:invalid_json, reason}}
    end
  end

  defp decode_any_response(_response), do: {:error, :invalid_payload}

  defp normalize_grid_summary(grid) do
    metadata = first_value(grid, ["metadata", :metadata]) || grid

    slug =
      metadata
      |> first_string(["graph_name", :graph_name, "slug", :slug, "name", :name, "id", :id])
      |> clean_slug()

    if slug do
      %{
        id: slug,
        slug: slug,
        title:
          first_string(metadata, ["title", :title, "question", :question, "name", :name]) || slug,
        url: first_string(metadata, ["url", :url, "grid_url", :grid_url]),
        graph_url: first_string(metadata, ["graph_url", :graph_url]),
        tags: string_list(first_value(metadata, ["tags", :tags])),
        node_count: integer_value(first_value(metadata, ["node_count", :node_count])),
        updated_at: first_string(metadata, ["updated_at", :updated_at]),
        inserted_at: first_string(metadata, ["inserted_at", :inserted_at]),
        source: slug
      }
    end
  end

  defp grid_sort_key(grid) do
    timestamp = grid.inserted_at || grid.updated_at

    case parse_timestamp(timestamp) do
      {:ok, datetime} -> {1, DateTime.to_unix(datetime, :microsecond)}
      :error -> {0, 0}
    end
  end

  defp parse_timestamp(timestamp) when is_binary(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, datetime, _offset} ->
        {:ok, datetime}

      {:error, _reason} ->
        parse_naive_or_date(timestamp)
    end
  end

  defp parse_timestamp(_timestamp), do: :error

  defp parse_naive_or_date(timestamp) do
    case NaiveDateTime.from_iso8601(timestamp) do
      {:ok, naive_datetime} ->
        {:ok, DateTime.from_naive!(naive_datetime, "Etc/UTC")}

      {:error, _reason} ->
        case Date.from_iso8601(timestamp) do
          {:ok, date} -> {:ok, DateTime.new!(date, ~T[00:00:00], "Etc/UTC")}
          {:error, _reason} -> :error
        end
    end
  end

  defp first_string(map, keys) do
    map
    |> first_value(keys)
    |> string_value()
  end

  defp first_value(map, keys) do
    Enum.find_value(keys, &Map.get(map, &1))
  end

  defp clean_slug(nil), do: nil

  defp clean_slug(value) do
    value
    |> Slug.normalize()
    |> case do
      {:ok, slug} -> slug
      {:error, _reason} -> nil
    end
  end

  defp string_value(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp string_value(value) when is_integer(value), do: Integer.to_string(value)
  defp string_value(_value), do: nil

  defp string_list(values) when is_list(values) do
    values
    |> Enum.map(&string_value/1)
    |> Enum.reject(&is_nil/1)
  end

  defp string_list(_values), do: []

  defp integer_value(value) when is_integer(value), do: value

  defp integer_value(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> number
      _ -> nil
    end
  end

  defp integer_value(_value), do: nil
end
