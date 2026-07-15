defmodule GridMediaManager.RationalGrid.MediaPayload do
  @moduledoc """
  Extracts the stable fields this app needs from RationalGrid promotion payloads.

  Canonical response shape:

      %{
        "metadata" => %{...},
        "graph" => %{"nodes" => [], "edges" => []},
        "highlights" => []
      }

  Older `grid`/`content` and `raw`/`assets` response shapes remain supported while
  the API settles.
  """

  alias GridMediaManager.RationalGrid.Slug
  alias GridMediaManager.TextNormalizer

  def campaign_attrs(payload, source_input) when is_map(payload) do
    metadata = metadata(payload)

    title =
      string_value(field(metadata, "title")) || origin_question(payload) ||
        "Untitled RationalGrid"

    slug = slug_from_payload(metadata, source_input, title)

    %{
      source_input: source_input,
      slug: slug,
      title: title,
      grid_url: string_value(field(metadata, "url")),
      graph_url: string_value(field(metadata, "graph_url")),
      tags: string_list(field(metadata, "tags")),
      node_count: integer_value(field(metadata, "node_count")) || length(graph_nodes(payload)),
      raw_payload: payload,
      fetched_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }
  end

  def asset_attrs(payload) when is_map(payload) do
    payload
    |> field("assets")
    |> case do
      assets when is_list(assets) -> assets
      _ -> []
    end
    |> Enum.filter(&is_map/1)
    |> Enum.map(&asset_attr/1)
    |> Enum.reject(&is_nil(&1.url))
  end

  def origin_question(payload) when is_map(payload) do
    content_value(payload, "origin_question") ||
      get_in_string(payload, ["raw", "origin_question"]) ||
      origin_node_question(payload) ||
      string_value(field(metadata(payload), "title"))
  end

  def first_answer(payload) when is_map(payload) do
    first_map([
      content_value(payload, "first_answer"),
      get_in_string(payload, ["raw", "first_answer"]),
      first_answer_node(payload)
    ])
  end

  def first_answer_excerpt(payload) when is_map(payload) do
    payload
    |> first_answer()
    |> case do
      answer when is_map(answer) ->
        string_value(field(answer, "excerpt")) || excerpt_from_text(field(answer, "content"))

      _ ->
        nil
    end
  end

  def answer_questions(payload) when is_map(payload) do
    origin = origin_question(payload)

    payload
    |> answer_sources()
    |> Enum.flat_map(fn answer ->
      answer
      |> answer_texts()
      |> Enum.flat_map(&extract_questions_from_text/1)
      |> Enum.reject(&same_question?(&1, origin))
      |> Enum.map(fn question ->
        %{
          "question" => question,
          "node_id" => node_id(answer),
          "answer_title" => node_title(answer)
        }
      end)
    end)
    |> Enum.uniq_by(&normalize_question(&1["question"]))
  end

  def follow_up_questions(payload) when is_map(payload) do
    explicit =
      payload
      |> content_or_raw_list("follow_up_questions")
      |> Enum.map(&question_text/1)
      |> Enum.filter(&question_text?/1)
      |> Enum.reject(&is_nil/1)

    extracted = extracted_questions(payload)
    origin = origin_question(payload)

    (explicit ++ extracted)
    |> unique_strings()
    |> Enum.reject(&same_question?(&1, origin))
  end

  def recommended_question(payload) when is_map(payload) do
    payload
    |> follow_up_questions()
    |> Enum.max_by(&question_score/1, fn -> nil end)
  end

  def user_questions(payload) when is_map(payload) do
    explicit =
      payload
      |> content_or_raw_list("user_questions")
      |> Enum.filter(&is_map/1)

    if explicit != [] do
      explicit
    else
      payload
      |> graph_nodes()
      |> Enum.filter(&question_node?/1)
      |> Enum.map(&question_node_to_map/1)
      |> Enum.reject(&is_nil(field(&1, "question")))
    end
  end

  def key_nodes(payload) when is_map(payload) do
    explicit =
      payload
      |> content_or_raw_list("key_nodes")
      |> Enum.filter(&is_map/1)

    if explicit != [] do
      explicit
    else
      payload
      |> graph_nodes()
      |> Enum.map(&normalize_node/1)
      |> Enum.reject(&is_nil/1)
    end
  end

  def highlights(payload) when is_map(payload) do
    first_list([
      field(payload, "highlights"),
      content_value(payload, "highlights"),
      get_in_string(payload, ["raw", "highlights"])
    ])
    |> Enum.filter(&is_map/1)
  end

  defp metadata(payload) do
    first_map([field(payload, "metadata"), field(payload, "grid")]) || %{}
  end

  defp graph_nodes(payload) do
    payload
    |> field("graph")
    |> case do
      graph when is_map(graph) -> first_list([field(graph, "nodes")])
      _ -> []
    end
  end

  defp origin_node_question(payload) do
    payload
    |> graph_nodes()
    |> Enum.find_value(fn node ->
      if node_class(node) == "origin" do
        node_question_text(node)
      end
    end)
  end

  defp answer_sources(payload) do
    answer_nodes = payload |> graph_nodes() |> Enum.filter(&answer_node?/1)

    if answer_nodes == [] do
      case first_answer(payload) do
        answer when is_map(answer) -> [answer]
        _ -> []
      end
    else
      answer_nodes
    end
  end

  defp answer_texts(answer) do
    [node_content(answer), field(answer, "excerpt")]
    |> Enum.map(&string_value/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp first_answer_node(payload) do
    payload
    |> graph_nodes()
    |> Enum.find(&answer_node?/1)
    |> case do
      node when is_map(node) ->
        %{
          "node_id" => node_id(node),
          "title" => node_title(node),
          "content" => node_content(node),
          "excerpt" => node_excerpt(node)
        }

      _ ->
        nil
    end
  end

  defp normalize_node(node) when is_map(node) do
    id = node_id(node)
    title = node_title(node)
    excerpt = node_excerpt(node)

    if id || title || excerpt do
      %{
        "id" => id,
        "class" => node_class(node) || "node",
        "title" => title || excerpt || "Node #{id}",
        "excerpt" => excerpt || title || "",
        "content" => node_content(node)
      }
    end
  end

  defp normalize_node(_node), do: nil

  defp question_node_to_map(node) do
    %{
      "node_id" => node_id(node),
      "question" => node_question_text(node)
    }
  end

  defp question_node?(node), do: node_class(node) in ["question", "user"]

  defp answer_node?(node), do: node_class(node) == "answer"

  defp node_id(node), do: node |> first_value(["id", "node_id"]) |> node_id_value()

  defp node_class(node) do
    node
    |> first_value(["class", "type", "sort_class"])
    |> string_value()
    |> case do
      nil -> nil
      class -> String.downcase(class)
    end
  end

  defp node_title(node) do
    first_value(node, ["title", "label", "question"])
    |> string_value()
    |> fallback(first_markdown_heading(node_content(node)))
    |> fallback(node_question_text(node))
    |> excerpt_from_text(140)
  end

  defp node_content(node), do: first_value(node, ["content", "text", "body", "markdown"])

  defp node_excerpt(node) do
    first_value(node, ["excerpt", "summary", "description"])
    |> string_value()
    |> fallback(excerpt_from_text(node_content(node)))
  end

  defp node_question_text(node) do
    candidates = [
      first_value(node, ["question", "title", "label"]),
      node_content(node),
      first_value(node, ["excerpt"])
    ]

    candidates
    |> Enum.find_value(fn candidate ->
      candidate
      |> string_value()
      |> extract_questions_from_text()
      |> List.first()
    end)
    |> fallback(first_value(node, ["question", "title", "label"]) |> string_value())
  end

  defp extracted_questions(payload) do
    payload
    |> strings_from_content()
    |> Enum.flat_map(&extract_questions_from_text/1)
    |> unique_strings()
  end

  defp strings_from_content(payload) do
    payload
    |> collect_strings()
    |> Enum.filter(fn string ->
      String.contains?(string, "?") and not String.starts_with?(string, "http")
    end)
  end

  defp collect_strings(value) when is_binary(value), do: [value]

  defp collect_strings(value) when is_list(value), do: Enum.flat_map(value, &collect_strings/1)

  defp collect_strings(value) when is_map(value) do
    value
    |> Enum.reject(fn {key, _value} ->
      key in ["url", :url, "api_url", :api_url, "graph_url", :graph_url]
    end)
    |> Enum.flat_map(fn {_key, value} -> collect_strings(value) end)
  end

  defp collect_strings(_value), do: []

  defp extract_questions_from_text(nil), do: []

  defp extract_questions_from_text(text) do
    text
    |> string_value()
    |> case do
      nil -> ""
      string -> string
    end
    |> String.replace(~r/\s+/, " ")
    |> then(&Regex.scan(~r/[^?.!]*(?:\?|\?+)/u, &1))
    |> List.flatten()
    |> Enum.map(&clean_question/1)
    |> Enum.filter(&question_text?/1)
    |> unique_strings()
  end

  defp clean_question(question) do
    question
    |> String.replace(~r/^[-*#>\s"“”]+/, "")
    |> String.trim()
  end

  defp question_text?(question) when is_binary(question) do
    (String.ends_with?(question, "?") or String.ends_with?(question, "...")) and
      String.length(question) >= 8 and
      not String.contains?(question, ["/", "\\", "://", "www.", ".com", ".ai"])
  end

  defp question_text?(_question), do: false

  defp question_score(question) when is_binary(question) do
    question = TextNormalizer.normalize_binary(question)
    words = Regex.scan(~r/[[:alpha:]]+/u, question) |> length()
    length_score = min(words, 18)

    question_word_score =
      if Regex.match?(~r/\b(why|how|what|can|could|would|should|does|is|if)\b/i, question),
        do: 8,
        else: 0

    length_score + question_word_score
  end

  defp same_question?(question, origin) when is_binary(question) and is_binary(origin) do
    normalize_question(question) == normalize_question(origin)
  end

  defp same_question?(_question, _origin), do: false

  defp normalize_question(question) do
    question
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, " ")
    |> String.trim()
  end

  defp content_value(payload, key) do
    payload
    |> field("content")
    |> case do
      content when is_map(content) -> field(content, key)
      _ -> nil
    end
  end

  defp content_or_raw_list(payload, key) do
    first_list([content_value(payload, key), get_in_string(payload, ["raw", key])])
  end

  defp first_map(values) when is_list(values), do: Enum.find(values, &is_map/1)

  defp first_list(values) when is_list(values) do
    Enum.find(values, &is_list/1) || []
  end

  defp question_text(value) when is_binary(value), do: string_value(value)
  defp question_text(%{"question" => question}), do: string_value(question)
  defp question_text(%{question: question}), do: string_value(question)
  defp question_text(_value), do: nil

  defp asset_attr(asset) do
    %{
      title: string_value(field(asset, "title")) || humanize_kind(field(asset, "kind")),
      kind: string_value(field(asset, "kind")) || "asset",
      url: string_value(field(asset, "url")),
      mime_type: string_value(field(asset, "mime_type")),
      text: string_value(field(asset, "text")),
      node_id: node_id_value(field(asset, "node_id")),
      highlight_id: integer_value(field(asset, "highlight_id")),
      recommended_platforms: string_list(field(asset, "recommended_platforms"))
    }
  end

  defp slug_from_payload(metadata, source_input, title) do
    cond do
      slug = string_value(field(metadata, "slug")) ->
        slug

      url = string_value(field(metadata, "url")) ->
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
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  defp first_markdown_heading(nil), do: nil

  defp first_markdown_heading(text) do
    text
    |> string_value()
    |> case do
      nil ->
        nil

      text ->
        Regex.run(~r/(?:^|\n)\s*#+\s+([^\n]+)/, text, capture: :all_but_first)
        |> case do
          [heading] -> heading
          _ -> nil
        end
    end
  end

  defp excerpt_from_text(text, max_length \\ 220)
  defp excerpt_from_text(nil, _max_length), do: nil

  defp excerpt_from_text(text, max_length) do
    text
    |> string_value()
    |> case do
      nil -> nil
      string -> string |> strip_markdown() |> truncate_string(max_length)
    end
  end

  defp strip_markdown(text) do
    text
    |> String.replace(~r/^\s*#+\s*/m, "")
    |> String.replace(~r/\*\*([^*]+)\*\*/, "\\1")
    |> String.replace(~r/\[([^\]]+)\]\([^\)]+\)/, "\\1")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp field(map, key) when is_map(map), do: Map.get(map, key) || Map.get(map, atom_key(key))
  defp field(_map, _key), do: nil

  defp first_value(map, keys), do: Enum.find_value(keys, &field(map, &1))

  defp get_in_string(map, keys) do
    Enum.reduce_while(keys, map, fn key, acc ->
      case field(acc, key) do
        nil -> {:halt, nil}
        value -> {:cont, value}
      end
    end)
  end

  defp atom_key("api_url"), do: :api_url
  defp atom_key("assets"), do: :assets
  defp atom_key("body"), do: :body
  defp atom_key("class"), do: :class
  defp atom_key("content"), do: :content
  defp atom_key("description"), do: :description
  defp atom_key("edges"), do: :edges
  defp atom_key("excerpt"), do: :excerpt
  defp atom_key("first_answer"), do: :first_answer
  defp atom_key("follow_up_questions"), do: :follow_up_questions
  defp atom_key("graph"), do: :graph
  defp atom_key("graph_url"), do: :graph_url
  defp atom_key("grid"), do: :grid
  defp atom_key("highlight_id"), do: :highlight_id
  defp atom_key("highlights"), do: :highlights
  defp atom_key("id"), do: :id
  defp atom_key("key_nodes"), do: :key_nodes
  defp atom_key("kind"), do: :kind
  defp atom_key("label"), do: :label
  defp atom_key("markdown"), do: :markdown
  defp atom_key("metadata"), do: :metadata
  defp atom_key("mime_type"), do: :mime_type
  defp atom_key("name"), do: :name
  defp atom_key("node_count"), do: :node_count
  defp atom_key("node_id"), do: :node_id
  defp atom_key("nodes"), do: :nodes
  defp atom_key("note"), do: :note
  defp atom_key("origin_question"), do: :origin_question
  defp atom_key("question"), do: :question
  defp atom_key("raw"), do: :raw
  defp atom_key("recommended_platforms"), do: :recommended_platforms
  defp atom_key("slug"), do: :slug
  defp atom_key("sort_class"), do: :sort_class
  defp atom_key("summary"), do: :summary
  defp atom_key("tags"), do: :tags
  defp atom_key("text"), do: :text
  defp atom_key("title"), do: :title
  defp atom_key("type"), do: :type
  defp atom_key("url"), do: :url
  defp atom_key("user_questions"), do: :user_questions
  defp atom_key(_key), do: :__unknown_key__

  defp fallback(nil, fallback), do: fallback
  defp fallback("", fallback), do: fallback
  defp fallback(value, _fallback), do: value

  defp string_value(value) when is_binary(value) do
    value = value |> TextNormalizer.normalize_binary() |> String.trim()
    if value == "", do: nil, else: value
  end

  defp string_value(value) when is_integer(value), do: Integer.to_string(value)
  defp string_value(value) when is_float(value), do: Float.to_string(value)
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

  defp unique_strings(strings) do
    strings
    |> Enum.map(&string_value/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp truncate_string(text, max) when is_binary(text) and max > 1 do
    if String.length(text) <= max do
      text
    else
      text
      |> String.slice(0, max - 1)
      |> String.trim()
      |> Kernel.<>("…")
    end
  end

  defp humanize_kind(kind) do
    kind
    |> string_value()
    |> case do
      nil -> "Media asset"
      kind -> kind |> String.replace("_", " ") |> String.capitalize()
    end
  end
end
