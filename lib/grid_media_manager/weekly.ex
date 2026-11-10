defmodule GridMediaManager.Weekly do
  @moduledoc "Saved weekly production, with a separate, explicit scheduling action."
  import Ecto.Query
  alias GridMediaManager.{Repo, Automation, Campaigns}
  alias GridMediaManager.Automation.EditorialBatch
  alias GridMediaManager.RationalGrid.Explorations
  alias GridMediaManager.Social.Platforms
  alias GridMediaManager.Weekly.{Run, Story, Delivery, Services, Evidence, Schedule, Validation}

  @active ~w(analysing discovering exploring planning copying rendering publication scheduling verifying)

  def list, do: Repo.all(from r in Run, order_by: [desc: r.id], limit: 20)

  def get!(id),
    do:
      Repo.get!(Run, id)
      |> Repo.preload(
        stories: from(s in Story, order_by: s.position, preload: [:exploration, :plan]),
        deliveries:
          from(d in Delivery, order_by: [d.scheduled_for, d.platform], preload: :post_draft)
      )

  def default_attrs do
    start = Date.add(Date.utc_today(), 1)
    finish = Date.add(start, 7 - Date.day_of_week(start))

    %{
      theme:
        "Philosophical questions unrelated to AI. Use concrete human tensions, varied topics, and the performance evidence.",
      start_date: start,
      end_date: finish
    }
  end

  def change(attrs \\ %{}), do: Run.changeset(%Run{}, attrs)

  def create(attrs) do
    Repo.transaction(fn ->
      # There is one shared studio account. Serialize creation across app instances.
      Repo.query!("SELECT pg_advisory_xact_lock(9412301)")
      existing = Repo.one(from r in Run, where: r.status not in ["completed", "cancelled"])

      if existing do
        existing
      else
        case %Run{next_run_at: now()} |> Run.changeset(attrs) |> Repo.insert() do
          {:ok, run} -> run
          {:error, c} -> Repo.rollback(c)
        end
      end
    end)
  end

  def process_next(services \\ Services) do
    claim =
      Repo.transaction(fn ->
        r =
          Repo.one(
            from r in Run,
              where:
                r.status in ^@active and r.next_run_at <= ^now() and
                  (is_nil(r.lease_until) or r.lease_until < ^now()),
              order_by: r.id,
              limit: 1,
              lock: "FOR UPDATE SKIP LOCKED"
          )

        if r,
          do: save(r, %{lease_until: DateTime.add(now(), 300), lease_token: Ecto.UUID.generate()})
      end)

    case claim do
      {:ok, nil} ->
        :idle

      {:ok, r} ->
        try do
          result = step(get!(r.id), services)
          current = Repo.get!(Run, r.id)

          if current.lease_token == r.lease_token,
            do: save(current, %{lease_until: nil, lease_token: nil})

          result
        rescue
          _ -> defer(r.id, "This step stopped unexpectedly. Saved progress is retained.")
        end

      error ->
        error
    end
  end

  defp step(%Run{status: "analysing"} = r, services) do
    with {:ok, %{queue: q, evidence: evidence}} <- services.snapshot() do
      quotas =
        Map.new(q.platforms, fn {p, c} ->
          {p, min(c.vacancies, 2 * (Date.diff(r.end_date, r.start_date) + 1))}
        end)

      count = quotas |> Map.values() |> Enum.max(fn -> 0 end)

      save(r, %{
        quotas: quotas,
        evidence: json(evidence),
        windows: Evidence.windows(evidence),
        story_count: count,
        status: if(count == 0, do: "completed", else: "discovering"),
        next_run_at: now(),
        error: nil,
        attempts: 0
      })
    else
      {:error, :reauthorization_required} ->
        attention(
          r,
          "Connect or reauthorize RationalGrid before generating this run.",
          "analysing"
        )

      {:error, :openai_not_configured} ->
        attention(r, "Configure the editorial model before generating this run.", "analysing")

      _ ->
        defer(r.id, "Could not refresh metrics and the live queues. Retry uses the same run.")
    end
  end

  defp step(%Run{status: "discovering"} = r, services) do
    with {:ok, %{"stories" => proposals}} <- services.proposals(r),
         true <- valid_proposals?(proposals, r.story_count) do
      Repo.transaction(fn ->
        batch =
          case r.batch_id do
            nil ->
              {:ok, b} = Automation.create_batch(Enum.map(proposals, & &1["question"]))
              b

            id ->
              Automation.get_batch(id)
          end

        for {p, i} <- Enum.with_index(proposals, 1) do
          Repo.insert!(
            %Story{run_id: r.id, position: i, question: p["question"], rationale: p["rationale"]},
            on_conflict: :nothing,
            conflict_target: [:run_id, :position]
          )
        end

        save(r, %{
          batch_id: batch.id,
          status: "exploring",
          attempts: 0,
          error: nil,
          next_run_at: now()
        })
      end)
    else
      _ -> defer(r.id, "Could not produce a valid set of distinct editorial questions.")
    end
  end

  defp step(%Run{status: "exploring"} = r, _services) do
    cond do
      s =
          Enum.find(
            r.stories,
            &(&1.exploration && &1.exploration.status in ["failed", "retry", "needs_access"])
          ) ->
        save(s, %{error: s.exploration.error})

        attention(
          r,
          "A grid needs attention. Reauthorize or inspect the preserved partial grid; generation will not silently restart.",
          "exploring"
        )

      Enum.all?(
        r.stories,
        &(&1.exploration && &1.exploration.status in ["review", "imported", "partial_review"])
      ) ->
        save(r, %{status: "planning", next_run_at: now()})

      Enum.any?(r.stories, &(&1.exploration && &1.exploration.status in ["queued", "generating"])) ->
        save(r, %{next_run_at: DateTime.add(now(), 10)})

      s = Enum.find(r.stories, &is_nil(&1.exploration_id)) ->
        Repo.transaction(fn ->
          {:ok, e} =
            Explorations.propose(%{question: s.question, rationale: s.rationale}, %{
              weekly_run_id: r.id,
              performance: r.evidence
            })

          save(s, %{exploration_id: e.id, status: "exploring"})
          Explorations.start(e.id)
          save(r, %{next_run_at: DateTime.add(now(), 10)})
        end)
    end
  end

  defp step(%Run{status: "planning"} = r, services) do
    case Enum.find(r.stories, &is_nil(&1.plan_id)) do
      nil ->
        Repo.get!(EditorialBatch, r.batch_id)
        |> Ecto.Changeset.change(status: "completed")
        |> Repo.update!()

        save(r, %{status: "copying", next_run_at: now()})

      story ->
        case services.plan(r, story) do
          {:ok, p} ->
            save(story, %{plan_id: p.id, status: "planned", error: nil})
            save(r, %{next_run_at: now(), attempts: 0})

          _ ->
            defer(r.id, "Could not plan this source. The completed grids are retained.")
        end
    end
  end

  defp step(%Run{status: "copying"} = r, services) do
    case Enum.find(r.stories, &(&1.status != "copied")) do
      nil ->
        save(r, %{status: "rendering", next_run_at: now()})

      story ->
        # Persist model output before applying it: a resumed application step does
        # not pay for another generation or reset an already copied story.
        result =
          if map_size(story.copy) == 0, do: services.copy(r, story), else: {:ok, story.copy}

        case result do
          {:ok, copy} ->
            story = save(story, %{copy: json(copy), copy_fingerprint: Validation.hash({1, copy})})

            case services.apply_copy(r, story) do
              {:ok, details} ->
                save(story, %{
                  status: "copied",
                  review:
                    json(
                      Map.put(
                        details,
                        :checks,
                        "Production checks passed; review the source-grounded package before scheduling."
                      )
                    ),
                  error: nil
                })

                save(r, %{next_run_at: now(), attempts: 0})

              {:error, {:copy_issues, issues}} ->
                message = Enum.join(issues, " ")

                if (story.review["copy_revision_count"] || 0) < 1 do
                  save(story, %{
                    copy: %{},
                    error: message,
                    review: Map.put(story.review, "copy_revision_count", 1)
                  })

                  save(r, %{next_run_at: now()})
                else
                  save(story, %{error: message})

                  attention(
                    r,
                    "A caption needs correction. Only this story needs regeneration.",
                    "copying"
                  )
                end

              _ ->
                defer(r.id, "The saved copy could not be applied to the package.")
            end

          _ ->
            defer(r.id, "The editorial model did not finish. Earlier stories are retained.")
        end
    end
  end

  defp step(%Run{status: "rendering"} = r, services) do
    cond do
      s = Enum.find(r.stories, &(not services.frames_ready?(&1))) ->
        save(s, %{status: "awaiting_frames"})
        save(r, %{next_run_at: DateTime.add(now(), 10)})

      s = Enum.find(r.stories, &(&1.status != "rendered")) ->
        case services.finish_media(s) do
          :ok ->
            save(s, %{status: "rendered", error: nil})
            save(r, %{next_run_at: now(), attempts: 0})

          _ ->
            defer(r.id, "Could not finish or upload media. Saved frames are retained.")
        end

      true ->
        save(r, %{status: "publication", next_run_at: now(), error: nil})
    end
  end

  defp step(%Run{status: "publication"} = r, services) do
    results =
      Enum.map(r.stories, fn s ->
        case services.public?(s) do
          {:ok, public?} ->
            save(s, %{public: public?})
            public?

          _ ->
            false
        end
      end)

    if Enum.all?(results),
      do: save(r, %{status: "ready", error: nil, next_run_at: nil}),
      else:
        save(r, %{
          next_run_at: DateTime.add(now(), 60),
          error:
            "Publish the completed grids in RationalGrid. Private grids cannot be used as public post destinations."
        })
  end

  defp step(%Run{status: "scheduling"} = r, services) do
    pending = Enum.find(r.deliveries, &(&1.status not in ["scheduled", "verified"]))

    cond do
      is_nil(pending) ->
        save(r, %{status: "verifying", next_run_at: now()})

      pending.status in ["sending", "reconciling"] ->
        reconcile(r, pending, services)

      pending.status == "attention" ->
        attention(
          r,
          "A Buffer submission needs reconciliation. It will not be sent again automatically.",
          "scheduling"
        )

      true ->
        with true <-
               Validation.hash(Campaigns.get_post_draft!(pending.post_draft_id).body) ==
                 pending.body_hash,
             true <-
               services.media_fingerprint(Enum.find(r.stories, &(&1.id == pending.story_id))) ==
                 Enum.find(r.stories, &(&1.id == pending.story_id)).review[
                   "delivery_media_fingerprint"
                 ],
             {:ok, true} <- services.public?(Enum.find(r.stories, &(&1.id == pending.story_id))),
             {:ok, q} <- services.queue([pending.platform]),
             true <- q.platforms[pending.platform].vacancies > 0 do
          d = save(pending, %{status: "sending", attempted_at: now()})
          # The send intent is committed before touching Buffer. Crashes and
          # uncertain responses always take the read/reconcile path on resume.
          case services.send(d) do
            {:ok, post} ->
              save(d, %{status: "scheduled", external_post_id: post.external_post_id, error: nil})

            _ ->
              save(d, %{
                status: "reconciling",
                error:
                  "Submission outcome is uncertain; checking Buffer before any further action."
              })
          end

          save(r, %{next_run_at: DateTime.add(now(), 2), attempts: 0})
        else
          _ ->
            attention(
              r,
              "Public access or live queue capacity changed. Existing scheduled posts are preserved.",
              "scheduling"
            )
        end
    end
  end

  defp step(%Run{status: "verifying"} = r, services) do
    with {:ok, q} <- services.queue() do
      all? =
        Enum.all?(r.deliveries, fn d ->
          draft = Campaigns.get_post_draft!(d.post_draft_id)

          found? =
            Enum.any?(
              q.platforms[d.platform].posts,
              &(&1.id == d.external_post_id and Schedule.match(&1, d, draft))
            )

          if found?, do: save(d, %{status: "verified", error: nil})
          found?
        end)

      if all?,
        do: save(r, %{status: "completed", error: nil, next_run_at: nil}),
        else: defer(r.id, "Not every scheduled ID and time is visible in Buffer yet.")
    else
      _ -> defer(r.id, "Buffer verification is temporarily unavailable.")
    end
  end

  defp reconcile(r, d, services) do
    case services.queue([d.platform]) do
      {:ok, q} ->
        draft = Campaigns.get_post_draft!(d.post_draft_id)
        matches = Enum.filter(q.platforms[d.platform].posts, &Schedule.match(&1, d, draft))

        case matches do
          [post] ->
            {:ok, _} = services.restore(d, post)
            save(d, %{status: "scheduled", external_post_id: post.id, error: nil})
            save(r, %{next_run_at: now(), attempts: 0})

          _ ->
            checks = d.checks + 1

            save(d, %{
              status: if(checks >= 3, do: "attention", else: "reconciling"),
              checks: checks
            })

            save(r, %{next_run_at: DateTime.add(now(), 30)})
        end

      _ ->
        defer(r.id, "Could not read Buffer to reconcile a possible submission.")
    end
  end

  def schedule(id, services \\ Services) do
    r = get!(id)

    cond do
      r.status in ["scheduling", "verifying", "completed"] ->
        {:ok, r}

      r.status != "ready" ->
        {:error, :not_ready}

      true ->
        with true <- Enum.all?(r.stories, &(services.public?(&1) == {:ok, true})),
             true <- Enum.all?(r.stories, &services.frames_ready?/1),
             {:ok, q} <- services.queue() do
          Repo.transaction(fn ->
            locked = Repo.one!(from x in Run, where: x.id == ^r.id, lock: "FOR UPDATE")

            if locked.status == "ready" do
              for story <- r.stories do
                save(story, %{
                  review:
                    Map.put(
                      story.review,
                      "delivery_media_fingerprint",
                      services.media_fingerprint(story)
                    )
                })
              end

              for platform <- Platforms.ids() do
                count = min(r.quotas[platform] || 0, q.platforms[platform].vacancies)
                slots = Schedule.slots(platform, count, q.platforms[platform].posts, r)

                for {story, slot} <- Enum.zip(r.stories, slots) do
                  draft = Enum.find(services.drafts(story), &(&1.platform == platform))
                  true = GridMediaManager.Social.Platforms.within_limit?(draft.body, platform)

                  {:ok, _} =
                    if draft.status == "approved",
                      do: {:ok, draft},
                      else: Campaigns.approve_post_draft(draft.id)

                  Repo.insert!(
                    %Delivery{
                      run_id: r.id,
                      story_id: story.id,
                      post_draft_id: draft.id,
                      platform: platform,
                      scheduled_for: slot.scheduled_for,
                      window: slot.window,
                      body_hash: Validation.hash(draft.body)
                    },
                    on_conflict: :nothing,
                    conflict_target: [:run_id, :post_draft_id]
                  )
                end
              end

              save(locked, %{status: "scheduling", next_run_at: now(), error: nil})
            else
              locked
            end
          end)
        else
          _ -> {:error, :publication_or_queue_check_failed}
        end
    end
  end

  def resume(id) do
    r = get!(id)

    if r.status == "attention" do
      phase = r.evidence["resume_phase"] || "analysing"

      for s <- r.stories,
          s.exploration && s.exploration.status in ["retry", "needs_access"],
          do: Explorations.retry(s.exploration_id)

      # Ambiguous Buffer writes stay read-only; resuming only checks again.
      for d <- r.deliveries,
          d.status == "attention",
          do: save(d, %{status: "reconciling", checks: 0})

      save(r, %{status: phase, attempts: 0, next_run_at: now(), error: nil})
    else
      save(r, %{next_run_at: now()})
    end
  end

  def use_partial(id, story_id) do
    r = get!(id)
    s = Enum.find(r.stories, &(&1.id == story_id))

    with true <-
           r.status == "attention" and r.evidence["resume_phase"] == "exploring" and not is_nil(s),
         {:ok, _} <- Explorations.review_partial(s.exploration_id) do
      save(s, %{error: "Approved use of available answers from an incomplete exploration."})
      {:ok, resume(id)}
    else
      _ -> {:error, :partial_grid_not_ready}
    end
  end

  def regenerate_copy(id, story_id) do
    r = get!(id)
    story = Enum.find(r.stories, &(&1.id == story_id))

    if story && r.status == "attention" && r.evidence["resume_phase"] == "copying" &&
         r.deliveries == [] do
      save(story, %{copy: %{}, copy_fingerprint: nil, status: "planned"})
      resume(id)
    else
      {:error, :not_editable}
    end
  end

  def cancel(id) do
    Repo.transaction(fn ->
      r =
        Repo.one!(from r in Run, where: r.id == ^id, lock: "FOR UPDATE")
        |> Repo.preload(:deliveries)

      if (not is_nil(r.lease_until) and DateTime.compare(r.lease_until, now()) == :gt) or
           r.status in ["scheduling", "verifying"] or
           Enum.any?(r.deliveries, &(&1.status in ["sending", "reconciling"])) do
        Repo.rollback(:submission_in_progress)
      else
        save(r, %{status: "cancelled", next_run_at: nil})
      end
    end)
  end

  def render_path(r) do
    case Enum.find(r.stories, &(map_size(&1.review) > 0 and not Services.frames_ready?(&1))) do
      nil -> nil
      s -> Services.render_path(s, "/weekly/#{r.id}/render")
    end
  end

  defp valid_proposals?(ps, n),
    do:
      is_list(ps) and length(ps) == n and
        Enum.all?(
          ps,
          &(is_binary(&1["question"]) and String.length(&1["question"]) in 3..300 and
              is_binary(&1["rationale"]))
        ) and length(Enum.uniq_by(ps, &String.downcase(String.trim(&1["question"])))) == n

  defp attention(r, message, phase),
    do:
      save(r, %{
        status: "attention",
        error: message,
        evidence: Map.put(r.evidence, "resume_phase", phase),
        lease_until: nil,
        lease_token: nil
      })

  defp defer(id, message) do
    r = Repo.get!(Run, id)

    if r.attempts >= 3,
      do: attention(r, message, r.status),
      else:
        save(r, %{
          attempts: r.attempts + 1,
          error: message,
          next_run_at: DateTime.add(now(), 15 * Integer.pow(2, r.attempts)),
          lease_until: nil,
          lease_token: nil
        })
  end

  def save(record, attrs), do: record |> Ecto.Changeset.change(attrs) |> Repo.update!()
  defp json(value), do: value |> Jason.encode!() |> Jason.decode!()
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
