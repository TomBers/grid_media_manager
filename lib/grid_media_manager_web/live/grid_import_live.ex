defmodule GridMediaManagerWeb.GridImportLive do
  use GridMediaManagerWeb, :live_view

  alias GridMediaManager.Campaigns
  alias GridMediaManager.RationalGrid.Client
  alias GridMediaManager.RationalGrid.GridIndex

  @page_size 24

  @impl true
  def mount(_params, _session, socket) do
    cached_grids = GridIndex.list(limit: @page_size)
    cached_total = GridIndex.count()
    cached_at = GridIndex.last_refreshed_at()
    cached_tags = GridIndex.list_tags()

    socket =
      socket
      |> assign(:page_title, "RationalGrid Share Studio")
      |> assign(:form, to_form(%{"source" => ""}, as: :import))
      |> assign(:tag_filter_form, to_form(%{"query" => "", "tag" => ""}, as: :filter))
      |> assign(:remote_grid_query, nil)
      |> assign(:remote_grid_filter, nil)
      |> assign(:remote_grid_tags, cached_tags)
      |> assign(:remote_grids_loaded?, not is_nil(cached_at))
      |> assign(:remote_grids_error, nil)
      |> assign(:remote_grids_refreshed_at, cached_at)
      |> assign(:remote_grid_count, cached_total)
      |> assign(:remote_grid_offset, length(cached_grids))
      |> assign(:remote_grids_has_more?, length(cached_grids) < cached_total)
      |> stream_configure(:remote_grids, dom_id: &"remote-grid-#{&1.id}")
      |> stream(:remote_grids, cached_grids)
      |> stream(:campaigns, Campaigns.list_campaigns())

    {:ok, socket}
  end

  @impl true
  def handle_event("import", %{"import" => %{"source" => source}}, socket) do
    import_source(socket, source)
  end

  def handle_event("import_remote_grid", %{"source" => source}, socket) do
    import_source(socket, source)
  end

  def handle_event("filter_remote_grids", %{"filter" => params}, socket) do
    query = normalize_query(Map.get(params, "query"))
    tag = normalize_tag(Map.get(params, "tag"))
    grids = GridIndex.list(query: query, tag: tag, limit: @page_size)
    total = GridIndex.count(query: query, tag: tag)

    {:noreply,
     socket
     |> assign(:remote_grid_query, query)
     |> assign(:remote_grid_filter, tag)
     |> assign(:remote_grid_count, total)
     |> assign(:remote_grid_offset, length(grids))
     |> assign(:remote_grids_has_more?, length(grids) < total)
     |> assign(
       :tag_filter_form,
       to_form(%{"query" => query || "", "tag" => tag || ""}, as: :filter)
     )
     |> stream(:remote_grids, grids, reset: true)}
  end

  def handle_event("load_more_grids", _params, socket) do
    grids =
      GridIndex.list(
        query: socket.assigns.remote_grid_query,
        tag: socket.assigns.remote_grid_filter,
        limit: @page_size,
        offset: socket.assigns.remote_grid_offset
      )

    next_offset = socket.assigns.remote_grid_offset + length(grids)

    {:noreply,
     socket
     |> assign(:remote_grid_offset, next_offset)
     |> assign(:remote_grids_has_more?, next_offset < socket.assigns.remote_grid_count)
     |> stream(:remote_grids, grids)}
  end

  def handle_event("load_remote_grids", _params, socket) do
    case Client.fetch_grid_index() do
      {:ok, grids} ->
        case GridIndex.replace_all(grids) do
          {:ok, _summaries} ->
            refreshed_tags = GridIndex.list_tags()

            selected_tag =
              selected_available_tag(socket.assigns.remote_grid_filter, refreshed_tags)

            refreshed_grids =
              GridIndex.list(
                query: socket.assigns.remote_grid_query,
                tag: selected_tag,
                limit: @page_size
              )

            refreshed_total =
              GridIndex.count(query: socket.assigns.remote_grid_query, tag: selected_tag)

            {:noreply,
             socket
             |> assign(
               :tag_filter_form,
               to_form(
                 %{
                   "query" => socket.assigns.remote_grid_query || "",
                   "tag" => selected_tag || ""
                 },
                 as: :filter
               )
             )
             |> assign(:remote_grid_filter, selected_tag)
             |> assign(:remote_grid_tags, refreshed_tags)
             |> assign(:remote_grids_loaded?, true)
             |> assign(:remote_grids_error, nil)
             |> assign(:remote_grids_refreshed_at, GridIndex.last_refreshed_at())
             |> assign(:remote_grid_count, refreshed_total)
             |> assign(:remote_grid_offset, length(refreshed_grids))
             |> assign(:remote_grids_has_more?, length(refreshed_grids) < refreshed_total)
             |> stream(:remote_grids, refreshed_grids, reset: true)}

          {:error, reason} ->
            {:noreply, assign(socket, :remote_grids_error, cache_error_message(reason))}
        end

      {:error, reason} ->
        {:noreply, assign(socket, :remote_grids_error, refresh_error_message(reason))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="relative isolate overflow-hidden px-4 py-10 sm:px-6 lg:px-8 lg:py-14">
        <div class="absolute inset-x-0 top-0 -z-10 h-80 bg-gradient-to-br from-orange-100 via-amber-50 to-sky-100 opacity-80 blur-3xl dark:from-orange-950/40 dark:via-slate-900 dark:to-indigo-950/40" />

        <div class="mx-auto max-w-7xl">
          <section class="rounded-[2rem] border border-base-content/10 bg-base-100/80 p-6 shadow-2xl shadow-orange-950/5 backdrop-blur md:p-8 lg:p-10">
            <p class="mb-4 inline-flex items-center rounded-full border border-orange-500/20 bg-orange-500/10 px-3 py-1 text-xs font-semibold uppercase tracking-[0.2em] text-orange-700 dark:text-orange-200">
              RationalGrid publishing studio
            </p>

            <h1 class="max-w-3xl text-4xl font-semibold tracking-tight text-base-content text-balance sm:text-5xl lg:text-6xl">
              Turn a grid into a story worth sharing.
            </h1>

            <p class="mt-5 max-w-2xl text-base leading-8 text-base-content/70 sm:text-lg">
              Find a grid, choose the moments that matter, then edit the text directly in polished social assets for X, LinkedIn, Facebook, Instagram, TikTok, and YouTube.
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
                  Your source content stays editable throughout the publishing workflow.
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

            <div
              id="browse-grids"
              class="mt-6 rounded-3xl border border-base-content/10 bg-base-100/70 p-4 shadow-lg shadow-base-content/5 sm:p-5"
            >
              <div class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
                <div>
                  <h2 class="text-lg font-semibold text-base-content">Browse RationalGrid</h2>
                  <p class="mt-1 text-sm leading-6 text-base-content/60">
                    Saved grids are ready when you return. Refresh the list when you want to check RationalGrid for new material.
                  </p>
                  <p
                    id="remote-grids-last-refreshed"
                    class="mt-2 text-xs font-medium text-base-content/45"
                  >
                    <%= if @remote_grids_refreshed_at do %>
                      Saved locally · refreshed {Calendar.strftime(
                        @remote_grids_refreshed_at,
                        "%b %-d, %Y · %H:%M UTC"
                      )}
                    <% else %>
                      No saved grid list yet
                    <% end %>
                  </p>
                </div>
                <div class="flex flex-col gap-3 sm:min-w-80 sm:items-stretch">
                  <.form
                    for={@tag_filter_form}
                    id="remote-grid-filter-form"
                    phx-change="filter_remote_grids"
                    class="grid gap-3"
                  >
                    <.input
                      field={@tag_filter_form[:query]}
                      type="search"
                      label="Search grids"
                      placeholder="Title, slug, or topic"
                      phx-debounce="250"
                    />
                    <.input
                      field={@tag_filter_form[:tag]}
                      type="text"
                      label="Narrow by exact tag"
                      placeholder="Optional"
                      phx-debounce="250"
                    />
                  </.form>
                  <button
                    id="load-remote-grids-button"
                    type="button"
                    phx-click="load_remote_grids"
                    class="inline-flex items-center justify-center rounded-2xl border border-base-content/15 bg-base-100 px-4 py-2.5 text-sm font-semibold text-base-content/75 shadow-sm transition duration-200 hover:-translate-y-0.5 hover:bg-base-200 hover:text-base-content phx-click-loading:opacity-60"
                  >
                    Refresh grid list
                    <.icon name="hero-arrow-path" class="ml-2 size-4 phx-click-loading:animate-spin" />
                  </button>
                </div>
              </div>

              <p
                :if={@remote_grids_error}
                id="remote-grids-error"
                class="mt-4 rounded-2xl border border-red-500/20 bg-red-500/10 px-4 py-3 text-sm text-red-700 dark:text-red-200"
              >
                {@remote_grids_error}
              </p>

              <div
                id="remote-grids"
                phx-update="stream"
                class="mt-5 grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-3"
              >
                <div
                  id="empty-remote-grids"
                  class="hidden rounded-2xl border border-dashed border-base-content/20 bg-base-200/40 p-5 text-sm text-base-content/60 only:col-span-full only:block"
                >
                  <%= if @remote_grids_loaded? do %>
                    No grids were returned by the promotion index endpoint.
                  <% else %>
                    Click “Refresh grid list” to fetch available RationalGrid promotion materials.
                  <% end %>
                </div>

                <article
                  :for={{id, grid} <- @streams.remote_grids}
                  id={id}
                  class="group rounded-2xl border border-base-content/10 bg-base-100 p-4 transition duration-200 hover:-translate-y-0.5 hover:border-orange-500/30 hover:shadow-lg hover:shadow-orange-950/5"
                >
                  <div class="flex min-h-48 flex-col">
                    <div class="min-w-0 flex-1 text-left">
                      <h3 class="line-clamp-2 font-semibold leading-6 text-base-content group-hover:text-orange-700 dark:group-hover:text-orange-200">
                        {grid.title}
                      </h3>
                      <p class="mt-1 line-clamp-1 text-xs text-base-content/50">/{grid.slug}</p>
                    </div>

                    <div class="mt-4 flex flex-wrap items-center gap-2">
                      <button
                        id={"import-remote-grid-#{grid.id}"}
                        type="button"
                        phx-click="import_remote_grid"
                        phx-value-source={grid.source}
                        class="inline-flex items-center rounded-full bg-base-content px-3 py-1.5 text-xs font-bold text-base-100 shadow-sm transition hover:-translate-y-0.5 hover:bg-orange-600 phx-click-loading:cursor-wait phx-click-loading:opacity-60"
                      >
                        Open in studio <.icon name="hero-arrow-right" class="ml-1.5 size-3.5" />
                      </button>
                      <a
                        :if={grid.url}
                        href={grid.url}
                        target="_blank"
                        rel="noopener noreferrer"
                        class="inline-flex items-center rounded-full bg-base-200 px-3 py-1.5 text-xs font-semibold text-base-content/65 transition hover:bg-base-content hover:text-base-100"
                      >
                        Open source <.icon name="hero-arrow-up-right" class="ml-1 size-3" />
                      </a>
                    </div>
                  </div>

                  <div class="mt-3 flex max-h-16 flex-wrap gap-2 overflow-hidden">
                    <span
                      :if={grid.node_count}
                      class="rounded-full border border-base-content/10 bg-base-200/80 px-2.5 py-1 text-xs font-medium text-base-content/60"
                    >
                      {grid.node_count} nodes
                    </span>
                    <span
                      :for={tag <- grid.tags}
                      class="rounded-full border border-indigo-500/15 bg-indigo-500/10 px-2.5 py-1 text-xs font-medium text-indigo-700 dark:text-indigo-200"
                    >
                      {tag}
                    </span>
                  </div>
                </article>
              </div>

              <div class="mt-5 flex flex-wrap items-center justify-between gap-3 border-t border-base-content/10 pt-4">
                <p class="text-sm text-base-content/55">
                  Showing {min(@remote_grid_offset, @remote_grid_count)} of {@remote_grid_count} grids
                </p>
                <button
                  :if={@remote_grids_has_more?}
                  id="load-more-grids"
                  type="button"
                  phx-click="load_more_grids"
                  class="inline-flex items-center rounded-xl border border-base-content/15 bg-base-100 px-4 py-2 text-sm font-semibold text-base-content transition hover:-translate-y-0.5 hover:bg-base-200 phx-click-loading:opacity-60"
                >
                  Show more <.icon name="hero-chevron-down" class="ml-1.5 size-4" />
                </button>
              </div>
            </div>
          </section>

          <aside class="mt-6 rounded-3xl border border-base-content/10 bg-base-100/60 shadow-lg shadow-base-content/5 backdrop-blur">
            <details id="recent-campaigns-panel" class="group" open>
              <summary class="flex cursor-pointer list-none items-center justify-between gap-4 p-4 sm:p-5">
                <span>
                  <span class="block text-sm font-semibold text-base-content">Your recent work</span>
                  <span class="mt-1 block text-xs text-base-content/55">
                    Reopen a previously imported grid when needed.
                  </span>
                </span>
                <span class="flex shrink-0 items-center gap-2 text-xs font-semibold text-base-content/55">
                  Show list
                  <.icon
                    name="hero-chevron-down"
                    class="size-4 transition duration-200 group-open:rotate-180"
                  />
                </span>
              </summary>

              <div
                id="recent-campaigns"
                phx-update="stream"
                class="grid gap-2 border-t border-base-content/10 p-4 sm:grid-cols-2 sm:p-5 lg:grid-cols-3"
              >
                <div
                  id="empty-recent-campaigns"
                  class="hidden rounded-2xl border border-dashed border-base-content/20 bg-base-200/40 p-4 text-sm text-base-content/60 only:col-span-full only:block"
                >
                  No campaigns yet. Import a grid to create the first one.
                </div>

                <.link
                  :for={{id, campaign} <- @streams.campaigns}
                  id={id}
                  navigate={~p"/campaigns/#{campaign.id}/studio"}
                  class="group block rounded-2xl border border-base-content/10 bg-base-100 p-3 transition duration-200 hover:-translate-y-0.5 hover:border-orange-500/30 hover:shadow-lg hover:shadow-orange-950/5"
                >
                  <div class="flex items-start justify-between gap-4">
                    <div class="min-w-0">
                      <h3 class="line-clamp-1 text-sm font-semibold leading-6 text-base-content group-hover:text-orange-700 dark:group-hover:text-orange-200">
                        {campaign.title}
                      </h3>
                      <p class="mt-1 line-clamp-1 text-xs text-base-content/50">
                        /{campaign.slug}
                      </p>
                    </div>
                    <.icon
                      name="hero-arrow-up-right"
                      class="mt-1 size-4 shrink-0 text-base-content/40 transition group-hover:text-orange-600"
                    />
                  </div>
                  <div class="mt-2 flex flex-wrap gap-2">
                    <span class="rounded-full bg-base-200 px-2.5 py-1 text-xs text-base-content/60">
                      {campaign.node_count || 0} nodes
                    </span>
                    <span class="rounded-full bg-base-200 px-2.5 py-1 text-xs text-base-content/60">
                      fetched {Calendar.strftime(campaign.fetched_at, "%b %-d, %Y")}
                    </span>
                  </div>
                </.link>
              </div>
            </details>
          </aside>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp import_source(socket, source) do
    case Campaigns.import_grid(source) do
      {:ok, campaign} ->
        {:noreply,
         socket
         |> put_flash(:info, "Loaded #{campaign.title}")
         |> push_navigate(to: ~p"/campaigns/#{campaign.id}/studio")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:form, to_form(%{"source" => source}, as: :import))
         |> put_flash(:error, error_message(reason))}
    end
  end

  defp error_message(:blank), do: "Enter a RationalGrid URL or slug."
  defp error_message(:invalid), do: "That does not look like a valid RationalGrid URL or slug."

  defp error_message(:untrusted_origin),
    do: "Use a RationalGrid URL from the configured RationalGrid site, or enter its slug."

  defp error_message({:http_error, 401}),
    do: "RationalGrid rejected the request. Check RATIONALGRID_PROMOTION_API_TOKEN."

  defp error_message({:http_error, 403}),
    do: "RationalGrid denied access. Check the promotion API token permissions."

  defp error_message({:http_error, 404}), do: "RationalGrid did not find media for that grid."
  defp error_message({:http_error, status}), do: "RationalGrid returned HTTP #{status}."

  defp error_message({:request_failed, reason}),
    do: "Could not reach RationalGrid: #{inspect(reason)}"

  defp error_message({:invalid_json, _reason}), do: "RationalGrid returned invalid JSON."

  defp error_message(:invalid_payload),
    do: "RationalGrid returned a payload this app could not understand."

  defp error_message(reason), do: "Could not import grid: #{inspect(reason)}"

  defp normalize_tag(tag) when is_binary(tag) do
    case String.trim(tag) do
      "" -> nil
      tag -> tag
    end
  end

  defp normalize_tag(_tag), do: nil

  defp normalize_query(query) when is_binary(query) do
    case String.trim(query) do
      "" -> nil
      value -> value
    end
  end

  defp normalize_query(_query), do: nil

  defp selected_available_tag(nil, _tags), do: nil
  defp selected_available_tag(tag, tags), do: if(tag in tags, do: tag, else: nil)

  defp refresh_error_message(reason) do
    "Could not refresh the RationalGrid list: #{error_message(reason)} Showing the saved list."
  end

  defp cache_error_message(reason) do
    "The RationalGrid list was fetched but could not be saved locally: #{inspect(reason)}"
  end
end
