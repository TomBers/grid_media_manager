defmodule GridMediaManagerWeb.AutopilotLive do
  use GridMediaManagerWeb, :live_view

  alias GridMediaManager.Automation

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Editorial autopilot")
     |> assign(:form, to_form(%{"count" => "3", "theme" => ""}, as: :autopilot))
     |> assign(:count_options, Enum.map(1..10, &{Integer.to_string(&1), &1}))}
  end

  @impl true
  def handle_event("start_autopilot", %{"autopilot" => params}, socket) do
    case Automation.create_autopilot_batch(params["count"], params["theme"]) do
      {:ok, batch} ->
        {:noreply, push_navigate(socket, to: ~p"/automation/#{batch.id}")}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> assign(:form, to_form(params, as: :autopilot))
         |> put_flash(:error, "Choose between 1 and 10 stories.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <main
        id="editorial-autopilot"
        class="relative isolate min-h-[calc(100vh-5rem)] overflow-hidden px-4 py-12 sm:px-6 lg:px-8"
      >
        <div class="absolute inset-0 -z-10 bg-gradient-to-br from-indigo-100 via-base-100 to-orange-100 dark:from-indigo-950/40 dark:via-base-100 dark:to-orange-950/30" />
        <div class="absolute left-1/2 top-0 -z-10 size-[38rem] -translate-x-1/2 rounded-full bg-indigo-400/15 blur-3xl" />

        <div class="mx-auto max-w-3xl">
          <.link
            id="back-to-home"
            navigate={~p"/"}
            class="inline-flex items-center gap-2 text-sm font-semibold text-base-content/55 transition hover:text-base-content"
          >
            <.icon name="hero-arrow-left" class="size-4" /> Campaigns
          </.link>

          <section class="mt-6 rounded-[2rem] border border-base-content/10 bg-base-100/90 p-6 shadow-2xl shadow-indigo-950/10 backdrop-blur sm:p-10">
            <div class="mx-auto max-w-2xl text-center">
              <span class="mx-auto grid size-14 place-items-center rounded-2xl bg-indigo-600 text-white shadow-xl shadow-indigo-950/25">
                <.icon name="hero-sparkles" class="size-7" />
              </span>
              <p class="mt-5 text-xs font-bold uppercase tracking-[0.22em] text-indigo-600 dark:text-indigo-300">
                Editorial autopilot
              </p>
              <h1 class="mt-3 text-4xl font-semibold tracking-tight text-base-content sm:text-5xl">
                How many stories should we make?
              </h1>
              <p class="mt-4 text-base leading-7 text-base-content/60">
                RationalGrid will choose the topics, find the strongest human signals and AI explanations, and recommend the most impactful supported format.
              </p>
            </div>

            <.form
              for={@form}
              id="autopilot-form"
              phx-submit="start_autopilot"
              class="mx-auto mt-9 max-w-xl rounded-3xl border border-base-content/10 bg-base-200/55 p-5 sm:p-6"
            >
              <.input
                field={@form[:count]}
                type="select"
                label="Number of stories"
                options={@count_options}
                required
              />
              <.input
                field={@form[:theme]}
                type="text"
                label="Theme or direction (optional)"
                placeholder="e.g. agency in the age of AI"
                autocomplete="off"
              />
              <p class="mt-1 text-xs leading-5 text-base-content/50">
                Leave the theme blank for a varied editorial mix from the available grids.
              </p>
              <button
                id="start-editorial-autopilot"
                type="submit"
                class="mt-5 inline-flex w-full items-center justify-center rounded-2xl bg-indigo-600 px-6 py-3.5 text-sm font-bold text-white shadow-lg shadow-indigo-950/20 transition hover:-translate-y-0.5 hover:bg-indigo-500 phx-submit-loading:opacity-60"
              >
                Build the editorial run <.icon name="hero-arrow-right" class="ml-2 size-4" />
              </button>
            </.form>
          </section>
        </div>
      </main>
    </Layouts.app>
    """
  end
end
