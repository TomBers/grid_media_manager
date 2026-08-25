defmodule GridMediaManager.Automation do
  @moduledoc """
  Persists and runs autonomous, grounded editorial planning batches.
  """

  import Ecto.Query

  alias GridMediaManager.Automation.EditorialBatch
  alias GridMediaManager.Automation.EditorialPlan
  alias GridMediaManager.Automation.BrowserRenderer
  alias GridMediaManager.Automation.LLMSelector
  alias GridMediaManager.Campaigns
  alias GridMediaManager.Campaigns.Campaign
  alias GridMediaManager.Promotion.ShareCard
  alias GridMediaManager.RationalGrid.GridIndex
  alias GridMediaManager.Repo
  alias GridMediaManager.Studio.Workflow
  alias GridMediaManager.Studio.PackageBuilder
  alias GridMediaManager.Studio.VisualDirection

  @grid_shortlist_size 10
  @discovery_source_size 120
  @candidate_shortlist_size 32
  @formats ~w(story_video portrait long_form combined_carousel)

  def create_batch(topics) when is_binary(topics) do
    topics
    |> String.split(~r/[\n,]+/u, trim: true)
    |> create_batch()
  end

  def create_batch(topics) when is_list(topics) do
    topics = Enum.map(topics, &normalize_topic/1)

    %EditorialBatch{}
    |> EditorialBatch.changeset(%{
      topics: topics,
      requested_count: length(topics),
      status: "pending",
      model: LLMSelector.model()
    })
    |> Repo.insert()
  end

  def create_batch(_topics) do
    changeset =
      EditorialBatch.changeset(%EditorialBatch{}, %{
        topics: nil,
        requested_count: 1,
        status: "pending",
        model: LLMSelector.model()
      })

    {:error, changeset}
  end

  def create_autopilot_batch(count, theme) do
    %EditorialBatch{}
    |> EditorialBatch.changeset(%{
      topics: [],
      requested_count: count,
      theme: normalize_optional_string(theme),
      status: "pending",
      model: LLMSelector.model()
    })
    |> Repo.insert()
  end

  def get_batch(id) do
    case positive_integer(id) do
      {:ok, id} -> Repo.get(EditorialBatch, id) |> Repo.preload(plans: :campaign)
      :error -> nil
    end
  end

  def get_plan(id) do
    case positive_integer(id) do
      {:ok, id} -> Repo.get(EditorialPlan, id)
      :error -> nil
    end
  end

  def list_recent_batches(limit \\ 6) do
    EditorialBatch
    |> order_by([batch], desc: batch.inserted_at)
    |> limit(^limit)
    |> preload(plans: :campaign)
    |> Repo.all()
  end

  def run_batch(%EditorialBatch{} = batch, opts \\ []) do
    claim_statuses =
      if Keyword.get(opts, :retry, false),
        do: ["pending", "partial", "failed", "completed"],
        else: ["pending"]

    case claim_batch(batch.id, claim_statuses) do
      {:ok, claimed_batch} -> run_claimed_batch(claimed_batch, opts)
      {:error, reason} -> {:error, reason}
    end
  end

  defp run_claimed_batch(batch, opts) do
    selector = Keyword.get(opts, :selector, LLMSelector)
    cover_search? = Keyword.get(opts, :cover_search, selector == LLMSelector)

    with {:ok, batch, topic_inputs} <- prepare_topic_inputs(batch, selector) do
      results =
        topic_inputs
        |> Task.async_stream(
          fn input -> plan_topic(input, selector, cover_search?) end,
          ordered: true,
          max_concurrency: 3,
          timeout: :infinity
        )
        |> Enum.map(&normalize_task_result/1)

      plans =
        results
        |> Enum.zip(topic_inputs)
        |> Enum.with_index(1)
        |> Enum.map(fn {{result, input}, position} ->
          result
          |> plan_attrs(input.topic, position)
          |> persist_plan(batch)
        end)

      planned_count = Enum.count(plans, &(&1.status == "planned"))

      status =
        cond do
          planned_count == length(plans) -> "completed"
          planned_count == 0 -> "failed"
          true -> "partial"
        end

      error_message =
        if status == "completed",
          do: nil,
          else:
            "#{length(plans) - planned_count} of #{length(plans)} topics could not be planned."

      with {:ok, _batch} <- update_batch(batch, %{status: status, error_message: error_message}) do
        {:ok, get_batch(batch.id)}
      end
    else
      {:error, reason} ->
        _result =
          update_batch(batch, %{status: "failed", error_message: error_message(reason)})

        {:error, reason}
    end
  rescue
    error ->
      _result = update_batch(batch, %{status: "failed", error_message: Exception.message(error)})
      {:error, error}
  end

  defp claim_batch(batch_id, statuses) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {claimed_count, _result} =
      EditorialBatch
      |> where([batch], batch.id == ^batch_id and batch.status in ^statuses)
      |> Repo.update_all(set: [status: "planning", error_message: nil, updated_at: now])

    case claimed_count do
      1 -> {:ok, Repo.get!(EditorialBatch, batch_id)}
      0 -> {:error, :editorial_batch_already_running}
    end
  end

  def selected_keys_for_campaign(plan_id, %Campaign{id: campaign_id}) do
    case get_plan(plan_id) do
      %EditorialPlan{campaign_id: ^campaign_id, status: "planned", selected_keys: keys} -> keys
      _plan -> []
    end
  end

  def plan_for_campaign(plan_id, %Campaign{id: campaign_id}) do
    case get_plan(plan_id) do
      %EditorialPlan{campaign_id: ^campaign_id, status: "planned"} = plan -> plan
      _plan -> nil
    end
  end

  def generate_plan_package(plan_id) do
    case get_plan(plan_id) do
      %EditorialPlan{status: "planned", campaign_id: campaign_id} = plan ->
        campaign = Campaigns.get_campaign!(campaign_id)
        PackageBuilder.generate_complete_plan(campaign, plan, Workflow.candidates(campaign))

      _plan ->
        %{assets: [], errors: [%{candidate: nil, reason: :editorial_plan_not_ready}]}
    end
  end

  @doc """
  Plans, generates, and finalizes every asset in an editorial batch.

  The function is resumable. A pending batch is planned once, generated assets are
  upserted, and renderer results distinguish completed output from browser frames
  that are still required. Pass a module implementing `Automation.Renderer` to
  `:renderer` when a different execution environment owns finalization.
  """
  def generate_batch_assets(batch_or_id, opts \\ [])

  def generate_batch_assets(%EditorialBatch{} = batch, opts) when is_list(opts) do
    renderer = Keyword.get(opts, :renderer, BrowserRenderer)
    max_concurrency = opts |> Keyword.get(:max_concurrency, 3) |> normalize_concurrency()
    renderer_opts = Keyword.get(opts, :renderer_options, [])

    with :ok <- validate_renderer(renderer),
         {:ok, batch} <- prepare_asset_batch(batch, opts) do
      plans = Enum.sort_by(batch.plans, & &1.position)

      plan_positions = Map.new(Enum.with_index(plans), fn {plan, index} -> {plan.id, index} end)

      campaign_plan_groups = plans |> Enum.group_by(& &1.campaign_id) |> Map.values()

      plan_results =
        campaign_plan_groups
        |> Task.async_stream(
          fn campaign_plans ->
            Enum.map(campaign_plans, &generate_plan_assets(&1, renderer, renderer_opts))
          end,
          ordered: true,
          max_concurrency: max_concurrency,
          timeout: :infinity
        )
        |> Enum.zip(campaign_plan_groups)
        |> Enum.flat_map(&normalize_plan_group_task/1)
        |> Enum.sort_by(&Map.fetch!(plan_positions, &1.plan_id))

      {:ok,
       %{
         batch_id: batch.id,
         status: aggregate_status(plan_results),
         plans: plan_results
       }}
    end
  end

  def generate_batch_assets(batch_id, opts) when is_list(opts) do
    case get_batch(batch_id) do
      %EditorialBatch{} = batch -> generate_batch_assets(batch, opts)
      nil -> {:error, :editorial_batch_not_found}
    end
  end

  def platforms_for_format("story_video"), do: ["tiktok", "instagram", "youtube"]
  def platforms_for_format("portrait"), do: ["x", "linkedin", "facebook"]
  def platforms_for_format("long_form"), do: ["linkedin", "facebook"]

  def platforms_for_format("combined_carousel"),
    do: ["x", "linkedin", "facebook", "tiktok", "instagram", "youtube"]

  def platforms_for_format(_format), do: []

  def shortlist_grids(topic) when is_binary(topic) do
    topic = normalize_topic(topic)

    GridIndex.list()
    |> Enum.sort_by(&grid_score(&1, topic), :desc)
    |> Enum.take(@grid_shortlist_size)
  end

  def shortlist_candidates(topic, candidates) when is_binary(topic) and is_list(candidates) do
    ranked = Enum.sort_by(candidates, &candidate_score(&1, topic), :desc)

    (Enum.take(ranked, @candidate_shortlist_size - 8) ++ Enum.take(candidates, 8))
    |> Enum.uniq_by(& &1.key)
    |> Enum.take(@candidate_shortlist_size)
  end

  def discovery_sources(theme) do
    all_sources = GridIndex.list()
    recent = Enum.take(all_sources, div(@discovery_source_size, 2))

    themed =
      case normalize_optional_string(theme) do
        nil ->
          []

        theme ->
          all_sources
          |> Enum.sort_by(&grid_score(&1, theme), :desc)
          |> Enum.take(div(@discovery_source_size, 2))
      end

    (themed ++ recent ++ Enum.take_random(all_sources, 20))
    |> Enum.uniq_by(& &1.slug)
    |> Enum.take(@discovery_source_size)
  end

  defp prepare_topic_inputs(%EditorialBatch{topics: []} = batch, selector) do
    sources = discovery_sources(batch.theme)

    with :ok <- ensure_present(sources, :no_matching_grids),
         {:ok, choice} <- selector.select_topics(batch.requested_count, batch.theme, sources),
         {:ok, inputs} <- validate_topic_choices(choice, sources, batch.requested_count),
         topics = Enum.map(inputs, & &1.topic),
         {:ok, batch} <- update_batch(batch, %{topics: topics}) do
      {:ok, batch, inputs}
    end
  end

  defp prepare_topic_inputs(%EditorialBatch{} = batch, _selector) do
    {:ok, batch, Enum.map(batch.topics, &%{topic: &1, source_choice: nil, source: nil})}
  end

  defp prepare_asset_batch(%EditorialBatch{} = batch, opts) do
    batch = get_batch(batch.id)

    cond do
      batch.status == "pending" or Keyword.get(opts, :replan, false) ->
        planning_opts =
          opts |> Keyword.take([:selector, :cover_search]) |> Keyword.put(:retry, true)

        run_batch(batch, planning_opts)

      batch.status == "planning" ->
        {:error, :editorial_batch_already_running}

      true ->
        {:ok, batch}
    end
  end

  defp generate_plan_assets(%EditorialPlan{status: "planned"} = plan, renderer, renderer_opts) do
    case generate_plan_package(plan.id) do
      %{assets: assets, errors: generation_errors} ->
        asset_results = Enum.map(assets, &render_asset(plan, &1, renderer, renderer_opts))
        render_errors = render_errors(asset_results)
        errors = Enum.map(generation_errors, &generation_error/1) ++ render_errors

        %{
          plan_id: plan.id,
          topic: plan.topic,
          status: plan_status(asset_results, errors),
          assets: asset_results,
          errors: errors
        }
    end
  rescue
    error -> failed_plan(plan, {:exception, Exception.message(error)})
  end

  defp generate_plan_assets(%EditorialPlan{} = plan, _renderer, _renderer_opts) do
    failed_plan(plan, plan.error_message || :editorial_plan_not_ready)
  end

  defp render_asset(plan, asset, renderer, renderer_opts) do
    campaign = Campaigns.get_campaign!(plan.campaign_id)

    base = asset_result_base(asset)

    case renderer.render(campaign, asset, renderer_opts) do
      {:ok, details} when is_map(details) ->
        Map.merge(base, %{status: :complete, output: details, error: nil})

      {:pending, details} when is_map(details) ->
        Map.merge(base, %{status: :awaiting_artifacts, output: details, error: nil})

      {:error, reason} ->
        Map.merge(base, %{status: :failed, output: nil, error: reason})

      response ->
        Map.merge(base, %{
          status: :failed,
          output: nil,
          error: {:invalid_renderer_response, response}
        })
    end
  rescue
    error ->
      Map.merge(asset_result_base(asset), %{
        status: :failed,
        output: nil,
        error: {:renderer_exception, Exception.message(error)}
      })
  end

  defp asset_result_base(asset) do
    %{
      asset_id: asset.id,
      kind: asset.kind,
      mime_type: asset.mime_type
    }
  end

  defp generation_error(%{candidate: candidate, reason: reason}) do
    %{stage: :generation, candidate: candidate, reason: reason}
  end

  defp generation_error(error), do: %{stage: :generation, reason: error}

  defp render_errors(asset_results) do
    for %{status: :failed, asset_id: asset_id, error: reason} <- asset_results do
      %{stage: :rendering, asset_id: asset_id, reason: reason}
    end
  end

  defp plan_status([], _errors), do: :failed

  defp plan_status(asset_results, errors) do
    statuses = Enum.map(asset_results, & &1.status)

    cond do
      errors != [] and Enum.all?(statuses, &(&1 == :failed)) -> :failed
      errors != [] -> :partial
      Enum.any?(statuses, &(&1 == :awaiting_artifacts)) -> :awaiting_artifacts
      Enum.all?(statuses, &(&1 == :complete)) -> :complete
      true -> :partial
    end
  end

  defp failed_plan(plan, reason) do
    %{
      plan_id: plan.id,
      topic: plan.topic,
      status: :failed,
      assets: [],
      errors: [%{stage: :planning, reason: reason}]
    }
  end

  defp normalize_plan_group_task({{:ok, results}, _campaign_plans}), do: results

  defp normalize_plan_group_task({{:exit, reason}, campaign_plans}) do
    Enum.map(campaign_plans, &failed_plan(&1, {:task_exit, reason}))
  end

  defp aggregate_status([]), do: :failed

  defp aggregate_status(plan_results) do
    statuses = Enum.map(plan_results, & &1.status)

    cond do
      Enum.all?(statuses, &(&1 == :complete)) -> :complete
      Enum.all?(statuses, &(&1 == :failed)) -> :failed
      Enum.any?(statuses, &(&1 in [:failed, :partial])) -> :partial
      Enum.any?(statuses, &(&1 == :awaiting_artifacts)) -> :awaiting_artifacts
      true -> :partial
    end
  end

  defp validate_renderer(renderer) when is_atom(renderer) do
    with {:module, ^renderer} <- Code.ensure_loaded(renderer),
         true <- function_exported?(renderer, :render, 3) do
      :ok
    else
      _error -> {:error, :invalid_renderer}
    end
  end

  defp validate_renderer(_renderer), do: {:error, :invalid_renderer}

  defp normalize_concurrency(value) when is_integer(value) and value > 0, do: min(value, 10)
  defp normalize_concurrency(_value), do: 3

  defp plan_topic(input, selector, cover_search?) do
    topic = input.topic

    with {:ok, source_choice, source} <- choose_source(input, selector),
         {:ok, campaign} <- load_campaign(source.slug),
         candidates <- shortlist_candidates(topic, Workflow.candidates(campaign)),
         :ok <- ensure_present(candidates, :no_story_candidates),
         {:ok, story_choice} <- selector.select_story(topic, campaign, candidates),
         {:ok, story} <- validate_story_choice(story_choice, candidates),
         cover <- VisualDirection.resolve_cover(selector, topic, story, cover_search?) do
      {:ok,
       %{
         campaign_id: campaign.id,
         source_slug: source.slug,
         source_title: source.title,
         selected_keys: story.selected_keys,
         hook: story.hook,
         rationale: story.rationale,
         recommended_format: story.recommended_format,
         recommended_platforms: platforms_for_format(story.recommended_format),
         confidence: min(source_choice["confidence"], story.confidence) / 1,
         status: "planned",
         error_message: nil,
         selection_details: %{
           "source_rationale" => source_choice["rationale"],
           "source_confidence" => source_choice["confidence"],
           "story_confidence" => story.confidence,
           "text_visual_key" => story.text_visual_key,
           "text_visual_role" => story.text_visual_role,
           "format_rationale" => story.format_rationale,
           "visual_style" => story.visual_style,
           "visual_rationale" => story.visual_rationale,
           "cover_search_query" => story.cover_search_query,
           "cover_brief" => story.cover_brief,
           "cover" => cover,
           "moments" => preview_moments(story.selected_keys, candidates)
         }
       }}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp choose_source(%{source_choice: choice, source: source}, _selector)
       when is_map(choice) and not is_nil(source),
       do: {:ok, choice, source}

  defp choose_source(%{topic: topic}, selector) do
    sources = shortlist_grids(topic)

    with :ok <- ensure_present(sources, :no_matching_grids),
         {:ok, choice} <- selector.select_grid(topic, sources),
         {:ok, source} <- validate_source_choice(choice, sources) do
      {:ok, choice, source}
    end
  end

  defp validate_topic_choices(%{"topics" => choices}, sources, count)
       when is_list(choices) and length(choices) == count do
    sources_by_slug = Map.new(sources, &{&1.slug, &1})

    inputs =
      Enum.map(choices, fn choice ->
        source = Map.get(sources_by_slug, choice["source_slug"])

        if is_map(source) and present_string?(choice["topic"]) and
             present_string?(choice["rationale"]) and valid_confidence?(choice["confidence"]) do
          %{
            topic: String.trim(choice["topic"]),
            source: source,
            source_choice: choice
          }
        end
      end)

    distinct_topics = inputs |> Enum.map(&String.downcase(&1.topic)) |> Enum.uniq()
    distinct_sources = inputs |> Enum.map(& &1.source.slug) |> Enum.uniq()

    if Enum.all?(inputs, &is_map/1) and length(distinct_topics) == count and
         length(distinct_sources) == count do
      {:ok, inputs}
    else
      {:error, :invalid_topic_selection}
    end
  rescue
    _error -> {:error, :invalid_topic_selection}
  end

  defp validate_topic_choices(_choice, _sources, _count),
    do: {:error, :invalid_topic_selection}

  defp validate_source_choice(choice, sources) when is_map(choice) do
    slug = choice["source_slug"]
    confidence = choice["confidence"]
    rationale = choice["rationale"]

    with %{slug: ^slug} = source <- Enum.find(sources, &(&1.slug == slug)),
         true <- is_number(confidence) and confidence >= 0 and confidence <= 1,
         true <- present_string?(rationale) do
      {:ok, source}
    else
      _invalid -> {:error, :invalid_source_selection}
    end
  end

  defp validate_source_choice(_choice, _sources), do: {:error, :invalid_source_selection}

  defp validate_story_choice(choice, candidates) when is_map(choice) do
    available_keys = MapSet.new(candidates, & &1.key)

    selected_keys =
      choice
      |> Map.get("selected_keys", [])
      |> Enum.filter(&is_binary/1)
      |> Enum.uniq()

    minimum = min(2, MapSet.size(available_keys))
    confidence = choice["confidence"]
    recommended_format = choice["recommended_format"]
    visual_style = choice["visual_style"]
    cover_mode = choice["cover_mode"]
    text_visual_key = choice["text_visual_key"]
    text_visual_role = choice["text_visual_role"]

    valid? =
      length(selected_keys) in minimum..min(6, MapSet.size(available_keys)) and
        Enum.all?(selected_keys, &MapSet.member?(available_keys, &1)) and
        present_string?(choice["hook"]) and
        text_visual_key in selected_keys and
        text_visual_role in ["question", "quotation", "evidence", "cover"] and
        present_string?(choice["rationale"]) and
        recommended_format in @formats and
        present_string?(choice["format_rationale"]) and
        Enum.any?(ShareCard.styles(), &(&1.id == visual_style)) and
        present_string?(choice["visual_rationale"]) and
        cover_mode in ["photo", "text"] and
        present_string?(choice["cover_search_query"]) and
        present_string?(choice["cover_brief"]) and
        is_number(confidence) and confidence >= 0 and confidence <= 1

    if valid? do
      {:ok,
       %{
         selected_keys: selected_keys,
         hook: choice["hook"],
         text_visual_key: text_visual_key,
         text_visual_role: text_visual_role,
         rationale: choice["rationale"],
         recommended_format: recommended_format,
         format_rationale: choice["format_rationale"],
         visual_style: visual_style,
         visual_rationale: choice["visual_rationale"],
         cover_mode: cover_mode,
         cover_search_query: choice["cover_search_query"] |> String.trim(),
         cover_brief: choice["cover_brief"],
         confidence: confidence / 1
       }}
    else
      {:error, :invalid_story_selection}
    end
  end

  defp validate_story_choice(_choice, _candidates), do: {:error, :invalid_story_selection}

  defp preview_moments(selected_keys, candidates) do
    candidates_by_key = Map.new(candidates, &{&1.key, &1})

    Enum.map(selected_keys, fn key ->
      candidate = Map.fetch!(candidates_by_key, key)

      %{
        "key" => candidate.key,
        "title" => candidate.title,
        "context" => candidate.excerpt,
        "type" => candidate.type,
        "provenance" => candidate.provenance,
        "label" => candidate.label
      }
    end)
  end

  defp load_campaign(slug) do
    case Campaigns.get_campaign_by_slug(slug) do
      %Campaign{} = campaign -> {:ok, campaign}
      nil -> Campaigns.import_grid(slug)
    end
  end

  defp persist_plan(attrs, batch) do
    attrs = sanitize_postgres_json(attrs)
    existing = Repo.get_by(EditorialPlan, editorial_batch_id: batch.id, position: attrs.position)

    (existing || %EditorialPlan{})
    |> EditorialPlan.changeset(Map.put(attrs, :editorial_batch_id, batch.id))
    |> then(fn changeset ->
      if existing, do: Repo.update!(changeset), else: Repo.insert!(changeset)
    end)
  end

  defp sanitize_postgres_json(value) when is_binary(value),
    do: String.replace(value, <<0>>, "")

  defp sanitize_postgres_json(value) when is_list(value),
    do: Enum.map(value, &sanitize_postgres_json/1)

  defp sanitize_postgres_json(value) when is_map(value) do
    Map.new(value, fn {key, item} ->
      {sanitize_postgres_json(key), sanitize_postgres_json(item)}
    end)
  end

  defp sanitize_postgres_json(value), do: value

  defp plan_attrs({:ok, attrs}, topic, position) do
    attrs
    |> Map.put(:topic, topic)
    |> Map.put(:position, position)
  end

  defp plan_attrs({:error, reason}, topic, position) do
    %{
      topic: topic,
      position: position,
      status: "failed",
      selected_keys: [],
      selection_details: %{},
      error_message: error_message(reason)
    }
  end

  defp normalize_task_result({:ok, result}), do: result
  defp normalize_task_result({:exit, reason}), do: {:error, {:task_exit, reason}}

  defp update_batch(batch, attrs) do
    batch
    |> EditorialBatch.changeset(attrs)
    |> Repo.update()
  end

  defp grid_score(grid, topic) do
    topic_tokens = tokens(topic)
    title = grid.title || ""
    tag_text = Enum.join(grid.tags || [], " ")
    haystack_tokens = tokens(title <> " " <> tag_text)
    overlap = MapSet.intersection(topic_tokens, haystack_tokens) |> MapSet.size()
    exact_tag? = Enum.any?(grid.tags || [], &(String.downcase(&1) == String.downcase(topic)))

    overlap * 12 +
      if(exact_tag?, do: 20, else: 0) +
      String.jaro_distance(String.downcase(topic), String.downcase(title)) * 8 +
      min(grid.node_count || 0, 20) / 20
  end

  defp candidate_score(candidate, topic) do
    topic_tokens = tokens(topic)
    text = Enum.join([candidate.title || "", candidate.excerpt || ""], " ")
    overlap = MapSet.intersection(topic_tokens, tokens(text)) |> MapSet.size()

    overlap * 10 +
      if(candidate.recommended?, do: 8, else: 0) +
      if(candidate.type == "highlight", do: 6, else: 0) +
      if(candidate.type == "question", do: 4, else: 0) +
      if(candidate.type == "key_node" and candidate.node_class == "answer", do: 5, else: 0)
  end

  defp tokens(text) do
    normalized = text |> to_string() |> String.downcase()

    ~r/[\p{L}\p{N}]{3,}/u
    |> Regex.scan(normalized)
    |> List.flatten()
    |> MapSet.new()
  end

  defp ensure_present([], reason), do: {:error, reason}
  defp ensure_present(_items, _reason), do: :ok

  defp normalize_topic(topic) when is_binary(topic), do: String.trim(topic)
  defp normalize_topic(topic), do: to_string(topic) |> String.trim()

  defp positive_integer(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp positive_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} when integer > 0 -> {:ok, integer}
      _result -> :error
    end
  end

  defp positive_integer(_value), do: :error

  defp present_string?(value), do: is_binary(value) and String.trim(value) != ""
  defp valid_confidence?(value), do: is_number(value) and value >= 0 and value <= 1

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      value -> value
    end
  end

  defp normalize_optional_string(_value), do: nil

  defp error_message({:llm_request_failed, message}),
    do: "Editorial model request failed: #{message}"

  defp error_message(:openai_not_configured), do: "OPENAI_API_KEY is not configured."
  defp error_message(:no_matching_grids), do: "No RationalGrid sources are available."
  defp error_message(:no_story_candidates), do: "The selected grid has no usable story moments."

  defp error_message(:invalid_topic_selection),
    do: "The model did not return distinct grounded topics."

  defp error_message(reason), do: "Could not create an editorial plan: #{inspect(reason)}"
end
