defmodule GridMediaManager.Automation do
  @moduledoc """
  Persists and runs autonomous, grounded editorial planning batches.
  """

  import Ecto.Query

  alias GridMediaManager.Automation.EditorialBatch
  alias GridMediaManager.Automation.EditorialPlan
  alias GridMediaManager.Automation.BrowserRenderer
  alias GridMediaManager.Automation.LLMSelector
  alias GridMediaManager.Automation.LLMEditor
  alias GridMediaManager.Campaigns
  alias GridMediaManager.Campaigns.Campaign
  alias GridMediaManager.Campaigns.MediaAsset
  alias GridMediaManager.Promotion.ArtifactStore
  alias GridMediaManager.Promotion.ShareCard
  alias GridMediaManager.RationalGrid.GridIndex
  alias GridMediaManager.Repo
  alias GridMediaManager.Social.Buffer
  alias GridMediaManager.Social.Platforms
  alias GridMediaManager.Studio.Workflow
  alias GridMediaManager.Studio.PackageBuilder
  alias GridMediaManager.Studio.VisualDirection

  @grid_shortlist_size 10
  @discovery_source_size 120
  @candidate_shortlist_size 32
  @formats ~w(story_video portrait long_form combined_carousel)
  @package_generation_version 6
  @publishing_times %{
    "linkedin" => ~T[16:30:00],
    "facebook" => ~T[17:30:00],
    "instagram" => ~T[15:22:00],
    "tiktok" => ~T[19:13:00],
    "youtube" => ~T[19:05:00],
    "x" => ~T[19:05:00]
  }

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
      {:ok, id} ->
        plans_query =
          from plan in EditorialPlan, order_by: [asc: plan.position], preload: :campaign

        Repo.get(EditorialBatch, id) |> Repo.preload(plans: plans_query)

      :error ->
        nil
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

  @doc """
  Schedules the canonical six destination drafts for every generated plan in a batch.

  The operation preflights artifacts, copy limits, future dates, and live Buffer
  vacancies before submitting anything. Drafts that already have a Buffer post ID
  are returned unchanged, making an interrupted run safe to resume.
  """
  def schedule_batch(batch_or_id, start_date, opts \\ [])

  def schedule_batch(%EditorialBatch{id: id}, start_date, opts),
    do: schedule_batch(id, start_date, opts)

  def schedule_batch(batch_id, start_date, opts) when is_list(opts) do
    with %EditorialBatch{} = batch <- get_batch(batch_id),
         {:ok, start_date} <- parse_start_date(start_date),
         {:ok, jobs} <- publishing_jobs(batch, start_date, opts),
         :ok <- preflight_publishing_jobs(jobs),
         {:ok, queue} <- Buffer.queue_snapshot(Platforms.ids()),
         :ok <- ensure_queue_capacity(queue, jobs) do
      schedule_publishing_jobs(jobs, Keyword.get(opts, :max_concurrency, 3))
    else
      nil -> {:error, :editorial_batch_not_found}
      {:error, _reason} = error -> error
    end
  end

  def schedule_batch(_batch_id, _start_date, _opts), do: {:error, :invalid_options}

  @doc """
  Runs a senior-editor assessment against every complete generated package in a batch.

  Reviews are persisted in each plan's `selection_details` and can be safely rerun.
  """
  def review_batch(batch_or_id, opts \\ [])

  def review_batch(%EditorialBatch{id: id}, opts), do: review_batch(id, opts)

  def review_batch(batch_id, opts) when is_list(opts) do
    editor = Keyword.get(opts, :editor, LLMEditor)
    force? = Keyword.get(opts, :force, true)
    requested_plan_ids = Keyword.get(opts, :plan_ids)

    with %EditorialBatch{} = batch <- get_batch(batch_id),
         :ok <- validate_editor(editor) do
      results =
        batch.plans
        |> Enum.filter(&(&1.status == "planned"))
        |> Enum.filter(&(is_nil(requested_plan_ids) or &1.id in requested_plan_ids))
        |> Task.async_stream(&review_plan(&1, editor, force?),
          ordered: true,
          max_concurrency: normalize_concurrency(Keyword.get(opts, :max_concurrency, 3)),
          timeout: :infinity
        )
        |> Enum.map(fn
          {:ok, result} -> result
          {:exit, reason} -> %{status: :failed, error: {:task_exit, reason}}
        end)

      status = if Enum.all?(results, &(&1.status == :complete)), do: :complete, else: :partial
      {:ok, %{batch_id: batch.id, status: status, plans: results}}
    else
      nil -> {:error, :editorial_batch_not_found}
      {:error, _reason} = error -> error
    end
  end

  def review_batch(_batch_id, _opts), do: {:error, :invalid_options}

  @doc """
  Generates and reviews a batch, then performs a bounded feedback-guided revision pass.

  Reviews tied to the same canonical asset IDs are reused when browser rendering resumes.
  """
  def prepare_quality_batch(batch_id, opts \\ [])

  def prepare_quality_batch(batch_id, opts) when is_list(opts) do
    threshold = opts |> Keyword.get(:quality_threshold, 75) |> normalize_quality_threshold()
    max_revisions = opts |> Keyword.get(:max_revisions, 1) |> normalize_revision_limit()
    selector = Keyword.get(opts, :selector, LLMSelector)
    editor = Keyword.get(opts, :editor, LLMEditor)
    plan_ids = Keyword.get(opts, :plan_ids)

    generation_opts =
      Keyword.take(opts, [
        :selector,
        :cover_search,
        :renderer,
        :renderer_options,
        :max_concurrency
      ])

    with {:ok, generation} <- generate_batch_assets(batch_id, generation_opts),
         {:ok, review} <-
           review_batch(batch_id, editor: editor, force: false, plan_ids: plan_ids),
         {:ok, refinements} <-
           refine_low_scoring_plans(
             batch_id,
             review,
             selector,
             threshold,
             max_revisions,
             plan_ids
           ),
         {:ok, final_generation, final_review} <-
           regenerate_refined_batch(
             batch_id,
             generation,
             review,
             refinements,
             generation_opts,
             editor,
             plan_ids
           ) do
      {:ok,
       %{
         batch_id: batch_id,
         generation: final_generation,
         review: final_review,
         refinements: refinements,
         quality_threshold: threshold
       }}
    end
  end

  def prepare_quality_batch(_batch_id, _opts), do: {:error, :invalid_options}

  def platforms_for_format("story_video"), do: ["tiktok", "instagram", "youtube"]
  def platforms_for_format("portrait"), do: ["x", "linkedin", "facebook"]
  def platforms_for_format("long_form"), do: ["linkedin", "facebook"]

  def platforms_for_format("combined_carousel"),
    do: ["x", "linkedin", "facebook", "tiktok", "instagram", "youtube"]

  def platforms_for_format(_format), do: []

  defp review_plan(%EditorialPlan{} = plan, editor, force?) do
    with {:ok, assets} <- reusable_plan_assets(plan),
         %Campaign{} = campaign <- Campaigns.get_campaign(plan.campaign_id),
         drafts <- Campaigns.list_post_drafts_for_assets(campaign, Enum.map(assets, & &1.id)),
         {:ok, review} <- assess_or_reuse_review(plan, assets, drafts, campaign, editor, force?) do
      review =
        review
        |> stringify_map_keys()
        |> Map.put(
          "reviewed_at",
          DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
        )
        |> Map.put("model", LLMSelector.model())
        |> Map.put("generated_asset_ids", Enum.map(assets, & &1.id))
        |> Map.put("generated_asset_signatures", asset_review_signatures(assets))

      details = Map.put(plan.selection_details || %{}, "editor_review", review)

      plan
      |> EditorialPlan.changeset(%{selection_details: details})
      |> Repo.update!()

      %{plan_id: plan.id, status: :complete, review: review}
    else
      :regenerate -> %{plan_id: plan.id, status: :failed, error: :assets_not_generated}
      nil -> %{plan_id: plan.id, status: :failed, error: :campaign_not_found}
      {:error, reason} -> %{plan_id: plan.id, status: :failed, error: reason}
    end
  end

  defp assess_or_reuse_review(plan, assets, drafts, campaign, editor, false) do
    review = get_in(plan.selection_details || %{}, ["editor_review"])

    if is_map(review) and
         review["generated_asset_signatures"] == asset_review_signatures(assets) do
      {:ok, review}
    else
      editor.assess(plan, campaign, assets, drafts)
    end
  end

  defp assess_or_reuse_review(plan, assets, drafts, campaign, editor, true),
    do: editor.assess(plan, campaign, assets, drafts)

  defp asset_review_signatures(assets) do
    Enum.map(assets, fn asset ->
      %{
        "id" => asset.id,
        "render_signature" => get_in(asset.metadata || %{}, ["render_signature"])
      }
    end)
  end

  defp validate_editor(editor) when is_atom(editor) do
    with {:module, ^editor} <- Code.ensure_loaded(editor),
         true <- function_exported?(editor, :assess, 4) do
      :ok
    else
      _error -> {:error, :invalid_editor}
    end
  end

  defp validate_editor(_editor), do: {:error, :invalid_editor}

  defp stringify_map_keys(value) when is_map(value) do
    Map.new(value, fn {key, item} -> {to_string(key), stringify_map_keys(item)} end)
  end

  defp stringify_map_keys(value) when is_list(value), do: Enum.map(value, &stringify_map_keys/1)
  defp stringify_map_keys(value), do: value

  defp refine_low_scoring_plans(
         batch_id,
         review_result,
         selector,
         threshold,
         max_revisions,
         plan_ids
       ) do
    batch = get_batch(batch_id)
    reviews = Map.new(review_result.plans, &{&1.plan_id, &1})

    results =
      batch.plans
      |> Enum.filter(&(is_nil(plan_ids) or &1.id in plan_ids))
      |> Enum.map(fn plan ->
        result = Map.get(reviews, plan.id)
        revision_count = Map.get(plan.selection_details || %{}, "quality_revision_count", 0)

        cond do
          is_nil(result) or result.status != :complete ->
            %{plan_id: plan.id, status: :skipped, reason: :review_unavailable}

          quality_pass?(result.review, threshold) ->
            %{plan_id: plan.id, status: :passed, score: result.review["overall_score"]}

          revision_count >= max_revisions ->
            %{plan_id: plan.id, status: :limit_reached, score: result.review["overall_score"]}

          publishing_locked?(plan) ->
            %{plan_id: plan.id, status: :publishing_locked, score: result.review["overall_score"]}

          true ->
            refine_plan(plan, selector, result.review)
        end
      end)

    failures = Enum.filter(results, &(&1.status == :failed))
    if failures == [], do: {:ok, results}, else: {:error, {:quality_refinement_failed, failures}}
  end

  defp refine_plan(%EditorialPlan{} = plan, selector, review) do
    campaign = Campaigns.get_campaign!(plan.campaign_id)
    candidates = shortlist_candidates(plan.topic, Workflow.candidates(campaign))

    with true <-
           function_exported?(selector, :revise_story, 5) || {:error, :revision_not_supported},
         {:ok, choice} <- selector.revise_story(plan.topic, campaign, candidates, plan, review),
         {:ok, story} <- validate_story_choice(choice, candidates) do
      old_details = plan.selection_details || %{}
      history = Map.get(old_details, "quality_history", [])

      details =
        old_details
        |> Map.drop([
          "generated_asset_ids",
          "package_generation_version",
          "renderer_version",
          "campaign_visual_fingerprint",
          "editor_review"
        ])
        |> Map.merge(%{
          "text_visual_key" => story.text_visual_key,
          "text_visual_role" => story.text_visual_role,
          "format_rationale" => story.format_rationale,
          "visual_style" => story.visual_style,
          "visual_rationale" => story.visual_rationale,
          "cover_search_query" => story.cover_search_query,
          "cover_brief" => story.cover_brief,
          "cover" => revised_cover(selector, plan.topic, story, old_details),
          "moments" => preview_moments(story.selected_keys, candidates),
          "quality_revision_count" => Map.get(old_details, "quality_revision_count", 0) + 1,
          "quality_history" =>
            history ++
              [
                %{
                  "hook" => plan.hook,
                  "selected_keys" => plan.selected_keys,
                  "review" => review
                }
              ]
        })

      {:ok, updated} =
        plan
        |> EditorialPlan.changeset(%{
          selected_keys: story.selected_keys,
          hook: story.hook,
          rationale: story.rationale,
          recommended_format: story.recommended_format,
          recommended_platforms: platforms_for_format(story.recommended_format),
          confidence: story.confidence,
          selection_details: details
        })
        |> Repo.update()

      %{plan_id: updated.id, status: :revised, previous_score: review["overall_score"]}
    else
      {:error, reason} -> %{plan_id: plan.id, status: :failed, reason: reason}
      false -> %{plan_id: plan.id, status: :failed, reason: :revision_not_supported}
    end
  end

  defp revised_cover(LLMSelector, topic, story, _details),
    do: VisualDirection.resolve_cover(LLMSelector, topic, story, true)

  defp revised_cover(_selector, _topic, _story, details),
    do: Map.get(details, "cover", %{"mode" => "text"})

  defp publishing_locked?(plan) do
    with {:ok, assets} <- reusable_plan_assets(plan),
         %Campaign{} = campaign <- Campaigns.get_campaign(plan.campaign_id) do
      campaign
      |> Campaigns.list_post_drafts_for_assets(Enum.map(assets, & &1.id))
      |> Enum.any?(&(&1.status in ["scheduled", "published"]))
    else
      _missing -> false
    end
  end

  defp regenerate_refined_batch(
         batch_id,
         generation,
         review,
         refinements,
         generation_opts,
         editor,
         plan_ids
       ) do
    if Enum.any?(refinements, &(&1.status == :revised)) do
      with {:ok, generation} <- generate_batch_assets(batch_id, generation_opts),
           {:ok, review} <-
             review_batch(batch_id, editor: editor, force: false, plan_ids: plan_ids) do
        {:ok, generation, review}
      end
    else
      {:ok, generation, review}
    end
  end

  defp quality_pass?(review, threshold) do
    review["overall_score"] >= threshold and review["thematic_consistency_score"] >= threshold and
      review["interest_score"] >= threshold and review["shareability_score"] >= threshold
  end

  defp normalize_quality_threshold(value) when is_integer(value), do: min(max(value, 0), 100)
  defp normalize_quality_threshold(_value), do: 75
  defp normalize_revision_limit(value) when is_integer(value), do: min(max(value, 0), 2)
  defp normalize_revision_limit(_value), do: 1

  defp publishing_jobs(%EditorialBatch{} = batch, start_date, opts) do
    times = Map.merge(@publishing_times, Keyword.get(opts, :times, %{}))

    batch.plans
    |> Enum.filter(&(&1.status == "planned"))
    |> Enum.sort_by(& &1.position)
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {plan, offset}, {:ok, jobs} ->
      case plan_publishing_jobs(plan, Date.add(start_date, offset), times) do
        {:ok, plan_jobs} -> {:cont, {:ok, jobs ++ plan_jobs}}
        {:error, reason} -> {:halt, {:error, %{plan_id: plan.id, reason: reason}}}
      end
    end)
  end

  defp plan_publishing_jobs(%EditorialPlan{} = plan, date, times) do
    with {:ok, assets} <- reusable_plan_assets(plan),
         {:ok, destinations} <- canonical_destinations(assets),
         %Campaign{} = campaign <- Campaigns.get_campaign(plan.campaign_id) do
      drafts = Campaigns.list_post_drafts_for_assets(campaign, Enum.map(assets, & &1.id))

      jobs =
        Enum.map(destinations, fn {platform, asset} ->
          draft = Enum.find(drafts, &(&1.platform == platform and &1.media_asset_id == asset.id))

          %{
            plan_id: plan.id,
            campaign_id: campaign.id,
            platform: platform,
            asset: asset,
            draft: draft,
            scheduled_for: scheduled_datetime(date, Map.fetch!(times, platform))
          }
        end)

      {:ok, jobs}
    else
      :regenerate -> {:error, :assets_not_generated}
      nil -> {:error, :campaign_not_found}
      {:error, _reason} = error -> error
    end
  end

  defp canonical_destinations(assets) do
    long_form = Enum.find(assets, &(&1.kind == "long_form_post"))
    x_post = Enum.find(assets, &(&1.kind == "curated_carousel"))
    video = Enum.find(assets, &(&1.kind == "curated_carousel_video"))

    if long_form && x_post && video do
      {:ok,
       [
         {"linkedin", long_form},
         {"facebook", long_form},
         {"x", x_post},
         {"instagram", video},
         {"tiktok", video},
         {"youtube", video}
       ]}
    else
      {:error, :canonical_package_incomplete}
    end
  end

  defp preflight_publishing_jobs(jobs) do
    now = DateTime.utc_now()

    Enum.reduce_while(jobs, :ok, fn job, :ok ->
      indexes = Campaigns.media_asset_slide_indexes(job.asset)

      reason =
        cond do
          is_nil(job.draft) -> :canonical_draft_missing
          job.draft.status == "scheduled" and is_binary(job.draft.external_post_id) -> nil
          not Platforms.within_limit?(job.draft.body, job.platform) -> :copy_limit_exceeded
          not ArtifactStore.ready?(job.asset, indexes) -> :artifacts_not_ready
          DateTime.compare(job.scheduled_for, now) != :gt -> :schedule_not_in_future
          true -> nil
        end

      if reason, do: {:halt, {:error, publishing_error(job, reason)}}, else: {:cont, :ok}
    end)
  end

  defp ensure_queue_capacity(%{platforms: platforms}, jobs) do
    required =
      jobs
      |> Enum.reject(&(&1.draft.status == "scheduled" and is_binary(&1.draft.external_post_id)))
      |> Enum.frequencies_by(& &1.platform)

    case Enum.find(required, fn {platform, count} ->
           get_in(platforms, [platform, :vacancies]) < count
         end) do
      nil -> :ok
      {platform, count} -> {:error, {:insufficient_queue_capacity, platform, count}}
    end
  end

  defp schedule_publishing_jobs(jobs, max_concurrency) do
    results =
      Task.async_stream(jobs, &schedule_publishing_job/1,
        ordered: true,
        max_concurrency: normalize_concurrency(max_concurrency),
        timeout: :infinity
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, reason} -> {:error, %{reason: {:task_exit, reason}}}
      end)

    failures = for {:error, failure} <- results, do: failure
    completed = for {:ok, post} <- results, do: post

    if failures == [] do
      {:ok, %{status: :complete, posts: completed}}
    else
      {:error, %{failed: failures, completed: completed}}
    end
  end

  defp schedule_publishing_job(job) do
    if job.draft.status == "scheduled" and is_binary(job.draft.external_post_id) do
      {:ok, publishing_result(job, job.draft, :already_scheduled)}
    else
      case Campaigns.schedule_post_draft(job.draft.id, job.scheduled_for) do
        {:ok, draft} -> {:ok, publishing_result(job, draft, :scheduled)}
        {:error, reason} -> {:error, publishing_error(job, reason)}
      end
    end
  end

  defp publishing_result(job, draft, status) do
    %{
      plan_id: job.plan_id,
      platform: job.platform,
      draft_id: draft.id,
      external_post_id: draft.external_post_id,
      scheduled_for: draft.scheduled_for,
      status: status
    }
  end

  defp publishing_error(job, reason) do
    %{
      plan_id: job.plan_id,
      platform: job.platform,
      draft_id: job.draft && job.draft.id,
      reason: reason
    }
  end

  defp scheduled_datetime(date, %Time{} = time) do
    {:ok, naive} = NaiveDateTime.new(date, time)
    DateTime.from_naive!(naive, "Etc/UTC")
  end

  defp parse_start_date(%Date{} = date), do: {:ok, date}

  defp parse_start_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      {:error, _reason} -> {:error, :invalid_start_date}
    end
  end

  defp parse_start_date(_value), do: {:error, :invalid_start_date}

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
    case generated_plan_package(plan) do
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

  defp generated_plan_package(%EditorialPlan{} = plan) do
    case reusable_plan_assets(plan) do
      {:ok, assets} ->
        %{assets: assets, errors: []}

      :regenerate ->
        result = generate_plan_package(plan.id)

        if result.errors == [] and result.assets != [] do
          persist_generated_assets(plan, result.assets)
        end

        result
    end
  end

  defp reusable_plan_assets(%EditorialPlan{} = plan) do
    details = plan.selection_details || %{}
    ids = Map.get(details, "generated_asset_ids", [])

    if Map.get(details, "package_generation_version") == @package_generation_version and
         Map.get(details, "renderer_version") == ArtifactStore.renderer_version() and
         Map.get(details, "campaign_visual_fingerprint") ==
           campaign_visual_fingerprint(plan.campaign_id) and
         length(ids) == 3 and Enum.all?(ids, &is_integer/1) do
      assets =
        MediaAsset
        |> where([asset], asset.campaign_id == ^plan.campaign_id and asset.id in ^ids)
        |> Repo.all()
        |> Map.new(&{&1.id, &1})

      case Enum.map(ids, &Map.get(assets, &1)) do
        [first, second, third] = ordered
        when not is_nil(first) and not is_nil(second) and not is_nil(third) ->
          {:ok, ordered}

        _missing ->
          :regenerate
      end
    else
      :regenerate
    end
  end

  defp persist_generated_assets(%EditorialPlan{} = plan, assets) do
    details =
      (plan.selection_details || %{})
      |> Map.put("generated_asset_ids", Enum.map(assets, & &1.id))
      |> Map.put("package_generation_version", @package_generation_version)
      |> Map.put("renderer_version", ArtifactStore.renderer_version())
      |> Map.put("campaign_visual_fingerprint", campaign_visual_fingerprint(plan.campaign_id))

    plan
    |> EditorialPlan.changeset(%{selection_details: details})
    |> Repo.update!()
  end

  defp campaign_visual_fingerprint(campaign_id) do
    case Campaigns.get_campaign(campaign_id) do
      %Campaign{} = campaign ->
        %{
          mode: Campaigns.title_card_mode(campaign),
          background: Campaigns.pexels_background(campaign)
        }
        |> :erlang.term_to_binary()
        |> then(&:crypto.hash(:sha256, &1))
        |> Base.encode16(case: :lower)

      nil ->
        nil
    end
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
