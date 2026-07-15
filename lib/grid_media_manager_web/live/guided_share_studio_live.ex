defmodule GridMediaManagerWeb.GuidedShareStudioLive do
  use GridMediaManagerWeb, :live_view

  alias GridMediaManager.Campaigns
  alias GridMediaManager.Campaigns.MediaAsset
  alias GridMediaManager.Campaigns.PostDraft
  alias GridMediaManager.Pexels.Client, as: Pexels
  alias GridMediaManager.Promotion.ShareCard
  alias GridMediaManager.Social.Buffer
  alias GridMediaManager.Social.Platforms
  alias GridMediaManager.Social.Templates
  alias GridMediaManager.Studio.Workflow

  @max_selection 6
  @steps [
    %{id: "curate", label: "Curate", description: "Find the signal"},
    %{id: "design", label: "Design", description: "Shape the media"},
    %{id: "generate", label: "Generate", description: "Create the package"},
    %{id: "review", label: "Review", description: "Refine and approve"}
  ]
  @candidate_filters [
    %{id: "all", label: "All signals"},
    %{id: "question", label: "Questions"},
    %{id: "highlight", label: "Highlights"},
    %{id: "key_node", label: "Key nodes"},
    %{id: "grid", label: "Overview"}
  ]
  @formats [
    %{
      id: "story_video",
      label: "Combined story video",
      size: "One 1080 × 1920 MP4",
      description:
        "Turn all selected moments into one coherent vertical video for TikTok, YouTube Shorts, and Instagram Reels.",
      icon: "hero-play-circle"
    },
    %{
      id: "landscape",
      label: "Feed hook",
      size: "1200 × 630 · X / Bluesky",
      description: "A concise landscape hook for fast feeds, links, and reposts.",
      icon: "hero-photo"
    },
    %{
      id: "linkedin",
      label: "LinkedIn explainer",
      size: "1200 × 1200",
      description: "A square, copy-dense layout that gives an argument room to develop.",
      icon: "hero-briefcase"
    },
    %{
      id: "portrait",
      label: "Instagram portrait",
      size: "1080 × 1350 · 4:5",
      description: "A feed-filling reading card with comfortable title and excerpt hierarchy.",
      icon: "hero-device-phone-mobile"
    },
    %{
      id: "carousel",
      label: "Instagram carousel + Shorts",
      size: "1080 × 1350 PNG · 1080 × 1920 MP4",
      description:
        "Key nodes become a carousel; questions and highlights become a portrait plus a six-second Short.",
      icon: "hero-rectangle-stack"
    },
    %{
      id: "combined_carousel",
      label: "Combined story carousel",
      size: "One carousel + one 1080 × 1920 Short",
      description:
        "Turn all selected questions, highlights, and key nodes into one coherent swipeable story and companion video.",
      icon: "hero-squares-plus"
    }
  ]

  @impl true
  def mount(%{"id" => id} = params, _session, socket) do
    campaign = Campaigns.get_campaign!(id)
    candidates = Workflow.candidates(campaign)
    restored_assets = restored_output_assets(campaign, params)
    restored_asset_ids = MapSet.new(restored_assets, & &1.id)
    restored_step = if restored_assets == [], do: "curate", else: "review"
    restored_platforms = restore_platforms(params)
    restored_asset_filter = restore_asset_filter(params, restored_asset_ids)
    restored_video_only? = restored_assets != [] and Enum.all?(restored_assets, &video_asset?/1)

    restored_content_mode =
      if restored_assets == [] or Enum.any?(restored_assets, &video_asset?/1),
        do: "video",
        else: "text"

    previous_packages = previous_output_packages(campaign)
    selected_keys = Workflow.default_selection(candidates)

    selected_order =
      candidates
      |> Workflow.selected_candidates(selected_keys)
      |> Enum.map(& &1.key)

    socket =
      socket
      |> assign(:page_title, "Guided studio · #{campaign.title}")
      |> assign(:campaign, campaign)
      |> assign(:max_selection, @max_selection)
      |> assign(:steps, @steps)
      |> assign(:candidate_filters, @candidate_filters)
      |> assign(:formats, @formats)
      |> assign(:card_styles, ShareCard.styles())
      |> assign(:platforms, Platforms.all())
      |> assign(:all_candidates, candidates)
      |> assign(:candidate_by_key, Map.new(candidates, &{&1.key, &1}))
      |> assign(:candidate_filter, "all")
      |> assign(:selected_keys, selected_keys)
      |> assign(:selected_order, selected_order)
      |> assign(:selected_count, MapSet.size(selected_keys))
      |> assign(:step, restored_step)
      |> assign(:selected_style, ShareCard.default_style())
      |> assign(:content_mode, restored_content_mode)
      |> assign(
        :selected_format,
        if(restored_content_mode == "video", do: "story_video", else: "portrait")
      )
      |> assign(:selected_platforms, restored_platforms)
      |> assign(:selected_output_asset_id, restored_asset_filter)
      |> assign(:output_asset_ids, restored_asset_ids)
      |> assign(:output_asset_count, length(restored_assets))
      |> assign(:output_video_only?, restored_video_only?)
      |> assign(:review_draft_count, 0)
      |> assign(:review_schedulable_count, 0)
      |> assign(:bulk_schedule_form, to_form(%{"scheduled_for" => ""}, as: :bulk_schedule))
      |> assign(:previous_package_count, length(previous_packages))
      |> assign(:generation_error, nil)
      |> assign(:pexels_configured?, Pexels.configured?())
      |> assign(:pexels_search_form, to_form(%{"query" => campaign.title}, as: :pexels))
      |> assign(:pexels_search_error, nil)
      |> assign(:pexels_by_id, %{})
      |> assign(:selected_pexels_background, Campaigns.pexels_background(campaign))
      |> stream_configure(:candidates, dom_id: &"candidate-#{&1.dom_id}")
      |> stream_configure(:selected_aspects, dom_id: &"selected-#{&1.dom_id}")
      |> stream_configure(:output_assets, dom_id: &"guided-output-#{&1.id}")
      |> stream_configure(:review_drafts, dom_id: &"guided-draft-#{&1.id}")
      |> stream_configure(:pexels_photos, dom_id: &"pexels-photo-#{&1.id}")
      |> stream_configure(:previous_packages, dom_id: &"previous-package-#{&1.dom_id}")
      |> stream(:candidates, candidate_items(candidates, selected_keys))
      |> stream(:selected_aspects, Workflow.selected_candidates(candidates, selected_order))
      |> stream(:output_assets, restored_assets)
      |> stream(:review_drafts, [])
      |> stream(:pexels_photos, [])
      |> stream(:previous_packages, previous_packages)
      |> maybe_restore_review_drafts(restored_assets)

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event("filter_candidates", %{"filter" => filter}, socket) do
    filter = if filter in Enum.map(@candidate_filters, & &1.id), do: filter, else: "all"

    candidates = Workflow.filter_candidates(socket.assigns.all_candidates, filter)

    {:noreply,
     socket
     |> assign(:candidate_filter, filter)
     |> stream(:candidates, candidate_items(candidates, socket.assigns.selected_keys),
       reset: true
     )}
  end

  def handle_event("toggle_aspect", %{"key" => key}, socket) do
    case Map.get(socket.assigns.candidate_by_key, key) do
      nil ->
        {:noreply, socket}

      candidate ->
        toggle_candidate(socket, candidate)
    end
  end

  def handle_event("continue_to_design", _params, socket) do
    {:noreply, move_to_step(socket, "design")}
  end

  def handle_event("continue_to_generate", _params, socket) do
    {:noreply, move_to_step(socket, "generate")}
  end

  def handle_event("go_to_step", %{"step" => step}, socket) do
    {:noreply, move_to_step(socket, step)}
  end

  def handle_event("select_style", %{"style" => style}, socket) do
    {:noreply, assign(socket, :selected_style, ShareCard.normalize_style(style))}
  end

  def handle_event("select_format", %{"format" => format}, socket) do
    format = if format in Enum.map(@formats, & &1.id), do: format, else: "landscape"

    content_mode =
      if format in ["story_video", "carousel", "combined_carousel"], do: "video", else: "text"

    {:noreply,
     socket
     |> assign(:selected_format, format)
     |> assign(:content_mode, content_mode)}
  end

  def handle_event("select_content_mode", %{"mode" => mode}, socket)
      when mode in ["video", "text"] do
    selected_format = if mode == "video", do: "story_video", else: "portrait"
    selected_platforms = content_mode_platforms(socket.assigns.selected_platforms, mode)

    {:noreply,
     socket
     |> assign(:content_mode, mode)
     |> assign(:selected_format, selected_format)
     |> assign(:selected_platforms, selected_platforms)}
  end

  def handle_event("select_content_mode", _params, socket), do: {:noreply, socket}

  def handle_event("search_pexels", %{"pexels" => %{"query" => query}}, socket) do
    case Pexels.search(query,
           orientation: pexels_orientation(socket.assigns.selected_format),
           per_page: 8
         ) do
      {:ok, photos} ->
        {:noreply,
         socket
         |> assign(:pexels_search_form, to_form(%{"query" => query}, as: :pexels))
         |> assign(:pexels_search_error, nil)
         |> assign(:pexels_by_id, Map.new(photos, &{to_string(&1.id), &1}))
         |> stream(:pexels_photos, photos, reset: true)}

      {:error, reason} ->
        {:noreply, assign(socket, :pexels_search_error, pexels_error_message(reason))}
    end
  end

  def handle_event("select_pexels_background", %{"id" => id}, socket) do
    case Map.get(socket.assigns.pexels_by_id, id) do
      nil ->
        {:noreply, put_flash(socket, :error, "That Pexels photo is no longer available.")}

      photo ->
        case Campaigns.set_pexels_background(socket.assigns.campaign, photo) do
          {:ok, campaign} ->
            {:noreply,
             socket
             |> assign(:campaign, campaign)
             |> assign(:selected_pexels_background, Campaigns.pexels_background(campaign))
             |> put_flash(:info, "Pexels background selected for this package.")}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Could not save that background.")}
        end
    end
  end

  def handle_event("clear_pexels_background", _params, socket) do
    case Campaigns.clear_pexels_background(socket.assigns.campaign) do
      {:ok, campaign} ->
        {:noreply,
         socket
         |> assign(:campaign, campaign)
         |> assign(:selected_pexels_background, nil)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not clear that background.")}
    end
  end

  def handle_event("generate_package", _params, socket) do
    selected_candidates =
      socket.assigns.all_candidates
      |> Workflow.selected_candidates(socket.assigns.selected_order)
      |> maybe_text_quote_candidates(socket.assigns.content_mode, socket.assigns.all_candidates)

    format =
      if socket.assigns.content_mode == "text",
        do: "portrait",
        else: socket.assigns.selected_format

    result =
      Workflow.generate(socket.assigns.campaign, selected_candidates,
        style: socket.assigns.selected_style,
        format: format
      )

    complete_generation(socket, result)
  end

  def handle_event("toggle_platform", %{"platform" => platform}, socket) do
    if platform in Platforms.ids() do
      selected_platforms =
        if platform in socket.assigns.selected_platforms do
          List.delete(socket.assigns.selected_platforms, platform)
        else
          socket.assigns.selected_platforms ++ [platform]
        end

      if selected_platforms == [] do
        {:noreply, put_flash(socket, :error, "Choose at least one channel for this package.")}
      else
        socket =
          socket
          |> assign(:selected_platforms, selected_platforms)
          |> ensure_review_channel_drafts(platform)
          |> refresh_review_drafts()
          |> maybe_patch_review_url()

        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("select_platform", params, socket),
    do: handle_event("toggle_platform", params, socket)

  def handle_event("select_output_asset", %{"id" => asset_id}, socket) do
    asset_id = valid_output_asset_filter(socket.assigns.output_asset_ids, asset_id)

    {:noreply,
     socket
     |> assign(:selected_output_asset_id, asset_id)
     |> refresh_review_drafts()
     |> maybe_patch_review_url()}
  end

  def handle_event("save_draft", %{"id" => id, "post_draft" => %{"body" => body}}, socket) do
    draft = Campaigns.get_post_draft!(id)

    if editable_draft?(socket, draft) do
      case Campaigns.update_post_draft(draft, %{body: body, status: "draft"}) do
        {:ok, updated_draft} ->
          updated_draft = Campaigns.get_post_draft_with_asset!(updated_draft.id)
          {:noreply, stream_insert(socket, :review_drafts, draft_item(updated_draft))}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Could not save this draft.")}
      end
    else
      {:noreply, put_flash(socket, :error, "That draft is not part of this package.")}
    end
  end

  def handle_event(
        "schedule_draft",
        %{"id" => id, "schedule" => %{"scheduled_for" => scheduled_for}},
        socket
      ) do
    draft = Campaigns.get_post_draft!(id)

    if editable_draft?(socket, draft) do
      case Campaigns.schedule_post_draft(id, scheduled_for) do
        {:ok, scheduled_draft} ->
          scheduled_draft = Campaigns.get_post_draft_with_asset!(scheduled_draft.id)

          {:noreply,
           socket
           |> stream_insert(:review_drafts, draft_item(scheduled_draft))
           |> put_flash(:info, "Post scheduled through Buffer.")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, reason)}
      end
    else
      {:noreply, put_flash(socket, :error, "That draft is not part of this package.")}
    end
  end

  def handle_event(
        "schedule_selected_drafts",
        %{"bulk_schedule" => %{"scheduled_for" => _scheduled_for}},
        %{assigns: %{content_mode: "text"}} = socket
      ) do
    {:noreply,
     put_flash(socket, :info, "Text packages are manual. Copy or download each post instead.")}
  end

  def handle_event(
        "schedule_selected_drafts",
        %{"bulk_schedule" => %{"scheduled_for" => scheduled_for}},
        socket
      ) do
    drafts =
      socket.assigns.campaign
      |> Campaigns.list_post_drafts()
      |> Enum.filter(&(&1.platform in socket.assigns.selected_platforms))
      |> Enum.filter(&review_draft?(socket, &1))
      |> deduplicate_review_drafts()
      |> schedulable_drafts()
      |> Enum.reject(&(&1.status == "scheduled"))

    results = Enum.map(drafts, &Campaigns.schedule_post_draft(&1.id, scheduled_for))
    scheduled_count = Enum.count(results, &match?({:ok, _draft}, &1))
    failed_count = length(results) - scheduled_count

    socket = refresh_review_drafts(socket)

    cond do
      drafts == [] ->
        {:noreply, put_flash(socket, :info, "All matching posts are already scheduled.")}

      failed_count == 0 ->
        {:noreply,
         put_flash(
           socket,
           :info,
           "Scheduled #{scheduled_count} #{if(scheduled_count == 1, do: "post", else: "posts")} through Buffer."
         )}

      true ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Scheduled #{scheduled_count} posts; #{failed_count} could not be scheduled. Check Buffer connections."
         )}
    end
  end

  def handle_event("approve_draft", %{"id" => id}, socket) do
    draft = Campaigns.get_post_draft!(id)

    if editable_draft?(socket, draft) do
      case Campaigns.approve_post_draft(id) do
        {:ok, approved_draft} ->
          approved_draft = Campaigns.get_post_draft_with_asset!(approved_draft.id)
          {:noreply, stream_insert(socket, :review_drafts, draft_item(approved_draft))}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Could not approve this draft.")}
      end
    else
      {:noreply, put_flash(socket, :error, "That draft is not part of this package.")}
    end
  end

  def handle_event("copied", %{"draft_id" => id}, socket) when is_binary(id) and id != "" do
    draft = Campaigns.get_post_draft!(id)

    if editable_draft?(socket, draft) do
      case Campaigns.mark_post_draft_copied(id) do
        {:ok, copied_draft} ->
          copied_draft = Campaigns.get_post_draft_with_asset!(copied_draft.id)
          {:noreply, stream_insert(socket, :review_drafts, draft_item(copied_draft))}

        {:error, _changeset} ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("copied", _params, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div
        id="guided-share-studio"
        class="relative isolate min-h-screen overflow-hidden px-4 py-8 sm:px-6 lg:px-8 lg:py-10"
      >
        <div class="pointer-events-none absolute inset-x-0 top-0 -z-10 h-[34rem] bg-[radial-gradient(circle_at_top_left,rgba(249,115,22,0.17),transparent_38%),radial-gradient(circle_at_top_right,rgba(14,165,233,0.13),transparent_36%)]" />

        <div class="mx-auto max-w-7xl space-y-6">
          <header class="overflow-hidden rounded-[2rem] border border-base-content/10 bg-base-100/85 shadow-2xl shadow-base-content/5 backdrop-blur-xl">
            <div class="grid gap-8 p-6 md:p-8 lg:grid-cols-[1fr_auto] lg:items-end lg:p-10">
              <div>
                <div class="flex flex-wrap items-center gap-3">
                  <span class="inline-flex items-center rounded-full bg-orange-500/10 px-3 py-1 text-xs font-bold uppercase tracking-[0.2em] text-orange-700 dark:text-orange-200">
                    Studio v2 · guided workflow
                  </span>
                  <span class="inline-flex items-center rounded-full border border-base-content/10 bg-base-100 px-3 py-1 text-xs font-medium text-base-content/55">
                    Human in the loop
                  </span>
                </div>

                <h1 class="mt-5 max-w-4xl text-3xl font-semibold tracking-tight text-base-content text-balance sm:text-4xl lg:text-5xl">
                  Turn this grid into a story people want to join.
                </h1>
                <p class="mt-4 max-w-3xl text-base leading-7 text-base-content/65">
                  Curate the strongest questions, human highlights, and key ideas. Then shape a coherent visual package and refine the invitation for each social channel.
                </p>

                <div class="mt-6 flex flex-wrap items-center gap-3 text-sm text-base-content/55">
                  <span class="inline-flex items-center gap-1.5">
                    <.icon name="hero-squares-2x2" class="size-4" /> {@campaign.node_count || 0} nodes
                  </span>
                  <span class="size-1 rounded-full bg-base-content/25" />
                  <span>{length(@all_candidates)} candidate moments</span>
                  <span class="size-1 rounded-full bg-base-content/25" />
                  <a
                    href={@campaign.grid_url}
                    target="_blank"
                    rel="noopener noreferrer"
                    class="inline-flex items-center font-semibold text-base-content/70 transition hover:text-orange-600"
                  >
                    Open source grid <.icon name="hero-arrow-up-right" class="ml-1 size-3.5" />
                  </a>
                </div>
              </div>

              <.link
                navigate={~p"/campaigns/#{@campaign.id}"}
                class="inline-flex items-center justify-center rounded-2xl border border-base-content/15 bg-base-100 px-4 py-3 text-sm font-semibold text-base-content/70 shadow-sm transition hover:-translate-y-0.5 hover:bg-base-200"
              >
                Open classic studio <.icon name="hero-arrow-up-right" class="ml-2 size-4" />
              </.link>
            </div>

            <div class="border-t border-base-content/10 bg-base-200/35 px-4 py-4 sm:px-6 lg:px-10">
              <ol id="studio-progress" class="grid grid-cols-2 gap-2 lg:grid-cols-4">
                <li :for={stage <- @steps}>
                  <button
                    id={"progress-step-#{stage.id}"}
                    type="button"
                    phx-click="go_to_step"
                    phx-value-step={stage.id}
                    disabled={
                      not step_available?(@step, stage.id, @selected_count, @output_asset_count)
                    }
                    aria-current={if(@step == stage.id, do: "step", else: nil)}
                    class={progress_step_class(@step, stage.id)}
                  >
                    <span class={progress_number_class(@step, stage.id)}>
                      {step_number(stage.id)}
                    </span>
                    <span class="min-w-0 text-left">
                      <span class="block text-sm font-semibold">{stage.label}</span>
                      <span class="block truncate text-xs text-current/55">{stage.description}</span>
                    </span>
                    <.icon
                      :if={step_complete?(@step, stage.id)}
                      name="hero-check-circle"
                      class="ml-auto size-5 text-emerald-500"
                    />
                  </button>
                </li>
              </ol>
            </div>
          </header>

          <details
            id="previous-outputs"
            class="group rounded-[2rem] border border-base-content/10 bg-base-100/85 shadow-lg shadow-base-content/5 backdrop-blur"
          >
            <summary class="flex cursor-pointer list-none items-center justify-between gap-4 px-5 py-4 md:px-7">
              <span>
                <span class="block text-xs font-bold uppercase tracking-[0.18em] text-violet-600 dark:text-violet-300">
                  Previous outputs
                </span>
                <span class="mt-1 block text-sm text-base-content/55">
                  {@previous_package_count} saved {if(@previous_package_count == 1,
                    do: "package",
                    else: "packages"
                  )}
                </span>
              </span>
              <span class="grid size-9 place-items-center rounded-xl bg-base-200 transition group-open:rotate-180">
                <.icon name="hero-chevron-down" class="size-4" />
              </span>
            </summary>

            <div
              id="previous-output-packages"
              phx-update="stream"
              class="grid gap-3 border-t border-base-content/10 p-4 sm:grid-cols-2 lg:grid-cols-3 md:p-6"
            >
              <div
                id="empty-previous-output-packages"
                class="hidden rounded-2xl border border-dashed border-base-content/20 p-5 text-sm text-base-content/50 only:block sm:col-span-2 lg:col-span-3"
              >
                Generated packages will appear here with a link back to their post screen.
              </div>

              <article
                :for={{id, package} <- @streams.previous_packages}
                id={id}
                class="flex gap-3 rounded-2xl border border-base-content/10 bg-base-100 p-3 transition hover:-translate-y-0.5 hover:shadow-lg"
              >
                <img
                  :if={package.preview}
                  src={package.preview.url}
                  alt={package.title}
                  loading="lazy"
                  class="h-20 w-20 shrink-0 rounded-xl bg-base-200 object-cover"
                />
                <span
                  :if={is_nil(package.preview)}
                  class="grid size-20 shrink-0 place-items-center rounded-xl bg-base-200"
                >
                  <.icon name="hero-photo" class="size-6 text-base-content/35" />
                </span>
                <div class="min-w-0 flex-1">
                  <p class="truncate text-sm font-bold text-base-content">{package.title}</p>
                  <p class="mt-1 text-xs text-base-content/50">{package.summary}</p>
                  <p class="mt-1 text-[0.68rem] text-base-content/40">
                    {Calendar.strftime(package.created_at, "%b %-d, %Y · %H:%M UTC")}
                  </p>
                  <.link
                    id={"resume-package-#{package.dom_id}"}
                    navigate={package.resume_path}
                    class="mt-2 inline-flex items-center text-xs font-bold text-violet-700 transition hover:text-violet-500 dark:text-violet-200"
                  >
                    Resume post screen <.icon name="hero-arrow-right" class="ml-1 size-3" />
                  </.link>
                </div>
              </article>
            </div>
          </details>

          <section
            :if={@step == "curate"}
            id="stage-curate"
            class="grid gap-6 xl:grid-cols-[minmax(0,1fr)_22rem]"
          >
            <div class="rounded-[2rem] border border-base-content/10 bg-base-100/85 p-5 shadow-xl shadow-base-content/5 backdrop-blur md:p-7">
              <div class="flex flex-col gap-5 lg:flex-row lg:items-end lg:justify-between">
                <div>
                  <p class="text-xs font-bold uppercase tracking-[0.2em] text-orange-600 dark:text-orange-300">
                    01 · Find the signal
                  </p>
                  <h2 class="mt-2 text-2xl font-semibold tracking-tight text-base-content">
                    What is worth sharing?
                  </h2>
                  <p class="mt-2 max-w-2xl text-sm leading-6 text-base-content/60">
                    The recommended question is preselected when available. Human highlights are surfaced next because they already carry an editorial signal.
                  </p>
                </div>
                <p class="rounded-2xl bg-base-200 px-4 py-2 text-sm font-semibold text-base-content/65">
                  Choose up to {@max_selection}
                </p>
              </div>

              <div id="candidate-filters" class="mt-6 flex gap-2 overflow-x-auto pb-1">
                <button
                  :for={filter <- @candidate_filters}
                  id={"candidate-filter-#{filter.id}"}
                  type="button"
                  phx-click="filter_candidates"
                  phx-value-filter={filter.id}
                  class={filter_button_class(@candidate_filter == filter.id)}
                >
                  {filter.label}
                </button>
              </div>

              <div id="content-candidates" phx-update="stream" class="mt-5 grid gap-3 md:grid-cols-2">
                <div
                  id="empty-content-candidates"
                  class="hidden rounded-3xl border border-dashed border-base-content/20 bg-base-200/40 p-8 text-center text-sm text-base-content/55 only:block md:col-span-2"
                >
                  No moments of this type were found in the imported grid payload.
                </div>
                <.candidate_card
                  :for={{id, candidate} <- @streams.candidates}
                  id={id}
                  candidate={candidate}
                />
              </div>
            </div>

            <aside class="xl:sticky xl:top-24 xl:self-start">
              <div class="rounded-[2rem] border border-base-content/10 bg-base-content p-5 text-base-100 shadow-2xl shadow-base-content/15 md:p-6">
                <div class="flex items-center justify-between gap-3">
                  <div>
                    <p class="text-xs font-bold uppercase tracking-[0.2em] text-orange-300">
                      Story queue
                    </p>
                    <h2 class="mt-1 text-xl font-semibold">{@selected_count} selected</h2>
                  </div>
                  <span class="grid size-11 place-items-center rounded-2xl bg-white/10 text-lg font-semibold">
                    {@selected_count}
                  </span>
                </div>

                <div id="selected-aspects" phx-update="stream" class="mt-5 space-y-2">
                  <div
                    id="empty-selected-aspects"
                    class="hidden rounded-2xl border border-dashed border-white/20 p-4 text-sm text-white/55 only:block"
                  >
                    Pick at least one moment to continue.
                  </div>
                  <.selected_aspect
                    :for={{id, candidate} <- @streams.selected_aspects}
                    id={id}
                    candidate={candidate}
                  />
                </div>

                <div class="mt-5 rounded-2xl bg-white/7 p-4">
                  <p class="flex items-center gap-2 text-xs font-semibold uppercase tracking-wide text-white/55">
                    <.icon name="hero-sparkles" class="size-4 text-orange-300" /> Automation seam
                  </p>
                  <p class="mt-2 text-xs leading-5 text-white/60">
                    Today you make the editorial choice. Later, an AI ranker can feed this same generation workflow.
                  </p>
                </div>

                <button
                  id="continue-to-design"
                  type="button"
                  phx-click="continue_to_design"
                  disabled={@selected_count == 0}
                  class="mt-5 inline-flex w-full items-center justify-center rounded-2xl bg-orange-500 px-5 py-3.5 text-sm font-bold text-white shadow-lg shadow-orange-950/25 transition hover:-translate-y-0.5 hover:bg-orange-400 disabled:cursor-not-allowed disabled:opacity-40"
                >
                  Design the package <.icon name="hero-arrow-right" class="ml-2 size-4" />
                </button>
              </div>
            </aside>
          </section>

          <section
            :if={@step == "design"}
            id="stage-design"
            class="grid gap-6 xl:grid-cols-[minmax(0,1fr)_22rem]"
          >
            <div class="space-y-6">
              <div class="rounded-[2rem] border border-base-content/10 bg-base-100/85 p-5 shadow-xl shadow-base-content/5 backdrop-blur md:p-7">
                <p class="text-xs font-bold uppercase tracking-[0.2em] text-orange-600 dark:text-orange-300">
                  02 · Art direction
                </p>
                <h2 class="mt-2 text-2xl font-semibold tracking-tight text-base-content">
                  Choose a visual voice.
                </h2>
                <p class="mt-2 max-w-2xl text-sm leading-6 text-base-content/60">
                  One style keeps the package coherent across every selected moment.
                </p>

                <div id="guided-style-picker" class="mt-6 grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
                  <button
                    :for={style <- @card_styles}
                    id={"guided-style-#{style.id}"}
                    type="button"
                    phx-click="select_style"
                    phx-value-style={style.id}
                    aria-pressed={@selected_style == style.id}
                    class={style_card_class(@selected_style == style.id)}
                  >
                    <span class={[
                      "block h-24 rounded-2xl border border-white/15 shadow-inner",
                      style_swatch_class(style.id)
                    ]} />
                    <span class="mt-3 flex items-start justify-between gap-3">
                      <span class="text-left">
                        <span class="mb-1 block text-[0.62rem] font-bold uppercase tracking-[0.15em] text-current/40">
                          {style.category}
                        </span>
                        <span class="block text-sm font-bold">{style.label}</span>
                        <span class="mt-0.5 block text-xs text-current/55">{style.description}</span>
                      </span>
                      <.icon
                        :if={@selected_style == style.id}
                        name="hero-check-circle-solid"
                        class="size-5 shrink-0 text-orange-500"
                      />
                    </span>
                  </button>
                </div>
              </div>

              <div
                id="pexels-background-picker"
                class="rounded-[2rem] border border-base-content/10 bg-base-100/85 p-5 shadow-xl shadow-base-content/5 md:p-7"
              >
                <div class="flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
                  <div>
                    <p class="text-xs font-bold uppercase tracking-[0.2em] text-emerald-600 dark:text-emerald-300">
                      Optional photo backdrop
                    </p>
                    <h2 class="mt-2 text-xl font-semibold text-base-content">
                      Add a view from Pexels.
                    </h2>
                    <p class="mt-2 max-w-2xl text-sm leading-6 text-base-content/60">
                      Search for a calm, relevant scene. The selected image is embedded behind the active card theme with a readability overlay.
                    </p>
                  </div>
                  <button
                    :if={@selected_pexels_background}
                    id="clear-pexels-background"
                    type="button"
                    phx-click="clear_pexels_background"
                    class="inline-flex items-center justify-center rounded-xl border border-base-content/15 px-3 py-2 text-xs font-bold text-base-content/60 transition hover:bg-base-200"
                  >
                    <.icon name="hero-x-mark" class="mr-1 size-4" /> Remove backdrop
                  </button>
                </div>

                <%= if @pexels_configured? do %>
                  <.form
                    for={@pexels_search_form}
                    id="pexels-search-form"
                    phx-submit="search_pexels"
                    class={["mt-5 flex flex-col gap-2 sm:flex-row sm:items-end"]}
                  >
                    <div class="min-w-0 flex-1">
                      <.input
                        field={@pexels_search_form[:query]}
                        type="search"
                        label="Search Pexels"
                        placeholder="Mountains, reading room, ocean horizon…"
                        required
                      />
                    </div>
                    <button
                      id="search-pexels"
                      type="submit"
                      class="inline-flex h-11 items-center justify-center rounded-xl bg-emerald-600 px-5 text-sm font-bold text-white transition hover:-translate-y-0.5 hover:bg-emerald-500"
                    >
                      <.icon name="hero-magnifying-glass" class="mr-1.5 size-4" /> Find photos
                    </button>
                  </.form>

                  <p :if={@pexels_search_error} class="mt-3 text-sm text-red-600 dark:text-red-300">
                    {@pexels_search_error}
                  </p>

                  <div
                    id="pexels-search-results"
                    phx-update="stream"
                    class="mt-5 grid gap-3 sm:grid-cols-2 lg:grid-cols-4"
                  >
                    <article
                      :for={{id, photo} <- @streams.pexels_photos}
                      id={id}
                      class="overflow-hidden rounded-2xl border border-base-content/10 bg-base-100 shadow-sm"
                    >
                      <button
                        id={"select-pexels-photo-#{photo.id}"}
                        type="button"
                        phx-click="select_pexels_background"
                        phx-value-id={photo.id}
                        class="group block w-full text-left"
                      >
                        <img
                          src={photo.preview_url}
                          alt={photo.alt || "Pexels background option"}
                          loading="lazy"
                          class="aspect-[4/3] w-full bg-base-200 object-cover transition duration-300 group-hover:scale-[1.03]"
                        />
                        <span class="block px-3 pt-3 text-xs font-bold text-base-content">
                          {photo.alt || "Untitled photo"}
                        </span>
                      </button>
                      <p class="px-3 pb-3 pt-1 text-[0.68rem] text-base-content/50">
                        Photo by
                        <a
                          href={photo.photographer_url}
                          target="_blank"
                          rel="noopener noreferrer"
                          class="font-semibold underline underline-offset-2"
                        >
                          {photo.photographer || "Pexels contributor"}
                        </a>
                        on
                        <a
                          href={photo.pexels_url}
                          target="_blank"
                          rel="noopener noreferrer"
                          class="font-semibold underline underline-offset-2"
                        >
                          Pexels
                        </a>
                      </p>
                    </article>
                  </div>
                <% else %>
                  <p class="mt-5 rounded-2xl border border-dashed border-base-content/20 bg-base-200/40 p-4 text-sm text-base-content/55">
                    <code class="font-mono font-semibold">PEXELS_API_KEY</code>
                    was not visible when the server started. Export it and restart the Phoenix server to enable photo search.
                  </p>
                <% end %>

                <div
                  :if={@selected_pexels_background}
                  id="selected-pexels-background"
                  class="mt-5 flex flex-col gap-3 rounded-2xl border border-emerald-500/20 bg-emerald-500/10 p-3 sm:flex-row sm:items-center"
                >
                  <img
                    src={
                      @selected_pexels_background["landscape_url"] ||
                        @selected_pexels_background["original_url"]
                    }
                    alt={@selected_pexels_background["alt"] || "Selected Pexels background"}
                    class="h-20 w-full rounded-xl object-cover sm:w-32"
                  />
                  <p class="text-xs leading-5 text-base-content/65">
                    Selected photo by
                    <a
                      href={@selected_pexels_background["photographer_url"]}
                      target="_blank"
                      rel="noopener noreferrer"
                      class="font-bold underline underline-offset-2"
                    >
                      {@selected_pexels_background["photographer"] || "Pexels contributor"}
                    </a>
                    on <a
                      href={@selected_pexels_background["pexels_url"]}
                      target="_blank"
                      rel="noopener noreferrer"
                      class="font-bold underline underline-offset-2"
                    >Pexels</a>.
                  </p>
                </div>

                <p class="mt-4 text-xs text-base-content/45">
                  Photos provided by <a
                    href="https://www.pexels.com"
                    target="_blank"
                    rel="noopener noreferrer"
                    class="font-semibold underline underline-offset-2"
                  >Pexels</a>.
                </p>
              </div>

              <div class="rounded-[2rem] border border-base-content/10 bg-base-100/85 p-5 shadow-xl shadow-base-content/5 md:p-7">
                <div class="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
                  <div>
                    <p class="text-xs font-bold uppercase tracking-[0.2em] text-sky-600 dark:text-sky-300">
                      Content mode
                    </p>
                    <h2 class="mt-2 text-xl font-semibold text-base-content">
                      How should we make this package?
                    </h2>
                    <p class="mt-1 max-w-2xl text-sm leading-6 text-base-content/60">
                      Video is automatic. Text creates one image per selected moment for manual publishing.
                    </p>
                  </div>
                  <span class="rounded-full bg-base-200 px-3 py-1 text-xs font-medium text-base-content/55">
                    {if @content_mode == "video", do: "Automatic video", else: "Manual text set"}
                  </span>
                </div>

                <div id="content-mode-picker" class="mt-5 grid gap-3 sm:grid-cols-2">
                  <button
                    id="content-mode-video"
                    type="button"
                    phx-click="select_content_mode"
                    phx-value-mode="video"
                    aria-pressed={@content_mode == "video"}
                    class={content_mode_card_class(@content_mode == "video")}
                  >
                    <span class="flex items-start justify-between gap-3">
                      <span class="grid size-11 place-items-center rounded-2xl bg-sky-500 text-white shadow-lg shadow-sky-950/15">
                        <.icon name="hero-play-circle" class="size-6" />
                      </span>
                      <.icon
                        :if={@content_mode == "video"}
                        name="hero-check-circle-solid"
                        class="size-5 text-sky-500"
                      />
                    </span>
                    <span class="mt-4 block text-base font-bold text-base-content">Video</span>
                    <span class="mt-1 block text-sm font-semibold text-base-content/70">
                      One combined vertical video
                    </span>
                    <span class="mt-2 block text-xs leading-5 text-base-content/55">
                      Automatically ready for Instagram Reels, YouTube Shorts, and TikTok.
                    </span>
                  </button>

                  <button
                    id="content-mode-text"
                    type="button"
                    phx-click="select_content_mode"
                    phx-value-mode="text"
                    aria-pressed={@content_mode == "text"}
                    class={content_mode_card_class(@content_mode == "text")}
                  >
                    <span class="flex items-start justify-between gap-3">
                      <span class="grid size-11 place-items-center rounded-2xl bg-orange-500 text-white shadow-lg shadow-orange-950/15">
                        <.icon name="hero-photo" class="size-6" />
                      </span>
                      <.icon
                        :if={@content_mode == "text"}
                        name="hero-check-circle-solid"
                        class="size-5 text-orange-500"
                      />
                    </span>
                    <span class="mt-4 block text-base font-bold text-base-content">Text</span>
                    <span class="mt-1 block text-sm font-semibold text-base-content/70">
                      One image per selected moment
                    </span>
                    <span class="mt-2 block text-xs leading-5 text-base-content/55">
                      Download the image set, then write and publish each post manually.
                    </span>
                  </button>
                </div>

                <div
                  id="story-package-default"
                  class="mt-5 flex items-start gap-4 rounded-3xl border border-sky-500/25 bg-sky-500/8 p-4"
                >
                  <span class="grid size-11 shrink-0 place-items-center rounded-2xl bg-sky-500 text-white shadow-lg shadow-sky-950/15">
                    <.icon name="hero-sparkles" class="size-5" />
                  </span>
                  <div>
                    <%= if @content_mode == "video" do %>
                      <p class="font-bold text-base-content">Automatic video selected</p>
                      <p class="mt-1 text-sm leading-6 text-base-content/60">
                        All selected moments will be woven into one vertical video. Channel copy is generated automatically and can be scheduled together.
                      </p>
                    <% else %>
                      <p class="font-bold text-base-content">Manual text selected</p>
                      <p class="mt-1 text-sm leading-6 text-base-content/60">
                        One portrait image will be generated for each selected moment. Copy stays editable for manual publishing.
                      </p>
                    <% end %>
                  </div>
                </div>
              </div>
            </div>

            <aside class="xl:sticky xl:top-24 xl:self-start">
              <div class="rounded-[2rem] border border-base-content/10 bg-base-100/90 p-5 shadow-xl shadow-base-content/5 md:p-6">
                <p class="text-xs font-bold uppercase tracking-[0.2em] text-base-content/45">
                  Package brief
                </p>
                <h2 class="mt-2 text-xl font-semibold text-base-content">
                  {@selected_count} story moments
                </h2>
                <div id="selected-aspects" phx-update="stream" class="mt-4 space-y-2">
                  <.selected_aspect
                    :for={{id, candidate} <- @streams.selected_aspects}
                    id={id}
                    candidate={candidate}
                    theme="light"
                  />
                </div>
                <dl class="mt-5 space-y-3 border-t border-base-content/10 pt-5 text-sm">
                  <div class="flex items-center justify-between gap-4">
                    <dt class="text-base-content/55">Visual style</dt>
                    <dd class="font-semibold text-base-content">
                      {style_label(@card_styles, @selected_style)}
                    </dd>
                  </div>
                  <div class="flex items-center justify-between gap-4">
                    <dt class="text-base-content/55">Package</dt>
                    <dd class="font-semibold text-base-content">
                      {format_label(@formats, @selected_format)}
                    </dd>
                  </div>
                </dl>
                <div class="mt-5 grid grid-cols-2 gap-2">
                  <button
                    id="back-to-curate"
                    type="button"
                    phx-click="go_to_step"
                    phx-value-step="curate"
                    class="rounded-2xl border border-base-content/15 px-4 py-3 text-sm font-semibold text-base-content/65 transition hover:bg-base-200"
                  >
                    Back
                  </button>
                  <button
                    id="continue-to-generate"
                    type="button"
                    phx-click="continue_to_generate"
                    class="inline-flex items-center justify-center rounded-2xl bg-base-content px-4 py-3 text-sm font-bold text-base-100 shadow-lg transition hover:-translate-y-0.5"
                  >
                    Continue <.icon name="hero-arrow-right" class="ml-1.5 size-4" />
                  </button>
                </div>
              </div>
            </aside>
          </section>

          <section
            :if={@step == "generate"}
            id="stage-generate"
            class="rounded-[2rem] border border-base-content/10 bg-base-100/90 p-6 shadow-2xl shadow-base-content/5 md:p-10"
          >
            <div class="mx-auto max-w-4xl">
              <div class="text-center">
                <span class="mx-auto grid size-16 place-items-center rounded-3xl bg-orange-500/10 text-orange-600 shadow-inner dark:text-orange-300">
                  <.icon name="hero-sparkles" class="size-8" />
                </span>
                <p class="mt-5 text-xs font-bold uppercase tracking-[0.2em] text-orange-600 dark:text-orange-300">
                  03 · Production run
                </p>
                <h2 class="mt-2 text-3xl font-semibold tracking-tight text-base-content">
                  Ready to create the package.
                </h2>
                <p class="mx-auto mt-3 max-w-2xl text-sm leading-6 text-base-content/60">
                  The media is generated deterministically from the source grid. Associated platform copy is created at the same time, ready for your editorial review.
                </p>
              </div>

              <div class="mt-8 grid gap-5 md:grid-cols-[1fr_18rem]">
                <div class="rounded-3xl border border-base-content/10 bg-base-200/35 p-5">
                  <div class="flex items-center justify-between gap-3">
                    <h3 class="font-semibold text-base-content">Production queue</h3>
                    <span class="rounded-full bg-base-100 px-3 py-1 text-xs font-semibold text-base-content/55">
                      {@selected_count} moments
                    </span>
                  </div>
                  <div
                    id="selected-aspects"
                    phx-update="stream"
                    class="mt-4 grid gap-2 sm:grid-cols-2"
                  >
                    <.selected_aspect
                      :for={{id, candidate} <- @streams.selected_aspects}
                      id={id}
                      candidate={candidate}
                      theme="light"
                    />
                  </div>
                </div>

                <div class="rounded-3xl bg-base-content p-5 text-base-100">
                  <p class="text-xs font-bold uppercase tracking-[0.15em] text-white/45">Recipe</p>
                  <p class="mt-3 text-sm font-semibold">
                    {style_label(@card_styles, @selected_style)}
                  </p>
                  <p class="mt-1 text-xs text-white/55">
                    {if(@content_mode == "video", do: "Combined story video", else: "Text image set")}
                  </p>
                  <div class="mt-5 space-y-2 text-xs text-white/60">
                    <p class="flex items-center gap-2">
                      <.icon name="hero-check" class="size-4 text-emerald-400" />
                      {if(@content_mode == "video",
                        do: "Generate one combined vertical video",
                        else: "Generate one image per selected moment"
                      )}
                    </p>
                    <p class="flex items-center gap-2">
                      <.icon name="hero-check" class="size-4 text-emerald-400" /> Create channel copy
                    </p>
                    <p class="flex items-center gap-2">
                      <.icon name="hero-check" class="size-4 text-emerald-400" />
                      Preserve source links
                    </p>
                  </div>
                </div>
              </div>

              <div
                id="generate-platform-picker"
                class="mt-5 rounded-3xl border border-sky-500/20 bg-sky-500/5 p-5"
              >
                <div class="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
                  <div>
                    <p class="text-xs font-bold uppercase tracking-[0.15em] text-sky-700 dark:text-sky-200">
                      Destinations
                    </p>
                    <h3 class="mt-1 font-semibold text-base-content">
                      Where should this package go?
                    </h3>
                    <p class="mt-1 text-xs text-base-content/60">
                      Pick one or more channels. You can add or remove destinations later.
                    </p>
                  </div>
                  <span class="rounded-full bg-base-100 px-3 py-1.5 text-xs font-bold text-base-content/60">
                    {length(@selected_platforms)} selected
                  </span>
                </div>
                <div class="mt-4 grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-6">
                  <button
                    :for={platform <- @platforms}
                    id={"generate-platform-#{platform.id}"}
                    type="button"
                    phx-click="toggle_platform"
                    phx-value-platform={platform.id}
                    aria-pressed={platform.id in @selected_platforms}
                    class={platform_tab_class(platform.id in @selected_platforms)}
                  >
                    <.icon name={platform_icon(platform.id)} class="mx-auto mb-1 size-4" />
                    <span class="block text-xs font-bold">{platform.label}</span>
                  </button>
                </div>
              </div>

              <p
                :if={@generation_error}
                id="generation-error"
                class="mt-5 rounded-2xl border border-red-500/20 bg-red-500/10 px-4 py-3 text-sm text-red-700 dark:text-red-200"
              >
                {@generation_error}
              </p>

              <div class="mt-8 flex flex-col-reverse gap-3 sm:flex-row sm:justify-center">
                <button
                  id="back-to-design"
                  type="button"
                  phx-click="go_to_step"
                  phx-value-step="design"
                  class="rounded-2xl border border-base-content/15 px-5 py-3.5 text-sm font-semibold text-base-content/65 transition hover:bg-base-200"
                >
                  Adjust design
                </button>
                <button
                  id="generate-story-package"
                  type="button"
                  phx-click="generate_package"
                  class="inline-flex items-center justify-center rounded-2xl bg-orange-500 px-7 py-3.5 text-sm font-bold text-white shadow-xl shadow-orange-950/20 transition hover:-translate-y-0.5 hover:bg-orange-400 phx-click-loading:cursor-wait phx-click-loading:opacity-60"
                >
                  <.icon name="hero-bolt" class="mr-2 size-5" />
                  {if(@content_mode == "video",
                    do: "Generate video package",
                    else: "Generate text image set"
                  )}
                </button>
              </div>
            </div>
          </section>

          <section :if={@step == "review"} id="stage-review" class="space-y-6">
            <div class="flex flex-col gap-4 rounded-[2rem] border border-emerald-500/20 bg-emerald-500/10 p-5 sm:flex-row sm:items-center sm:justify-between md:p-6">
              <div class="flex items-start gap-4">
                <span class="grid size-11 shrink-0 place-items-center rounded-2xl bg-emerald-500 text-white shadow-lg shadow-emerald-950/15">
                  <.icon name="hero-check" class="size-6" />
                </span>
                <div>
                  <p class="text-xs font-bold uppercase tracking-[0.2em] text-emerald-700 dark:text-emerald-200">
                    04 · Package created
                  </p>
                  <h2 class="mt-1 text-xl font-semibold text-base-content">
                    {cond do
                      @output_video_only? -> "Review the combined video and its copy."
                      @content_mode == "text" -> "Review the image set and edit its copy."
                      true -> "Review the visuals and their copy together."
                    end}
                  </h2>
                  <p class="mt-1 text-sm text-base-content/60">
                    {@output_asset_count} {if(@output_asset_count == 1,
                      do: "media asset is",
                      else: "media assets are"
                    )} in this production run. Edits save when a text field loses focus.
                  </p>
                </div>
              </div>
              <button
                id="revise-package"
                type="button"
                phx-click="go_to_step"
                phx-value-step="design"
                class="inline-flex shrink-0 items-center justify-center rounded-2xl border border-base-content/15 bg-base-100 px-4 py-2.5 text-sm font-semibold text-base-content/65 transition hover:-translate-y-0.5 hover:bg-base-200"
              >
                <.icon name="hero-pencil-square" class="mr-2 size-4" /> Revise package
              </button>
            </div>

            <p
              :if={@generation_error}
              id="partial-generation-warning"
              class="rounded-2xl border border-amber-500/20 bg-amber-500/10 px-4 py-3 text-sm text-amber-800 dark:text-amber-100"
            >
              {@generation_error}
            </p>

            <div class="space-y-6">
              <div class="rounded-[2rem] border border-base-content/10 bg-base-100/85 p-5 shadow-xl shadow-base-content/5 md:p-6">
                <div class="flex items-end justify-between gap-4">
                  <div>
                    <p class="text-xs font-bold uppercase tracking-[0.2em] text-orange-600 dark:text-orange-300">
                      01 · Visual assets
                    </p>
                    <h3 class="mt-2 text-xl font-semibold text-base-content">
                      Choose the visual to publish
                    </h3>
                    <p class="mt-1 text-sm text-base-content/60">
                      Select a visual to see the channel copy written for it below.
                    </p>
                  </div>
                  <button
                    id="show-all-output-drafts"
                    type="button"
                    phx-click="select_output_asset"
                    phx-value-id="all"
                    class={output_filter_class(@selected_output_asset_id == "all")}
                  >
                    Show all visuals
                  </button>
                </div>

                <div
                  id="guided-output-assets"
                  phx-update="stream"
                  class="mt-5 grid gap-4 sm:grid-cols-2 lg:grid-cols-3"
                >
                  <.output_asset_card
                    :for={{id, asset} <- @streams.output_assets}
                    id={id}
                    asset={asset}
                    selected={@selected_output_asset_id == Integer.to_string(asset.id)}
                  />
                </div>
              </div>

              <div class="rounded-[2rem] border border-sky-500/25 bg-base-100/90 p-5 shadow-xl shadow-base-content/5 md:p-6">
                <div>
                  <p class="text-xs font-bold uppercase tracking-[0.2em] text-sky-600 dark:text-sky-300">
                    02 · Associated copy
                  </p>
                  <h3 class="mt-2 text-xl font-semibold text-base-content">
                    {if(@content_mode == "text",
                      do: "Edit the copy for these images.",
                      else: "Write the post for this visual."
                    )}
                  </h3>
                  <p class="mt-1 text-sm leading-6 text-base-content/60">
                    <%= if @content_mode == "text" do %>
                      Refine each caption, then copy it into the platform where you want to publish.
                    <% else %>
                      <%= if @selected_output_asset_id == "all" do %>
                        Showing copy across all visuals. Select one above to focus on a single visual.
                      <% else %>
                        The drafts below belong to the visual selected above. Each channel has its own copy, limits, and scheduling controls.
                      <% end %>
                    <% end %>
                  </p>
                </div>

                <div
                  :if={@content_mode == "video"}
                  class="mt-4 flex items-center gap-2 rounded-2xl bg-sky-500/10 px-3 py-2.5 text-xs font-semibold text-sky-800 dark:text-sky-100"
                >
                  <.icon name="hero-information-circle" class="size-4 shrink-0" />
                  {length(@selected_platforms)} {if(length(@selected_platforms) == 1,
                    do: "channel",
                    else: "channels"
                  )} selected
                </div>

                <div
                  :if={@content_mode == "video"}
                  id="guided-platform-tabs"
                  class="mt-5 grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-6"
                >
                  <button
                    :for={platform <- @platforms}
                    id={"guided-platform-#{platform.id}"}
                    type="button"
                    phx-click="toggle_platform"
                    phx-value-platform={platform.id}
                    aria-pressed={platform.id in @selected_platforms}
                    class={platform_tab_class(platform.id in @selected_platforms)}
                  >
                    <span class="mb-1 inline-flex items-center gap-1 text-[0.65rem] font-bold uppercase tracking-wide opacity-70">
                      <.icon name={platform_icon(platform.id)} class="size-3.5" />
                      {if(platform.id in @selected_platforms, do: "Selected", else: "Add")}
                    </span>
                    <span class="block text-sm font-bold">{platform.label}</span>
                    <span class="block text-[0.65rem] text-current/55">
                      {platform.max_chars || "long-form"}
                    </span>
                  </button>
                </div>

                <div class="mt-4 flex items-center justify-between gap-3 text-xs text-base-content/50">
                  <span>{@review_draft_count} matching drafts</span>
                  <span :if={@selected_output_asset_id != "all"}>Filtered to one asset</span>
                </div>

                <.form
                  :if={@content_mode == "video"}
                  for={@bulk_schedule_form}
                  id="guided-bulk-schedule-form"
                  phx-submit="schedule_selected_drafts"
                  class="mt-4 flex flex-col gap-3 rounded-3xl border border-emerald-500/25 bg-emerald-500/5 p-4 sm:flex-row sm:items-end"
                >
                  <div class="min-w-0 flex-1">
                    <.input
                      id="guided-bulk-scheduled-for"
                      field={@bulk_schedule_form[:scheduled_for]}
                      type="datetime-local"
                      label="Publish all selected posts at (UTC)"
                      required
                    />
                    <p class="mt-1 text-xs text-base-content/50">
                      X uses image assets; Instagram and YouTube Shorts use video assets when available.
                    </p>
                    <p
                      :if={not Buffer.configured?()}
                      class="mt-1 text-xs font-semibold text-amber-700 dark:text-amber-200"
                    >
                      Configure Buffer to schedule these posts.
                    </p>
                  </div>
                  <button
                    id="guided-schedule-selected-drafts"
                    type="submit"
                    disabled={@review_schedulable_count == 0}
                    class="inline-flex h-11 items-center justify-center rounded-xl bg-emerald-600 px-5 text-sm font-bold text-white shadow-lg shadow-emerald-950/15 transition hover:-translate-y-0.5 hover:bg-emerald-500 disabled:cursor-not-allowed disabled:opacity-40"
                  >
                    <.icon name="hero-calendar-days" class="mr-1.5 size-4" />
                    Schedule {@review_schedulable_count} posts
                  </button>
                </.form>

                <div
                  :if={@content_mode == "text"}
                  id="manual-publishing-note"
                  class="mt-4 flex items-start gap-3 rounded-3xl border border-orange-500/25 bg-orange-500/8 p-4 text-sm text-base-content/70"
                >
                  <.icon name="hero-pencil-square" class="mt-0.5 size-5 shrink-0 text-orange-500" />
                  <p>
                    Text mode is manual. Download the generated images, refine each caption above, and publish them directly to your text-first channels.
                  </p>
                </div>

                <div id="guided-review-drafts" phx-update="stream" class="mt-4 space-y-4">
                  <div
                    id="empty-guided-review-drafts"
                    class="hidden rounded-3xl border border-dashed border-base-content/20 bg-base-200/40 p-6 text-center text-sm text-base-content/55 only:block"
                  >
                    No copy was recommended for this asset and channel. Try another channel or show all assets.
                  </div>
                  <.review_draft_card :for={{id, item} <- @streams.review_drafts} id={id} item={item} />
                </div>
              </div>
            </div>
          </section>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :candidate, :map, required: true

  defp candidate_card(assigns) do
    ~H"""
    <article id={@id} class={candidate_card_class(@candidate.selected?)}>
      <button
        id={"select-aspect-#{@candidate.dom_id}"}
        type="button"
        phx-click="toggle_aspect"
        phx-value-key={@candidate.key}
        aria-pressed={@candidate.selected?}
        class="flex h-full w-full flex-col text-left"
      >
        <span class="flex items-start justify-between gap-4">
          <span class="flex flex-wrap items-center gap-2">
            <span class={candidate_type_class(@candidate.type)}>{@candidate.label}</span>
            <span
              :if={@candidate.recommended?}
              class="inline-flex items-center gap-1 rounded-full bg-orange-500 px-2.5 py-1 text-[0.65rem] font-bold uppercase tracking-wide text-white"
            >
              <.icon name="hero-sparkles-mini" class="size-3" /> Best opener
            </span>
          </span>
          <span class={selection_indicator_class(@candidate.selected?)}>
            <.icon
              name={if(@candidate.selected?, do: "hero-check", else: "hero-plus")}
              class="size-4"
            />
          </span>
        </span>
        <h3 class="mt-4 text-base font-semibold leading-6 text-base-content">{@candidate.title}</h3>
        <p :if={@candidate.excerpt} class="mt-2 line-clamp-3 text-sm leading-6 text-base-content/58">
          {@candidate.excerpt}
        </p>
        <p class="mt-auto flex items-center gap-1.5 pt-4 text-xs font-medium text-base-content/45">
          <.icon name="hero-signal" class="size-3.5" /> {@candidate.signal}
        </p>
      </button>
    </article>
    """
  end

  attr :id, :string, required: true
  attr :candidate, :map, required: true
  attr :theme, :string, default: "dark"

  defp selected_aspect(assigns) do
    ~H"""
    <div id={@id} class={selected_aspect_class(@theme)}>
      <span class={selected_aspect_icon_class(@theme)}>
        <.icon name={candidate_icon(@candidate.type)} class="size-4" />
      </span>
      <span class="min-w-0">
        <span class="block text-[0.65rem] font-bold uppercase tracking-wide opacity-50">
          {@candidate.label}
        </span>
        <span class="mt-0.5 block truncate text-xs font-semibold">{@candidate.title}</span>
      </span>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :asset, MediaAsset, required: true
  attr :selected, :boolean, required: true

  defp output_asset_card(assigns) do
    ~H"""
    <article id={@id} class={output_asset_card_class(@selected)}>
      <video
        :if={video_asset?(@asset)}
        id={"guided-video-preview-#{@asset.id}"}
        src={@asset.url}
        controls
        playsinline
        preload="metadata"
        class="aspect-[9/16] max-h-[34rem] w-full rounded-2xl border border-base-content/10 bg-slate-950 object-contain"
      >
      </video>
      <img
        :if={not video_asset?(@asset)}
        src={@asset.url}
        alt={@asset.title}
        loading="lazy"
        class={asset_image_class(@asset)}
      />
      <div
        :if={@asset.kind == "curated_carousel"}
        id={"curated-carousel-slides-#{@asset.id}"}
        class="mt-3 grid grid-cols-4 gap-2"
      >
        <a
          :for={{url, index} <- curated_carousel_slide_urls(@asset)}
          id={"curated-carousel-slide-#{@asset.id}-#{index}"}
          href={url}
          target="_blank"
          rel="noopener noreferrer"
          class="group relative overflow-hidden rounded-lg border border-base-content/10 bg-base-200"
        >
          <img
            src={url}
            alt={"Carousel slide #{index}"}
            loading="lazy"
            class="aspect-[4/5] w-full object-cover transition group-hover:scale-105"
          />
          <span class="absolute bottom-1 right-1 rounded-full bg-black/65 px-1.5 py-0.5 text-[0.6rem] font-bold text-white">
            {index}
          </span>
        </a>
      </div>
      <button
        id={"filter-output-asset-#{@asset.id}"}
        type="button"
        phx-click="select_output_asset"
        phx-value-id={@asset.id}
        aria-pressed={@selected}
        class="mt-3 block w-full text-left"
      >
        <span class="flex items-start justify-between gap-3">
          <span class="min-w-0">
            <span class="block truncate text-sm font-bold text-base-content">{@asset.title}</span>
            <span class="mt-0.5 block text-xs text-base-content/45">{asset_kind_label(@asset)}</span>
          </span>
          <span
            :if={@selected}
            class="rounded-full bg-orange-500/10 px-2 py-1 text-[0.65rem] font-bold uppercase text-orange-700 dark:text-orange-200"
          >
            Selected visual
          </span>
          <span
            :if={not @selected}
            class="rounded-full border border-base-content/10 px-2 py-1 text-[0.65rem] font-bold uppercase text-base-content/45"
          >
            View copy
          </span>
        </span>
      </button>
      <div class="mt-3 flex gap-2">
        <a
          href={@asset.url}
          target="_blank"
          rel="noopener noreferrer"
          class="inline-flex items-center rounded-full bg-base-content px-3 py-1.5 text-xs font-semibold text-base-100 transition hover:-translate-y-0.5"
        >
          Open {media_label(@asset)} <.icon name="hero-arrow-up-right" class="ml-1 size-3" />
        </a>
        <button
          id={"copy-guided-asset-url-#{@asset.id}"}
          type="button"
          phx-hook="CopyToClipboard"
          phx-update="ignore"
          data-copy-text={@asset.url}
          class="rounded-full border border-base-content/15 px-3 py-1.5 text-xs font-semibold text-base-content/65 transition hover:bg-base-200"
        >
          Copy URL
        </button>
      </div>
    </article>
    """
  end

  attr :id, :string, required: true
  attr :item, :map, required: true

  defp review_draft_card(assigns) do
    ~H"""
    <article
      id={@id}
      class="rounded-3xl border border-base-content/10 bg-base-100 p-4 shadow-lg shadow-base-content/5"
    >
      <div class="flex items-start justify-between gap-3">
        <div>
          <div class="flex flex-wrap gap-2">
            <span class="rounded-full bg-base-content px-2.5 py-1 text-xs font-bold text-base-100">
              {Platforms.label(@item.draft.platform)}
            </span>
            <span class="rounded-full bg-base-200 px-2.5 py-1 text-xs font-semibold text-base-content/60">
              {Templates.angle_label(@item.draft.angle)}
            </span>
          </div>
          <p class="mt-2 text-xs text-base-content/45">{@item.asset_title}</p>
        </div>
        <span class={character_count_class(@item.character_over_limit)}>
          {@item.character_count}<span :if={@item.character_limit}>/{@item.character_limit}</span>
        </span>
      </div>

      <.form
        for={@item.form}
        id={"guided-draft-form-#{@item.id}"}
        phx-change="save_draft"
        phx-value-id={@item.id}
        class="mt-4"
      >
        <.input
          id={"guided-draft-body-#{@item.id}"}
          field={@item.form[:body]}
          type="textarea"
          label="Post copy"
          rows="8"
          phx-debounce="blur"
        />
      </.form>

      <p
        :if={@item.draft.status == "scheduled" and @item.draft.scheduled_for}
        class="mt-3 rounded-2xl bg-sky-500/10 px-3 py-2 text-xs font-semibold text-sky-700 dark:text-sky-200"
      >
        Scheduled through Buffer for {Calendar.strftime(
          @item.draft.scheduled_for,
          "%Y-%m-%d %H:%M UTC"
        )}.
      </p>
      <p :if={@item.draft.error_message} class="mt-2 text-xs text-red-600 dark:text-red-300">
        {@item.draft.error_message}
      </p>

      <div class="mt-3 flex flex-wrap items-center justify-between gap-3">
        <p class="text-xs text-base-content/45">
          Status: <span class="font-bold uppercase tracking-wide">{@item.draft.status}</span>
        </p>
        <div class="flex flex-wrap justify-end gap-2">
          <%= if @item.draft.status == "approved" do %>
            <span class="inline-flex items-center rounded-2xl bg-emerald-500/10 px-3 py-2 text-sm font-semibold text-emerald-700 dark:text-emerald-200">
              <.icon name="hero-check" class="mr-1.5 size-4" /> Approved
            </span>
          <% else %>
            <button
              id={"guided-approve-draft-#{@item.id}"}
              type="button"
              phx-click="approve_draft"
              phx-value-id={@item.id}
              class="inline-flex items-center rounded-2xl border border-emerald-500/25 bg-emerald-500/10 px-3 py-2 text-sm font-semibold text-emerald-700 transition hover:-translate-y-0.5 dark:text-emerald-200"
            >
              <.icon name="hero-check" class="mr-1.5 size-4" /> Approve
            </button>
          <% end %>
          <button
            id={"guided-copy-draft-#{@item.id}"}
            type="button"
            phx-hook="CopyToClipboard"
            phx-update="ignore"
            data-copy-source={"#guided-draft-body-#{@item.id}"}
            data-draft-id={@item.id}
            class="inline-flex items-center rounded-2xl bg-base-content px-3 py-2 text-sm font-semibold text-base-100 shadow-lg transition hover:-translate-y-0.5"
          >
            Copy text
          </button>
        </div>
      </div>
    </article>
    """
  end

  defp toggle_candidate(socket, candidate) do
    selected_keys = socket.assigns.selected_keys
    selected_order = socket.assigns.selected_order

    cond do
      MapSet.member?(selected_keys, candidate.key) ->
        selected_keys = MapSet.delete(selected_keys, candidate.key)
        selected_order = List.delete(selected_order, candidate.key)
        {:noreply, update_selection(socket, selected_keys, selected_order, candidate)}

      MapSet.size(selected_keys) >= @max_selection ->
        {:noreply,
         put_flash(socket, :error, "Choose up to #{@max_selection} moments per package.")}

      true ->
        selected_keys = MapSet.put(selected_keys, candidate.key)
        selected_order = selected_order ++ [candidate.key]
        {:noreply, update_selection(socket, selected_keys, selected_order, candidate)}
    end
  end

  defp update_selection(socket, selected_keys, selected_order, candidate) do
    candidates = socket.assigns.all_candidates

    socket
    |> assign(:selected_keys, selected_keys)
    |> assign(:selected_order, selected_order)
    |> assign(:selected_count, MapSet.size(selected_keys))
    |> stream_insert(
      :candidates,
      Map.put(candidate, :selected?, MapSet.member?(selected_keys, candidate.key))
    )
    |> stream(:selected_aspects, Workflow.selected_candidates(candidates, selected_order),
      reset: true
    )
  end

  defp move_to_step(socket, step) do
    if step_available?(
         socket.assigns.step,
         step,
         socket.assigns.selected_count,
         socket.assigns.output_asset_count
       ) do
      socket
      |> assign(:step, step)
      |> stream(
        :selected_aspects,
        Workflow.selected_candidates(
          socket.assigns.all_candidates,
          socket.assigns.selected_order
        ),
        reset: true
      )
    else
      put_flash(socket, :error, step_error(step))
    end
  end

  defp complete_generation(socket, %{assets: [], errors: errors}) do
    {:noreply,
     socket
     |> assign(:generation_error, generation_error(errors))
     |> put_flash(:error, "No assets could be generated. Review the selection and try again.")}
  end

  defp complete_generation(socket, %{assets: assets, errors: errors}) do
    output_asset_ids = assets |> Enum.map(& &1.id) |> MapSet.new()

    selected_platforms =
      suggested_platforms(socket.assigns.selected_platforms, socket.assigns.selected_format)

    Campaigns.ensure_post_drafts_for_platforms(
      socket.assigns.campaign,
      assets,
      selected_platforms
    )

    socket =
      socket
      |> assign(:step, "review")
      |> assign(:output_asset_ids, output_asset_ids)
      |> assign(:output_asset_count, length(assets))
      |> assign(:output_video_only?, Enum.all?(assets, &video_asset?/1))
      |> assign(:selected_output_asset_id, "all")
      |> assign(:selected_platforms, selected_platforms)
      |> assign(:generation_error, generation_error(errors))
      |> stream(:output_assets, assets, reset: true)
      |> refresh_review_drafts()
      |> refresh_previous_packages()
      |> put_flash(
        :info,
        "Created #{length(assets)} media #{if(length(assets) == 1, do: "asset", else: "assets")} and associated copy."
      )
      |> maybe_patch_review_url()

    {:noreply, socket}
  end

  defp previous_output_packages(campaign) do
    campaign
    |> Campaigns.list_media_assets()
    |> Enum.filter(&(is_binary(&1.source_type) and &1.source_type != ""))
    |> Enum.group_by(&previous_package_key/1)
    |> Enum.map(fn {package_id, assets} -> previous_package(campaign, package_id, assets) end)
    |> Enum.sort_by(&DateTime.to_unix(&1.created_at), :desc)
    |> Enum.take(18)
  end

  defp previous_package_key(asset) do
    Map.get(asset.metadata || %{}, "generation_batch_id") ||
      if(asset.kind in ["curated_carousel", "curated_carousel_video"],
        do: "curated-#{asset.source_id}",
        else: "asset-#{asset.id}"
      )
  end

  defp previous_package(campaign, package_id, assets) do
    assets = Enum.sort_by(assets, & &1.id)
    preview = Enum.find(assets, &(not video_asset?(&1)))
    created_at = Enum.max_by(assets, &DateTime.to_unix(&1.inserted_at)).inserted_at
    platform = previous_package_platform(assets)
    asset_ids = Enum.map(assets, & &1.id)
    dom_id = package_dom_id(package_id)

    %{
      id: package_id,
      dom_id: dom_id,
      title: previous_package_title(campaign, assets),
      summary: previous_package_summary(assets),
      preview: preview,
      created_at: created_at,
      resume_path: review_path(campaign, asset_ids, platform, "all")
    }
  end

  defp package_dom_id(value) do
    value
    |> to_string()
    |> String.replace(~r/[^A-Za-z0-9_-]+/, "-")
    |> String.trim("-")
  end

  defp previous_package_title(campaign, assets) do
    if Enum.any?(assets, &(&1.kind in ["curated_carousel", "curated_carousel_video"])) do
      "#{campaign.title} · Story package"
    else
      case assets do
        [asset] -> asset.title
        assets -> "#{length(assets)}-asset package · #{campaign.title}"
      end
    end
  end

  defp previous_package_summary(assets) do
    labels =
      assets
      |> Enum.map(&previous_asset_label/1)
      |> Enum.uniq()
      |> Enum.join(" + ")

    "#{length(assets)} #{if(length(assets) == 1, do: "asset", else: "assets")} · #{labels}"
  end

  defp previous_asset_label(%MediaAsset{kind: "curated_carousel"}), do: "carousel"
  defp previous_asset_label(%MediaAsset{kind: "curated_carousel_video"}), do: "Short"
  defp previous_asset_label(%MediaAsset{mime_type: "video/mp4"}), do: "video"
  defp previous_asset_label(%MediaAsset{}), do: "image"

  defp previous_package_platform(assets) do
    cond do
      Enum.any?(assets, &("instagram" in (&1.recommended_platforms || []))) -> "instagram"
      Enum.any?(assets, &("linkedin" in (&1.recommended_platforms || []))) -> "linkedin"
      Enum.any?(assets, &("x" in (&1.recommended_platforms || []))) -> "x"
      true -> "linkedin"
    end
  end

  defp refresh_previous_packages(socket) do
    packages = previous_output_packages(socket.assigns.campaign)

    socket
    |> assign(:previous_package_count, length(packages))
    |> stream(:previous_packages, packages, reset: true)
  end

  defp restored_output_assets(campaign, %{"step" => "review", "assets" => asset_ids})
       when is_binary(asset_ids) do
    assets_by_id = campaign |> Campaigns.list_media_assets() |> Map.new(&{&1.id, &1})

    asset_ids
    |> String.split(",", trim: true)
    |> Enum.map(&parse_asset_id/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.map(&Map.get(assets_by_id, &1))
    |> Enum.reject(&is_nil/1)
  end

  defp restored_output_assets(_campaign, _params), do: []

  defp parse_asset_id(value) do
    case Integer.parse(value) do
      {id, ""} -> id
      _result -> nil
    end
  end

  defp restore_platforms(%{"platform" => platform}) when is_binary(platform) do
    platforms =
      platform
      |> String.split(",", trim: true)
      |> Enum.filter(&(&1 in Platforms.ids()))
      |> Enum.uniq()

    if platforms == [], do: ["instagram", "youtube", "tiktok"], else: platforms
  end

  defp restore_platforms(_params), do: ["instagram", "youtube", "tiktok"]

  defp restore_asset_filter(%{"asset" => asset_id}, asset_ids),
    do: valid_output_asset_filter(asset_ids, asset_id)

  defp restore_asset_filter(_params, _asset_ids), do: "all"

  defp maybe_restore_review_drafts(socket, []), do: socket
  defp maybe_restore_review_drafts(socket, _assets), do: refresh_review_drafts(socket)

  defp maybe_patch_review_url(socket) do
    if socket.assigns.step == "review" and socket.assigns.output_asset_count > 0 do
      asset_ids =
        socket.assigns.output_asset_ids
        |> Enum.sort()
        |> Enum.map_join(",", &Integer.to_string/1)

      push_patch(socket,
        to:
          review_path(
            socket.assigns.campaign,
            String.split(asset_ids, ",", trim: true),
            Enum.join(socket.assigns.selected_platforms, ","),
            socket.assigns.selected_output_asset_id
          ),
        replace: true
      )
    else
      socket
    end
  end

  defp review_path(campaign, asset_ids, platform, asset_filter) do
    ids = Enum.map_join(asset_ids, ",", &to_string/1)
    query = [step: "review", assets: ids, platform: platform, asset: asset_filter]
    ~p"/campaigns/#{campaign.id}/studio?#{query}"
  end

  defp refresh_review_drafts(socket) do
    drafts =
      socket.assigns.campaign
      |> Campaigns.list_post_drafts()
      |> Enum.filter(&(&1.platform in socket.assigns.selected_platforms))
      |> Enum.filter(&review_draft?(socket, &1))
      |> deduplicate_review_drafts()

    socket
    |> assign(:review_draft_count, length(drafts))
    |> assign(
      :review_schedulable_count,
      drafts |> schedulable_drafts() |> Enum.count(&(&1.status != "scheduled"))
    )
    |> stream(:review_drafts, Enum.map(drafts, &draft_item/1), reset: true)
  end

  defp schedulable_drafts(drafts) do
    has_video? = Enum.any?(drafts, &video_asset?(&1.media_asset))

    Enum.filter(drafts, fn draft ->
      case draft.platform do
        "x" ->
          not video_asset?(draft.media_asset)

        platform when platform in ["instagram", "youtube", "tiktok"] ->
          not has_video? or video_asset?(draft.media_asset)

        _ ->
          true
      end
    end)
  end

  defp deduplicate_review_drafts(drafts) do
    drafts
    |> Enum.sort_by(&review_draft_preference/1, :desc)
    |> Enum.uniq_by(&{&1.platform, &1.body})
    |> Enum.sort_by(&{&1.platform, &1.id})
  end

  defp review_draft_preference(%PostDraft{platform: platform, media_asset: asset, status: status}) do
    media_score =
      case {platform, video_asset?(asset)} do
        {platform, false} when platform in ["x"] -> 2
        {platform, true} when platform in ["instagram", "youtube", "tiktok"] -> 2
        _ -> 1
      end

    {media_score, if(status == "scheduled", do: 1, else: 0)}
  end

  defp ensure_review_channel_drafts(socket, platform) do
    if socket.assigns.output_asset_count > 0 do
      assets =
        socket.assigns.campaign
        |> Campaigns.list_media_assets()
        |> Enum.filter(&MapSet.member?(socket.assigns.output_asset_ids, &1.id))

      Campaigns.ensure_post_drafts_for_platforms(
        socket.assigns.campaign,
        assets,
        [platform]
      )
    end

    socket
  end

  defp review_draft?(socket, draft) do
    MapSet.member?(socket.assigns.output_asset_ids, draft.media_asset_id) and
      (socket.assigns.selected_output_asset_id == "all" or
         socket.assigns.selected_output_asset_id == Integer.to_string(draft.media_asset_id))
  end

  defp editable_draft?(socket, %PostDraft{} = draft) do
    draft.campaign_id == socket.assigns.campaign.id and
      MapSet.member?(socket.assigns.output_asset_ids, draft.media_asset_id)
  end

  defp draft_item(%PostDraft{} = draft) do
    character_count = Platforms.character_count(draft.body, draft.platform)
    character_limit = Platforms.max_chars(draft.platform)

    %{
      id: draft.id,
      draft: draft,
      form: to_form(%{"body" => draft.body}, as: :post_draft),
      schedule_form:
        to_form(%{"scheduled_for" => schedule_input_value(draft.scheduled_for)}, as: :schedule),
      buffer_channel?: Buffer.configured?() and is_binary(Buffer.channel_id(draft.platform)),
      asset_title: draft.media_asset.title,
      character_count: character_count,
      character_limit: character_limit,
      character_over_limit: is_integer(character_limit) and character_count > character_limit
    }
  end

  defp schedule_input_value(nil), do: ""

  defp schedule_input_value(%DateTime{} = datetime) do
    datetime
    |> DateTime.to_naive()
    |> NaiveDateTime.to_iso8601()
    |> String.slice(0, 16)
  end

  defp candidate_items(candidates, selected_keys) do
    Enum.map(candidates, &Map.put(&1, :selected?, MapSet.member?(selected_keys, &1.key)))
  end

  defp pexels_orientation("linkedin"), do: "square"

  defp pexels_orientation(format)
       when format in ["portrait", "carousel", "combined_carousel", "story_video"],
       do: "portrait"

  defp pexels_orientation(_format), do: "landscape"

  defp pexels_error_message(:not_configured),
    do: "Export PEXELS_API_KEY and restart the Phoenix server before searching."

  defp pexels_error_message(:invalid_query), do: "Enter a search term."

  defp pexels_error_message({:api_error, _status, message}),
    do: "Pexels could not complete the search: #{message}"

  defp pexels_error_message({:http_error, status}),
    do: "Pexels returned HTTP #{status}. Try again shortly."

  defp pexels_error_message(_reason), do: "Pexels search is unavailable right now."

  defp suggested_platforms(["linkedin"], "portrait"), do: ["instagram"]
  defp suggested_platforms(["linkedin"], "story_video"), do: ["instagram", "youtube", "tiktok"]
  defp suggested_platforms(["linkedin"], "carousel"), do: ["instagram", "youtube"]
  defp suggested_platforms(["linkedin"], "combined_carousel"), do: ["instagram", "youtube"]
  defp suggested_platforms(platforms, _format), do: platforms

  defp content_mode_platforms(["instagram", "youtube", "tiktok"], "text"),
    do: ["x", "linkedin", "bluesky"]

  defp content_mode_platforms(["x", "linkedin", "bluesky"], "video"),
    do: ["instagram", "youtube", "tiktok"]

  defp content_mode_platforms(platforms, _mode), do: platforms

  defp maybe_text_quote_candidates(candidates, "text", all_candidates) do
    quote_candidates = Enum.filter(candidates, &quote_candidate?/1)

    cond do
      quote_candidates != [] ->
        quote_candidates

      Enum.any?(all_candidates, &quote_candidate?/1) ->
        Enum.filter(all_candidates, &quote_candidate?/1) |> Enum.take(1)

      true ->
        candidates
    end
  end

  defp maybe_text_quote_candidates(candidates, _mode, _all_candidates), do: candidates

  defp quote_candidate?(%{type: type}) when type in ["question", "highlight", "key_node"],
    do: true

  defp quote_candidate?(_candidate), do: false

  defp valid_output_asset_filter(_output_asset_ids, "all"), do: "all"

  defp valid_output_asset_filter(output_asset_ids, asset_id) do
    case Integer.parse(asset_id) do
      {parsed_id, ""} -> if MapSet.member?(output_asset_ids, parsed_id), do: asset_id, else: "all"
      _ -> "all"
    end
  end

  defp generation_error([]), do: nil

  defp generation_error(errors) do
    if Enum.any?(errors, &match?({:video, _reason}, &1.reason)) do
      "The carousel slides were created, but the short video could not be encoded. Check that FFmpeg is available and try again."
    else
      titles = errors |> Enum.map(& &1.candidate.title) |> Enum.take(3) |> Enum.join(", ")
      "Some selections could not be generated: #{titles}."
    end
  end

  defp step_error("design"), do: "Choose at least one story moment before designing the package."
  defp step_error("generate"), do: "Choose at least one story moment before generating."
  defp step_error("review"), do: "Generate a package before opening review."
  defp step_error(_step), do: "That stage is not available yet."

  defp step_available?(_current_step, "curate", _selected_count, _output_count), do: true

  defp step_available?(_current_step, step, selected_count, _output_count)
       when step in ["design", "generate"], do: selected_count > 0

  defp step_available?(_current_step, "review", _selected_count, output_count),
    do: output_count > 0

  defp step_available?(_current_step, _step, _selected_count, _output_count), do: false

  defp step_number(step), do: Enum.find_index(@steps, &(&1.id == step)) + 1
  defp step_index(step), do: Enum.find_index(@steps, &(&1.id == step)) || 0
  defp step_complete?(current, stage), do: step_index(stage) < step_index(current)

  defp style_label(styles, id), do: Enum.find_value(styles, id, &if(&1.id == id, do: &1.label))
  defp format_label(formats, id), do: Enum.find_value(formats, id, &if(&1.id == id, do: &1.label))

  defp progress_step_class(current, stage) do
    [
      "flex w-full items-center gap-3 rounded-2xl px-3 py-2.5 text-left transition disabled:cursor-not-allowed disabled:opacity-35",
      if(current == stage,
        do: "bg-base-content text-base-100 shadow-lg shadow-base-content/10",
        else: "text-base-content/60 hover:bg-base-100 hover:text-base-content"
      )
    ]
  end

  defp progress_number_class(current, stage) do
    [
      "grid size-8 shrink-0 place-items-center rounded-xl text-xs font-bold",
      if(current == stage,
        do: "bg-orange-500 text-white",
        else: "bg-base-100 text-base-content/55"
      )
    ]
  end

  defp filter_button_class(active?) do
    [
      "shrink-0 rounded-full px-4 py-2 text-sm font-semibold transition hover:-translate-y-0.5",
      if(active?,
        do: "bg-base-content text-base-100 shadow-lg",
        else: "border border-base-content/10 bg-base-100 text-base-content/60 hover:bg-base-200"
      )
    ]
  end

  defp candidate_card_class(selected?) do
    [
      "min-h-60 rounded-3xl border p-5 transition duration-200 hover:-translate-y-0.5 hover:shadow-xl",
      if(selected?,
        do: "border-orange-500/50 bg-orange-500/8 shadow-lg shadow-orange-950/5",
        else: "border-base-content/10 bg-base-100 hover:border-base-content/20"
      )
    ]
  end

  defp candidate_type_class("question"),
    do:
      "rounded-full bg-sky-500/10 px-2.5 py-1 text-[0.65rem] font-bold uppercase tracking-wide text-sky-700 dark:text-sky-200"

  defp candidate_type_class("highlight"),
    do:
      "rounded-full bg-violet-500/10 px-2.5 py-1 text-[0.65rem] font-bold uppercase tracking-wide text-violet-700 dark:text-violet-200"

  defp candidate_type_class("key_node"),
    do:
      "rounded-full bg-emerald-500/10 px-2.5 py-1 text-[0.65rem] font-bold uppercase tracking-wide text-emerald-700 dark:text-emerald-200"

  defp candidate_type_class(_type),
    do:
      "rounded-full bg-base-200 px-2.5 py-1 text-[0.65rem] font-bold uppercase tracking-wide text-base-content/55"

  defp selection_indicator_class(selected?) do
    [
      "grid size-9 shrink-0 place-items-center rounded-xl border transition",
      if(selected?,
        do: "border-orange-500 bg-orange-500 text-white",
        else: "border-base-content/15 bg-base-100 text-base-content/45"
      )
    ]
  end

  defp candidate_icon("question"), do: "hero-chat-bubble-left-right"
  defp candidate_icon("highlight"), do: "hero-bookmark"
  defp candidate_icon("key_node"), do: "hero-cube-transparent"
  defp candidate_icon(_type), do: "hero-squares-2x2"

  defp selected_aspect_class("light"),
    do:
      "flex items-center gap-3 rounded-2xl border border-base-content/10 bg-base-100 p-3 text-base-content"

  defp selected_aspect_class(_theme),
    do: "flex items-center gap-3 rounded-2xl bg-white/8 p-3 text-white"

  defp selected_aspect_icon_class("light"),
    do: "grid size-9 shrink-0 place-items-center rounded-xl bg-base-200 text-base-content/60"

  defp selected_aspect_icon_class(_theme),
    do: "grid size-9 shrink-0 place-items-center rounded-xl bg-white/10 text-orange-300"

  defp style_card_class(active?) do
    [
      "rounded-3xl border p-3 text-left transition duration-200 hover:-translate-y-0.5 hover:shadow-xl",
      if(active?,
        do: "border-orange-500/50 bg-orange-500/8 shadow-lg",
        else:
          "border-base-content/10 bg-base-100 text-base-content/70 hover:border-base-content/20"
      )
    ]
  end

  defp content_mode_card_class(active?) do
    [
      "rounded-3xl border p-4 text-left transition duration-200 hover:-translate-y-0.5 hover:shadow-xl",
      if(active?,
        do: "border-sky-500/50 bg-sky-500/8 shadow-lg",
        else: "border-base-content/10 bg-base-100 text-base-content/70 hover:bg-base-200"
      )
    ]
  end

  defp style_swatch_class("minimal_light"),
    do: "bg-white ring-1 ring-inset ring-black/15"

  defp style_swatch_class("minimal_dark"),
    do: "bg-black ring-1 ring-inset ring-white/20"

  defp style_swatch_class("editorial_dark"),
    do: "bg-gradient-to-br from-rose-400 via-indigo-950 to-cyan-400"

  defp style_swatch_class("gradient_poster"),
    do: "bg-gradient-to-br from-fuchsia-300 via-violet-700 to-teal-500"

  defp style_swatch_class("minimal_academic"),
    do: "bg-gradient-to-br from-slate-100 via-blue-100 to-slate-400"

  defp style_swatch_class("warm_paper"),
    do: "bg-gradient-to-br from-amber-200 via-orange-700 to-stone-900"

  defp style_swatch_class("signal_red"),
    do: "bg-gradient-to-br from-rose-300 via-red-800 to-amber-500"

  defp style_swatch_class("deep_ocean"),
    do: "bg-gradient-to-br from-cyan-300 via-sky-950 to-emerald-400"

  defp style_swatch_class("newsprint"),
    do: "bg-gradient-to-br from-stone-100 via-amber-100 to-red-800"

  defp style_swatch_class(_style), do: "bg-base-300"

  defp output_asset_card_class(selected?) do
    [
      "rounded-3xl border p-3 transition duration-200 hover:-translate-y-0.5 hover:shadow-xl",
      if(selected?,
        do: "border-orange-500/50 bg-orange-500/8 shadow-lg",
        else: "border-base-content/10 bg-base-100"
      )
    ]
  end

  defp curated_carousel_slide_urls(%MediaAsset{url: url, metadata: metadata}) do
    count = Map.get(metadata || %{}, "slide_count", 1)

    Enum.map(1..count, fn index ->
      {String.replace(url, "/slides/1/", "/slides/#{index}/"), index}
    end)
  end

  defp asset_image_class(%MediaAsset{kind: "curated_carousel"}),
    do: "aspect-[4/5] w-full rounded-2xl border border-base-content/10 bg-base-200 object-contain"

  defp asset_image_class(%MediaAsset{metadata: %{"format" => "portrait"}}),
    do: "aspect-[4/5] w-full rounded-2xl border border-base-content/10 bg-base-200 object-contain"

  defp asset_image_class(%MediaAsset{metadata: %{"format" => "linkedin"}}),
    do:
      "aspect-square w-full rounded-2xl border border-base-content/10 bg-base-200 object-contain"

  defp asset_image_class(_asset),
    do:
      "aspect-[1.91/1] w-full rounded-2xl border border-base-content/10 bg-base-200 object-contain"

  defp asset_kind_label(%MediaAsset{kind: "curated_carousel", metadata: metadata}),
    do: "Combined carousel · #{Map.get(metadata, "slide_count")} slides"

  defp asset_kind_label(%MediaAsset{kind: "curated_carousel_video", metadata: metadata}),
    do: "Story Short · #{Map.get(metadata, "duration_seconds")}s · 1080 × 1920"

  defp asset_kind_label(%MediaAsset{kind: "key_node_carousel_slide", metadata: metadata}),
    do: "Carousel · slide #{Map.get(metadata, "slide_index")}"

  defp asset_kind_label(%MediaAsset{kind: "key_node_video", metadata: metadata}),
    do: "Short video · #{Map.get(metadata, "duration_seconds")}s · 1080 × 1920"

  defp asset_kind_label(%MediaAsset{kind: "question_video"}),
    do: "Question Short · 6s · 1080 × 1920"

  defp asset_kind_label(%MediaAsset{kind: "highlight_video"}),
    do: "Highlight Reel · 6s · 1080 × 1920"

  defp asset_kind_label(%MediaAsset{kind: "key_node_card", metadata: %{"format" => "portrait"}}),
    do: "Instagram portrait · 1080 × 1350"

  defp asset_kind_label(%MediaAsset{kind: "key_node_card", metadata: %{"format" => "linkedin"}}),
    do: "LinkedIn explainer · 1200 × 1200"

  defp asset_kind_label(%MediaAsset{metadata: %{"format" => "portrait"}}),
    do: "Instagram portrait · 1080 × 1350"

  defp asset_kind_label(%MediaAsset{metadata: %{"format" => "linkedin"}}),
    do: "LinkedIn quote · 1200 × 1200"

  defp asset_kind_label(%MediaAsset{kind: kind}),
    do: kind |> String.replace("_", " ") |> String.capitalize()

  defp video_asset?(%MediaAsset{mime_type: "video/mp4"}), do: true
  defp video_asset?(_asset), do: false

  defp media_label(asset), do: if(video_asset?(asset), do: "video", else: "image")

  defp output_filter_class(active?) do
    [
      "rounded-full px-3 py-1.5 text-xs font-semibold transition",
      if(active?,
        do: "bg-base-content text-base-100",
        else: "border border-base-content/15 text-base-content/60 hover:bg-base-200"
      )
    ]
  end

  defp platform_tab_class(active?) do
    [
      "rounded-2xl px-2 py-2.5 text-center transition hover:-translate-y-0.5",
      if(active?,
        do: "bg-base-content text-base-100 shadow-lg",
        else: "border border-base-content/10 bg-base-100 text-base-content/60 hover:bg-base-200"
      )
    ]
  end

  defp platform_icon("x"), do: "hero-chat-bubble-left-ellipsis"
  defp platform_icon("instagram"), do: "hero-camera"
  defp platform_icon("youtube"), do: "hero-play-circle"
  defp platform_icon("tiktok"), do: "hero-musical-note"
  defp platform_icon("linkedin"), do: "hero-briefcase"
  defp platform_icon("bluesky"), do: "hero-cloud"
  defp platform_icon("substack"), do: "hero-envelope"
  defp platform_icon(_platform), do: "hero-globe-alt"

  defp character_count_class(true),
    do: "rounded-full bg-red-500/10 px-2.5 py-1 text-xs font-bold text-red-700 dark:text-red-200"

  defp character_count_class(false),
    do: "rounded-full bg-base-200 px-2.5 py-1 text-xs font-bold text-base-content/50"
end
