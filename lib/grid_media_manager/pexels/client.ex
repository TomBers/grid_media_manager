defmodule GridMediaManager.Pexels.Client do
  @moduledoc """
  A focused client for the Pexels photo search API.

  Configure it under `:grid_media_manager, :pexels`:

      config :grid_media_manager, :pexels,
        api_key: System.fetch_env!("PEXELS_API_KEY"),
        endpoint: "https://api.pexels.com/v1/search"

  The endpoint defaults to the public Pexels search endpoint. A `:plug` option may
  be configured to replace Req's transport, which is useful with `Req.Test`.
  """

  @default_endpoint "https://api.pexels.com/v1/search"

  @type photo :: %{
          id: integer() | String.t() | nil,
          alt: String.t() | nil,
          photographer: String.t() | nil,
          photographer_url: String.t() | nil,
          pexels_url: String.t() | nil,
          avg_color: String.t() | nil,
          preview_url: String.t() | nil,
          landscape_url: String.t() | nil,
          portrait_url: String.t() | nil,
          original_url: String.t() | nil
        }

  @doc "Returns whether a non-blank Pexels API key is configured."
  @spec configured?() :: boolean()
  def configured?, do: not is_nil(api_key())

  @doc """
  Searches Pexels and returns normalized photo maps.

  Supported options are `:orientation` and `:per_page`.
  """
  @spec search(String.t(), keyword()) ::
          {:ok, [photo()]}
          | {:error, :not_configured | :invalid_query | :invalid_response}
          | {:error, {:api_error, pos_integer(), String.t()}}
          | {:error, {:http_error, pos_integer()}}
          | {:error, {:request_failed, term()}}
  def search(query, opts \\ [])

  def search(query, opts) when is_binary(query) and is_list(opts) do
    query = String.trim(query)

    cond do
      query == "" ->
        {:error, :invalid_query}

      not configured?() ->
        {:error, :not_configured}

      true ->
        query
        |> request_options(opts)
        |> Req.get()
        |> handle_response()
    end
  end

  def search(_query, _opts), do: {:error, :invalid_query}

  defp request_options(query, opts) do
    [
      url: endpoint(),
      headers: [{"authorization", api_key()}],
      params:
        [query: query]
        |> put_param(:orientation, Keyword.get(opts, :orientation))
        |> put_param(:per_page, Keyword.get(opts, :per_page)),
      retry: false
    ]
    |> put_request_option(:plug, config_value(:plug))
  end

  defp handle_response({:ok, %{status: status, body: body}}) when status in 200..299 do
    case value(body, "photos", :photos) do
      photos when is_list(photos) ->
        if Enum.all?(photos, &is_map/1) do
          {:ok, Enum.map(photos, &normalize_photo/1)}
        else
          {:error, :invalid_response}
        end

      _other ->
        {:error, :invalid_response}
    end
  end

  defp handle_response({:ok, %{status: status, body: body}}) do
    case error_message(body) do
      nil -> {:error, {:http_error, status}}
      message -> {:error, {:api_error, status, message}}
    end
  end

  defp handle_response({:error, reason}), do: {:error, {:request_failed, reason}}

  defp normalize_photo(photo) do
    src = value(photo, "src", :src)

    %{
      id: value(photo, "id", :id),
      alt: value(photo, "alt", :alt),
      photographer: value(photo, "photographer", :photographer),
      photographer_url: value(photo, "photographer_url", :photographer_url),
      pexels_url: value(photo, "url", :url),
      avg_color: value(photo, "avg_color", :avg_color),
      preview_url: value(src, "medium", :medium),
      landscape_url: value(src, "landscape", :landscape),
      portrait_url: value(src, "portrait", :portrait),
      original_url: value(src, "original", :original)
    }
  end

  defp error_message(body) when is_map(body) do
    body
    |> value("error", :error)
    |> non_blank_string()
  end

  defp error_message(body) when is_binary(body), do: non_blank_string(body)
  defp error_message(_body), do: nil

  defp value(map, string_key, atom_key) when is_map(map) do
    case Map.fetch(map, string_key) do
      {:ok, value} -> value
      :error -> Map.get(map, atom_key)
    end
  end

  defp value(_value, _string_key, _atom_key), do: nil

  defp put_param(params, _key, nil), do: params
  defp put_param(params, key, value), do: Keyword.put(params, key, value)

  defp put_request_option(options, _key, nil), do: options
  defp put_request_option(options, key, value), do: Keyword.put(options, key, value)

  defp endpoint do
    config_value(:endpoint)
    |> non_blank_string()
    |> then(&(&1 || @default_endpoint))
  end

  defp api_key do
    config_value(:api_key)
    |> non_blank_string()
  end

  defp config_value(key) do
    case Application.get_env(:grid_media_manager, :pexels, []) do
      config when is_list(config) -> Keyword.get(config, key)
      config when is_map(config) -> Map.get(config, key)
      _other -> nil
    end
  end

  defp non_blank_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      value -> value
    end
  end

  defp non_blank_string(_value), do: nil
end
