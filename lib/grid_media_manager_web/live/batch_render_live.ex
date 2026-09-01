defmodule GridMediaManagerWeb.BatchRenderLive do
  use GridMediaManagerWeb, :live_view

  alias GridMediaManager.Automation

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Automation.get_batch(id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "That editorial batch is no longer available.")
         |> redirect(to: ~p"/")}

      batch ->
        socket =
          socket
          |> assign(:page_title, "Render editorial batch")
          |> assign(:batch, batch)
          |> assign(:rendering?, connected?(socket))
          |> assign(:scheduling?, false)
          |> assign(:result, nil)
          |> assign(:schedule_result, nil)
          |> assign(
            :schedule_form,
            to_form(%{"start_date" => Date.to_iso8601(Date.utc_today())}, as: :schedule)
          )
          |> assign(:error, nil)

        {:ok, if(connected?(socket), do: start_render_pass(socket), else: socket)}
    end
  end

  @impl true
  def handle_event("retry", _params, socket) do
    {:noreply, start_render_pass(socket)}
  end

  def handle_event("schedule", %{"schedule" => %{"start_date" => start_date}}, socket) do
    batch_id = socket.assigns.batch.id

    {:noreply,
     socket
     |> assign(:scheduling?, true)
     |> assign(:error, nil)
     |> start_async(:schedule_batch, fn -> Automation.schedule_batch(batch_id, start_date) end)}
  end

  @impl true
  def handle_async(:render_batch, {:ok, {:ok, result}}, socket) do
    socket = assign(socket, rendering?: false, result: result, error: nil)

    case next_render_path(socket.assigns.batch, result, socket.assigns.batch.id) do
      nil -> {:noreply, socket}
      path -> {:noreply, push_navigate(socket, to: path)}
    end
  end

  def handle_async(:render_batch, {:ok, {:error, reason}}, socket) do
    {:noreply, assign(socket, rendering?: false, error: inspect(reason))}
  end

  def handle_async(:render_batch, {:exit, reason}, socket) do
    {:noreply, assign(socket, rendering?: false, error: inspect(reason))}
  end

  def handle_async(:schedule_batch, {:ok, {:ok, result}}, socket) do
    {:noreply, assign(socket, scheduling?: false, schedule_result: result, error: nil)}
  end

  def handle_async(:schedule_batch, {:ok, {:error, reason}}, socket) do
    {:noreply, assign(socket, scheduling?: false, error: inspect(reason))}
  end

  def handle_async(:schedule_batch, {:exit, reason}, socket) do
    {:noreply, assign(socket, scheduling?: false, error: inspect(reason))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <main id="batch-render" class="min-h-screen px-4 py-10 sm:px-6 lg:px-8">
        <section class="mx-auto max-w-3xl overflow-hidden rounded-[2rem] border border-base-content/10 bg-base-100 shadow-2xl shadow-indigo-950/10">
          <div class="border-b border-base-content/10 p-6 sm:p-8">
            <p class="text-xs font-bold uppercase tracking-[0.2em] text-indigo-600 dark:text-indigo-300">
              Sequential browser renderer
            </p>
            <h1 class="mt-3 text-3xl font-semibold tracking-tight text-base-content">
              Preparing {@batch.requested_count} editorial packages
            </h1>
            <p class="mt-3 text-sm leading-6 text-base-content/60">
              Finished packages are skipped. The next incomplete package opens automatically and returns here after its browser frames are safely stored.
            </p>
          </div>

          <div class="p-6 sm:p-8">
            <div :if={@rendering?} id="batch-render-progress" class="rounded-3xl bg-indigo-500/10 p-5">
              <div class="flex items-center gap-3">
                <span class="size-3 animate-pulse rounded-full bg-indigo-500" />
                <p class="font-semibold text-base-content">
                  Checking generated assets and saved frames…
                </p>
              </div>
            </div>

            <div
              :if={@result && @result.status == :complete}
              id="batch-render-complete"
              class="rounded-3xl border border-emerald-500/20 bg-emerald-500/10 p-5"
            >
              <p class="font-semibold text-emerald-800 dark:text-emerald-100">
                Every package is rendered and ready.
              </p>
              <p class="mt-2 text-sm text-emerald-700/80 dark:text-emerald-100/70">
                You can now review the batch or schedule its canonical channel drafts.
              </p>
              <.form
                for={@schedule_form}
                id="schedule-editorial-batch"
                phx-submit="schedule"
                class="mt-5 flex flex-col gap-3 sm:flex-row sm:items-end"
              >
                <.input
                  field={@schedule_form[:start_date]}
                  type="date"
                  label="First publishing day"
                  required
                />
                <button
                  id="submit-batch-schedule"
                  type="submit"
                  disabled={@scheduling?}
                  class="h-10 rounded-xl bg-emerald-700 px-4 text-sm font-bold text-white transition hover:-translate-y-0.5 disabled:cursor-wait disabled:opacity-60"
                >
                  {if(@scheduling?, do: "Scheduling…", else: "Fill Buffer queues")}
                </button>
              </.form>
            </div>

            <div
              :if={@schedule_result}
              id="batch-schedule-complete"
              class="mt-5 rounded-3xl border border-sky-500/20 bg-sky-500/10 p-5"
            >
              <p class="font-semibold text-sky-800 dark:text-sky-100">
                Buffer scheduling is complete.
              </p>
              <p class="mt-2 text-sm text-sky-700 dark:text-sky-200">
                {length(@schedule_result.posts)} canonical posts are confirmed or were already scheduled.
              </p>
            </div>

            <div
              :if={@error}
              id="batch-render-error"
              class="rounded-3xl border border-red-500/20 bg-red-500/10 p-5"
            >
              <p class="font-semibold text-red-800 dark:text-red-100">
                The render pass stopped safely.
              </p>
              <p class="mt-2 text-sm text-red-700 dark:text-red-200">{@error}</p>
              <button
                id="retry-batch-render"
                type="button"
                phx-click="retry"
                class="mt-4 rounded-xl bg-base-content px-4 py-2 text-sm font-bold text-base-100 transition hover:-translate-y-0.5"
              >
                Retry from saved progress
              </button>
            </div>

            <div class="mt-6 flex flex-wrap gap-3">
              <.link
                id="back-to-editorial-batch"
                navigate={~p"/automation/#{@batch.id}"}
                class="rounded-xl border border-base-content/15 px-4 py-2 text-sm font-bold transition hover:bg-base-200"
              >
                Back to editorial batch
              </.link>
            </div>
          </div>
        </section>
      </main>
    </Layouts.app>
    """
  end

  defp start_render_pass(socket) do
    batch_id = socket.assigns.batch.id

    socket
    |> assign(:rendering?, true)
    |> assign(:error, nil)
    |> start_async(:render_batch, fn ->
      Automation.generate_batch_assets(batch_id, max_concurrency: 1)
    end)
  end

  defp next_render_path(batch, result, batch_id) do
    with %{plan_id: plan_id, assets: assets} <-
           Enum.find(result.plans, &(&1.status == :awaiting_artifacts)),
         [_first | _rest] <- assets,
         plan <- Enum.find(batch.plans, &(&1.id == plan_id)),
         campaign_id when is_integer(campaign_id) <- plan && plan.campaign_id do
      asset_ids = Enum.map_join(assets, ",", & &1.asset_id)
      return_to = ~p"/automation/#{batch_id}/render"

      ~p"/campaigns/#{campaign_id}/studio?#{[step: "review", assets: asset_ids, asset: "all", return_to: return_to]}"
    else
      _missing -> nil
    end
  end
end
