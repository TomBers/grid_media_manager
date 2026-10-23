defmodule GridMediaManagerWeb.PerformanceLive do
  use GridMediaManagerWeb, :live_view
  alias GridMediaManager.Social.{Performance, Platforms}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Content results")
     |> assign(:platform, "x")
     |> assign(:syncing?, false)
     |> load_results()}
  end

  @impl true
  def handle_event("platform", %{"platform" => platform}, socket) do
    if platform in Platforms.ids(),
      do: {:noreply, socket |> assign(:platform, platform) |> load_results()},
      else: {:noreply, socket}
  end

  def handle_event("sync", _params, socket) do
    {:noreply,
     socket |> assign(:syncing?, true) |> start_async(:sync, fn -> Performance.sync() end)}
  end

  @impl true
  def handle_async(:sync, {:ok, {:ok, result}}, socket) do
    {:noreply,
     socket
     |> assign(:syncing?, false)
     |> load_results()
     |> put_flash(:info, "Updated #{result.matched} studio posts from Buffer.")}
  end

  def handle_async(:sync, _error, socket) do
    {:noreply,
     socket
     |> assign(:syncing?, false)
     |> put_flash(
       :error,
       "Buffer metrics could not be refreshed. Your saved results are still available."
     )}
  end

  defp load_results(socket) do
    rows = Performance.results(socket.assigns.platform)

    socket
    |> assign(:count, length(rows))
    |> assign(:synced_at, Performance.latest_sync())
    |> stream(:results, rows, reset: true)
  end

  defp metric(nil), do: "—"
  defp metric(value) when is_float(value), do: Float.round(value, 2)
  defp metric(value), do: value
  defp timestamp(nil), do: "Not yet synced"
  defp timestamp(value), do: Calendar.strftime(value, "%d %b %Y · %H:%M UTC")

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div id="content-results" class="mx-auto max-w-7xl px-4 py-12 sm:px-6">
        <div class="flex flex-wrap items-start justify-between gap-6">
          <div class="max-w-2xl">
            <p class="text-xs font-bold uppercase tracking-[0.2em] text-teal-600">
              The feedback loop
            </p>
            <h1 class="mt-3 text-4xl font-semibold tracking-tight">What earns a response?</h1>
            <p class="mt-4 text-base leading-7 text-base-content/65">
              Compare stories within each channel. Clicks, saves, shares and comments come first; views provide context.
            </p>
          </div>
          <div class="text-right">
            <button
              id="sync-performance"
              phx-click="sync"
              disabled={@syncing?}
              class="inline-flex items-center gap-2 rounded-xl bg-teal-700 px-5 py-3 text-sm font-semibold text-white transition hover:bg-teal-600 disabled:opacity-50"
            >
              <.icon
                name="hero-arrow-path"
                class={if(@syncing?, do: "size-4 animate-spin", else: "size-4")}
              />
              {if(@syncing?, do: "Refreshing…", else: "Refresh from Buffer")}
            </button>
            <p id="performance-freshness" class="mt-3 text-xs text-base-content/55">
              Last sync: {timestamp(@synced_at)}
            </p>
          </div>
        </div>
        <div
          id="performance-platforms"
          class="mt-9 flex flex-wrap gap-2"
          aria-label="Choose a channel"
        >
          <button
            :for={platform <- Platforms.ids()}
            id={"results-#{platform}"}
            phx-click="platform"
            phx-value-platform={platform}
            aria-pressed={to_string(@platform == platform)}
            class={[
              "rounded-full border px-4 py-2 text-sm font-semibold transition",
              if(@platform == platform,
                do: "border-teal-700 bg-teal-700 text-white",
                else: "border-base-content/15 hover:bg-base-200"
              )
            ]}
          >
            {Platforms.label(platform)}
          </button>
        </div>
        <p id="performance-sample" class="mt-6 text-sm text-base-content/65">
          {@count} matched studio posts · published 72 hours to 90 days ago · cumulative results, not equal-age comparisons
        </p>
        <div class="mt-4 overflow-x-auto rounded-2xl border border-base-content/10">
          <table class="w-full text-left text-sm">
            <thead class="bg-base-200">
              <tr>
                <th class="p-4">Story</th>
                <th class="p-4">Exposure</th>
                <th class="p-4">Clicks</th>
                <th class="p-4">Saves</th>
                <th class="p-4">Shares</th>
                <th class="p-4">Comments</th>
                <th class="p-4">Avg. watch</th>
              </tr>
            </thead>
            <tbody id="performance-results" phx-update="stream">
              <tr id="performance-empty" class="hidden only:table-row">
                <td colspan="7" class="p-8 text-center text-base-content/60">
                  No mature results yet. Refresh from Buffer after your posts have had at least 72 hours.
                </td>
              </tr>
              <tr :for={{id, row} <- @streams.results} id={id} class="border-t border-base-content/10">
                <td class="min-w-72 max-w-md p-4">
                  <.link
                    navigate={~p"/campaigns/#{row.campaign_id}"}
                    class="font-semibold text-teal-700 hover:underline dark:text-teal-300"
                  >
                    {row.hook}
                  </.link>
                  <p class="mt-2 text-xs text-base-content/50">{timestamp(row.sent_at)}</p>
                  <p class="mt-1 text-xs text-base-content/50">
                    Metrics updated: {if(row.metrics_updated_at,
                      do: timestamp(row.metrics_updated_at),
                      else: "Not reported by Buffer"
                    )}
                  </p>
                </td>
                <td class="p-4">
                  {metric(row.exposure)}<span class="block text-xs text-base-content/50">{row.exposure_label}</span>
                </td>
                <td class="p-4">{metric(row.clicks)}</td>
                <td class="p-4">{metric(row.saves)}</td>
                <td class="p-4">{metric(row.shares)}</td>
                <td class="p-4">{metric(row.comments)}</td>
                <td class="p-4">{metric(row.watch_seconds)}{if(row.watch_seconds, do: "s")}</td>
              </tr>
            </tbody>
          </table>
        </div>
        <p class="mt-5 max-w-3xl text-xs leading-6 text-base-content/55">
          A dash means Buffer did not report that metric. Metrics are experimental and can lag; small samples are directional. New links include channel, campaign and asset UTM tags for RationalGrid analytics. Website visits and conversions require analytics on RationalGrid and are not measured here.
        </p>
      </div>
    </Layouts.app>
    """
  end
end
