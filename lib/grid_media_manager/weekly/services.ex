defmodule GridMediaManager.Weekly.Services do
  @moduledoc false
  alias GridMediaManager.{Automation, Campaigns, Repo}
  alias GridMediaManager.Automation.EditorialPlan
  alias GridMediaManager.RationalGrid.{MCP, Explorations, Accounts}
  alias GridMediaManager.Social.{Buffer, Performance, Platforms, Tracking}
  alias GridMediaManager.Weekly.{Editor, Evidence, Validation, SourceSelector}
  alias GridMediaManager.Studio.VisualDirection

  def snapshot do
    with {:ok, queue} <- queue() do
      if Enum.all?(queue.platforms, fn {_, c} -> c.vacancies == 0 end) do
        {:ok,
         %{
           queue: queue,
           evidence: %{
             "note" => "Queues are full; no new generation or metrics refresh was needed."
           }
         }}
      else
        with %{status: "connected"} <-
               Accounts.connection() || {:error, :reauthorization_required},
             true <-
               GridMediaManager.Automation.LLMSelector.configured?() ||
                 {:error, :openai_not_configured},
             {:ok, _} <- Performance.refresh_if_stale() do
          {:ok, %{queue: queue, evidence: Evidence.snapshot()}}
        else
          %{status: _} -> {:error, :reauthorization_required}
          error -> error
        end
      end
    end
  end

  def queue(platforms \\ Platforms.ids()), do: Buffer.queue_snapshot(platforms)

  def proposals(run),
    do:
      Editor.proposals(
        run.story_count,
        run.theme,
        run.evidence,
        Enum.map(Explorations.list(), & &1.question)
      )

  def plan(run, story) do
    with {:ok, campaign} <- Explorations.create_campaign(story.exploration_id) do
      Automation.plan_campaign(run.batch_id, campaign.id, story.position,
        selector: SourceSelector,
        cover_search: false
      )
    end
  end

  def copy(run, story) do
    plan = Automation.get_plan(story.plan_id)

    with {:ok, copy} <-
           Editor.copy(plan, Campaigns.get_campaign!(plan.campaign_id), run.theme, story.error) do
      {:ok, Validation.normalise(copy)}
    end
  end

  def apply_copy(run, story) do
    plan = Automation.get_plan(story.plan_id)
    c = Campaigns.get_campaign!(plan.campaign_id)
    copy = story.copy

    with [] <- Validation.copy_issues(copy, run.theme) do
      cover = get_in(plan.selection_details, ["cover"])

      cover =
        if cover["status"] == "not_searched",
          do: search_cover(copy["cover_search_query"]),
          else: cover

      details =
        Map.merge(plan.selection_details, %{
          "video_script" => copy["video_script"],
          "cover" => cover,
          "weekly_copy_version" => 1
        })

      {:ok, plan} =
        plan
        |> EditorialPlan.changeset(%{hook: copy["hook"], selection_details: details})
        |> Repo.update()

      result = Automation.generate_plan_package(plan.id)

      if result.errors != [] do
        {:error, :package_generation_failed}
      else
        with {:ok, details} <- apply_assets(c, result.assets, copy),
             {:ok, _} <-
               Automation.remember_plan_assets(
                 plan.id,
                 Enum.map(details.asset_ids, &Campaigns.get_media_asset!/1)
               ) do
          {:ok, details}
        end
      end
    else
      issues when is_list(issues) -> {:error, {:copy_issues, issues}}
    end
  end

  defp apply_assets(c, assets, copy) do
    x = Enum.find(assets, &(&1.kind == "curated_carousel"))
    index = Enum.find_index(x.metadata["slides"], &(&1["kind"] not in ["cover", "cta"]))

    {:ok, x} =
      Campaigns.update_media_asset_slide(x, index + 1, %{
        "title" => copy["idea_card"],
        "body" => ""
      })

    slides =
      List.update_at(
        x.metadata["slides"],
        index,
        &Map.merge(&1, %{"kind" => "node_text", "label" => "The tension"})
      )

    x |> Ecto.Changeset.change(metadata: Map.put(x.metadata, "slides", slides)) |> Repo.update!()

    Enum.each(assets, fn a ->
      a = Campaigns.get_media_asset!(a.id)

      indexes =
        case a.kind do
          "long_form_post" ->
            [1, length(a.metadata["slides"])]

          "curated_carousel" ->
            a.metadata["slides"]
            |> Enum.with_index(1)
            |> Enum.reject(fn {s, _} -> s["kind"] == "cover" end)
            |> Enum.map(&elem(&1, 1))

          _ ->
            Campaigns.media_asset_slide_indexes(a)
        end

      a
      |> Ecto.Changeset.change(metadata: Map.put(a.metadata, "selected_slide_indexes", indexes))
      |> Repo.update!()
    end)

    drafts = Campaigns.list_post_drafts_for_assets(c, Enum.map(assets, & &1.id))

    changes =
      for platform <- Platforms.ids() do
        asset = destination(assets, platform)
        draft = Enum.find(drafts, &(&1.platform == platform and &1.media_asset_id == asset.id))
        url = Tracking.url(c.grid_url, platform, c.id, "asset-#{asset.id}-#{draft.angle}")

        suffix =
          if platform == "x",
            do: "\n\n#{url}",
            else: "\n\nExplore the connected argument at RationalGrid.ai:\n#{url}"

        {draft, String.trim(copy[platform]) <> suffix}
      end

    if Enum.all?(changes, fn {d, body} -> Platforms.within_limit?(body, d.platform) end) do
      Repo.transaction(fn ->
        Enum.each(changes, fn {d, body} ->
          {:ok, _} = Campaigns.update_post_draft_body(d, body)
        end)

        %{
          asset_ids: Enum.map(assets, & &1.id),
          draft_ids: Enum.map(changes, fn {d, _} -> d.id end)
        }
      end)
    else
      {:error,
       {:copy_issues, ["A caption exceeds its platform allowance after adding the link."]}}
    end
  end

  defp search_cover(query) do
    case VisualDirection.search(query, per_page: 1, orientation: "portrait") do
      {:ok, [photo | _]} -> VisualDirection.cover("pexels", photo)
      _ -> %{"mode" => "text", "status" => "no_photo_available"}
    end
  end

  def destination(assets, p) do
    kind =
      cond do
        p in ["linkedin", "facebook"] -> "long_form_post"
        p == "x" -> "curated_carousel"
        true -> "curated_carousel_video"
      end

    Enum.find(assets, &(&1.kind == kind))
  end

  def assets(story), do: Enum.map(story.review["asset_ids"] || [], &Campaigns.get_media_asset!/1)

  def render_path(story, return_to) do
    p = Automation.get_plan(story.plan_id)
    ids = Enum.join(story.review["asset_ids"] || [], ",")

    "/campaigns/#{p.campaign_id}/render-assets?" <>
      URI.encode_query(%{assets: ids, asset: "all", step: "review", return_to: return_to})
  end

  def frames_ready?(story),
    do:
      Enum.all?(
        assets(story),
        &GridMediaManager.Promotion.ArtifactStore.ready?(
          &1,
          Campaigns.media_asset_slide_indexes(&1)
        )
      )

  def finish_media(story) do
    p = Automation.get_plan(story.plan_id)
    c = Campaigns.get_campaign!(p.campaign_id)

    Enum.reduce_while(assets(story), :ok, fn a, :ok ->
      with :ok <- GridMediaManager.Promotion.ShortVideo.validate_asset(a),
           {:ok, _} <- GridMediaManager.Automation.BrowserRenderer.render(c, a, []),
           {:ok, _} <- Campaigns.publish_media_assets(c, Campaigns.get_media_asset!(a.id)) do
        {:cont, :ok}
      else
        _ -> {:halt, {:error, :media_not_ready}}
      end
    end)
  end

  def public?(story) do
    e = Explorations.get!(story.exploration_id)
    grid_id = e.result["grid"]["id"]

    case MCP.read_public_grid(grid_id) do
      {:ok, %{"grid" => %{"id" => ^grid_id, "visibility" => "public"}}} ->
        {:ok, true}

      {:error, reason} when reason in [:transport_unavailable, :invalid_tool_response] ->
        {:error, :publication_check_unavailable}

      _ ->
        {:ok, false}
    end
  end

  def drafts(story), do: Enum.map(story.review["draft_ids"] || [], &Campaigns.get_post_draft!/1)

  def media_fingerprint(story) do
    assets(story)
    |> Enum.map(fn a ->
      {a.id,
       Map.take(
         a.metadata,
         ~w(slides selected_slide_indexes render_signature published_urls sha256s)
       )}
    end)
    |> Validation.hash()
  end

  def send(delivery),
    do: Campaigns.schedule_post_draft(delivery.post_draft_id, delivery.scheduled_for)

  def restore(delivery, post) do
    d = Campaigns.get_post_draft!(delivery.post_draft_id)

    Campaigns.update_post_draft(d, %{
      status: "scheduled",
      external_post_id: post.id,
      scheduled_for: delivery.scheduled_for,
      error_message: nil
    })
  end
end
