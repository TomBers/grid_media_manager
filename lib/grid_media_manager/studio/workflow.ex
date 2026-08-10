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
  @formats ~w(landscape linkedin portrait carousel combined_carousel story_video long_form)

  def candidates(%Campaign{} = campaign) do
    recommended_question = Campaigns.recommended_question(campaign)
    conversation_context = conversation_context(campaign)

    question_sources = campaign |> ShareCard.questions() |> prefer_sourced_questions()
    recommended_question_id = recommended_question_id(question_sources, recommended_question)

    questions =
      question_sources
      |> Enum.map(&question_candidate(&1, recommended_question_id))
      |> Enum.take(@max_candidates_per_type)

    (questions ++
       highlight_candidates(campaign) ++
       key_node_candidates(campaign) ++
       [grid_candidate(campaign)])
    |> Enum.map(&attach_conversation_context(&1, conversation_context))
    |> remove_duplicate_prompt_nodes()
    |> cognitive_order()
  end

  def default_selection(candidates) when is_list(candidates), do: MapSet.new()

  def selected_candidates(candidates, %MapSet{} = selected_keys) when is_list(candidates) do
    Enum.filter(candidates, &MapSet.member?(selected_keys, &1.key))
  end

  def selected_candidates(candidates, selected_order)
      when is_list(candidates) and is_list(selected_order) do
    candidates_by_key = Map.new(candidates, &{&1.key, &1})

    selected_order
    |> Enum.map(&Map.get(candidates_by_key, &1))
    |> Enum.reject(&is_nil/1)
  end

  def filter_candidates(candidates, "all") when is_list(candidates), do: candidates

  def filter_candidates(candidates, type) when is_list(candidates) and is_binary(type) do
    Enum.filter(candidates, &(&1.type == type))
  end

  def generate(%Campaign{} = campaign, candidates, opts \\ []) when is_list(candidates) do
    case Campaigns.get_campaign(campaign.id) do
      nil ->
        %{assets: [], errors: [%{candidate: List.first(candidates), reason: :campaign_not_found}]}

      %Campaign{} = campaign ->
        generate_for_campaign(campaign, candidates, opts)
    end
  end

  defp generate_for_campaign(campaign, candidates, opts) do
    style = opts |> Keyword.get(:style) |> ShareCard.normalize_style()
    format = normalize_format(Keyword.get(opts, :format, "landscape"))

    result =
      cond do
        format == "combined_carousel" ->
          generate_combined_carousel(campaign, candidates, style)

        format == "story_video" ->
          generate_story_video(campaign, candidates, style)

        format == "long_form" ->
          generate_long_form_post(campaign, candidates, style)

        format == "portrait" ->
          generate_text_carousel(campaign, candidates, style)

        true ->
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

    assign_generation_batch(result)
  end

  defp generate_text_carousel(campaign, candidates, style) do
    case Campaigns.generate_curated_carousel(campaign, candidates, style) do
      {:ok, carousel} ->
        %{assets: [carousel], errors: []}

      {:error, reason} ->
        candidate = List.first(candidates) || %{title: campaign.title}
        %{assets: [], errors: [%{candidate: candidate, reason: reason}]}
    end
  end

  defp assign_generation_batch(%{assets: []} = result), do: result

  defp assign_generation_batch(%{assets: assets} = result) do
    case Campaigns.assign_generation_batch(assets) do
      {:ok, updated_assets} -> %{result | assets: updated_assets}
      {:error, _reason} -> result
    end
  end

  defp generate_combined_carousel(campaign, candidates, style) do
    case Campaigns.generate_curated_carousel_bundle(campaign, candidates, style) do
      {:ok, carousel} ->
        case Campaigns.generate_curated_carousel_video(campaign, carousel) do
          {:ok, video} ->
            %{assets: [carousel, video], errors: []}

          {:error, reason} ->
            candidate = List.first(candidates) || %{title: campaign.title}

            %{
              assets: [carousel],
              errors: [%{candidate: candidate, reason: {:video, reason}}]
            }
        end

      {:error, reason} ->
        candidate = List.first(candidates) || %{title: campaign.title}
        %{assets: [], errors: [%{candidate: candidate, reason: reason}]}
    end
  end

  defp generate_story_video(campaign, candidates, style) do
    case candidates do
      [%{type: "key_node", source_id: source_id} = candidate] ->
        case Campaigns.generate_key_node_video(campaign, source_id, style) do
          {:ok, video} ->
            %{assets: [video], errors: []}

          {:error, reason} ->
            %{assets: [], errors: [%{candidate: candidate, reason: {:video, reason}}]}
        end

      _ ->
        generate_story_video_from_carousel(campaign, candidates, style)
    end
  end

  defp generate_story_video_from_carousel(campaign, candidates, style) do
    case Campaigns.generate_curated_carousel_for_video(campaign, candidates, style) do
      {:ok, carousel} ->
        case Campaigns.generate_curated_carousel_video(campaign, carousel) do
          {:ok, video} ->
            %{assets: [video], errors: []}

          {:error, reason} ->
            candidate = List.first(candidates) || %{title: campaign.title}
            %{assets: [], errors: [%{candidate: candidate, reason: {:video, reason}}]}
        end

      {:error, reason} ->
        candidate = List.first(candidates) || %{title: campaign.title}
        %{assets: [], errors: [%{candidate: candidate, reason: reason}]}
    end
  end

  defp generate_long_form_post(campaign, candidates, style) do
    case Campaigns.generate_long_form_post(campaign, candidates, style) do
      {:ok, asset} ->
        %{assets: [asset], errors: []}

      {:error, reason} ->
        candidate = List.first(candidates) || %{title: campaign.title}
        %{assets: [], errors: [%{candidate: candidate, reason: reason}]}
    end
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
      node_id: present_string(map_value(question, "node_id")),
      title: text,
      excerpt: question_context(question, kind, recommended?),
      label: question_label(kind),
      signal: question_signal(kind, recommended?),
      character_count: String.length(text),
      slide_count: 1,
      node_class: "question",
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
          node_id: present_string(map_value(highlight, "node_id")),
          title: text,
          excerpt:
            present_string(note) || "A passage a person chose to preserve from the conversation.",
          label: "Highlight",
          signal: "Human-curated signal",
          character_count: String.length(text),
          slide_count: 1,
          node_class: "highlight",
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
    |> Enum.reject(fn node ->
      node
      |> map_value("id")
      |> to_string()
      |> String.downcase()
      |> then(&(&1 in ["main"]))
    end)
    |> Enum.map(fn node ->
      source_id = map_value(node, "id")
      title = map_value(node, "title")

      if source_id && is_binary(title) && String.trim(title) != "" do
        node_class = map_value(node, "class") || "node"
        reading_slides = ShareCard.node_reading_slides(campaign, node)

        content_slides =
          Enum.reject(reading_slides, &(Map.get(&1, "kind") in ["node_title", "cta"]))

        character_count =
          [title | Enum.map(content_slides, &Map.get(&1, "body", ""))]
          |> Enum.join(" ")
          |> String.length()

        %{
          key: "key_node:#{source_id}",
          dom_id: dom_id("key-node", source_id),
          type: "key_node",
          source_id: to_string(source_id),
          node_id: to_string(source_id),
          title: title,
          excerpt: present_string(map_value(node, "excerpt")),
          label: node_label(node_class),
          signal: node_signal(node_class),
          character_count: character_count,
          slide_count: max(length(content_slides), 1),
          node_class: node_class,
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
      character_count: String.length(campaign.title || ""),
      slide_count: 1,
      node_class: "grid",
      recommended?: false
    }
  end

  defp node_label("origin"), do: "Origin question"
  defp node_label(node_class) when node_class in ["question", "user"], do: "Question"
  defp node_label("answer"), do: "Answer"
  defp node_label(_node_class), do: "Node"

  defp node_signal("origin"), do: "Starting point"
  defp node_signal(node_class) when node_class in ["question", "user"], do: "Prompt in stream"
  defp node_signal("answer"), do: "Answer in stream"
  defp node_signal(_node_class), do: "Structural context"

  defp prefer_sourced_questions(questions) do
    Enum.uniq_by(questions, &(map_value(&1, "question") |> normalize_question()))
  end

  defp conversation_context(%Campaign{raw_payload: payload}) do
    graph = map_value(payload || %{}, "graph") || %{}
    nodes = map_value(graph, "nodes") || []
    edges = map_value(graph, "edges") || []

    node_classes =
      Map.new(nodes, fn node ->
        {present_string(map_value(node, "id")),
         node |> map_value("class") |> present_string() |> to_string() |> String.downcase()}
      end)

    answer_to_prompt =
      Enum.reduce(edges, %{}, fn edge, pairs ->
        edge = map_value(edge, "data") || edge
        source = present_string(map_value(edge, "source"))
        target = present_string(map_value(edge, "target"))

        if Map.get(node_classes, source) in ["origin", "question", "user"] and
             Map.get(node_classes, target) == "answer" do
          Map.put(pairs, target, source)
        else
          pairs
        end
      end)

    question_to_previous_answer =
      Enum.reduce(edges, %{}, fn edge, pairs ->
        edge = map_value(edge, "data") || edge
        source = present_string(map_value(edge, "source"))
        target = present_string(map_value(edge, "target"))

        if Map.get(node_classes, source) == "answer" and
             Map.get(node_classes, target) in ["question", "user"] do
          Map.put(pairs, target, source)
        else
          pairs
        end
      end)

    %{
      answer_to_prompt: answer_to_prompt,
      question_to_previous_answer: question_to_previous_answer
    }
  end

  defp attach_conversation_context(%{node_id: node_id} = candidate, context)
       when is_binary(node_id) and node_id != "" do
    thread_id = Map.get(context.answer_to_prompt, node_id, node_id)
    previous_answer_id = Map.get(context.question_to_previous_answer, node_id)

    continues_from_thread_id =
      if previous_answer_id do
        Map.get(context.answer_to_prompt, previous_answer_id, previous_answer_id)
      end

    candidate
    |> Map.put(:thread_id, thread_id)
    |> Map.put(:continues_from_thread_id, continues_from_thread_id)
  end

  defp attach_conversation_context(candidate, _context) do
    candidate
    |> Map.put(:thread_id, nil)
    |> Map.put(:continues_from_thread_id, nil)
  end

  defp remove_duplicate_prompt_nodes(candidates) do
    question_node_ids =
      candidates
      |> Enum.filter(&(&1.type == "question" and is_binary(&1.node_id)))
      |> MapSet.new(& &1.node_id)

    Enum.reject(candidates, fn candidate ->
      candidate.type == "key_node" and candidate.node_class in ["question", "user"] and
        MapSet.member?(question_node_ids, candidate.node_id)
    end)
  end

  defp cognitive_order(candidates) do
    candidates
    |> Enum.with_index()
    |> Enum.sort_by(fn {candidate, discovery_index} ->
      {
        stream_order(candidate.thread_id),
        cognitive_role_order(candidate),
        candidate_detail_order(candidate, discovery_index)
      }
    end)
    |> Enum.map(&elem(&1, 0))
  end

  defp cognitive_role_order(candidate) do
    cond do
      candidate.type == "grid" -> 9
      candidate.node_id == candidate.thread_id and candidate.type == "question" -> 0
      candidate.node_id == candidate.thread_id and candidate.node_class == "origin" -> 0
      candidate.type == "key_node" and candidate.node_class == "answer" -> 1
      candidate.type == "highlight" -> 2
      candidate.type == "question" -> 3
      candidate.type == "key_node" -> 4
      true -> 8
    end
  end

  defp candidate_detail_order(%{type: "highlight", source_id: source_id}, _discovery_index),
    do: stream_order(source_id)

  defp candidate_detail_order(_candidate, discovery_index), do: {0, discovery_index}

  defp stream_order(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> {0, integer}
      _ -> {1, value}
    end
  end

  defp stream_order(_value), do: {2, ""}

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

  defp question_label("answer_question"), do: "Question"
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

  defp present_string(value) when is_integer(value), do: Integer.to_string(value)

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
