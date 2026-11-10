defmodule GridMediaManagerWeb.WeeklyLive do
  use GridMediaManagerWeb, :live_view
  alias GridMediaManager.Weekly

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Process.send_after(self(), :refresh, 3_000)

    {:ok,
     socket
     |> assign(:next_render_path, nil)
     |> assign(:run, nil)
     |> assign(:run_id, nil)
     |> assign(:form, to_form(Weekly.change(Weekly.default_attrs())))
     |> assign(:story_count, 0)
     |> assign(:delivery_count, 0)
     |> assign(:verified_count, 0)
     |> stream(:runs, Weekly.list())
     |> stream(:stories, [])
     |> stream(:deliveries, [])}
  end

  @impl true
  def handle_params(params, _, socket) do
    {:noreply, socket |> assign(:run_id, params["id"]) |> refresh() |> maybe_render()}
  end

  @impl true
  def handle_event("prepare", %{"run" => attrs}, socket) do
    case Weekly.create(attrs) do
      {:ok, r} -> {:noreply, push_navigate(socket, to: ~p"/weekly/#{r.id}")}
      {:error, c} -> {:noreply, assign(socket, :form, to_form(c))}
    end
  end

  def handle_event("resume", _, socket) do
    Weekly.resume(socket.assigns.run.id)
    {:noreply, refresh(socket)}
  end

  def handle_event("copy", %{"id" => id}, socket) do
    Weekly.regenerate_copy(socket.assigns.run.id, parse_id(id))
    {:noreply, refresh(socket)}
  end

  def handle_event("partial", %{"id" => id}, socket) do
    case Weekly.use_partial(socket.assigns.run.id, parse_id(id)) do
      {:ok, _} -> {:noreply, refresh(socket)}
      _ -> {:noreply, put_flash(socket, :error, "The available answers are not ready to use.")}
    end
  end

  def handle_event("schedule", _, socket) do
    id = socket.assigns.run.id
    {:noreply, start_async(socket, :schedule, fn -> Weekly.schedule(id) end)}
  end

  def handle_event("cancel", _, socket) do
    case Weekly.cancel(socket.assigns.run.id) do
      {:ok, _} ->
        {:noreply, refresh(socket)}

      _ ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "A step or submission is in progress. Wait for it to finish before cancelling."
         )}
    end
  end

  @impl true
  def handle_async(:schedule, {:ok, {:ok, _}}, socket), do: {:noreply, refresh(socket)}

  def handle_async(:schedule, _, socket),
    do:
      {:noreply,
       put_flash(
         socket,
         :error,
         "Public access or Buffer capacity changed. Check the run before scheduling."
       )}

  @impl true
  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, 3_000)
    {:noreply, socket |> refresh() |> maybe_render()}
  end

  defp refresh(socket) do
    r = if socket.assigns.run_id, do: Weekly.get!(socket.assigns.run_id)

    socket
    |> assign(:run, if(r, do: %{r | stories: [], deliveries: []}, else: nil))
    |> assign(
      :next_render_path,
      if(r && r.status == "rendering" && socket.assigns.live_action == :render,
        do: Weekly.render_path(r),
        else: nil
      )
    )
    |> assign(:story_count, if(r, do: length(r.stories), else: 0))
    |> assign(:delivery_count, if(r, do: length(r.deliveries), else: 0))
    |> assign(
      :verified_count,
      if(r, do: Enum.count(r.deliveries, &(&1.status == "verified")), else: 0)
    )
    |> stream(:runs, Weekly.list(), reset: true)
    |> stream(:stories, if(r, do: r.stories, else: []), reset: true)
    |> stream(:deliveries, if(r, do: r.deliveries, else: []), reset: true)
  end

  defp maybe_render(%{assigns: %{live_action: :render, next_render_path: path}} = socket)
       when is_binary(path),
       do: push_navigate(socket, to: path)

  defp maybe_render(socket), do: socket

  defp parse_id(id) do
    case Integer.parse(id) do
      {id, ""} -> id
      _ -> nil
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div id="weekly-workflow" class="mx-auto max-w-7xl px-4 py-10 sm:px-6 lg:px-8">
        <div class="flex flex-wrap items-end justify-between gap-5">
          <div>
            <p class="text-xs font-bold uppercase tracking-[0.2em] text-indigo-600">
              A week of worthwhile questions
            </p>
            <h1 class="mt-3 text-4xl font-semibold tracking-tight">
              Prepare the week. Keep the progress.
            </h1>
            <p class="mt-4 max-w-2xl leading-7 text-base-content/65">
              One saved run connects the evidence, new grids, six platform versions, media and Buffer confirmations. Resume where it stopped.
            </p>
          </div>
          <.link
            :if={@run}
            id="new-weekly-run"
            navigate={~p"/weekly"}
            class="rounded-xl border border-base-content/15 px-4 py-2 text-sm font-semibold"
          >
            Weekly desk
          </.link>
        </div>
        <%= if !@run do %>
          <div class="mt-8 grid gap-8 lg:grid-cols-[1.2fr_0.8fr]">
            <section class="rounded-3xl border border-indigo-500/20 bg-indigo-500/5 p-6 sm:p-8">
              <h2 class="text-xl font-semibold">Prepare this week’s posts</h2>
              <p class="mt-3 text-sm leading-6 text-base-content/65">
                Checks live vacancies first. Creates up to ten distinct stories, enough to fill available slots across all six platforms, at up to two daily posts. Full queues require no new generation.
              </p>
              <.form for={@form} id="weekly-run-form" phx-submit="prepare" class="mt-6 space-y-4">
                <.input
                  field={@form[:theme]}
                  type="textarea"
                  label="Editorial direction and exclusions"
                  required
                />
                <div class="grid gap-4 sm:grid-cols-2">
                  <.input
                    field={@form[:start_date]}
                    type="date"
                    label="First publishing day (UTC)"
                    required
                  />
                  <.input
                    field={@form[:end_date]}
                    type="date"
                    label="Last publishing day (UTC)"
                    required
                  />
                </div>
                <button
                  id="prepare-weekly-run"
                  class="rounded-xl bg-indigo-600 px-5 py-3 font-semibold text-white transition hover:bg-indigo-500 phx-submit-loading:opacity-50"
                >
                  Prepare the weekly run <.icon name="hero-arrow-right" class="ml-2 size-4" />
                </button>
              </.form>
              <p class="mt-4 text-xs leading-6 text-base-content/55">
                Preparation uses the connected RationalGrid account and configured editorial model. Grids stay private until complete. Review the finished posts before filling Buffer.
              </p>
            </section>
            <section>
              <h2 class="mb-4 text-lg font-semibold">Saved runs</h2>
              <div id="weekly-runs" phx-update="stream" class="space-y-3">
                <p id="no-weekly-runs" class="hidden text-sm text-base-content/55 only:block">
                  Your next weekly run will appear here.
                </p>
                <.link
                  :for={{id, r} <- @streams.runs}
                  id={id}
                  navigate={~p"/weekly/#{r.id}"}
                  class="block rounded-2xl border border-base-content/10 p-4 transition hover:border-indigo-500/40"
                >
                  <span class="block font-semibold">{r.start_date}–{r.end_date}</span>
                  <span class="mt-1 block text-sm text-base-content/60">
                    {String.replace(r.status, "_", " ")} · {r.story_count} stories
                  </span>
                </.link>
              </div>
            </section>
          </div>
        <% else %>
          <section class="mt-8 rounded-3xl border border-base-content/10 bg-base-200/30 p-6">
            <p
              id="weekly-status"
              role="status"
              class="text-sm font-bold uppercase tracking-wider text-indigo-600"
            >
              {@run.status}
            </p>
            <h2 class="mt-3 text-2xl font-semibold">
              {@run.start_date}–{@run.end_date} · {@story_count} stories
            </h2>
            <p class="mt-3 text-sm leading-6 text-base-content/65">{@run.theme}</p>
            <p :if={@run.error} id="weekly-error" class="mt-4 rounded-xl bg-amber-500/10 p-4 text-sm">
              {@run.error}
            </p>
            <p
              :if={@run.status == "completed"}
              id="weekly-completed"
              class="mt-4 text-sm font-semibold text-emerald-700"
            >
              <%= if @run.story_count == 0 do %>
                No new posts needed. The queues already have enough posts for this date range.
              <% else %>
                {@verified_count} posts confirmed in Buffer.
              <% end %>
            </p>
            <p :if={@run.status == "exploring"} class="mt-4 text-sm text-base-content/65">
              Generating one grid at a time. Keep grids private until exploration finishes; background work continues if you leave this page.
            </p>
            <p
              :if={@run.status == "publication"}
              id="weekly-publication-help"
              class="mt-4 text-sm text-base-content/65"
            >
              Generation and media are finished. Publish the grids linked below in RationalGrid, then recheck access. The MCP server does not yet expose publication.
            </p>
            <p :if={@run.status == "rendering"} class="mt-4 text-sm text-base-content/65">
              Keep this browser open during canvas rendering. Saved frames are skipped when you return.
            </p>
            <div class="mt-5 flex flex-wrap gap-3">
              <.link
                :if={@run.status == "rendering"}
                id="render-weekly-media"
                navigate={~p"/weekly/#{@run.id}/render"}
                class="rounded-xl bg-indigo-600 px-4 py-3 font-semibold text-white"
              >
                Render remaining media
              </.link>
              <button
                :if={@run.status in ["attention", "publication"]}
                id="resume-weekly-run"
                phx-click="resume"
                class="rounded-xl border border-base-content/20 px-4 py-3 font-semibold"
              >
                {if @run.status == "publication",
                  do: "Recheck public access",
                  else: "Resume saved run"}
              </button>
              <button
                :if={@run.status == "ready"}
                id="schedule-weekly-run"
                phx-click="schedule"
                class="rounded-xl bg-indigo-600 px-4 py-3 font-semibold text-white phx-click-loading:opacity-50"
              >
                Approve reviewed posts and fill Buffer queues
              </button>
              <.link
                :if={@run.batch_id}
                id="weekly-editorial-batch"
                navigate={~p"/automation/#{@run.batch_id}"}
                class="rounded-xl border border-base-content/15 px-4 py-3 text-sm font-semibold"
              >
                Editorial batch
              </.link>
              <button
                :if={@run.status not in ["completed", "cancelled", "scheduling", "verifying"]}
                id="cancel-weekly-run"
                phx-click="cancel"
                class="px-3 py-2 text-sm text-base-content/60"
              >
                Cancel run
              </button>
            </div>
            <details id="weekly-evidence" class="mt-6 border-t border-base-content/10 pt-4">
              <summary class="cursor-pointer text-sm font-semibold">
                Evidence, quotas and UTC test windows
              </summary>
              <p class="mt-3 text-sm text-base-content/60">
                Cumulative account observations; sample sizes, ages and formats differ. Timing is an experiment, not a proven optimum.
              </p>
              <pre class="mt-4 max-h-96 overflow-auto whitespace-pre-wrap break-words text-xs">{Jason.encode!(%{quotas: @run.quotas, windows: @run.windows, evidence: @run.evidence}, pretty: true)}</pre>
            </details>
          </section>
          <div id="weekly-stories" phx-update="stream" class="mt-6 grid gap-5 lg:grid-cols-2">
            <article
              :for={{id, s} <- @streams.stories}
              id={id}
              class="min-w-0 rounded-3xl border border-base-content/10 p-6"
            >
              <p class="text-xs font-bold uppercase tracking-wider text-indigo-600">
                {s.position} · {s.status} · {if s.public,
                  do: "Public access confirmed",
                  else: "Public access pending"}
              </p>
              <h3 class="mt-3 text-xl font-semibold">{s.question}</h3>
              <p class="mt-3 text-sm leading-6 text-base-content/65">{s.rationale}</p>
              <p :if={s.error} class="mt-3 rounded-xl bg-amber-500/10 p-3 text-sm">{s.error}</p>
              <div class="mt-4 flex gap-4 text-sm font-semibold">
                <.link :if={s.exploration_id} navigate={~p"/explorations/#{s.exploration_id}"}>
                  Inspect exploration
                </.link>
                <a
                  :if={s.exploration && get_in(s.exploration.result, ["grid", "url"])}
                  href={get_in(s.exploration.result, ["grid", "url"])}
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  Open grid <.icon name="hero-arrow-up-right" class="size-4" />
                </a>
                <button
                  :if={s.error && @run.status == "attention" && map_size(s.copy) > 0}
                  id={"regenerate-story-#{s.id}"}
                  phx-click="copy"
                  phx-value-id={s.id}
                >
                  Regenerate this story’s copy
                </button>
              </div>
              <details
                :if={map_size(s.copy) > 0}
                id={"weekly-copy-#{s.id}"}
                class="mt-5 border-t border-base-content/10 pt-4"
              >
                <summary class="cursor-pointer text-sm font-semibold">
                  Generated captions · edit the finished copy in the package
                </summary>
                <div :for={platform <- ~w(x linkedin facebook instagram tiktok youtube)} class="mt-4">
                  <h4 class="text-xs font-bold uppercase tracking-wider">{platform}</h4>
                  <p class="mt-2 whitespace-pre-wrap text-sm leading-6">{s.copy[platform]}</p>
                </div>
              </details>
            </article>
          </div>
          <section :if={@delivery_count > 0} class="mt-8">
            <h2 class="text-xl font-semibold">
              Buffer confirmations · {@verified_count} / {@delivery_count}
            </h2>
            <div
              id="weekly-deliveries"
              phx-update="stream"
              class="mt-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-3"
            >
              <article
                :for={{id, d} <- @streams.deliveries}
                id={id}
                class="rounded-2xl border border-base-content/10 p-4 text-sm"
              >
                <p class="font-semibold">{d.platform} · {d.status}</p>
                <p class="mt-2 text-base-content/65">
                  {Calendar.strftime(d.scheduled_for, "%a %d %b · %H:%M UTC")}
                </p>
                <p :if={d.external_post_id} class="mt-2 break-all text-xs text-base-content/50">
                  {d.external_post_id}
                </p>
                <p :if={d.error} class="mt-2 text-amber-700">{d.error}</p>
              </article>
            </div>
          </section>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
