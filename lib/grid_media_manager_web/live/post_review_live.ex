defmodule GridMediaManagerWeb.PostReviewLive do
  use GridMediaManagerWeb, :live_view

  alias GridMediaManager.Campaigns
  alias GridMediaManager.Campaigns.Campaign
  alias GridMediaManager.Campaigns.MediaAsset
  alias GridMediaManager.Social.Platforms
  alias GridMediaManager.Social.PostReview

  @queue_filters [
    {"attention", "To review"},
    {"approved", "Approved"},
    {"scheduled", "Scheduled"},
    {"published", "Published"},
    {"all", "All"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Proposed post queue")
      |> assign(:queue_filter, "attention")
      |> assign(:queue_filters, @queue_filters)
      |> stream_configure(:post_packages, dom_id: & &1.id)

    {:ok, load_review(socket)}
  end

  def handle_event("filter_queue", %{"status" => status}, socket) do
    status = if status in Enum.map(@queue_filters, &elem(&1, 0)), do: status, else: "attention"
    {:noreply, socket |> assign(:queue_filter, status) |> load_review()}
  end

  @impl true
  def handle_event("approve_all_posts", _params, socket) do
    ids = socket.assigns.pending_ids
    package_count = socket.assigns.pending_count

    case Campaigns.approve_post_drafts(ids) do
      {:ok, approved} ->
        {:noreply,
         socket
         |> load_review()
         |> put_flash(
           :info,
           "Approved #{package_count} #{if(package_count == 1, do: "post", else: "posts")} across #{length(approved)} channel drafts."
         )}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not approve the proposed posts.")}
    end
  end

  def handle_event("delete_post_package", %{"package-id" => package_id}, socket) do
    case Map.get(socket.assigns.package_by_id, package_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "That proposal is no longer in the queue.")}

      package ->
        case Campaigns.delete_post_drafts(package.deletable_ids) do
          {:ok, deleted_count} ->
            {:noreply,
             socket
             |> load_review()
             |> put_flash(
               :info,
               "Removed the proposal from the queue across #{deleted_count} channel drafts."
             )}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, "Could not remove that proposal.")}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="relative isolate min-h-screen overflow-hidden px-4 py-8 sm:px-6 lg:px-8 lg:py-12">
        <div class="absolute inset-x-0 top-0 -z-10 h-96 bg-gradient-to-br from-orange-100 via-amber-50 to-sky-100 opacity-80 blur-3xl dark:from-orange-950/40 dark:via-slate-900 dark:to-indigo-950/40" />

        <div class="mx-auto max-w-7xl space-y-6">
          <header class="rounded-[2rem] border border-base-content/10 bg-base-100/85 p-6 shadow-2xl shadow-base-content/5 backdrop-blur md:p-8">
            <div class="flex flex-col gap-6 lg:flex-row lg:items-end lg:justify-between">
              <div>
                <.link
                  navigate={~p"/"}
                  class="inline-flex items-center text-sm font-semibold text-base-content/55 transition hover:text-base-content"
                >
                  <.icon name="hero-arrow-left" class="mr-2 size-4" /> Back to campaigns
                </.link>
                <p class="mt-6 text-xs font-bold uppercase tracking-[0.2em] text-orange-600 dark:text-orange-300">
                  Global post queue
                </p>
                <h1 class="mt-2 max-w-4xl text-3xl font-semibold tracking-tight text-base-content text-balance sm:text-5xl">
                  Review potential posts before they go live.
                </h1>
                <p class="mt-4 max-w-3xl text-base leading-7 text-base-content/65">
                  This is a simple queue across every campaign. Remove anything that is not right, approve what is ready, then open its campaign post page when you want to schedule it to Buffer.
                </p>
              </div>

              <div class="shrink-0 rounded-3xl border border-sky-500/20 bg-sky-500/5 p-4 lg:w-72">
                <p class="text-xs font-bold uppercase tracking-[0.16em] text-sky-700 dark:text-sky-200">
                  One-click approval
                </p>
                <p class="mt-2 text-sm leading-6 text-base-content/65">
                  Approve the complete proposed queue together after checking the copy and timing.
                </p>
                <button
                  id="approve-all-posts"
                  type="button"
                  phx-click="approve_all_posts"
                  phx-confirm="Approve all proposed posts? This will not publish or schedule them."
                  disabled={@pending_count == 0}
                  class="mt-4 inline-flex w-full items-center justify-center rounded-2xl bg-emerald-600 px-4 py-3 text-sm font-bold text-white shadow-lg shadow-emerald-900/15 transition hover:-translate-y-0.5 hover:bg-emerald-500 disabled:cursor-not-allowed disabled:opacity-40"
                >
                  <.icon name="hero-check-circle" class="mr-2 size-5" />
                  Approve {@pending_count} {if(@pending_count == 1, do: "post", else: "posts")}
                </button>
              </div>
            </div>
          </header>

          <section id="post-review-summary" class="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
            <div class="rounded-3xl border border-base-content/10 bg-base-100/80 p-5 shadow-lg shadow-base-content/5">
              <p class="text-xs font-bold uppercase tracking-[0.16em] text-base-content/45">
                Proposed posts
              </p>
              <p class="mt-2 text-3xl font-semibold text-base-content">{@package_count}</p>
            </div>
            <div class="rounded-3xl border border-amber-500/20 bg-amber-500/5 p-5 shadow-lg shadow-base-content/5">
              <p class="text-xs font-bold uppercase tracking-[0.16em] text-amber-700 dark:text-amber-200">
                Awaiting approval
              </p>
              <p class="mt-2 text-3xl font-semibold text-base-content">{@pending_count}</p>
            </div>
            <div class="rounded-3xl border border-red-500/20 bg-red-500/5 p-5 shadow-lg shadow-base-content/5">
              <p class="text-xs font-bold uppercase tracking-[0.16em] text-red-700 dark:text-red-200">
                Needs attention
              </p>
              <p class="mt-2 text-3xl font-semibold text-base-content">{@failed_count}</p>
            </div>
            <div class="rounded-3xl border border-emerald-500/20 bg-emerald-500/5 p-5 shadow-lg shadow-base-content/5">
              <p class="text-xs font-bold uppercase tracking-[0.16em] text-emerald-700 dark:text-emerald-200">
                Queue state
              </p>
              <p class="mt-2 text-xl font-semibold text-base-content">
                {queue_state(@package_count, @pending_count, @failed_count)}
              </p>
            </div>
          </section>

          <nav
            id="post-review-filters"
            aria-label="Filter publishing queue"
            class="flex flex-wrap gap-2 rounded-2xl border border-base-content/10 bg-base-100/80 p-2 shadow-sm"
          >
            <button
              :for={{status, label} <- @queue_filters}
              id={"post-review-filter-#{status}"}
              type="button"
              phx-click="filter_queue"
              phx-value-status={status}
              aria-pressed={@queue_filter == status}
              class={[
                "inline-flex items-center gap-2 rounded-xl px-3 py-2 text-sm font-bold transition",
                @queue_filter == status && "bg-base-content text-base-100 shadow-sm",
                @queue_filter != status &&
                  "text-base-content/60 hover:bg-base-200 hover:text-base-content"
              ]}
            >
              {label}
              <span class={[
                "rounded-full px-2 py-0.5 text-xs",
                @queue_filter == status && "bg-base-100/15",
                @queue_filter != status && "bg-base-200"
              ]}>
                {Map.get(@queue_counts, status, 0)}
              </span>
            </button>
          </nav>

          <section
            id="post-review-packages"
            phx-update="stream"
            class="mx-auto max-w-6xl space-y-5"
          >
            <div
              id="empty-post-review-packages"
              class="hidden rounded-[2rem] border border-dashed border-base-content/20 bg-base-100/70 p-10 text-center text-base-content/55 only:block xl:col-span-2"
            >
              No posts match this view.
            </div>
            <.post_package
              :for={{id, package} <- @streams.post_packages}
              id={id}
              package={package}
            />
          </section>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp load_review(socket) do
    drafts =
      Campaigns.list_all_post_drafts()
      |> Enum.filter(&PostReview.valid_for_asset?/1)
      |> Enum.filter(&PostReview.queueable?/1)

    all_packages = PostReview.packages(drafts)
    packages = filter_packages(all_packages, socket.assigns.queue_filter)
    pending_ids = Enum.flat_map(all_packages, & &1.reviewable_ids)
    pending_count = Enum.count(all_packages, &PostReview.pending?/1)

    socket
    |> assign(:package_count, length(all_packages))
    |> assign(:queue_counts, queue_counts(all_packages))
    |> assign(:pending_count, pending_count)
    |> assign(:pending_draft_count, length(pending_ids))
    |> assign(:pending_ids, pending_ids)
    |> assign(:package_by_id, Map.new(all_packages, &{&1.id, &1}))
    |> assign(:failed_count, Enum.count(all_packages, &(&1.status == "failed")))
    |> stream(:post_packages, packages, reset: true)
  end

  defp filter_packages(packages, "attention"),
    do: Enum.filter(packages, &(&1.status in ["draft", "failed"]))

  defp filter_packages(packages, "all"), do: packages
  defp filter_packages(packages, status), do: Enum.filter(packages, &(&1.status == status))

  defp queue_counts(packages) do
    %{
      "attention" => Enum.count(packages, &(&1.status in ["draft", "failed"])),
      "approved" => Enum.count(packages, &(&1.status == "approved")),
      "scheduled" => Enum.count(packages, &(&1.status == "scheduled")),
      "published" => Enum.count(packages, &(&1.status == "published")),
      "all" => length(packages)
    }
  end

  attr :id, :string, required: true
  attr :package, :map, required: true

  defp post_package(assigns) do
    ~H"""
    <article
      id={@id}
      class="overflow-hidden rounded-[2rem] border border-base-content/10 bg-base-100 shadow-xl shadow-base-content/5 transition-shadow hover:shadow-2xl"
    >
      <div class="grid gap-0 lg:grid-cols-[20rem_minmax(0,1fr)]">
        <div class="bg-base-200/70 p-5">
          <%= if @package.asset && @package.artifacts_ready? do %>
            <%= if video_asset?(@package.asset) do %>
              <video
                id={"#{@id}-video"}
                controls
                preload="metadata"
                class="aspect-[9/16] w-full rounded-2xl bg-black object-contain shadow-lg"
              >
                <source src={package_preview_url(@package)} type="video/mp4" />
              </video>
            <% else %>
              <%= if length(@package.preview_images) > 1 do %>
                <div id={"#{@id}-carousel-previews"} class="grid grid-cols-2 gap-3">
                  <figure :for={preview <- @package.preview_images} class="relative">
                    <img
                      id={"#{@id}-carousel-slide-#{preview.index}"}
                      src={preview.url}
                      alt={"#{package_title(@package)} · image #{preview.index}"}
                      loading="lazy"
                      class="aspect-[4/5] w-full rounded-2xl bg-base-200 object-contain shadow-lg"
                    />
                    <figcaption class="absolute bottom-2 left-2 rounded-full bg-black/70 px-2 py-1 text-[0.68rem] font-bold text-white">
                      {preview.index}
                    </figcaption>
                  </figure>
                </div>
              <% else %>
                <img
                  id={"#{@id}-image"}
                  src={package_preview_url(@package)}
                  alt={package_title(@package)}
                  loading="lazy"
                  class="aspect-[4/5] w-full rounded-2xl bg-base-200 object-contain shadow-lg"
                />
              <% end %>
            <% end %>
          <% else %>
            <div class="grid aspect-[4/5] place-items-center rounded-2xl border border-dashed border-base-content/15 bg-base-100 px-5 text-center text-sm font-semibold text-base-content/45">
              <div>
                <.icon name="hero-photo" class="mx-auto mb-3 size-7" />
                <p>Finished media is not ready yet.</p>
                <.link
                  navigate={
                    ~p"/campaigns/#{@package.campaign_id}/studio?step=review&asset=#{@package.asset && @package.asset.id}"
                  }
                  class="mt-3 inline-flex text-xs font-bold text-sky-700 dark:text-sky-200"
                >
                  Open the campaign to finish it
                </.link>
              </div>
            </div>
          <% end %>
        </div>

        <div class="min-w-0 p-6 md:p-8">
          <div class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
            <div class="min-w-0">
              <div class="flex flex-wrap items-center gap-2">
                <span class={kind_badge_class(@package.kind)}>
                  {if(@package.kind == :video, do: "Video", else: "Text card")}
                </span>
                <span class="rounded-full bg-base-200 px-3 py-1 text-xs font-bold text-base-content/60">
                  {platform_labels(@package.platforms)}
                </span>
              </div>
              <h2 class="mt-3 text-xl font-bold leading-7 text-base-content md:text-2xl">
                {package_title(@package)}
              </h2>
              <.link
                id={"open-post-page-#{@id}"}
                navigate={~p"/campaigns/#{@package.campaign_id}/studio"}
                class="mt-1 inline-flex items-center text-xs font-bold text-sky-700 transition hover:text-sky-500 dark:text-sky-200"
              >
                {campaign_title(@package)} <.icon name="hero-arrow-right" class="ml-1 size-3" />
              </.link>
              <p class="mt-1 text-xs text-base-content/45">
                One logical post · {length(@package.drafts)} channels
                <%= if length(@package.preview_images) > 1 do %>
                  · {length(@package.preview_images)} images in order
                <% end %>
              </p>
            </div>

            <div class="flex shrink-0 flex-wrap items-center justify-end gap-2">
              <span class={status_badge_class(@package.status)}>
                {String.capitalize(@package.status)}
              </span>
              <button
                :if={@package.deletable_ids != []}
                id={"remove-post-package-#{@id}"}
                type="button"
                phx-click="delete_post_package"
                phx-value-package-id={@package.id}
                phx-confirm="Remove this proposal from the queue? It will not be posted to Buffer."
                class="inline-flex items-center rounded-xl border border-red-500/20 bg-red-500/5 px-2.5 py-1.5 text-xs font-bold text-red-700 transition hover:bg-red-500/10 dark:text-red-200"
              >
                <.icon name="hero-trash" class="mr-1 size-3.5" /> Remove
              </button>
            </div>
          </div>

          <div class="mt-5 rounded-2xl border border-sky-500/20 bg-sky-500/5 px-4 py-3">
            <p class="text-[0.68rem] font-bold uppercase tracking-[0.16em] text-sky-700 dark:text-sky-200">
              {if(@package.suggested?, do: "Suggested publish time", else: "Scheduled publish time")}
            </p>
            <p class="mt-1 text-sm font-bold text-base-content">
              {Calendar.strftime(@package.suggested_for, "%A, %b %-d · %H:%M UTC")}
            </p>
          </div>

          <div class="mt-7">
            <div class="flex items-center justify-between gap-3">
              <p class="text-xs font-bold uppercase tracking-[0.16em] text-base-content/45">
                Post copy
              </p>
              <span class="text-xs font-semibold text-base-content/40">
                {length(@package.copy_variants)} {if(length(@package.copy_variants) == 1,
                  do: "version",
                  else: "versions"
                )}
              </span>
            </div>
            <div
              :if={length(@package.copy_variants) > 1}
              class="mt-2 rounded-2xl border border-amber-500/25 bg-amber-500/10 px-4 py-3 text-xs font-semibold leading-5 text-amber-800 dark:text-amber-100"
            >
              These channel drafts do not currently have identical copy. Review the variants before approving.
            </div>
            <div class="mt-3 space-y-3">
              <div
                :for={variant <- @package.copy_variants}
                class="rounded-2xl border border-base-content/10 bg-base-200/40 p-5"
              >
                <p
                  :if={length(@package.copy_variants) > 1}
                  class="mb-2 text-[0.68rem] font-bold uppercase tracking-wide text-base-content/45"
                >
                  {platform_labels(variant.platforms)}
                </p>
                <div class="whitespace-pre-wrap break-words text-base leading-8 text-base-content/85">
                  {variant.body}
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </article>
    """
  end

  defp video_asset?(%MediaAsset{mime_type: "video/mp4"}), do: true
  defp video_asset?(_asset), do: false

  defp package_preview_url(%{preview_images: [%{url: url} | _rest]}), do: url
  defp package_preview_url(_package), do: nil

  defp package_title(%{asset: %MediaAsset{title: title}}) when is_binary(title) and title != "",
    do: title

  defp package_title(_package), do: "Campaign post"

  defp campaign_title(%{campaign: %Campaign{title: title}}) when is_binary(title) and title != "",
    do: title

  defp campaign_title(%{campaign_id: campaign_id}), do: "Campaign #{campaign_id}"

  defp platform_labels(platforms), do: Enum.map_join(platforms, ", ", &Platforms.label/1)

  defp queue_state(0, _pending_count, _failed_count), do: "Empty"

  defp queue_state(_package_count, _pending_count, failed_count) when failed_count > 0,
    do: "Needs attention"

  defp queue_state(_package_count, pending_count, _failed_count) when pending_count > 0,
    do: "Needs review"

  defp queue_state(_package_count, _pending_count, _failed_count), do: "Up to date"

  defp kind_badge_class(:video),
    do:
      "rounded-full bg-violet-500/10 px-3 py-1 text-xs font-bold text-violet-700 dark:text-violet-200"

  defp kind_badge_class(:text),
    do:
      "rounded-full bg-orange-500/10 px-3 py-1 text-xs font-bold text-orange-700 dark:text-orange-200"

  defp status_badge_class("approved"),
    do:
      "rounded-full bg-emerald-500/10 px-3 py-1 text-xs font-bold uppercase tracking-wide text-emerald-700 dark:text-emerald-200"

  defp status_badge_class("scheduled"),
    do:
      "rounded-full bg-sky-500/10 px-3 py-1 text-xs font-bold uppercase tracking-wide text-sky-700 dark:text-sky-200"

  defp status_badge_class("published"),
    do:
      "rounded-full bg-base-content/10 px-3 py-1 text-xs font-bold uppercase tracking-wide text-base-content/60"

  defp status_badge_class("failed"),
    do:
      "rounded-full bg-red-500/10 px-3 py-1 text-xs font-bold uppercase tracking-wide text-red-700 dark:text-red-200"

  defp status_badge_class(_status),
    do:
      "rounded-full bg-amber-500/10 px-3 py-1 text-xs font-bold uppercase tracking-wide text-amber-700 dark:text-amber-200"
end
