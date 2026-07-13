defmodule GridMediaManager.Studio.Workflow do
  @moduledoc """
  Discovers shareable moments in a campaign and turns a curated selection into media assets.

  The workflow is intentionally independent of LiveView so the same selection and generation
  pipeline can later be driven by an automated ranking or scheduling process.
  """

  alias GridMediaManager.Campaigns
  alias GridMediaManager.Campaigns.Campaign
  alias GridMediaManager.Promotion.ShareCard

  @max_candidates_per_type 24
  @formats ~w(landscape linkedin portrait carousel)

  def candidates(%Campaign{} = campaign) do
    recommended_question = Campaigns.recommended_question(campaign)

    question_sources = campaign |> ShareCard.questions() |> prefer_sourced_questions()
    recommended_question_id = recommended_question_id(question_sources, recommended_question)

    questions =
      question_sources
      |> Enum.map(&question_candidate(&1, recommended_question_id))
      |> Enum.sort_by(&if(&1.recommended?, do: 0, else: 1))
      |> Enum.take(@max_candidates_per_type)

    {recommended_questions, other_questions} = Enum.split_with(questions, & &1.recommended?)

    recommended_questions ++
      highlight_candidates(campaign) ++
      other_questions ++
      key_node_candidates(campaign) ++
      [grid_candidate(campaign)]
  end

  def default_selection(candidates) when is_list(candidates) do
    candidate =
      Enum.find(candidates, & &1.recommended?) ||
        Enum.find(candidates, &(&1.type == "highlight")) ||
        Enum.find(candidates, &(&1.type == "grid"))

    case candidate do
      nil -> MapSet.new()
      candidate -> MapSet.new([candidate.key])
    end
  end

  def selected_candidates(candidates, %MapSet{} = selected_keys) when is_list(candidates) do
    Enum.filter(candidates, &MapSet.member?(selected_keys, &1.key))
  end

  def filter_candidates(candidates, "all") when is_list(candidates), do: candidates

  def filter_candidates(candidates, type) when is_list(candidates) and is_binary(type) do
    Enum.filter(candidates, &(&1.type == type))
  end

  def generate(%Campaign{} = campaign, candidates, opts \\ []) when is_list(candidates) do
    style = opts |> Keyword.get(:style) |> ShareCard.normalize_style()
    format = normalize_format(Keyword.get(opts, :format, "landscape"))

    {assets, errors} =
      Enum.reduce(candidates, {[], []}, fn candidate, {assets, errors} ->
        case generate_candidate(campaign, candidate, style, format) do
          {:ok, generated_assets} ->
            {Enum.reverse(List.wrap(generated_assets), assets), errors}

          {:partial, generated_assets, reason} ->
            {
              Enum.reverse(List.wrap(generated_assets), assets),
              [%{candidate: candidate, reason: reason} | errors]
            }

          {:error, reason} ->
            {assets, [%{candidate: candidate, reason: reason} | errors]}
        end
      end)

    %{
      assets: assets |> Enum.reverse() |> Enum.uniq_by(& &1.id),
      errors: Enum.reverse(errors)
    }
  end

  defp generate_candidate(campaign, %{type: "grid"}, style, _format) do
    Campaigns.generate_grid_asset(campaign, style)
  end

  defp generate_candidate(campaign, %{type: "question", source_id: source_id}, style, "carousel") do
    with {:ok, image} <- Campaigns.generate_question_asset(campaign, source_id, style, "portrait") do
      case Campaigns.generate_question_short_video(campaign, source_id, style) do
        {:ok, video} -> {:ok, [image, video]}
        {:error, reason} -> {:partial, [image], {:video, reason}}
      end
    end
  end

  defp generate_candidate(campaign, %{type: "question", source_id: source_id}, style, format) do
    Campaigns.generate_question_asset(campaign, source_id, style, format)
  end

  defp generate_candidate(campaign, %{type: "highlight", source_id: source_id}, style, "carousel") do
    with {:ok, image} <-
           Campaigns.generate_highlight_asset(campaign, source_id, style, "portrait") do
      case Campaigns.generate_highlight_short_video(campaign, source_id, style) do
        {:ok, video} -> {:ok, [image, video]}
        {:error, reason} -> {:partial, [image], {:video, reason}}
      end
    end
  end

  defp generate_candidate(campaign, %{type: "highlight", source_id: source_id}, style, format) do
    Campaigns.generate_highlight_asset(campaign, source_id, style, format)
  end

  defp generate_candidate(campaign, %{type: "key_node", source_id: source_id}, style, "carousel") do
    case Campaigns.generate_key_node_carousel(campaign, source_id, style) do
      {:ok, slides} ->
        case Campaigns.generate_key_node_video(campaign, source_id, style) do
          {:ok, video} -> {:ok, slides ++ [video]}
          {:error, reason} -> {:partial, slides, {:video, reason}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp generate_candidate(campaign, %{type: "key_node", source_id: source_id}, style, format) do
    Campaigns.generate_key_node_asset(campaign, source_id, style, format)
  end

  defp generate_candidate(_campaign, _candidate, _style, _format), do: {:error, :unsupported}

  defp question_candidate(question, recommended_question_id) do
    text = map_value(question, "question") |> to_string()
    source_id = map_value(question, "id") |> to_string()
    kind = map_value(question, "kind")
    recommended? = source_id == recommended_question_id

    %{
      key: "question:#{source_id}",
      dom_id: dom_id("question", source_id),
      type: "question",
      source_id: source_id,
      title: text,
      excerpt: question_context(question, kind, recommended?),
      label: question_label(kind),
      signal: question_signal(kind, recommended?),
      recommended?: recommended?
    }
  end

  defp highlight_candidates(campaign) do
    campaign
    |> Campaigns.highlights()
    |> Enum.map(fn highlight ->
      source_id = map_value(highlight, "id")
      text = map_value(highlight, "text")
      note = map_value(highlight, "note")

      if source_id && is_binary(text) && String.trim(text) != "" do
        %{
          key: "highlight:#{source_id}",
          dom_id: dom_id("highlight", source_id),
          type: "highlight",
          source_id: to_string(source_id),
          title: text,
          excerpt:
            present_string(note) || "A passage a person chose to preserve from the conversation.",
          label: "Highlight",
          signal: "Human-curated signal",
          recommended?: false
        }
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.take(@max_candidates_per_type)
  end

  defp key_node_candidates(campaign) do
    campaign
    |> Campaigns.key_nodes()
    |> Enum.map(fn node ->
      source_id = map_value(node, "id")
      title = map_value(node, "title")

      if source_id && is_binary(title) && String.trim(title) != "" do
        node_class = map_value(node, "class") || "node"

        %{
          key: "key_node:#{source_id}",
          dom_id: dom_id("key-node", source_id),
          type: "key_node",
          source_id: to_string(source_id),
          title: title,
          excerpt: present_string(map_value(node, "excerpt")),
          label: "Key node",
          signal: "#{node_class} · structural context",
          recommended?: false
        }
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.take(@max_candidates_per_type)
  end

  defp grid_candidate(campaign) do
    %{
      key: "grid:#{campaign.id}",
      dom_id: dom_id("grid", campaign.id),
      type: "grid",
      source_id: Integer.to_string(campaign.id),
      title: campaign.title,
      excerpt: "A title card that introduces the complete grid rather than one moment within it.",
      label: "Grid overview",
      signal: "Broad entry point",
      recommended?: false
    }
  end

  defp prefer_sourced_questions(questions) do
    answer_question_texts =
      questions
      |> Enum.filter(&(map_value(&1, "kind") == "answer_question"))
      |> Enum.map(&(map_value(&1, "question") |> normalize_question()))
      |> MapSet.new()

    Enum.reject(questions, fn question ->
      map_value(question, "kind") == "follow_up_question" and
        MapSet.member?(
          answer_question_texts,
          question |> map_value("question") |> normalize_question()
        )
    end)
  end

  defp recommended_question_id(questions, recommended_question) do
    matching_questions =
      Enum.filter(questions, &(map_value(&1, "question") == recommended_question))

    question =
      Enum.find(matching_questions, &(map_value(&1, "kind") == "follow_up_question")) ||
        List.first(matching_questions)

    case question do
      nil -> nil
      question -> question |> map_value("id") |> to_string()
    end
  end

  defp question_context(question, "answer_question", recommended?) do
    answer_title = present_string(map_value(question, "answer_title")) || "an answer"
    prefix = if recommended?, do: "Recommended opener found", else: "Found"
    "#{prefix} inside “#{answer_title}”."
  end

  defp question_context(_question, _kind, true),
    do: "The strongest question-shaped invitation detected in this grid."

  defp question_context(_question, "user_question", false),
    do: "A question contributed within the grid."

  defp question_context(_question, _kind, false),
    do: "A follow-up path surfaced from the conversation."

  defp question_label("answer_question"), do: "Answer question"
  defp question_label(_kind), do: "Question"

  defp question_signal("answer_question", true), do: "Recommended · found in answer"
  defp question_signal("answer_question", false), do: "Found in answer"
  defp question_signal("user_question", true), do: "Recommended · audience question"
  defp question_signal("user_question", false), do: "Audience question"
  defp question_signal(_kind, true), do: "Recommended conversation starter"
  defp question_signal(_kind, false), do: "Follow-up question"

  defp normalize_question(question) when is_binary(question) do
    question
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, " ")
    |> String.trim()
  end

  defp normalize_question(_question), do: ""

  defp normalize_format(format) when format in @formats, do: format
  defp normalize_format(_format), do: "landscape"

  defp map_value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, String.to_existing_atom(key))
  rescue
    ArgumentError -> Map.get(map, key)
  end

  defp present_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      value -> value
    end
  end

  defp present_string(_value), do: nil

  defp dom_id(type, source_id) do
    source_id =
      source_id
      |> to_string()
      |> String.replace(~r/[^A-Za-z0-9_-]+/, "-")
      |> String.trim("-")

    "#{type}-#{if(source_id == "", do: "unknown", else: source_id)}"
  end
end
