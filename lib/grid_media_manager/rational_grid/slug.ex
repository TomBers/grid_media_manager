defmodule GridMediaManager.RationalGrid.Slug do
  @moduledoc """
  Normalizes the internal input we accept for a RationalGrid grid.

  Internal users can paste a full grid URL, a direct media endpoint URL, or just a
  slug. The importer stores and routes by the normalized grid slug.
  """

  @slug_pattern ~r/^[a-z0-9][a-z0-9_-]*[a-z0-9]$/

  def normalize(input) when is_binary(input) do
    input = String.trim(input)

    cond do
      input == "" ->
        {:error, :blank}

      uri = parse_http_uri(input) ->
        normalize_uri(uri)

      true ->
        input
        |> String.trim("/")
        |> String.split("/", trim: true)
        |> List.last()
        |> clean_segment()
        |> validate()
    end
  end

  def normalize(_input), do: {:error, :invalid}

  def normalize!(input) do
    case normalize(input) do
      {:ok, slug} -> slug
      {:error, reason} -> raise ArgumentError, "invalid RationalGrid slug: #{inspect(reason)}"
    end
  end

  def direct_media_url?(input) when is_binary(input) do
    with %URI{scheme: scheme, host: host, path: path}
         when scheme in ["http", "https"] and is_binary(host) <- URI.parse(String.trim(input)),
         true <- is_binary(path) do
      path = String.downcase(path)
      segments = String.split(path, "/", trim: true)

      String.ends_with?(path, ".json") or "media" in segments or "media.json" in segments or
        "materials" in segments
    else
      _ -> false
    end
  end

  def direct_media_url?(_input), do: false

  defp parse_http_uri(input) do
    case URI.parse(input) do
      %URI{scheme: scheme, host: host} = uri
      when scheme in ["http", "https"] and is_binary(host) ->
        uri

      _ ->
        nil
    end
  end

  defp normalize_uri(%URI{path: path}) when is_binary(path) do
    segments = String.split(path, "/", trim: true)

    slug = slug_after(segments, "g") || slug_after(segments, "grids") || List.last(segments)

    slug
    |> clean_segment()
    |> validate()
  end

  defp normalize_uri(_uri), do: {:error, :invalid}

  defp slug_after(segments, marker) do
    case Enum.find_index(segments, &(&1 == marker)) do
      nil -> nil
      index -> Enum.at(segments, index + 1)
    end
  end

  defp clean_segment(nil), do: ""

  defp clean_segment(segment) do
    segment
    |> URI.decode()
    |> String.trim()
    |> String.trim_trailing(".json")
    |> String.downcase()
  end

  defp validate(slug) when is_binary(slug) do
    if Regex.match?(@slug_pattern, slug) do
      {:ok, slug}
    else
      {:error, :invalid}
    end
  end
end
