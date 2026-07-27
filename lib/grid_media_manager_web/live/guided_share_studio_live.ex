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
      size: "1200 × 630 · X",
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
    case Campaigns.get_campaign(id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "That campaign is no longer available.")
         |> redirect(to: ~p"/")}

      campaign ->
        mount_campaign(campaign, params, socket)
    end
  end

  defp mount_campaign(campaign, params, socket) do
    candidates = Workflow.candidates(campaign)
    restored_assets = restored_output_assets(campaign, params)
    restored_asset_ids = MapSet.new(restored_assets, & &1.id)
    default_step = if restored_assets == [], do: "curate", else: "review"

    restored_step =
      if params["step"] in Enum.map(@steps, & &1.id), do: params["step"], else: default_step

    restored_asset_filter = restore_asset_filter(params, restored_asset_ids)
    restored_video_only? = restored_assets != [] and Enum.all?(restored_assets, &video_asset?/1)

    restored_content_mode =
      if restored_assets == [] or Enum.any?(restored_assets, &video_asset?/1),
        do: "video",
        else: "text"

    restored_platforms =
      if restored_assets == [],
        do: Platforms.video_ids(),
        else: platforms_for_assets(restored_assets)

    previous_packages = previous_output_packages(campaign)
    studio_state = Campaigns.guided_studio_state(campaign)
    selected_keys = restored_selected_keys(candidates, studio_state)

    selected_order =
      restored_selected_order(candidates, selected_keys, studio_state)

    restored_content_mode = Map.get(studio_state, "content_mode", restored_content_mode)
    restored_format = Map.get(studio_state, "selected_format")

    restored_format =
      if restored_format in @formats,
        do: restored_format,
        else: if(restored_content_mode == "video", do: "story_video", else: "portrait")

    restored_style = ShareCard.normalize_style(Map.get(studio_state, "selected_style"))

    restored_filter =
      if Map.get(studio_state, "candidate_filter") in Enum.map(@candidate_filters, & &1.id),
        do: Map.get(studio_state, "candidate_filter"),
        else: "all"

    socket =
      socket
      |> assign(:page_title, "Guided studio · #{campaign.title}")
      |> assign(:campaign, campaign)
      |> assign(:max_selection, @max_selection)
      |> assign(:steps, @steps)
      |> assign(:candidate_filters, @candidate_filters)
      |> assign(:formats, @formats)
      |> assign(:card_styles, ShareCard.styles())
      |> assign(:all_candidates, candidates)
      |> assign(:candidate_by_key, Map.new(candidates, &{&1.key, &1}))
      |> assign(:candidate_filter, restored_filter)
      |> assign(:selected_keys, selected_keys)
      |> assign(:selected_order, selected_order)
      |> assign(:selected_count, MapSet.size(selected_keys))
      |> assign(:step, restored_step)
      |> assign(:selected_style, restored_style)
      |> assign(:content_mode, restored_content_mode)
      |> assign(
        :selected_format,
        restored_format
      )
      |> assign(:selected_platforms, restored_platforms)
      |> assign(:selected_output_asset_id, restored_asset_filter)
      |> assign(:carousel_preview_slides, %{})
      |> assign(:output_asset_ids, restored_asset_ids)
      |> assign(:output_asset_count, length(restored_assets))
      |> assign(:output_video_only?, restored_video_only?)
      |> assign(:review_draft_count, 0)
      |> assign(:review_schedulable_count, 0)
      |> assign(:preview_mode?, true)
      |> assign(:bulk_schedule_form, to_form(%{"scheduled_for" => ""}, as: :bulk_schedule))
      |> assign(:previous_package_count, length(previous_packages))
      |> assign(:generation_error, nil)
      |> assign(:generation_in_progress?, false)
      |> assign(:pexels_configured?, Pexels.configured?())
      |> assign(:pexels_search_form, to_form(%{"query" => campaign.title}, as: :pexels))
      |> assign(:pexels_search_error, nil)
      |> assign(:pexels_by_id, %{})
      |> assign(:selected_pexels_background, Campaigns.pexels_background(campaign))
      |> assign(:title_card_mode, Campaigns.title_card_mode(campaign))
      |> stream_configure(:candidate_groups, dom_id: &"candidate-group-#{&1.dom_id}")
      |> stream_configure(:selected_aspects, dom_id: &"selected-#{&1.dom_id}")
      |> stream_configure(:output_assets, dom_id: &"guided-output-#{&1.id}")
      |> stream_configure(:review_drafts, dom_id: &"guided-draft-#{&1.id}")
      |> stream_configure(:pexels_photos, dom_id: &"pexels-photo-#{&1.id}")
      |> stream_configure(:previous_packages, dom_id: &"previous-package-#{&1.dom_id}")
      |> stream(
        :candidate_groups,
        candidate_groups(
          Workflow.filter_candidates(candidates, restored_filter),
          selected_keys,
          candidates
        )
      )
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
  def handle_async(:generate_package, {:ok, result}, socket) do
    socket
    |> assign(:generation_in_progress?, false)
    |> complete_generation(result)
  end

  @impl true
  def handle_async(:generate_package, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> assign(:generation_in_progress?, false)
     |> assign(:generation_error, "Video generation failed before a package could be created.")
     |> put_flash(:error, "Video generation failed. Try again or adjust the selection.")}
  end

  @impl true
  def handle_event("filter_candidates", %{"filter" => filter}, socket) do
    filter = if filter in Enum.map(@candidate_filters, & &1.id), do: filter, else: "all"

    candidates = Workflow.filter_candidates(socket.assigns.all_candidates, filter)

    {:noreply,
     socket
     |> assign(:candidate_filter, filter)
     |> stream(
       :candidate_groups,
       candidate_groups(candidates, socket.assigns.selected_keys, socket.assigns.all_candidates),
       reset: true
     )
     |> persist_studio_state()}
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
    {:noreply,
     socket
     |> assign(:selected_style, ShareCard.normalize_style(style))
     |> persist_studio_state()}
  end

  def handle_event("select_format", %{"format" => format}, socket) do
    format = if format in Enum.map(@formats, & &1.id), do: format, else: "landscape"

    content_mode =
      if format in ["story_video", "carousel", "combined_carousel"], do: "video", else: "text"

    {:noreply,
     socket
     |> assign(:selected_format, format)
     |> assign(:content_mode, content_mode)
     |> assign(:selected_platforms, platforms_for_mode(content_mode))
     |> persist_studio_state()}
  end

  def handle_event("select_content_mode", %{"mode" => mode}, socket)
      when mode in ["video", "text"] do
    selected_format = if mode == "video", do: "story_video", else: "portrait"
    selected_platforms = platforms_for_mode(mode)

    {:noreply,
     socket
     |> assign(:content_mode, mode)
     |> assign(:selected_format, selected_format)
     |> assign(:selected_platforms, selected_platforms)
     |> persist_studio_state()}
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

  def handle_event("select_title_card_mode", %{"mode" => mode}, socket)
      when mode in ["text", "pexels"] do
    case Campaigns.set_title_card_mode(socket.assigns.campaign, mode) do
      {:ok, campaign} ->
        {:noreply,
         socket
         |> assign(:campaign, campaign)
         |> assign(:title_card_mode, mode)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not save the title card choice.")}
    end
  end

  def handle_event(
        "generate_package",
        _params,
        %{assigns: %{generation_in_progress?: true}} = socket
      ) do
    {:noreply, socket}
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

    campaign = socket.assigns.campaign
    style = socket.assigns.selected_style

    socket =
      socket
      |> assign(:generation_in_progress?, true)
      |> assign(:generation_error, nil)
      |> start_async(:generate_package, fn ->
        Workflow.generate(campaign, selected_candidates, style: style, format: format)
      end)

    {:noreply, socket}
  end

  def handle_event("toggle_platform", _params, socket), do: {:noreply, socket}

  def handle_event("select_platform", _params, socket), do: {:noreply, socket}

  def handle_event("select_output_asset", %{"id" => asset_id}, socket) do
    asset_id = valid_output_asset_filter(socket.assigns.output_asset_ids, asset_id)

    {:noreply,
     socket
     |> assign(:selected_output_asset_id, asset_id)
     |> refresh_review_drafts()
     |> maybe_patch_review_url()}
  end

  def handle_event(
        "preview_carousel_slide",
        %{"asset-id" => asset_id, "slide-index" => slide_index},
        socket
      ) do
    with {:ok, asset} <- review_carousel_asset(socket, asset_id),
         {:ok, slide_index} <- positive_integer(slide_index),
         true <- carousel_slide_index?(asset, slide_index) do
      socket = update(socket, :carousel_preview_slides, &Map.put(&1, asset.id, slide_index))
      {:noreply, stream_insert(socket, :output_assets, asset)}
    else
      {:error, :not_in_package} -> {:noreply, socket}
      {:error, :invalid_index} -> {:noreply, socket}
      false -> {:noreply, socket}
    end
  end

  def handle_event(
        "toggle_carousel_slide",
        %{"asset-id" => asset_id, "slide-index" => slide_index},
        socket
      ) do
    with {:ok, asset} <- review_carousel_asset(socket, asset_id),
         {:ok, slide_index} <- positive_integer(slide_index),
         true <- carousel_content_slide?(asset, slide_index) do
      selected_indexes = carousel_selected_slide_indexes(asset)
      content_indexes = Enum.reject(selected_indexes, &carousel_slide_cta?(asset, &1))

      next_indexes =
        cond do
          slide_index in content_indexes and length(content_indexes) == 1 ->
            :keep_one_content_slide

          slide_index in content_indexes ->
            List.delete(content_indexes, slide_index)

          true ->
            content_indexes ++ [slide_index]
        end

      case next_indexes do
        :keep_one_content_slide ->
          {:noreply, put_flash(socket, :error, "Keep at least one content image before the CTA.")}

        next_indexes ->
          persist_carousel_selection(socket, asset, next_indexes)
      end
    else
      {:error, :not_in_package} -> {:noreply, socket}
      {:error, :invalid_index} -> {:noreply, socket}
      false -> {:noreply, socket}
    end
  end

  def handle_event(
        "move_carousel_slide",
        %{
          "asset-id" => asset_id,
          "slide-index" => slide_index,
          "direction" => direction
        },
        socket
      )
      when direction in ["up", "down"] do
    with {:ok, asset} <- review_carousel_asset(socket, asset_id),
         {:ok, slide_index} <- positive_integer(slide_index),
         true <- carousel_content_slide?(asset, slide_index) do
      content_indexes =
        asset
        |> carousel_selected_slide_indexes()
        |> Enum.reject(&carousel_slide_cta?(asset, &1))

      case Enum.find_index(content_indexes, &(&1 == slide_index)) do
        nil ->
          {:noreply, socket}

        position ->
          persist_carousel_selection(
            socket,
            asset,
            move_carousel_index(content_indexes, position, direction)
          )
      end
    else
      {:error, :not_in_package} -> {:noreply, socket}
      {:error, :invalid_index} -> {:noreply, socket}
      false -> {:noreply, socket}
    end
  end

  def handle_event("move_carousel_slide", _params, socket), do: {:noreply, socket}

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

              <div class="flex flex-wrap justify-end gap-2">
                <.link
                  id="open-post-review"
                  navigate={~p"/posts/review"}
                  class="inline-flex items-center justify-center rounded-2xl bg-base-content px-4 py-3 text-sm font-semibold text-base-100 shadow-sm transition hover:-translate-y-0.5 hover:bg-base-content/85"
                >
                  Review proposed posts <.icon name="hero-queue-list" class="ml-2 size-4" />
                </.link>
                <.link
                  navigate={~p"/campaigns/#{@campaign.id}"}
                  class="inline-flex items-center justify-center rounded-2xl border border-base-content/15 bg-base-100 px-4 py-3 text-sm font-semibold text-base-content/70 shadow-sm transition hover:-translate-y-0.5 hover:bg-base-200"
                >
                  Open classic studio <.icon name="hero-arrow-up-right" class="ml-2 size-4" />
                </.link>
              </div>
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

              <div id="content-candidates" phx-update="stream" class="mt-5 space-y-5">
                <div
                  id="empty-content-candidates"
                  class="hidden rounded-3xl border border-dashed border-base-content/20 bg-base-200/40 p-8 text-center text-sm text-base-content/55 only:block"
                >
                  No moments of this type were found in the imported grid payload.
                </div>
                <section
                  :for={{id, group} <- @streams.candidate_groups}
                  id={id}
                  class="rounded-3xl border border-base-content/10 bg-base-200/45 p-3 md:p-4"
                >
                  <div class="flex items-center justify-between gap-3 px-2 pb-3">
                    <div class="min-w-0">
                      <p class="text-[0.65rem] font-bold uppercase tracking-[0.18em] text-orange-600 dark:text-orange-300">
                        {group.label}
                      </p>
                      <h3 class="mt-1 truncate text-base font-semibold text-base-content">
                        {group.title}
                      </h3>
                    </div>
                    <span class="shrink-0 rounded-full bg-base-100 px-2.5 py-1 text-xs font-semibold text-base-content/55">
                      {length(group.candidates)} {if(length(group.candidates) == 1,
                        do: "option",
                        else: "options"
                      )}
                    </span>
                  </div>
                  <div class="grid gap-3 md:grid-cols-2">
                    <.candidate_card
                      :for={candidate <- group.candidates}
                      id={"candidate-#{candidate.dom_id}"}
                      candidate={candidate}
                    />
                  </div>
                </section>
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
                id="title-card-picker"
                class="rounded-[2rem] border border-base-content/10 bg-base-100/85 p-5 shadow-xl shadow-base-content/5 md:p-7"
              >
                <p class="text-xs font-bold uppercase tracking-[0.2em] text-orange-600 dark:text-orange-300">
                  Title card
                </p>
                <h2 class="mt-2 text-xl font-semibold text-base-content">
                  Choose the opening frame.
                </h2>
                <p class="mt-2 max-w-2xl text-sm leading-6 text-base-content/60">
                  Use a clean text title, or make the title card a Pexels image with a readability overlay.
                </p>
                <div class="mt-5 grid gap-3 sm:grid-cols-2">
                  <button
                    id="title-card-mode-text"
                    type="button"
                    phx-click="select_title_card_mode"
                    phx-value-mode="text"
                    aria-pressed={@title_card_mode == "text"}
                    class={title_card_mode_class(@title_card_mode == "text")}
                  >
                    <.icon name="hero-document-text" class="size-5" />
                    <span>
                      <span class="block text-sm font-bold">Text title</span>
                      <span class="mt-1 block text-xs text-current/55">
                        The default, typography-led opening.
                      </span>
                    </span>
                  </button>
                  <button
                    id="title-card-mode-pexels"
                    type="button"
                    phx-click="select_title_card_mode"
                    phx-value-mode="pexels"
                    aria-pressed={@title_card_mode == "pexels"}
                    class={title_card_mode_class(@title_card_mode == "pexels")}
                  >
                    <.icon name="hero-photo" class="size-5" />
                    <span>
                      <span class="block text-sm font-bold">Pexels image</span>
                      <span class="mt-1 block text-xs text-current/55">
                        Use the selected photo as the opening frame.
                      </span>
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
                      Video is automatic. Text creates one ordered image carousel with the RationalGrid CTA last.
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
                      Automatically ready for TikTok, Instagram, and YouTube.
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
                      Ordered multi-image carousel
                    </span>
                    <span class="mt-2 block text-xs leading-5 text-base-content/55">
                      Buffer-ready text cards for X, LinkedIn, and Facebook with the RationalGrid CTA last.
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
                    {if(@content_mode == "video",
                      do: "Combined story video",
                      else: "Ordered image carousel"
                    )}
                  </p>
                  <div class="mt-5 space-y-2 text-xs text-white/60">
                    <p class="flex items-center gap-2">
                      <.icon name="hero-check" class="size-4 text-emerald-400" />
                      {if(@content_mode == "video",
                        do: "Generate one combined vertical video",
                        else: "Generate one ordered image carousel"
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
                <div
                  id="generate-platform-summary"
                  class="mt-4 rounded-2xl bg-base-100 px-4 py-3 text-sm font-semibold text-base-content"
                >
                  {destination_summary(@selected_platforms)}
                </div>
              </div>

              <p
                :if={@generation_error}
                id="generation-error"
                class="mt-5 rounded-2xl border border-red-500/20 bg-red-500/10 px-4 py-3 text-sm text-red-700 dark:text-red-200"
              >
                {@generation_error}
              </p>

              <p
                :if={@generation_in_progress?}
                id="generation-progress"
                class="mt-5 rounded-2xl border border-orange-500/20 bg-orange-500/10 px-4 py-3 text-sm text-orange-800 dark:text-orange-100"
              >
                Generating the package in the background. This can take a few minutes for longer nodes; you can keep this page open.
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
                  disabled={@generation_in_progress?}
                  class="inline-flex items-center justify-center rounded-2xl bg-orange-500 px-7 py-3.5 text-sm font-bold text-white shadow-xl shadow-orange-950/20 transition hover:-translate-y-0.5 hover:bg-orange-400 phx-click-loading:cursor-wait phx-click-loading:opacity-60"
                >
                  <.icon name="hero-bolt" class="mr-2 size-5" />
                  {cond do
                    @generation_in_progress? -> "Generating package…"
                    @content_mode == "video" -> "Generate video package"
                    true -> "Generate image carousel"
                  end}
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
                      @content_mode == "text" -> "Review the image carousel and edit its copy."
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
              <div class="flex shrink-0 flex-wrap justify-end gap-2">
                <.link
                  id="review-all-proposed-posts"
                  navigate={~p"/posts/review"}
                  class="inline-flex items-center justify-center rounded-2xl bg-base-content px-4 py-2.5 text-sm font-semibold text-base-100 transition hover:-translate-y-0.5 hover:bg-base-content/85"
                >
                  <.icon name="hero-queue-list" class="mr-2 size-4" /> Review all posts
                </.link>
                <button
                  id="revise-package"
                  type="button"
                  phx-click="go_to_step"
                  phx-value-step="design"
                  class="inline-flex items-center justify-center rounded-2xl border border-base-content/15 bg-base-100 px-4 py-2.5 text-sm font-semibold text-base-content/65 transition hover:-translate-y-0.5 hover:bg-base-200"
                >
                  <.icon name="hero-pencil-square" class="mr-2 size-4" /> Revise package
                </button>
              </div>
            </div>

            <p
              :if={@generation_error}
              id="partial-generation-warning"
              class="rounded-2xl border border-amber-500/20 bg-amber-500/10 px-4 py-3 text-sm text-amber-800 dark:text-amber-100"
            >
              {@generation_error}
            </p>

            <div
              :if={@preview_mode?}
              id="preview-only-notice"
              class="flex items-start gap-3 rounded-2xl border border-sky-500/25 bg-sky-500/10 px-4 py-3 text-sm text-sky-900 dark:text-sky-100"
            >
              <.icon name="hero-eye" class="mt-0.5 size-5 shrink-0 text-sky-600 dark:text-sky-300" />
              <p>
                <span class="font-bold">Preview mode.</span>
                Nothing has been sent to Buffer. Review the media and copy below; scheduling is the only action that creates live social posts.
              </p>
            </div>

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
                  class={[
                    "mt-5 grid gap-4",
                    if(@output_asset_count == 1,
                      do: "lg:grid-cols-1",
                      else: "sm:grid-cols-2 lg:grid-cols-3"
                    )
                  ]}
                >
                  <.output_asset_card
                    :for={{id, asset} <- @streams.output_assets}
                    id={id}
                    asset={asset}
                    selected={@selected_output_asset_id == Integer.to_string(asset.id)}
                    preview_slide={Map.get(@carousel_preview_slides, asset.id, 1)}
                    wide={@output_asset_count == 1}
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
                      Refine each caption, then schedule the X, LinkedIn, and Facebook posts together below.
                    <% else %>
                      <%= if @selected_output_asset_id == "all" do %>
                        Showing copy across all visuals. Select one above to focus on a single visual.
                      <% else %>
                        The drafts below belong to the visual selected above. The same reviewed copy will be posted to TikTok, Instagram, and YouTube.
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
                  id="guided-platform-summary"
                  class="mt-5 rounded-2xl border border-base-content/10 bg-base-200/50 px-4 py-3 text-sm font-semibold text-base-content"
                >
                  {destination_summary(@selected_platforms)}
                </div>

                <div class="mt-4 flex items-center justify-between gap-3 text-xs text-base-content/50">
                  <span>{@review_draft_count} matching drafts</span>
                  <span :if={@selected_output_asset_id != "all"}>Filtered to one asset</span>
                </div>

                <.form
                  :if={@content_mode in ["video", "text"]}
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
                      label={schedule_label(@selected_platforms)}
                      required
                    />
                    <p class="mt-1 text-xs text-base-content/50">
                      {schedule_help(@selected_platforms)}
                    </p>
                    <p
                      :if={not buffer_ready_for_platforms?(@selected_platforms)}
                      class="mt-1 text-xs font-semibold text-amber-700 dark:text-amber-200"
                    >
                      Configure the Buffer account and channel IDs before scheduling.
                    </p>
                  </div>
                  <button
                    id="guided-schedule-selected-drafts"
                    type="submit"
                    disabled={@review_schedulable_count == 0}
                    phx-confirm="This will create live posts in Buffer for the selected channels. Continue only after reviewing the media and copy."
                    class="inline-flex h-11 items-center justify-center rounded-xl bg-emerald-600 px-5 text-sm font-bold text-white shadow-lg shadow-emerald-950/15 transition hover:-translate-y-0.5 hover:bg-emerald-500 disabled:cursor-not-allowed disabled:opacity-40"
                  >
                    <.icon name="hero-calendar-days" class="mr-1.5 size-4" />
                    Publish {@review_schedulable_count} posts
                  </button>
                </.form>

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
  attr :preview_slide, :integer, default: 1
  attr :wide, :boolean, default: false

  defp output_asset_card(assigns) do
    ~H"""
    <article id={@id} class={output_asset_card_class(@selected, @wide, @asset)}>
      <video
        :if={video_asset?(@asset)}
        id={"guided-video-preview-#{@asset.id}"}
        src={if(@asset.kind == "curated_carousel_video", do: nil, else: @asset.url)}
        data-browser-frame-video-url={
          if(@asset.kind == "curated_carousel_video", do: @asset.url, else: nil)
        }
        controls
        playsinline
        preload="metadata"
        class={[
          "aspect-[9/16] max-h-[34rem] w-full rounded-2xl border border-base-content/10 bg-slate-950 object-contain",
          @wide && "lg:col-start-1 lg:row-start-1"
        ]}
      >
      </video>
      <img
        :if={not video_asset?(@asset)}
        id={"guided-output-preview-#{@asset.id}"}
        src={output_asset_preview_url(@asset, @preview_slide)}
        alt={@asset.title}
        loading="lazy"
        class={[asset_image_class(@asset), @wide && "lg:col-start-1 lg:row-start-1"]}
      />
      <div
        :if={@asset.kind in ["curated_carousel", "curated_carousel_video"]}
        id={"curated-carousel-slides-#{@asset.id}"}
        data-slides={Jason.encode!(Map.get(@asset.metadata || %{}, "slides", []))}
        data-selected-indexes={Jason.encode!(carousel_selected_slide_indexes(@asset))}
        data-preview-slide={@preview_slide}
        data-main-preview-id={"guided-output-preview-#{@asset.id}"}
        data-video-preview-id={
          if(@asset.kind == "curated_carousel_video",
            do: "guided-video-preview-#{@asset.id}",
            else: ""
          )
        }
        data-style={@asset.style}
        data-cover-card-url={curated_carousel_cover_url(@asset)}
        data-logo-src="/images/rg_logo.webp"
        data-upload-url={"/api/campaigns/#{@asset.campaign_id}/curated-carousels/#{@asset.source_id}/browser-frames"}
        class={[
          "mt-4 space-y-4 rounded-2xl border border-orange-500/20 bg-orange-500/5 p-3",
          @wide && "lg:col-start-2 lg:row-start-1 lg:row-span-3 lg:mt-0"
        ]}
      >
        <div
          id={"curated-carousel-renderer-#{@asset.id}"}
          phx-hook="CanvasSlideRenderer"
          phx-update="ignore"
          data-root-id={"curated-carousel-slides-#{@asset.id}"}
          class="hidden"
        >
        </div>
        <div class="flex flex-wrap items-start justify-between gap-3">
          <div>
            <p class="text-xs font-bold uppercase tracking-[0.16em] text-orange-700 dark:text-orange-200">
              {if(@asset.kind == "curated_carousel",
                do: "Choose the publishable images",
                else: "Preview the video frames"
              )}
            </p>
            <p
              :if={@asset.kind == "curated_carousel"}
              class="mt-1 text-xs leading-5 text-base-content/60"
            >
              Choose the images to publish. Click in the order you want, then refine it below. The RationalGrid CTA is always last.
            </p>
            <p
              :if={@asset.kind == "curated_carousel_video"}
              class="mt-1 text-xs leading-5 text-base-content/60"
            >
              These are the ordered Canvas frames used to rebuild the video. Save them after reviewing the text.
            </p>
            <p
              data-browser-render-status
              class="mt-1 text-xs font-semibold text-emerald-700 dark:text-emerald-200"
            >
              Preparing browser-rendered preview…
            </p>
          </div>
          <div class="flex flex-wrap items-center justify-end gap-2">
            <span
              :if={@asset.kind == "curated_carousel"}
              class="rounded-full bg-base-100 px-2.5 py-1 text-[0.65rem] font-bold text-base-content/60"
            >
              {carousel_selection_summary(@asset)}
            </span>
            <button
              type="button"
              data-browser-render-upload
              class="rounded-lg bg-orange-500 px-2.5 py-1.5 text-[0.65rem] font-bold text-white transition hover:bg-orange-600 disabled:cursor-not-allowed disabled:opacity-60"
            >
              Save browser-rendered frames
            </button>
          </div>
        </div>

        <div class="grid grid-cols-2 gap-2 sm:grid-cols-4">
          <div :for={{url, index} <- curated_carousel_slide_urls(@asset)} class="min-w-0">
            <button
              id={"curated-carousel-slide-#{@asset.id}-#{index}"}
              type="button"
              phx-click="preview_carousel_slide"
              phx-value-asset-id={@asset.id}
              phx-value-slide-index={index}
              data-carousel-preview
              data-preview-target={"guided-output-preview-#{@asset.id}"}
              data-preview-canvas={"canvas-curated-carousel-slide-#{@asset.id}-#{index}"}
              data-preview-url={url}
              aria-label={"Preview carousel slide #{index}"}
              class={[
                carousel_slide_link_class(@asset, index),
                @preview_slide == index && "ring-2 ring-sky-400/80"
              ]}
            >
              <canvas
                id={"canvas-curated-carousel-slide-#{@asset.id}-#{index}"}
                width="1080"
                height="1350"
                data-canvas-slide
                data-slide-index={index}
                phx-update="ignore"
                aria-label={"Browser-rendered carousel slide #{index}"}
                class="hidden aspect-[4/5] w-full object-cover"
              >
              </canvas>
              <img
                src={url}
                alt={"Carousel slide #{index}"}
                loading="lazy"
                class="aspect-[4/5] w-full object-cover transition group-hover:scale-105"
              />
              <span class="absolute bottom-1 right-1 rounded-full bg-black/65 px-1.5 py-0.5 text-[0.6rem] font-bold text-white">
                {index}
              </span>
            </button>
            <div
              :if={@asset.kind == "curated_carousel"}
              class="mt-1 flex items-center justify-between gap-1"
            >
              <button
                id={"toggle-curated-carousel-slide-#{@asset.id}-#{index}"}
                type="button"
                phx-click="toggle_carousel_slide"
                phx-value-asset-id={@asset.id}
                phx-value-slide-index={index}
                disabled={carousel_slide_cta?(@asset, index)}
                aria-pressed={carousel_slide_selected?(@asset, index)}
                class={carousel_slide_button_class(@asset, index)}
              >
                {carousel_slide_action_label(@asset, index)}
              </button>
              <span
                :if={carousel_slide_position(@asset, index)}
                class="shrink-0 text-[0.65rem] font-bold text-orange-700 dark:text-orange-200"
              >
                #{carousel_slide_position(@asset, index)}
              </span>
            </div>
          </div>
        </div>

        <div
          :if={@asset.kind == "curated_carousel"}
          id={"curated-carousel-order-#{@asset.id}"}
          class="rounded-xl border border-base-content/10 bg-base-100/70 p-3"
        >
          <p class="text-xs font-bold uppercase tracking-wide text-base-content/55">Publish order</p>
          <div class="mt-2 space-y-1.5">
            <div
              :for={{index, position} <- carousel_selected_slide_positions(@asset)}
              class="flex items-center justify-between gap-2 rounded-lg bg-base-200/70 px-2.5 py-2"
            >
              <span class="min-w-0 truncate text-xs font-semibold text-base-content/75">
                {position}. {carousel_slide_summary(@asset, index)}
              </span>
              <div :if={not carousel_slide_cta?(@asset, index)} class="flex shrink-0 gap-1">
                <button
                  id={"move-curated-carousel-slide-up-#{@asset.id}-#{index}"}
                  type="button"
                  phx-click="move_carousel_slide"
                  phx-value-asset-id={@asset.id}
                  phx-value-slide-index={index}
                  phx-value-direction="up"
                  disabled={position == 1}
                  aria-label="Move slide earlier"
                  class="rounded-md border border-base-content/10 p-1 text-base-content/55 transition hover:bg-base-300 disabled:cursor-not-allowed disabled:opacity-30"
                >
                  <.icon name="hero-chevron-up-mini" class="size-3.5" />
                </button>
                <button
                  id={"move-curated-carousel-slide-down-#{@asset.id}-#{index}"}
                  type="button"
                  phx-click="move_carousel_slide"
                  phx-value-asset-id={@asset.id}
                  phx-value-slide-index={index}
                  phx-value-direction="down"
                  disabled={position == carousel_content_selection_count(@asset)}
                  aria-label="Move slide later"
                  class="rounded-md border border-base-content/10 p-1 text-base-content/55 transition hover:bg-base-300 disabled:cursor-not-allowed disabled:opacity-30"
                >
                  <.icon name="hero-chevron-down-mini" class="size-3.5" />
                </button>
              </div>
              <span
                :if={carousel_slide_cta?(@asset, index)}
                class="shrink-0 text-[0.65rem] font-bold uppercase tracking-wide text-emerald-700 dark:text-emerald-200"
              >
                Final CTA
              </span>
            </div>
          </div>
        </div>
      </div>
      <button
        id={"filter-output-asset-#{@asset.id}"}
        type="button"
        phx-click="select_output_asset"
        phx-value-id={@asset.id}
        aria-pressed={@selected}
        class={[
          "mt-3 block w-full text-left",
          @wide && "lg:col-start-1 lg:row-start-2"
        ]}
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
      <div class={["mt-3 flex gap-2", @wide && "lg:col-start-1 lg:row-start-3"]}>
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

  defp update_selection(socket, selected_keys, selected_order, _candidate) do
    candidates = socket.assigns.all_candidates
    visible_candidates = Workflow.filter_candidates(candidates, socket.assigns.candidate_filter)

    socket
    |> assign(:selected_keys, selected_keys)
    |> assign(:selected_order, selected_order)
    |> assign(:selected_count, MapSet.size(selected_keys))
    |> stream(
      :candidate_groups,
      candidate_groups(visible_candidates, selected_keys, candidates),
      reset: true
    )
    |> stream(:selected_aspects, Workflow.selected_candidates(candidates, selected_order),
      reset: true
    )
    |> persist_studio_state()
  end

  defp persist_studio_state(socket) do
    state = %{
      "selected_keys" => socket.assigns.selected_order,
      "selected_style" => socket.assigns.selected_style,
      "selected_format" => socket.assigns.selected_format,
      "content_mode" => socket.assigns.content_mode,
      "candidate_filter" => socket.assigns.candidate_filter
    }

    case Campaigns.save_guided_studio_state(socket.assigns.campaign, state) do
      {:ok, campaign} -> assign(socket, :campaign, campaign)
      {:error, _changeset} -> socket
    end
  end

  defp restored_selected_keys(candidates, state) do
    keys = Map.get(state, "selected_keys")

    if is_list(keys) and keys != [] do
      valid_keys = MapSet.new(candidates, & &1.key)
      keys |> Enum.filter(&MapSet.member?(valid_keys, &1)) |> MapSet.new()
    else
      Workflow.default_selection(candidates)
    end
  end

  defp restored_selected_order(candidates, selected_keys, state) do
    order = Map.get(state, "selected_keys", [])
    selected = Workflow.selected_candidates(candidates, selected_keys) |> Enum.map(& &1.key)
    Enum.uniq(Enum.filter(order, &MapSet.member?(selected_keys, &1)) ++ selected)
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

    selected_platforms = platforms_for_assets(assets)

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
    assets
    |> platforms_for_assets()
    |> Enum.join(",")
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

  defp restore_asset_filter(%{"asset" => asset_id}, asset_ids),
    do: valid_output_asset_filter(asset_ids, asset_id)

  defp restore_asset_filter(_params, _asset_ids), do: "all"

  defp maybe_restore_review_drafts(socket, []), do: socket

  defp maybe_restore_review_drafts(socket, assets) do
    Campaigns.ensure_post_drafts_for_platforms(
      socket.assigns.campaign,
      assets,
      socket.assigns.selected_platforms
    )

    refresh_review_drafts(socket)
  end

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

    preview_mode? = Enum.all?(drafts, &(&1.status not in ["scheduled", "published"]))

    socket
    |> assign(:preview_mode?, preview_mode?)
    |> assign(:review_draft_count, length(drafts))
    |> assign(
      :review_schedulable_count,
      drafts |> schedulable_drafts() |> Enum.count(&(&1.status != "scheduled"))
    )
    |> stream(:review_drafts, Enum.map(drafts, &draft_item/1), reset: true)
  end

  defp schedulable_drafts(drafts) do
    Enum.filter(drafts, fn draft ->
      Buffer.account_for(draft.platform) != nil and
        if draft.platform in Platforms.video_ids(),
          do: video_asset?(draft.media_asset),
          else: not video_asset?(draft.media_asset)
    end)
  end

  defp buffer_ready_for_platforms?(platforms) do
    Enum.all?(platforms, &(Buffer.account_for(&1) != nil))
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
      buffer_channel?: Buffer.account_for(draft.platform) != nil,
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

  defp candidate_groups(candidates, selected_keys, all_candidates) do
    candidates = candidate_items(candidates, selected_keys)
    node_titles = Map.new(all_candidates, &{&1.source_id, &1.title})

    group_keys =
      all_candidates
      |> Enum.filter(&(&1.type == "key_node"))
      |> Enum.map(&candidate_group_key/1)
      |> Enum.filter(fn group_key ->
        Enum.any?(candidates, fn candidate -> candidate_group_key(candidate) == group_key end)
      end)

    group_keys =
      group_keys ++
        (candidates
         |> Enum.map(&candidate_group_key/1)
         |> Enum.uniq()
         |> Enum.reject(&(&1 in group_keys)))

    Enum.map(group_keys, fn group_key ->
      group_candidates = Enum.filter(candidates, &(candidate_group_key(&1) == group_key))
      node_candidate = Enum.find(group_candidates, &(&1.type == "key_node"))
      node_id = group_node_id(group_key)

      ordered_candidates =
        case node_candidate do
          nil -> group_candidates
          node -> [node | Enum.reject(group_candidates, &(&1.key == node.key))]
        end

      %{
        dom_id: candidate_group_dom_id(group_key),
        label: if(node_id, do: "Node package", else: "Other moments"),
        title: node_candidate_title(node_candidate, node_id, node_titles),
        candidates: ordered_candidates
      }
    end)
  end

  defp candidate_group_key(%{node_id: node_id}) when is_binary(node_id) and node_id != "",
    do: "node:#{node_id}"

  defp candidate_group_key(%{type: "grid"}), do: "grid"
  defp candidate_group_key(_candidate), do: "other"

  defp group_node_id("node:" <> node_id), do: node_id
  defp group_node_id(_group_key), do: nil

  defp candidate_group_dom_id(group_key) do
    group_key
    |> String.replace(~r/[^A-Za-z0-9_-]+/, "-")
    |> then(&String.trim(&1, "-"))
    |> then(&if(&1 == "", do: "other", else: &1))
  end

  defp node_candidate_title(%{title: title}, _node_id, _node_titles), do: title

  defp node_candidate_title(nil, node_id, node_titles) when is_binary(node_id) do
    Map.get(node_titles, node_id, "Node #{node_id}")
  end

  defp node_candidate_title(nil, _node_id, _node_titles), do: "Other moments"

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

  defp platforms_for_mode("text"), do: Platforms.text_ids()
  defp platforms_for_mode("video"), do: Platforms.video_ids()

  defp platforms_for_assets(assets) do
    has_video? = Enum.any?(assets, &video_asset?/1)
    has_text? = Enum.any?(assets, &(not video_asset?(&1)))

    cond do
      has_video? and has_text? -> Platforms.text_ids() ++ Platforms.video_ids()
      has_video? -> Platforms.video_ids()
      true -> Platforms.text_ids()
    end
  end

  defp destination_summary(platforms) do
    cond do
      platforms == Platforms.text_ids() ->
        "Text cards will be posted to X, LinkedIn, and Facebook with the same copy."

      platforms == Platforms.video_ids() ->
        "The video will be posted to TikTok, Instagram, and YouTube with the same copy."

      true ->
        "Text cards will be posted to X, LinkedIn, and Facebook; videos will be posted to TikTok, Instagram, and YouTube."
    end
  end

  defp schedule_label(platforms) do
    cond do
      platforms == Platforms.text_ids() ->
        "Publish X, LinkedIn, and Facebook posts at (UTC)"

      platforms == Platforms.video_ids() ->
        "Publish TikTok, Instagram, and YouTube posts at (UTC)"

      true ->
        "Publish text and video posts at (UTC)"
    end
  end

  defp schedule_help(platforms) do
    cond do
      platforms == Platforms.text_ids() ->
        "X, LinkedIn, and Facebook use the text Buffer accounts."

      platforms == Platforms.video_ids() ->
        "TikTok, Instagram, and YouTube use the generated video asset."

      true ->
        "Text and video posts use their matching Buffer accounts and assets."
    end
  end

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

  defp review_carousel_asset(socket, asset_id) do
    case parse_asset_id(asset_id) do
      id when is_integer(id) ->
        if MapSet.member?(socket.assigns.output_asset_ids, id) do
          asset = Campaigns.get_media_asset!(id)

          if asset.campaign_id == socket.assigns.campaign.id and
               asset.kind in ["curated_carousel", "curated_carousel_video"] do
            {:ok, asset}
          else
            {:error, :not_in_package}
          end
        else
          {:error, :not_in_package}
        end

      _id ->
        {:error, :not_in_package}
    end
  end

  defp persist_carousel_selection(socket, asset, selection) do
    case Campaigns.update_curated_carousel_selection(asset, selection) do
      {:ok, updated_asset} ->
        {:noreply, stream_insert(socket, :output_assets, updated_asset)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not save the carousel selection.")}
    end
  end

  defp positive_integer(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp positive_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} when integer > 0 -> {:ok, integer}
      _result -> {:error, :invalid_index}
    end
  end

  defp positive_integer(_value), do: {:error, :invalid_index}

  defp carousel_selected_slide_indexes(%MediaAsset{
         kind: "curated_carousel_video",
         metadata: metadata
       }) do
    metadata = metadata || %{}

    case Map.get(metadata, "selected_slide_indexes") do
      indexes when is_list(indexes) ->
        indexes

      _ ->
        case length(Map.get(metadata, "slides", [])) do
          0 -> []
          count -> Enum.to_list(1..count)
        end
    end
  end

  defp carousel_selected_slide_indexes(%MediaAsset{metadata: metadata}) do
    metadata = metadata || %{}
    slides = Map.get(metadata, "slides", [])

    ShareCard.curated_carousel_selected_slide_indexes(
      slides,
      Map.get(metadata, "selected_slide_indexes")
    )
  end

  defp carousel_content_slide?(asset, slide_index) do
    slide_index < carousel_slide_count(asset)
  end

  defp carousel_slide_index?(asset, slide_index) do
    slide_index in 1..carousel_slide_count(asset)
  end

  defp carousel_slide_cta?(asset, slide_index) do
    slide_index == carousel_slide_count(asset)
  end

  defp carousel_slide_count(%MediaAsset{metadata: metadata}) do
    metadata = metadata || %{}
    metadata |> Map.get("slides", []) |> length()
  end

  defp carousel_selected_slide_positions(asset) do
    asset
    |> carousel_selected_slide_indexes()
    |> Enum.with_index(1)
  end

  defp carousel_content_selection_count(asset) do
    asset
    |> carousel_selected_slide_indexes()
    |> Enum.reject(&carousel_slide_cta?(asset, &1))
    |> length()
  end

  defp carousel_slide_selected?(asset, slide_index),
    do: slide_index in carousel_selected_slide_indexes(asset)

  defp carousel_slide_position(asset, slide_index) do
    asset
    |> carousel_selected_slide_positions()
    |> Enum.find_value(fn {index, position} -> if(index == slide_index, do: position) end)
  end

  defp carousel_slide_summary(%MediaAsset{metadata: metadata}, slide_index) do
    slides = Map.get(metadata || %{}, "slides", [])
    slide = Enum.at(slides, slide_index - 1) || %{}
    title = slide |> Map.get("title", "") |> to_string() |> String.trim()

    body =
      slide |> Map.get("body", "") |> to_string() |> String.replace(~r/\s+/, " ") |> String.trim()

    cond do
      title != "" -> title
      body != "" -> String.slice(body, 0, 72)
      true -> "Slide #{slide_index}"
    end
  end

  defp carousel_selection_summary(asset) do
    "#{length(carousel_selected_slide_indexes(asset))} images"
  end

  defp carousel_slide_action_label(asset, slide_index) do
    cond do
      carousel_slide_cta?(asset, slide_index) -> "Final CTA"
      carousel_slide_selected?(asset, slide_index) -> "Remove"
      true -> "Use"
    end
  end

  defp carousel_slide_link_class(asset, slide_index) do
    [
      "group relative block w-full appearance-none overflow-hidden rounded-lg border bg-base-200 text-left",
      if(carousel_slide_selected?(asset, slide_index),
        do: "border-orange-500 ring-2 ring-orange-500/35",
        else: "border-base-content/10"
      )
    ]
  end

  defp carousel_slide_button_class(asset, slide_index) do
    [
      "min-w-0 flex-1 truncate rounded-md px-2 py-1 text-[0.65rem] font-bold transition",
      cond do
        carousel_slide_cta?(asset, slide_index) ->
          "cursor-default bg-emerald-500/10 text-emerald-700 dark:text-emerald-200"

        carousel_slide_selected?(asset, slide_index) ->
          "bg-orange-500 text-white hover:bg-orange-600"

        true ->
          "border border-base-content/15 text-base-content/60 hover:bg-base-200"
      end
    ]
  end

  defp move_carousel_index(indexes, position, "up") when position > 0 do
    swap_carousel_indexes(indexes, position, position - 1)
  end

  defp move_carousel_index(indexes, position, "down") when position < length(indexes) - 1 do
    swap_carousel_indexes(indexes, position, position + 1)
  end

  defp move_carousel_index(indexes, _position, _direction), do: indexes

  defp swap_carousel_indexes(indexes, first, second) do
    first_value = Enum.at(indexes, first)
    second_value = Enum.at(indexes, second)

    indexes
    |> List.replace_at(first, second_value)
    |> List.replace_at(second, first_value)
  end

  defp generation_error([]), do: nil

  defp generation_error(errors) do
    cond do
      Enum.any?(errors, &(&1.reason == :campaign_not_found)) ->
        "This campaign is no longer available. Return to Import and choose an active campaign."

      Enum.any?(errors, &match?({:video, _reason}, &1.reason)) ->
        "The carousel slides were created, but the short video could not be encoded. Check that FFmpeg is available and try again."

      true ->
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

  defp title_card_mode_class(active?) do
    [
      "flex items-start gap-3 rounded-2xl border p-4 text-left transition duration-200 hover:-translate-y-0.5 hover:shadow-lg",
      if(active?,
        do: "border-orange-500/50 bg-orange-500/8 shadow-md",
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

  defp output_asset_card_class(selected?, wide?, asset) do
    [
      "rounded-3xl border p-3 transition duration-200 hover:-translate-y-0.5 hover:shadow-xl",
      (wide? and asset.kind in ["curated_carousel", "curated_carousel_video"]) &&
        "grid gap-4 lg:grid-cols-[minmax(18rem,28rem)_minmax(0,1fr)] lg:items-start",
      if(selected?,
        do: "border-orange-500/50 bg-orange-500/8 shadow-lg",
        else: "border-base-content/10 bg-base-100"
      )
    ]
  end

  defp curated_carousel_slide_urls(%MediaAsset{
         kind: "curated_carousel",
         url: url,
         metadata: metadata
       }) do
    count = Map.get(metadata || %{}, "slide_count", 1)

    Enum.map(1..count, fn index ->
      {String.replace(url, "/slides/1/", "/slides/#{index}/"), index}
    end)
  end

  defp curated_carousel_slide_urls(%MediaAsset{kind: "curated_carousel_video"} = asset) do
    metadata = asset.metadata || %{}
    count = Map.get(metadata, "slide_count", 1)
    indexes = Map.get(metadata, "selected_slide_indexes") || Enum.to_list(1..count)
    token = URI.encode(to_string(asset.source_id), &URI.char_unreserved?/1)
    query = URI.encode_query(%{style: asset.style})

    Enum.map(indexes, fn index ->
      {"/campaigns/#{asset.campaign_id}/curated-carousels/#{token}/slides/#{index}/image.png?#{query}",
       index}
    end)
  end

  defp curated_carousel_cover_url(%MediaAsset{kind: kind} = asset)
       when kind in ["curated_carousel", "curated_carousel_video"] do
    curated_carousel_slide_urls(asset)
    |> Enum.find_value(fn {url, index} -> if(index == 1, do: url) end)
  end

  defp curated_carousel_cover_url(%MediaAsset{}), do: nil

  defp output_asset_preview_url(%MediaAsset{kind: "curated_carousel"} = asset, slide) do
    curated_carousel_slide_urls(asset)
    |> Enum.find_value(fn {url, index} -> if(index == slide, do: url) end)
    |> Kernel.||(asset.url)
  end

  defp output_asset_preview_url(%MediaAsset{url: url}, _slide), do: url

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

  defp asset_kind_label(%MediaAsset{kind: "curated_carousel", metadata: metadata}) do
    slides = Map.get(metadata || %{}, "slides", [])

    selected =
      ShareCard.curated_carousel_selected_slide_indexes(
        slides,
        Map.get(metadata || %{}, "selected_slide_indexes")
      )

    "Carousel · #{length(selected)} images · CTA final"
  end

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

  defp character_count_class(true),
    do: "rounded-full bg-red-500/10 px-2.5 py-1 text-xs font-bold text-red-700 dark:text-red-200"

  defp character_count_class(false),
    do: "rounded-full bg-base-200 px-2.5 py-1 text-xs font-bold text-base-content/50"
end
