defmodule GridMediaManagerWeb.AutonomousPlannerLive do
  use GridMediaManagerWeb, :live_view

  alias GridMediaManager.Automation
  alias GridMediaManager.Automation.EditorialBatch
  alias GridMediaManager.Promotion.ShareCard
  alias GridMediaManager.Studio.VisualDirection

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
          |> assign(:page_title, "Autonomous editorial plan")
          |> assign(:batch, batch)
          |> assign(:planning?, batch.status == "planning")
          |> stream_configure(:editorial_plans, dom_id: &"editorial-plan-#{&1.id}")
          |> stream(:editorial_plans, batch.plans)

        {:ok, maybe_start_planning(socket)}
    end
  end

  @impl true
  def handle_async(:plan_batch, {:ok, {:ok, %EditorialBatch{} = batch}}, socket) do
    {:noreply,
     socket
     |> assign(:batch, batch)
     |> assign(:planning?, false)
     |> stream(:editorial_plans, batch.plans, reset: true)}
  end

  def handle_async(:plan_batch, _result, socket) do
    batch = Automation.get_batch(socket.assigns.batch.id)

    {:noreply,
     socket
     |> assign(:batch, batch)
     |> assign(:planning?, false)
     |> stream(:editorial_plans, batch.plans, reset: true)
     |> put_flash(:error, "The editorial planner stopped before completing the batch.")}
  end

  @impl true
  def handle_event("retry_planning", _params, socket) do
    {:noreply, start_planning(socket, retry: true)}
  end

  @impl true
  def handle_info(:refresh_planning, socket) do
    batch = Automation.get_batch(socket.assigns.batch.id)

    if batch.status == "planning" do
      schedule_planning_refresh()

      {:noreply,
       socket
       |> assign(:batch, batch)
       |> assign(:planning?, true)
       |> stream(:editorial_plans, batch.plans, reset: true)}
    else
      {:noreply,
       socket
       |> assign(:batch, batch)
       |> assign(:planning?, false)
       |> stream(:editorial_plans, batch.plans, reset: true)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <main
        id="autonomous-planner"
        class="relative isolate overflow-hidden px-4 py-10 sm:px-6 lg:px-8 lg:py-14"
      >
        <div class="absolute inset-x-0 top-0 -z-10 h-96 bg-gradient-to-br from-indigo-100 via-orange-50 to-sky-100 opacity-80 blur-3xl dark:from-indigo-950/40 dark:via-slate-900 dark:to-sky-950/30" />

        <div class="mx-auto max-w-6xl">
          <.link
            id="back-to-campaigns"
            navigate={~p"/"}
            class="inline-flex items-center gap-2 text-sm font-semibold text-base-content/55 transition hover:text-base-content"
          >
            <.icon name="hero-arrow-left" class="size-4" /> Campaigns
          </.link>

          <section class="mt-5 overflow-hidden rounded-[2rem] border border-base-content/10 bg-base-100/85 shadow-2xl shadow-indigo-950/10 backdrop-blur">
            <div class="border-b border-base-content/10 p-6 sm:p-8">
              <div class="flex flex-col gap-5 sm:flex-row sm:items-start sm:justify-between">
                <div>
                  <p class="text-xs font-bold uppercase tracking-[0.2em] text-indigo-600 dark:text-indigo-300">
                    Autonomous editorial desk
                  </p>
                  <h1 class="mt-3 text-3xl font-semibold tracking-tight text-base-content sm:text-4xl">
                    {@batch.requested_count} grounded {if(@batch.requested_count == 1,
                      do: "story",
                      else: "stories"
                    )} ready for editorial review.
                  </h1>
                  <p class="mt-3 max-w-2xl text-sm leading-6 text-base-content/60 sm:text-base">
                    The planner chooses the topics and sources, builds provenance-aware story arcs, and recommends formats compatible with the publishing channels.
                  </p>
                  <p
                    :if={@batch.theme}
                    id="editorial-batch-theme"
                    class="mt-3 inline-flex rounded-full bg-indigo-500/10 px-3 py-1 text-xs font-semibold text-indigo-700 dark:text-indigo-200"
                  >
                    Theme · {@batch.theme}
                  </p>
                </div>
                <.status_badge status={@batch.status} planning?={@planning?} />
              </div>

              <div id="batch-topics" class="mt-6 flex flex-wrap gap-2">
                <span
                  :for={{topic, index} <- Enum.with_index(@batch.topics, 1)}
                  id={"batch-topic-#{index}"}
                  class="rounded-full border border-indigo-500/20 bg-indigo-500/10 px-3 py-1.5 text-sm font-semibold text-indigo-800 dark:text-indigo-100"
                >
                  {index}. {topic}
                </span>
              </div>
            </div>

            <div
              :if={@planning?}
              id="planning-progress"
              class="grid gap-4 p-6 sm:grid-cols-3 sm:p-8"
            >
              <div
                :for={index <- 1..@batch.requested_count}
                id={"planning-topic-#{index}"}
                class="relative overflow-hidden rounded-3xl border border-base-content/10 bg-base-200/50 p-5"
              >
                <div class="absolute inset-x-0 top-0 h-1 animate-pulse bg-gradient-to-r from-indigo-500 via-orange-400 to-sky-500" />
                <span class="grid size-9 place-items-center rounded-xl bg-base-content text-sm font-bold text-base-100">
                  {index}
                </span>
                <p class="mt-4 font-semibold text-base-content">
                  {Enum.at(@batch.topics, index - 1) || "Choosing topic #{index}"}
                </p>
                <p class="mt-2 text-sm text-base-content/55">
                  Finding the source, story arc, provenance mix, and best format…
                </p>
              </div>
            </div>

            <div
              :if={!@planning?}
              id="editorial-plans"
              phx-update="stream"
              class="grid gap-5 p-6 sm:p-8 lg:grid-cols-2"
            >
              <article
                :for={{id, plan} <- @streams.editorial_plans}
                id={id}
                class="flex min-h-96 flex-col rounded-3xl border border-base-content/10 bg-base-100 p-5 shadow-lg shadow-base-content/5"
              >
                <div class="flex items-start justify-between gap-4">
                  <span class="grid size-10 place-items-center rounded-2xl bg-indigo-500 text-sm font-bold text-white shadow-lg shadow-indigo-950/20">
                    {plan.position}
                  </span>
                  <span class={plan_status_class(plan.status)}>{plan.status}</span>
                </div>

                <p class="mt-5 text-xs font-bold uppercase tracking-[0.16em] text-base-content/45">
                  {plan.topic}
                </p>

                <%= if plan.status == "planned" do %>
                  <h2 class="mt-2 text-xl font-semibold leading-7 text-base-content text-balance">
                    {plan.hook}
                  </h2>
                  <p class="mt-4 text-sm leading-6 text-base-content/65">{plan.rationale}</p>

                  <div class="mt-5 flex flex-wrap items-center gap-2">
                    <span class="inline-flex items-center gap-1.5 rounded-full bg-indigo-500/10 px-3 py-1.5 text-xs font-bold text-indigo-700 dark:text-indigo-200">
                      <.icon name={format_icon(plan.recommended_format)} class="size-3.5" />
                      {format_label(plan.recommended_format)}
                    </span>
                    <span
                      :for={platform <- plan.recommended_platforms}
                      class="rounded-full bg-base-200 px-2.5 py-1 text-xs font-semibold text-base-content/60"
                    >
                      {platform_label(platform)}
                    </span>
                  </div>

                  <div
                    :if={visual_direction?(plan)}
                    id={"plan-visual-#{plan.id}"}
                    class="mt-5 overflow-hidden rounded-2xl border border-base-content/10 bg-base-200/55"
                  >
                    <img
                      :if={cover_photo_url(plan)}
                      src={cover_photo_url(plan)}
                      alt={cover_photo_alt(plan)}
                      class="aspect-[16/7] w-full object-cover"
                    />
                    <div class="p-4">
                      <p class="text-xs font-bold uppercase tracking-wider text-base-content/40">
                        Visual direction
                      </p>
                      <p class="mt-1 text-sm font-semibold text-base-content">
                        {visual_style_label(plan)}
                      </p>
                      <p class="mt-1 text-xs leading-5 text-base-content/60">
                        {Map.get(plan.selection_details, "visual_rationale")}
                      </p>
                      <p
                        :if={cover_rationale(plan)}
                        class="mt-2 text-xs leading-5 text-base-content/50"
                      >
                        Cover · {cover_rationale(plan)}
                      </p>
                    </div>
                  </div>

                  <ol
                    id={"plan-moments-#{plan.id}"}
                    class="mt-5 grid gap-2"
                  >
                    <li
                      :for={
                        {moment, index} <-
                          Enum.with_index(Map.get(plan.selection_details, "moments", []), 1)
                      }
                      id={"plan-moment-#{plan.id}-#{index}"}
                      class="rounded-2xl border border-base-content/10 bg-base-100 p-3"
                    >
                      <div class="flex items-start gap-3">
                        <span class="grid size-7 shrink-0 place-items-center rounded-lg bg-base-content text-xs font-bold text-base-100">
                          {index}
                        </span>
                        <div class="min-w-0">
                          <span class={provenance_class(moment["provenance"])}>
                            {provenance_label(moment["provenance"])}
                          </span>
                          <p class="mt-1.5 text-sm font-semibold leading-5 text-base-content">
                            {moment["title"]}
                          </p>
                        </div>
                      </div>
                    </li>
                  </ol>

                  <div class="mt-5 rounded-2xl bg-base-200/70 p-4">
                    <p class="text-xs font-bold uppercase tracking-wider text-base-content/40">
                      Source
                    </p>
                    <p class="mt-1 text-sm font-semibold text-base-content">{plan.source_title}</p>
                    <div class="mt-3 flex items-center justify-between gap-3 text-xs text-base-content/55">
                      <span>{length(plan.selected_keys)} moments selected</span>
                      <span>{confidence_label(plan.confidence)} confidence</span>
                    </div>
                  </div>

                  <.link
                    id={"open-editorial-plan-#{plan.id}"}
                    navigate={~p"/campaigns/#{plan.campaign_id}/studio?plan=#{plan.id}&step=design"}
                    class="mt-auto inline-flex items-center justify-center rounded-2xl bg-base-content px-4 py-3 text-sm font-bold text-base-100 shadow-lg shadow-base-content/15 transition hover:-translate-y-0.5 hover:shadow-xl"
                  >
                    Approve & prepare package <.icon name="hero-arrow-right" class="ml-2 size-4" />
                  </.link>
                <% else %>
                  <h2 class="mt-2 text-xl font-semibold text-base-content">
                    This topic needs attention
                  </h2>
                  <p class="mt-4 rounded-2xl border border-red-500/20 bg-red-500/10 p-4 text-sm leading-6 text-red-700 dark:text-red-200">
                    {plan.error_message}
                  </p>
                <% end %>
              </article>
            </div>

            <div
              :if={!@planning? && @batch.status in ["partial", "failed"]}
              class="flex items-center justify-between gap-4 border-t border-base-content/10 p-6 sm:px-8"
            >
              <p class="text-sm text-base-content/60">{@batch.error_message}</p>
              <button
                id="retry-editorial-planning"
                type="button"
                phx-click="retry_planning"
                class="inline-flex items-center rounded-xl border border-base-content/15 bg-base-100 px-4 py-2 text-sm font-bold transition hover:bg-base-200"
              >
                <.icon name="hero-arrow-path" class="mr-2 size-4" /> Retry
              </button>
            </div>
          </section>
        </div>
      </main>
    </Layouts.app>
    """
  end

  defp maybe_start_planning(socket) do
    cond do
      connected?(socket) and socket.assigns.batch.status == "pending" ->
        start_planning(socket)

      connected?(socket) and socket.assigns.batch.status == "planning" ->
        schedule_planning_refresh()
        assign(socket, :planning?, true)

      true ->
        socket
    end
  end

  defp start_planning(socket, opts \\ []) do
    batch = socket.assigns.batch

    socket
    |> assign(:planning?, true)
    |> start_async(:plan_batch, fn -> Automation.run_batch(batch, opts) end)
  end

  defp schedule_planning_refresh do
    Process.send_after(self(), :refresh_planning, 1_000)
  end

  defp confidence_label(confidence) when is_number(confidence) do
    confidence
    |> Kernel.*(100)
    |> round()
    |> then(&"#{&1}%")
  end

  defp confidence_label(_confidence), do: "—"

  defp visual_direction?(plan) do
    details = plan.selection_details || %{}
    is_binary(details["visual_style"]) or is_map(details["cover"])
  end

  defp visual_style_label(plan) do
    style_id = Map.get(plan.selection_details, "visual_style")

    Enum.find_value(
      ShareCard.styles(),
      style_id || "Editorial",
      &if(&1.id == style_id, do: &1.label)
    )
  end

  defp cover_photo_url(plan) do
    (plan.selection_details || %{})
    |> Map.get("cover", %{})
    |> VisualDirection.cover_url()
  end

  defp cover_photo_alt(plan) do
    get_in(plan.selection_details, ["cover", "photo", "alt"]) || "Selected editorial cover"
  end

  defp cover_rationale(plan), do: get_in(plan.selection_details, ["cover", "rationale"])

  defp format_label("story_video"), do: "Vertical story video"
  defp format_label("portrait"), do: "Image carousel"
  defp format_label("long_form"), do: "Long-form post"
  defp format_label("combined_carousel"), do: "Video + carousel"
  defp format_label(_format), do: "Editorial package"

  defp format_icon("story_video"), do: "hero-play-circle"
  defp format_icon("long_form"), do: "hero-document-text"
  defp format_icon(_format), do: "hero-rectangle-stack"

  defp platform_label("x"), do: "X"
  defp platform_label("youtube"), do: "YouTube"
  defp platform_label(platform), do: String.capitalize(platform)

  defp provenance_label("human_question"), do: "Human question"
  defp provenance_label("human_highlight"), do: "Human highlight"
  defp provenance_label("ai_answer"), do: "AI answer"
  defp provenance_label("ai_question"), do: "AI question"
  defp provenance_label(_provenance), do: "Grid context"

  defp provenance_class(provenance) when provenance in ["human_question", "human_highlight"],
    do:
      "inline-flex rounded-full bg-orange-500/10 px-2 py-0.5 text-[0.65rem] font-bold uppercase tracking-wide text-orange-700 dark:text-orange-200"

  defp provenance_class(_provenance),
    do:
      "inline-flex rounded-full bg-sky-500/10 px-2 py-0.5 text-[0.65rem] font-bold uppercase tracking-wide text-sky-700 dark:text-sky-200"

  defp plan_status_class("planned"),
    do:
      "rounded-full bg-emerald-500/10 px-2.5 py-1 text-xs font-bold capitalize text-emerald-700 dark:text-emerald-200"

  defp plan_status_class(_status),
    do:
      "rounded-full bg-red-500/10 px-2.5 py-1 text-xs font-bold capitalize text-red-700 dark:text-red-200"

  attr :status, :string, required: true
  attr :planning?, :boolean, required: true

  defp status_badge(assigns) do
    ~H"""
    <span
      id="editorial-batch-status"
      class="inline-flex shrink-0 items-center gap-2 rounded-full border border-base-content/10 bg-base-200 px-3 py-1.5 text-xs font-bold uppercase tracking-wider text-base-content/65"
    >
      <span class={[
        "size-2 rounded-full",
        if(@planning?, do: "animate-pulse bg-orange-500", else: "bg-emerald-500")
      ]} />
      {if(@planning?, do: "Planning", else: @status)}
    </span>
    """
  end
end
