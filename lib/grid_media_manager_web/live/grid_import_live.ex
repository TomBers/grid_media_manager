defmodule GridMediaManagerWeb.GridImportLive do
  use GridMediaManagerWeb, :live_view

  alias GridMediaManager.Campaigns

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "RationalGrid Share Studio")
      |> assign(:form, to_form(%{"source" => ""}, as: :import))
      |> stream(:campaigns, Campaigns.list_campaigns())

    {:ok, socket}
  end

  @impl true
  def handle_event("import", %{"import" => %{"source" => source}}, socket) do
    case Campaigns.import_grid(source) do
      {:ok, campaign} ->
        {:noreply,
         socket
         |> put_flash(:info, "Loaded #{campaign.title}")
         |> push_navigate(to: ~p"/campaigns/#{campaign.id}")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:form, to_form(%{"source" => source}, as: :import))
         |> put_flash(:error, error_message(reason))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="relative isolate overflow-hidden px-4 py-10 sm:px-6 lg:px-8 lg:py-14">
        <div class="absolute inset-x-0 top-0 -z-10 h-80 bg-gradient-to-br from-orange-100 via-amber-50 to-sky-100 opacity-80 blur-3xl dark:from-orange-950/40 dark:via-slate-900 dark:to-indigo-950/40" />

        <div class="mx-auto grid max-w-7xl gap-8 lg:grid-cols-[1.05fr_0.95fr] lg:items-start">
          <section class="rounded-[2rem] border border-base-content/10 bg-base-100/80 p-6 shadow-2xl shadow-orange-950/5 backdrop-blur md:p-8 lg:p-10">
            <p class="mb-4 inline-flex items-center rounded-full border border-orange-500/20 bg-orange-500/10 px-3 py-1 text-xs font-semibold uppercase tracking-[0.2em] text-orange-700 dark:text-orange-200">
              Internal RationalGrid sharing workbench
            </p>

            <h1 class="max-w-3xl text-4xl font-semibold tracking-tight text-base-content text-balance sm:text-5xl lg:text-6xl">
              Turn argument maps into copy-ready social assets.
            </h1>

            <p class="mt-5 max-w-2xl text-base leading-8 text-base-content/70 sm:text-lg">
              Paste a RationalGrid URL or slug. We’ll fetch the media payload, save a campaign, preview the share cards, and generate deterministic drafts for X, Bluesky, LinkedIn, Instagram, and Substack.
            </p>

            <.form
              for={@form}
              id="grid-import-form"
              phx-submit="import"
              class="mt-8 rounded-3xl border border-base-content/10 bg-base-200/50 p-4 shadow-inner shadow-base-content/5 sm:p-5"
            >
              <.input
                field={@form[:source]}
                type="text"
                label="RationalGrid URL or slug"
                placeholder="https://rationalgrid.ai/g/example-slug or example-slug"
                autocomplete="off"
                required
              />

              <div class="mt-4 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
                <p class="text-sm text-base-content/60">
                  No auth or LLM calls — just the RationalGrid media endpoint and simple templates.
                </p>
                <button
                  id="load-grid-media-button"
                  type="submit"
                  class="inline-flex items-center justify-center rounded-2xl bg-base-content px-5 py-3 text-sm font-semibold text-base-100 shadow-lg shadow-base-content/15 transition duration-200 hover:-translate-y-0.5 hover:shadow-xl focus:outline-none focus:ring-2 focus:ring-base-content/30 phx-submit-loading:opacity-60"
                >
                  Load grid media <.icon name="hero-arrow-right" class="ml-2 size-4" />
                </button>
              </div>
            </.form>
          </section>

          <aside class="rounded-[2rem] border border-base-content/10 bg-base-100/70 p-6 shadow-xl shadow-base-content/5 backdrop-blur md:p-8">
            <div class="flex items-start justify-between gap-4">
              <div>
                <h2 class="text-lg font-semibold text-base-content">Recent campaigns</h2>
                <p class="mt-1 text-sm text-base-content/60">
                  Reopen previously imported grids and continue editing copy.
                </p>
              </div>
              <span class="rounded-full bg-base-200 px-3 py-1 text-xs font-medium text-base-content/70">
                Internal
              </span>
            </div>

            <div id="recent-campaigns" phx-update="stream" class="mt-6 space-y-3">
              <div
                id="empty-recent-campaigns"
                class="hidden rounded-2xl border border-dashed border-base-content/20 bg-base-200/40 p-5 text-sm text-base-content/60 only:block"
              >
                No campaigns yet. Import a grid to create the first one.
              </div>

              <.link
                :for={{id, campaign} <- @streams.campaigns}
                id={id}
                navigate={~p"/campaigns/#{campaign.id}"}
                class="group block rounded-2xl border border-base-content/10 bg-base-100 p-4 transition duration-200 hover:-translate-y-0.5 hover:border-orange-500/30 hover:shadow-lg hover:shadow-orange-950/5"
              >
                <div class="flex items-start justify-between gap-4">
                  <div>
                    <h3 class="font-semibold leading-6 text-base-content group-hover:text-orange-700 dark:group-hover:text-orange-200">
                      {campaign.title}
                    </h3>
                    <p class="mt-1 text-xs text-base-content/50">
                      /{campaign.slug}
                    </p>
                  </div>
                  <.icon
                    name="hero-arrow-up-right"
                    class="mt-1 size-4 shrink-0 text-base-content/40 transition group-hover:text-orange-600"
                  />
                </div>
                <div class="mt-3 flex flex-wrap gap-2">
                  <span class="rounded-full bg-base-200 px-2.5 py-1 text-xs text-base-content/60">
                    {campaign.node_count || 0} nodes
                  </span>
                  <span class="rounded-full bg-base-200 px-2.5 py-1 text-xs text-base-content/60">
                    fetched {Calendar.strftime(campaign.fetched_at, "%b %-d, %Y")}
                  </span>
                </div>
              </.link>
            </div>
          </aside>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp error_message(:blank), do: "Enter a RationalGrid URL or slug."
  defp error_message(:invalid), do: "That does not look like a valid RationalGrid URL or slug."
  defp error_message({:http_error, 404}), do: "RationalGrid did not find media for that grid."
  defp error_message({:http_error, status}), do: "RationalGrid returned HTTP #{status}."

  defp error_message({:request_failed, reason}),
    do: "Could not reach RationalGrid: #{inspect(reason)}"

  defp error_message({:invalid_json, _reason}), do: "RationalGrid returned invalid JSON."

  defp error_message(:invalid_payload),
    do: "RationalGrid returned a payload this app could not understand."

  defp error_message(reason), do: "Could not import grid: #{inspect(reason)}"
end
