defmodule GridMediaManager.RationalGrid.MediaPayload do
  @moduledoc """
  Extracts the stable fields this app needs from the RationalGrid promotion content payload.

  The current promotion API returns `grid` and `content`. The older endpoint shape
  returned rendered `assets` and a `raw` object; we keep backward-compatible
  readers for that older payload while treating `content` as the canonical source.
  """

  alias GridMediaManager.RationalGrid.Slug

  def campaign_attrs(payload, source_input) when is_map(payload) do
    grid = Map.get(payload, "grid", %{})
    title = string_value(Map.get(grid, "title")) || "Untitled RationalGrid"
    slug = slug_from_payload(grid, source_input, title)

    %{
      source_input: source_input,
      slug: slug,
      title: title,
      grid_url: string_value(Map.get(grid, "url")),
      graph_url: string_value(Map.get(grid, "graph_url")),
      tags: string_list(Map.get(grid, "tags", [])),
      node_count: integer_value(Map.get(grid, "node_count")),
      raw_payload: payload,
      fetched_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }
  end

  def asset_attrs(payload) when is_map(payload) do
    payload
    |> Map.get("assets", [])
    |> Enum.filter(&is_map/1)
    |> Enum.map(&asset_attr/1)
    |> Enum.reject(&is_nil(&1.url))
  end

  def origin_question(payload) when is_map(payload) do
    payload
    |> content_value("origin_question")
    |> fallback(get_in(payload, ["raw", "origin_question"]))
    |> string_value()
  end

  def first_answer(payload) when is_map(payload) do
    first_map(content_value(payload, "first_answer"), get_in(payload, ["raw", "first_answer"]))
  end

  def first_answer_excerpt(payload) when is_map(payload) do
    payload
    |> first_answer()
    |> case do
      answer when is_map(answer) -> string_value(Map.get(answer, "excerpt"))
      _ -> nil
    end
  end

  def follow_up_questions(payload) when is_map(payload) do
    payload
    |> content_or_raw_list("follow_up_questions")
    |> Enum.map(&question_text/1)
    |> Enum.reject(&is_nil/1)
  end

  def user_questions(payload) when is_map(payload) do
    payload
    |> content_or_raw_list("user_questions")
    |> Enum.filter(&is_map/1)
  end

  def key_nodes(payload) when is_map(payload) do
    payload
    |> content_or_raw_list("key_nodes")
    |> Enum.filter(&is_map/1)
  end

  def highlights(payload) when is_map(payload) do
    payload
    |> content_or_raw_list("highlights")
    |> Enum.filter(&is_map/1)
  end

  defp content_value(payload, key) do
    payload
    |> Map.get("content", %{})
    |> case do
      content when is_map(content) -> Map.get(content, key)
      _ -> nil
    end
  end

  defp content_or_raw_list(payload, key) do
    first_list(content_value(payload, key), get_in(payload, ["raw", key]))
  end

  defp first_map(first, _second) when is_map(first), do: first
  defp first_map(_first, second) when is_map(second), do: second
  defp first_map(_first, _second), do: nil

  defp first_list(first, _second) when is_list(first), do: first
  defp first_list(_first, second) when is_list(second), do: second
  defp first_list(_first, _second), do: []

  defp question_text(value) when is_binary(value), do: string_value(value)
  defp question_text(%{"question" => question}), do: string_value(question)
  defp question_text(%{question: question}), do: string_value(question)
  defp question_text(_value), do: nil

  defp asset_attr(asset) do
    %{
      title: string_value(Map.get(asset, "title")) || humanize_kind(Map.get(asset, "kind")),
      kind: string_value(Map.get(asset, "kind")) || "asset",
      url: string_value(Map.get(asset, "url")),
      mime_type: string_value(Map.get(asset, "mime_type")),
      text: string_value(Map.get(asset, "text")),
      node_id: node_id_value(Map.get(asset, "node_id")),
      highlight_id: integer_value(Map.get(asset, "highlight_id")),
      recommended_platforms: string_list(Map.get(asset, "recommended_platforms", []))
    }
  end

  defp slug_from_payload(grid, source_input, title) do
    cond do
      slug = string_value(Map.get(grid, "slug")) ->
        slug

      url = string_value(Map.get(grid, "url")) ->
        Slug.normalize!(url)

      true ->
        case Slug.normalize(source_input) do
          {:ok, slug} -> slug
          {:error, _reason} -> slugify_title(title)
        end
    end
  end

  defp slugify_title(title) do
    title
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  defp fallback(nil, fallback), do: fallback
  defp fallback("", fallback), do: fallback
  defp fallback(value, _fallback), do: value

  defp string_value(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp string_value(value) when is_integer(value), do: Integer.to_string(value)
  defp string_value(_value), do: nil

  defp node_id_value(value) when is_binary(value), do: string_value(value)
  defp node_id_value(value) when is_integer(value), do: Integer.to_string(value)
  defp node_id_value(_value), do: nil

  defp integer_value(value) when is_integer(value), do: value

  defp integer_value(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> number
      _ -> nil
    end
  end

  defp integer_value(_value), do: nil

  defp string_list(values) when is_list(values) do
    values
    |> Enum.map(&string_value/1)
    |> Enum.reject(&is_nil/1)
  end

  defp string_list(_values), do: []

  defp humanize_kind(kind) do
    kind
    |> string_value()
    |> case do
      nil -> "Media asset"
      kind -> kind |> String.replace("_", " ") |> String.capitalize()
    end
  end
end
