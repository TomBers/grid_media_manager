defmodule GridMediaManagerWeb.GuidedShareStudioLive do
  use GridMediaManagerWeb, :live_view

  alias GridMediaManager.Campaigns
  alias GridMediaManager.Campaigns.Campaign
  alias GridMediaManager.Campaigns.MediaAsset
  alias GridMediaManager.Campaigns.PostDraft
  alias GridMediaManager.Pexels.Client, as: Pexels
  alias GridMediaManager.Promotion.ArtifactStore
  alias GridMediaManager.Promotion.CarouselVideo
  alias GridMediaManager.Promotion.ShareCard
  alias GridMediaManager.Social.Buffer
  alias GridMediaManager.Social.Platforms
  alias GridMediaManager.Social.Templates
  alias GridMediaManager.Studio.Workflow

  @max_selection 6
  @steps [
    %{id: "curate", label: "Curate", description: "Find the signal"},
    %{id: "design", label: "Design", description: "Shape the media"},
    %{id: "review", label: "Review", description: "Refine and approve"}
  ]
  @candidate_filters [
    %{id: "all", label: "All threads"},
    %{id: "with_highlights", label: "With highlights"},
    %{id: "selected", label: "Selected threads"}
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
      id: "combined_carousel",
      label: "Video + image carousel",
      size: "One MP4 + portrait PNGs",
      description:
        "Create the vertical video and editable image carousel together from the same story.",
      icon: "hero-squares-2x2"
    },
    %{
      id: "long_form",
      label: "Long-form LinkedIn/Facebook post",
      size: "One portrait cover + editable text",
      description:
        "Publish selected answers, questions, and highlights as one editable post for LinkedIn and Facebook.",
      icon: "hero-document-text"
    },
    %{
      id: "portrait",
      label: "Editable image carousel",
      size: "1080 × 1350 PNGs",
      description: "A readable, swipeable story with editable headlines and supporting text.",
      icon: "hero-rectangle-stack"
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

    requested_step = if(params["step"] == "generate", do: "design", else: params["step"])

    restored_step =
      if requested_step in Enum.map(@steps, & &1.id), do: requested_step, else: default_step

    restored_asset_filter = restore_asset_filter(params, restored_asset_ids)
    restored_video_only? = restored_assets != [] and Enum.all?(restored_assets, &video_asset?/1)

    previous_packages = previous_output_packages(campaign)
    studio_state = Campaigns.guided_studio_state(campaign)
    selected_keys = restored_selected_keys(candidates, studio_state)

    selected_order =
      restored_selected_order(candidates, selected_keys, studio_state)

    expanded_thread_ids = initial_expanded_thread_ids(candidates, selected_keys)

    saved_content_mode = Map.get(studio_state, "content_mode")

    restored_content_mode =
      cond do
        restored_assets != [] -> content_mode_for_assets(restored_assets)
        saved_content_mode in ["video", "bundle", "text", "long_form"] -> saved_content_mode
        true -> "video"
      end

    saved_format = Map.get(studio_state, "selected_format")

    restored_format =
      if restored_assets == [] and Enum.any?(@formats, &(&1.id == saved_format)) do
        saved_format
      else
        format_for_content_mode(restored_content_mode)
      end

    available_platforms =
      if restored_assets == [],
        do: platforms_for_mode(restored_content_mode),
        else: platforms_for_assets(restored_assets)

    requested_platforms = requested_review_platforms(params, available_platforms)

    saved_platforms =
      if restored_assets == [], do: Map.get(studio_state, "selected_platforms", []), else: []

    saved_platforms = Enum.filter(saved_platforms, &(&1 in available_platforms))

    restored_platforms =
      cond do
        requested_platforms != [] -> requested_platforms
        saved_platforms != [] -> saved_platforms
        true -> available_platforms
      end

    restored_style = ShareCard.normalize_style(Map.get(studio_state, "selected_style"))

    restored_filter = "all"

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
      |> assign(:expanded_thread_ids, expanded_thread_ids)
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
      |> assign(:review_pending_count, 0)
      |> assign(:review_schedulable_count, 0)
      |> assign(:bulk_schedule_ready?, false)
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
          visible_thread_candidates(candidates, restored_filter, selected_keys),
          selected_keys,
          candidates,
          expanded_thread_ids
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
     |> assign(:generation_error, "Media generation failed before a package could be created.")
     |> put_flash(:error, "Media generation failed. Try again or adjust the selection.")}
  end

  @impl true
  def handle_event("filter_candidates", %{"filter" => filter}, socket) do
    filter = if filter in Enum.map(@candidate_filters, & &1.id), do: filter, else: "all"

    candidates =
      visible_thread_candidates(
        socket.assigns.all_candidates,
        filter,
        socket.assigns.selected_keys
      )

    {:noreply,
     socket
     |> assign(:candidate_filter, filter)
     |> stream(
       :candidate_groups,
       candidate_groups(
         candidates,
         socket.assigns.selected_keys,
         socket.assigns.all_candidates,
         socket.assigns.expanded_thread_ids
       ),
       reset: true
     )
     |> persist_studio_state()}
  end

  def handle_event("toggle_thread", %{"thread" => thread_id}, socket) do
    valid_thread_ids =
      socket.assigns.all_candidates
      |> Enum.map(&candidate_group_key/1)
      |> Enum.reject(&(&1 == "grid"))
      |> Enum.map(&candidate_group_dom_id/1)
      |> MapSet.new()

    if MapSet.member?(valid_thread_ids, thread_id) do
      expanded_thread_ids =
        toggle_map_set_member(socket.assigns.expanded_thread_ids, thread_id)

      visible_candidates =
        visible_thread_candidates(
          socket.assigns.all_candidates,
          socket.assigns.candidate_filter,
          socket.assigns.selected_keys
        )

      group =
        visible_candidates
        |> candidate_groups(
          socket.assigns.selected_keys,
          socket.assigns.all_candidates,
          expanded_thread_ids
        )
        |> Enum.find(&(&1.dom_id == thread_id))

      {:noreply,
       socket
       |> assign(:expanded_thread_ids, expanded_thread_ids)
       |> update_candidate_group_stream(group, [])}
    else
      {:noreply, socket}
    end
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

  def handle_event("go_to_step", %{"step" => step}, socket) do
    {:noreply, move_to_step(socket, step)}
  end

  def handle_event("select_style", %{"style" => style}, socket) do
    {:noreply,
     socket
     |> assign(:selected_style, ShareCard.normalize_style(style))
     |> persist_studio_state()}
  end

  def handle_event("select_content_mode", %{"mode" => mode}, socket)
      when mode in ["video", "bundle", "text", "long_form"] do
    {:noreply, socket |> put_content_mode(mode) |> persist_studio_state()}
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
         |> assign(:title_card_mode, mode)
         |> rehydrate_step("design")}

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
    {:noreply, start_package_generation(socket, socket.assigns.content_mode)}
  end

  def handle_event(
        "generate_companion",
        _params,
        %{assigns: %{generation_in_progress?: true}} = socket
      ) do
    {:noreply, socket}
  end

  def handle_event("generate_companion", %{"mode" => "text"}, socket) do
    socket = socket |> put_content_mode("text") |> persist_studio_state()

    case existing_companion_carousel(socket) do
      %MediaAsset{} = carousel ->
        assets =
          case Campaigns.assign_generation_batch([carousel]) do
            {:ok, updated_assets} -> updated_assets
            {:error, _reason} -> [carousel]
          end

        complete_generation(socket, %{assets: assets, errors: []})

      nil ->
        {:noreply, start_package_generation(socket, "text")}
    end
  end

  def handle_event("generate_companion", _params, socket), do: {:noreply, socket}

  def handle_event("toggle_platform", %{"platform" => platform}, socket) do
    available = platforms_for_mode(socket.assigns.content_mode)

    if platform in available do
      selected = socket.assigns.selected_platforms

      next =
        cond do
          platform in selected and length(selected) == 1 -> selected
          platform in selected -> List.delete(selected, platform)
          true -> Enum.filter(available, &(&1 in selected or &1 == platform))
        end

      {:noreply,
       socket
       |> assign(:selected_platforms, next)
       |> persist_studio_state()}
    else
      {:noreply, socket}
    end
  end

  def handle_event("toggle_platform", _params, socket), do: {:noreply, socket}

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

  def handle_event(
        "save_asset_slide",
        %{
          "asset-id" => asset_id,
          "slide-index" => slide_index,
          "slide" => slide_params
        },
        socket
      ) do
    with {:ok, asset} <- review_output_asset(socket, asset_id),
         {:ok, updated_asset} <-
           Campaigns.update_media_asset_slide(asset, slide_index, slide_params) do
      {:noreply, stream_insert(socket, :output_assets, updated_asset)}
    else
      {:error, :not_in_package} ->
        {:noreply, socket}

      {:error, :invalid_slide} ->
        {:noreply, put_flash(socket, :error, "Could not save that slide.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not save that slide.")}
    end
  end

  def handle_event("save_draft", %{"id" => id, "post_draft" => %{"body" => body}}, socket) do
    draft = Campaigns.get_post_draft!(id)

    if editable_draft?(socket, draft) do
      case Campaigns.update_post_draft_body(draft, body) do
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

    if schedulable_draft?(socket, draft) do
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
    pending_drafts =
      socket.assigns.campaign
      |> Campaigns.list_post_drafts()
      |> Enum.filter(&(&1.platform in socket.assigns.selected_platforms))
      |> Enum.filter(&review_draft?(socket, &1))
      |> deduplicate_review_drafts()
      |> Enum.filter(&PostDraft.schedulable?/1)

    drafts =
      pending_drafts
      |> schedulable_drafts()

    cond do
      pending_drafts == [] ->
        {:noreply, put_flash(socket, :info, "All matching posts are already scheduled.")}

      socket.assigns.content_mode == "bundle" and length(drafts) != length(pending_drafts) ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "The combined package is still preparing. Save both media assets before scheduling all channels together."
         )}

      true ->
        schedule_bulk_drafts(socket, drafts, scheduled_for)
    end
  end

  def handle_event("approve_draft", %{"id" => id}, socket) do
    draft = Campaigns.get_post_draft!(id)

    if editable_draft?(socket, draft) do
      case Campaigns.approve_post_draft(id) do
        {:ok, approved_draft} ->
          approved_draft = Campaigns.get_post_draft_with_asset!(approved_draft.id)
          {:noreply, stream_insert(socket, :review_drafts, draft_item(approved_draft))}

        {:error, _reason} ->
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

  def handle_event("artifacts_saved", %{"asset_id" => asset_id}, socket) do
    with {:ok, _asset} <- review_output_asset(socket, to_string(asset_id)) do
      {:noreply, refresh_review_drafts(socket)}
    else
      _error -> {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div
        id="guided-share-studio"
        phx-hook="PreserveScrollPosition"
        class="relative isolate min-h-screen overflow-hidden px-4 py-8 sm:px-6 lg:px-8 lg:py-10"
      >
        <div class="pointer-events-none absolute inset-x-0 top-0 -z-10 h-[34rem] bg-[radial-gradient(circle_at_top_left,rgba(249,115,22,0.17),transparent_38%),radial-gradient(circle_at_top_right,rgba(14,165,233,0.13),transparent_36%)]" />

        <div class="mx-auto max-w-7xl space-y-6">
          <header class="overflow-hidden rounded-[2rem] border border-base-content/10 bg-base-100/85 shadow-2xl shadow-base-content/5 backdrop-blur-xl">
            <div class="grid gap-5 p-5 md:p-7 lg:grid-cols-[1fr_auto] lg:items-center">
              <div>
                <p class="text-xs font-bold uppercase tracking-[0.2em] text-orange-700 dark:text-orange-200">
                  RationalGrid publishing studio
                </p>
                <h1 class="mt-2 max-w-4xl text-2xl font-semibold tracking-tight text-base-content text-balance sm:text-3xl">
                  {@campaign.title}
                </h1>
                <p class="mt-2 max-w-3xl text-sm leading-6 text-base-content/60">
                  <%= case @step do %>
                    <% "curate" -> %>
                      Choose the moments that tell one focused story.
                    <% "design" -> %>
                      Choose the output, visual treatment, and destinations.
                    <% _ -> %>
                      Refine the finished media and channel copy before publishing.
                  <% end %>
                </p>

                <div class="mt-4 flex flex-wrap items-center gap-2 text-xs font-semibold text-base-content/55">
                  <span class="rounded-full bg-base-200 px-3 py-1.5">
                    {length(@all_candidates)} available moments
                  </span>
                  <span class="rounded-full bg-orange-500/10 px-3 py-1.5 text-orange-700 dark:text-orange-200">
                    {@selected_count} selected
                  </span>
                </div>
              </div>

              <div class="flex flex-wrap gap-2 lg:justify-end">
                <a
                  id="open-source-grid"
                  href={@campaign.grid_url}
                  target="_blank"
                  rel="noopener noreferrer"
                  class="inline-flex items-center justify-center rounded-xl border border-base-content/15 px-3 py-2.5 text-sm font-semibold text-base-content/65 transition hover:bg-base-200"
                >
                  Source grid <.icon name="hero-arrow-up-right" class="ml-1.5 size-4" />
                </a>
                <.link
                  id="open-post-review"
                  navigate={~p"/posts/review"}
                  class="inline-flex items-center justify-center rounded-xl bg-base-content px-3 py-2.5 text-sm font-semibold text-base-100 shadow-sm transition hover:-translate-y-0.5 hover:bg-base-content/85"
                >
                  All posts <.icon name="hero-queue-list" class="ml-1.5 size-4" />
                </.link>
              </div>
            </div>

            <div class="border-t border-base-content/10 bg-base-200/35 px-4 py-4 sm:px-6 lg:px-10">
              <ol id="studio-progress" class="grid grid-cols-3 gap-2">
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
            class="space-y-6"
          >
            <div class="rounded-[2rem] border border-base-content/10 bg-base-100/85 p-5 shadow-xl shadow-base-content/5 backdrop-blur md:p-7">
              <div class="flex flex-col gap-5 lg:flex-row lg:items-end lg:justify-between">
                <div>
                  <p class="text-xs font-bold uppercase tracking-[0.2em] text-orange-600 dark:text-orange-300">
                    01 · Find the signal
                  </p>
                  <h2 class="mt-2 text-2xl font-semibold tracking-tight text-base-content">
                    Pick the moments for this package.
                  </h2>
                  <p class="mt-2 max-w-2xl text-sm leading-6 text-base-content/60">
                    Choose a clear opener, then add only the questions, passages, or answers needed to support it.
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

              <div
                id="content-candidates"
                phx-update="stream"
                class="mt-5 flex flex-col gap-4"
              >
                <div
                  id="empty-content-candidates"
                  class="hidden rounded-3xl border border-dashed border-base-content/20 bg-base-200/40 p-8 text-center text-sm text-base-content/55 only:block"
                >
                  No story threads match this view.
                </div>
                <section
                  :for={{id, group} <- @streams.candidate_groups}
                  id={id}
                  class={candidate_group_class(group.kind, group.selected_count)}
                >
                  <%= if group.kind == "overview" do %>
                    <div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
                      <div class="flex min-w-0 items-start gap-4">
                        <span class="grid size-11 shrink-0 place-items-center rounded-2xl bg-base-content text-base-100 shadow-lg shadow-base-content/10">
                          <.icon name="hero-squares-2x2" class="size-5" />
                        </span>
                        <div class="min-w-0">
                          <p class="text-[0.65rem] font-bold uppercase tracking-[0.18em] text-base-content/45">
                            {group.label}
                          </p>
                          <h3 class="mt-1 text-base font-semibold leading-6 text-base-content">
                            {group.title}
                          </h3>
                          <p class="mt-1 text-sm leading-6 text-base-content/55">
                            Add a whole-grid title card before the conversation begins.
                          </p>
                        </div>
                      </div>
                      <.signal_select_button
                        :if={group.prompt_candidate}
                        candidate={group.prompt_candidate}
                        action="opening"
                      />
                    </div>
                  <% else %>
                    <a
                      :if={group.continues_from_dom_id}
                      id={"thread-continuation-#{group.dom_id}"}
                      href={"#candidate-group-#{group.continues_from_dom_id}"}
                      class="mx-4 mt-4 inline-flex items-center gap-1.5 rounded-full bg-sky-500/10 px-3 py-1.5 text-xs font-bold text-sky-700 transition hover:bg-sky-500/15 dark:text-sky-200 md:mx-5"
                    >
                      <.icon name="hero-arrow-up-left" class="size-3.5" />
                      Continues from {group.continues_from_label}
                    </a>
                    <div class="flex items-start gap-3 p-4 md:p-5">
                      <button
                        id={"toggle-thread-#{group.dom_id}"}
                        type="button"
                        phx-click="toggle_thread"
                        phx-value-thread={group.dom_id}
                        disabled={not group.expandable?}
                        aria-expanded={if(group.expandable?, do: group.expanded?, else: nil)}
                        aria-controls={
                          if(group.expandable?, do: "thread-body-#{group.dom_id}", else: nil)
                        }
                        class="group min-w-0 flex-1 text-left disabled:cursor-default"
                      >
                        <span class="flex flex-wrap items-center gap-2">
                          <span class="text-[0.65rem] font-bold uppercase tracking-[0.18em] text-orange-600 dark:text-orange-300">
                            {group.label}
                          </span>
                          <span
                            :if={group.prompt_candidate}
                            class={candidate_type_class(group.prompt_candidate.type)}
                          >
                            <.icon
                              name={candidate_icon(group.prompt_candidate.type)}
                              class="size-3.5"
                            />
                            {group.prompt_candidate.label}
                          </span>
                          <span
                            :if={group.prompt_candidate && group.prompt_candidate.recommended?}
                            class="inline-flex items-center gap-1 rounded-full bg-orange-500 px-2 py-1 text-[0.62rem] font-bold uppercase tracking-wide text-white"
                          >
                            <.icon name="hero-sparkles-mini" class="size-3" /> Best opener
                          </span>
                          <span
                            :if={group.selected_count > 0}
                            class="rounded-full bg-orange-500/10 px-2 py-0.5 text-[0.65rem] font-bold text-orange-700 dark:text-orange-200"
                          >
                            {group.selected_count} selected
                          </span>
                        </span>
                        <span class="mt-1.5 block text-lg font-semibold leading-7 text-base-content text-balance">
                          {group.title}
                        </span>
                        <span
                          :if={
                            group.prompt_candidate && group.prompt_candidate.type == "question" &&
                              group.prompt_candidate.excerpt
                          }
                          class="mt-1 block text-sm leading-6 text-base-content/55"
                        >
                          {group.prompt_candidate.excerpt}
                        </span>
                        <span class="mt-3 flex flex-wrap items-center gap-x-3 gap-y-1 text-xs font-medium text-base-content/50">
                          <span :if={group.answer_count > 0}>
                            {group.answer_count} {if(group.answer_count == 1,
                              do: "answer",
                              else: "answers"
                            )}
                          </span>
                          <span :if={group.highlight_count > 0}>
                            {group.highlight_count} {if(group.highlight_count == 1,
                              do: "highlight",
                              else: "highlights"
                            )}
                          </span>
                          <span :if={group.follow_up_count > 0}>
                            {group.follow_up_count} follow-up {if(group.follow_up_count == 1,
                              do: "question",
                              else: "questions"
                            )}
                          </span>
                        </span>
                      </button>

                      <div class="flex shrink-0 items-center gap-2">
                        <.signal_select_button
                          :if={group.prompt_candidate}
                          candidate={group.prompt_candidate}
                          action="prompt"
                        />
                        <button
                          :if={group.expandable?}
                          id={"toggle-thread-control-#{group.dom_id}"}
                          type="button"
                          phx-click="toggle_thread"
                          phx-value-thread={group.dom_id}
                          aria-label={
                            if(group.expanded?,
                              do: "Collapse #{group.label}",
                              else: "Expand #{group.label}"
                            )
                          }
                          aria-expanded={group.expanded?}
                          aria-controls={"thread-body-#{group.dom_id}"}
                          class="grid size-9 place-items-center rounded-xl bg-base-200 text-base-content/45"
                        >
                          <.icon
                            name="hero-chevron-down"
                            class={
                              if(group.expanded?,
                                do: "size-4 rotate-180 transition duration-200",
                                else: "size-4 transition duration-200"
                              )
                            }
                          />
                        </button>
                      </div>
                    </div>

                    <div
                      :if={group.expanded? && group.expandable?}
                      id={"thread-body-#{group.dom_id}"}
                      class="border-t border-base-content/10 bg-base-100/55 px-4 py-5 md:px-6"
                    >
                      <div class="space-y-3 border-l-2 border-base-content/10 pl-4 md:pl-6">
                        <.thread_candidate
                          :for={candidate <- group.body_candidates}
                          id={"candidate-#{candidate.dom_id}"}
                          candidate={candidate}
                        />
                      </div>
                    </div>
                  <% end %>
                </section>
              </div>
            </div>

            <aside id="story-queue">
              <div class="rounded-[2rem] border border-orange-500/25 bg-orange-500/5 p-5 shadow-xl shadow-base-content/5 md:p-6">
                <div class="flex items-center justify-between gap-3">
                  <div>
                    <p class="text-xs font-bold uppercase tracking-[0.2em] text-orange-700 dark:text-orange-200">
                      Your story
                    </p>
                    <h2 class="mt-1 text-xl font-semibold text-base-content">
                      {@selected_count} of {@max_selection} moments selected
                    </h2>
                  </div>
                  <span class="grid size-11 place-items-center rounded-2xl bg-orange-500 text-lg font-semibold text-white shadow-lg shadow-orange-950/15">
                    {@selected_count}
                  </span>
                </div>

                <div
                  id="selected-aspects"
                  phx-update="stream"
                  class="mt-5 grid gap-2 md:grid-cols-2"
                >
                  <div
                    id="empty-selected-aspects"
                    class="hidden rounded-2xl border border-dashed border-base-content/20 p-4 text-sm text-base-content/55 only:block md:col-span-2"
                  >
                    Pick at least one moment to continue.
                  </div>
                  <.selected_aspect
                    :for={{id, candidate} <- @streams.selected_aspects}
                    id={id}
                    candidate={candidate}
                    theme="light"
                  />
                </div>

                <div class="mt-5 flex justify-end">
                  <button
                    id="continue-to-design"
                    type="button"
                    phx-click="continue_to_design"
                    disabled={@selected_count == 0}
                    class="inline-flex items-center justify-center rounded-2xl bg-orange-500 px-6 py-3.5 text-sm font-bold text-white shadow-lg shadow-orange-950/25 transition hover:-translate-y-0.5 hover:bg-orange-400 disabled:cursor-not-allowed disabled:opacity-40"
                  >
                    Continue to design <.icon name="hero-arrow-right" class="ml-2 size-4" />
                  </button>
                </div>
              </div>
            </aside>
          </section>

          <section
            :if={@step == "design"}
            id="stage-design"
            class="space-y-6"
          >
            <div class="space-y-6">
              <div class="rounded-[2rem] border border-base-content/10 bg-base-100/85 p-5 shadow-xl shadow-base-content/5 md:p-7">
                <div class="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
                  <div>
                    <p class="text-xs font-bold uppercase tracking-[0.2em] text-sky-600 dark:text-sky-300">
                      01 · Output
                    </p>
                    <h2 class="mt-2 text-xl font-semibold text-base-content">
                      What are you creating?
                    </h2>
                    <p class="mt-1 max-w-2xl text-sm leading-6 text-base-content/60">
                      Choose the finished format first. This keeps the visual and channel choices relevant.
                    </p>
                  </div>
                  <span class="rounded-full bg-base-200 px-3 py-1 text-xs font-medium text-base-content/55">
                    {cond do
                      @content_mode == "video" -> "Vertical video"
                      @content_mode == "bundle" -> "Video + carousel"
                      @content_mode == "long_form" -> "Long-form post"
                      true -> "Image carousel"
                    end}
                  </span>
                </div>

                <div id="content-mode-picker" class="mt-5 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
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
                    id="content-mode-bundle"
                    type="button"
                    phx-click="select_content_mode"
                    phx-value-mode="bundle"
                    aria-pressed={@content_mode == "bundle"}
                    class={content_mode_card_class(@content_mode == "bundle")}
                  >
                    <span class="flex items-start justify-between gap-3">
                      <span class="grid size-11 place-items-center rounded-2xl bg-violet-500 text-white shadow-lg shadow-violet-950/15">
                        <.icon name="hero-squares-2x2" class="size-6" />
                      </span>
                      <.icon
                        :if={@content_mode == "bundle"}
                        name="hero-check-circle-solid"
                        class="size-5 text-violet-500"
                      />
                    </span>
                    <span class="mt-4 block text-base font-bold text-base-content">
                      Video + carousel
                    </span>
                    <span class="mt-1 block text-sm font-semibold text-base-content/70">
                      Create both together
                    </span>
                    <span class="mt-2 block text-xs leading-5 text-base-content/55">
                      One story and style, packaged for every supported social channel.
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
                    <span class="mt-4 block text-base font-bold text-base-content">
                      Image carousel
                    </span>
                    <span class="mt-1 block text-sm font-semibold text-base-content/70">
                      Swipeable portrait images
                    </span>
                    <span class="mt-2 block text-xs leading-5 text-base-content/55">
                      Editable PNG cards for X, LinkedIn, and Facebook.
                    </span>
                  </button>

                  <button
                    id="content-mode-long-form"
                    type="button"
                    phx-click="select_content_mode"
                    phx-value-mode="long_form"
                    aria-pressed={@content_mode == "long_form"}
                    class={content_mode_card_class(@content_mode == "long_form")}
                  >
                    <span class="flex items-start justify-between gap-3">
                      <span class="grid size-11 items-center justify-center rounded-2xl bg-emerald-500 text-white shadow-lg shadow-emerald-950/15">
                        <.icon name="hero-document-text" class="size-6" />
                      </span>
                      <.icon
                        :if={@content_mode == "long_form"}
                        name="hero-check-circle-solid"
                        class="size-5 text-emerald-500"
                      />
                    </span>
                    <span class="mt-4 block text-base font-bold text-base-content">Long post</span>
                    <span class="mt-1 block text-sm font-semibold text-base-content/70">
                      Full text with a cover
                    </span>
                    <span class="mt-2 block text-xs leading-5 text-base-content/55">
                      Keep longer answers, questions, and highlights as editable LinkedIn and Facebook text instead of squeezing them onto slides.
                    </span>
                  </button>
                </div>
              </div>
              <div class="rounded-[2rem] border border-base-content/10 bg-base-100/85 p-5 shadow-xl shadow-base-content/5 backdrop-blur md:p-7">
                <p class="text-xs font-bold uppercase tracking-[0.2em] text-orange-600 dark:text-orange-300">
                  02 · Visual style
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
                      "block h-16 rounded-2xl border border-white/15 shadow-inner",
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
                  03 · Opening frame
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
                :if={@title_card_mode == "pexels"}
                id="pexels-background-picker"
                class="rounded-[2rem] border border-base-content/10 bg-base-100/85 p-5 shadow-xl shadow-base-content/5 md:p-7"
              >
                <div class="flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
                  <div>
                    <p class="text-xs font-bold uppercase tracking-[0.2em] text-emerald-600 dark:text-emerald-300">
                      Photo search
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

              <div
                id="design-platform-picker"
                class="rounded-[2rem] border border-sky-500/20 bg-sky-500/5 p-5 shadow-xl shadow-base-content/5 md:p-7"
              >
                <div class="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
                  <div>
                    <p class="text-xs font-bold uppercase tracking-[0.15em] text-sky-700 dark:text-sky-200">
                      04 · Destinations
                    </p>
                    <h2 class="mt-1 text-xl font-semibold text-base-content">
                      Where should this package go?
                    </h2>
                    <p class="mt-1 text-sm text-base-content/60">
                      Pick one or more channels. You can change these later in review.
                    </p>
                  </div>
                  <span class="rounded-full bg-base-100 px-3 py-1.5 text-xs font-bold text-base-content/60">
                    {length(@selected_platforms)} selected
                  </span>
                </div>
                <div
                  id="design-platform-summary"
                  class="mt-4 rounded-2xl bg-base-100 px-4 py-3 text-sm font-semibold text-base-content"
                >
                  {destination_summary(@selected_platforms)}
                </div>
                <div class="mt-3 grid gap-2 sm:grid-cols-2 xl:grid-cols-3">
                  <button
                    :for={platform <- platforms_for_mode(@content_mode)}
                    id={"toggle-platform-#{platform}"}
                    type="button"
                    phx-click="toggle_platform"
                    phx-value-platform={platform}
                    aria-pressed={platform in @selected_platforms}
                    class={platform_button_class(platform in @selected_platforms)}
                  >
                    <span>{Platforms.label(platform)}</span>
                    <.icon
                      name={
                        if(platform in @selected_platforms,
                          do: "hero-check-circle",
                          else: "hero-plus-circle"
                        )
                      }
                      class="size-5"
                    />
                  </button>
                </div>
              </div>
            </div>

            <aside id="package-brief">
              <div class="rounded-[2rem] border border-base-content/10 bg-base-100/90 p-5 shadow-xl shadow-base-content/5 md:p-6">
                <p class="text-xs font-bold uppercase tracking-[0.2em] text-base-content/45">
                  Ready to create
                </p>
                <h2 class="mt-2 text-xl font-semibold text-base-content">
                  Review this package
                </h2>
                <p class="mt-1 text-sm text-base-content/55">
                  <%= if @content_mode == "long_form" do %>
                    {@selected_count} selected {if(@selected_count == 1,
                      do: "moment becomes",
                      else: "moments become"
                    )} one editable text post, in the order shown below.
                  <% else %>
                    {@selected_count} {if(@selected_count == 1,
                      do: "story moment",
                      else: "story moments"
                    )} will use the choices below.
                  <% end %>
                </p>
                <div
                  id="selected-aspects"
                  phx-update="stream"
                  class="mt-4 grid gap-2 md:grid-cols-2"
                >
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
                  <div class="flex items-center justify-between gap-4">
                    <dt class="text-base-content/55">Destinations</dt>
                    <dd class="text-right font-semibold text-base-content">
                      {length(@selected_platforms)} selected
                    </dd>
                  </div>
                </dl>

                <p
                  :if={@generation_error}
                  id="generation-error"
                  class="mt-4 rounded-2xl border border-red-500/20 bg-red-500/10 px-3 py-2 text-xs text-red-700 dark:text-red-200"
                >
                  {@generation_error}
                </p>

                <p
                  :if={@generation_in_progress?}
                  id="generation-progress"
                  class="mt-4 rounded-2xl border border-orange-500/20 bg-orange-500/10 px-3 py-2 text-xs text-orange-800 dark:text-orange-100"
                >
                  Creating editable slides and channel copy…
                </p>

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
                    id="create-story-package"
                    type="button"
                    phx-click="generate_package"
                    disabled={@generation_in_progress?}
                    class="inline-flex items-center justify-center rounded-2xl bg-orange-500 px-4 py-3 text-sm font-bold text-white shadow-lg shadow-orange-950/20 transition hover:-translate-y-0.5 hover:bg-orange-400 phx-click-loading:cursor-wait phx-click-loading:opacity-60 disabled:cursor-wait disabled:opacity-60"
                  >
                    <.icon name="hero-bolt" class="mr-1.5 size-4" />
                    {cond do
                      @generation_in_progress? -> "Creating…"
                      @content_mode == "video" -> "Create video"
                      @content_mode == "bundle" -> "Create both"
                      @content_mode == "long_form" -> "Create post"
                      true -> "Create carousel"
                    end}
                  </button>
                </div>
              </div>
            </aside>
          </section>

          <section :if={@step == "review"} id="stage-review" class="space-y-6">
            <div class="flex flex-col gap-4 rounded-[2rem] border border-emerald-500/20 bg-emerald-500/10 p-5 sm:flex-row sm:items-center sm:justify-between md:p-6">
              <div class="flex items-start gap-4">
                <span class="grid size-11 shrink-0 place-items-center rounded-2xl bg-emerald-500 text-white shadow-lg shadow-emerald-950/15">
                  <.icon name="hero-check" class="size-6" />
                </span>
                <div>
                  <p class="text-xs font-bold uppercase tracking-[0.2em] text-emerald-700 dark:text-emerald-200">
                    03 · Package created
                  </p>
                  <h2 class="mt-1 text-xl font-semibold text-base-content">
                    {cond do
                      @output_video_only? -> "Review the combined video and its copy."
                      @content_mode == "bundle" -> "Review the video, image carousel and copy."
                      @content_mode == "text" -> "Review the image carousel and edit its copy."
                      @content_mode == "long_form" -> "Review the cover image and full text post."
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
                <button
                  :if={@output_video_only?}
                  id="create-companion-carousel"
                  type="button"
                  phx-click="generate_companion"
                  phx-value-mode="text"
                  disabled={@generation_in_progress?}
                  class="inline-flex items-center justify-center rounded-2xl bg-orange-500 px-4 py-2.5 text-sm font-semibold text-white shadow-lg shadow-orange-950/15 transition hover:-translate-y-0.5 hover:bg-orange-400 disabled:cursor-wait disabled:opacity-60"
                >
                  <.icon name="hero-photo" class="mr-2 size-4" />
                  {if(@generation_in_progress?,
                    do: "Creating carousel…",
                    else: "Create image carousel"
                  )}
                </button>
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
                    campaign={@campaign}
                    selected={@selected_output_asset_id == Integer.to_string(asset.id)}
                    preview_slide={Map.get(@carousel_preview_slides, asset.id, 1)}
                    wide={@output_asset_count == 1}
                    auto_save={@content_mode in ["bundle", "long_form"]}
                    cover_image_url={
                      pexels_cover_url(
                        @selected_pexels_background,
                        @title_card_mode
                      )
                    }
                  />
                </div>
              </div>

              <div class="rounded-[2rem] border border-sky-500/25 bg-base-100/90 p-5 shadow-xl shadow-base-content/5 md:p-6">
                <div>
                  <p class="text-xs font-bold uppercase tracking-[0.2em] text-sky-600 dark:text-sky-300">
                    02 · Associated copy
                  </p>
                  <h3 class="mt-2 text-xl font-semibold text-base-content">
                    {cond do
                      @content_mode == "bundle" -> "Edit the carousel and video copy."
                      @content_mode == "text" -> "Edit the copy for these images."
                      @content_mode == "long_form" -> "Edit the longer post."
                      true -> "Write the post for this visual."
                    end}
                  </h3>
                  <p class="mt-1 text-sm leading-6 text-base-content/60">
                    <%= if @content_mode == "bundle" do %>
                      Choose one publishing time below. Text channels will use the image carousel; TikTok, Instagram, and YouTube will use the video.
                    <% else %>
                      <%= if @content_mode == "text" do %>
                        Refine each caption, then schedule the X, LinkedIn, and Facebook posts together below.
                      <% else %>
                        <%= if @content_mode == "long_form" do %>
                          The full answer is kept in one editable post with the themed cover image above. It will be scheduled to LinkedIn and Facebook.
                        <% else %>
                          <%= if @selected_output_asset_id == "all" do %>
                            Showing copy across all visuals. Select one above to focus on a single visual.
                          <% else %>
                            The drafts below belong to the visual selected above. The same reviewed copy will be posted to TikTok, Instagram, and YouTube.
                          <% end %>
                        <% end %>
                      <% end %>
                    <% end %>
                  </p>
                </div>

                <div
                  :if={@content_mode in ["video", "bundle", "long_form"]}
                  class="mt-4 flex items-center gap-2 rounded-2xl bg-sky-500/10 px-3 py-2.5 text-xs font-semibold text-sky-800 dark:text-sky-100"
                >
                  <.icon name="hero-information-circle" class="size-4 shrink-0" />
                  {length(@selected_platforms)} {if(length(@selected_platforms) == 1,
                    do: "channel",
                    else: "channels"
                  )} selected
                </div>

                <div
                  :if={@content_mode in ["video", "bundle", "long_form"]}
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
                  :if={@content_mode in ["video", "bundle", "text", "long_form"]}
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
                    disabled={not @bulk_schedule_ready?}
                    phx-confirm="This will create live posts in Buffer for the selected channels. Continue only after reviewing the media and copy."
                    class="inline-flex h-11 items-center justify-center rounded-xl bg-emerald-600 px-5 text-sm font-bold text-white shadow-lg shadow-emerald-950/15 transition hover:-translate-y-0.5 hover:bg-emerald-500 disabled:cursor-not-allowed disabled:opacity-40"
                  >
                    <.icon name="hero-calendar-days" class="mr-1.5 size-4" />
                    <%= if @content_mode == "bundle" and not @bulk_schedule_ready? and @review_pending_count > 0 do %>
                      Preparing {@review_schedulable_count} of {@review_pending_count} posts…
                    <% else %>
                      Publish {@review_schedulable_count} posts
                    <% end %>
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

  attr :candidate, :map, required: true
  attr :action, :string, default: "prompt"

  defp signal_select_button(assigns) do
    action_label = if(assigns.action == "opening", do: "opening", else: "prompt")
    assigns = assign(assigns, :action_label, action_label)

    ~H"""
    <button
      id={"select-aspect-#{@candidate.dom_id}"}
      phx-hook="PreventSelectionScroll"
      type="button"
      phx-click="toggle_aspect"
      phx-value-key={@candidate.key}
      aria-pressed={@candidate.selected?}
      class={signal_select_button_class(@candidate.selected?)}
    >
      <.icon
        name={if(@candidate.selected?, do: "hero-check", else: "hero-plus")}
        class="size-4"
      />
      {if(@candidate.selected?, do: "Added", else: "Add #{@action_label}")}
    </button>
    """
  end

  attr :id, :string, required: true
  attr :candidate, :map, required: true

  defp thread_candidate(assigns) do
    role_label =
      if(assigns.candidate.type == "question",
        do: "Follow-up question",
        else: assigns.candidate.label
      )

    assigns = assign(assigns, :role_label, role_label)

    ~H"""
    <article id={@id} class={thread_candidate_class(@candidate)}>
      <button
        id={"select-aspect-#{@candidate.dom_id}"}
        phx-hook="PreventSelectionScroll"
        type="button"
        phx-click="toggle_aspect"
        phx-value-key={@candidate.key}
        aria-pressed={@candidate.selected?}
        class="flex w-full items-start gap-3 text-left md:gap-4"
      >
        <span class={thread_candidate_icon_class(@candidate.type)}>
          <.icon name={candidate_icon(@candidate.type)} class="size-4" />
        </span>
        <span class="min-w-0 flex-1">
          <span class="flex flex-wrap items-center gap-2">
            <span class={candidate_type_class(@candidate.type)}>{@role_label}</span>
            <span
              :if={@candidate.recommended?}
              class="inline-flex items-center gap-1 rounded-full bg-orange-500 px-2 py-1 text-[0.62rem] font-bold uppercase tracking-wide text-white"
            >
              <.icon name="hero-sparkles-mini" class="size-3" /> Best opener
            </span>
          </span>
          <span class="mt-2 block text-sm font-semibold leading-6 text-base-content md:text-base">
            {@candidate.title}
          </span>
          <span
            :if={@candidate.excerpt}
            class="mt-1 block line-clamp-3 text-sm leading-6 text-base-content/55"
          >
            {@candidate.excerpt}
          </span>
          <span class="mt-2 flex flex-wrap items-center gap-2 text-[0.68rem] font-semibold text-base-content/45">
            <span class="inline-flex items-center gap-1">
              <.icon name="hero-rectangle-stack" class="size-3.5" />
              {@candidate.slide_count} {if(@candidate.slide_count == 1,
                do: "slide",
                else: "slides"
              )}
            </span>
            <span>{candidate_type_description(@candidate.type)}</span>
          </span>
        </span>
        <span class={selection_indicator_class(@candidate.selected?)}>
          <.icon
            name={if(@candidate.selected?, do: "hero-check", else: "hero-plus")}
            class="size-4"
          />
        </span>
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
  attr :campaign, Campaign, required: true
  attr :selected, :boolean, required: true
  attr :preview_slide, :integer, default: 1
  attr :wide, :boolean, default: false
  attr :auto_save, :boolean, default: false
  attr :cover_image_url, :string, default: nil

  defp output_asset_card(assigns) do
    slides = canvas_slides(assigns.campaign, assigns.asset)
    preview_slide = min(max(assigns.preview_slide, 1), max(length(slides), 1))
    slide = Enum.at(slides, preview_slide - 1) || %{}

    assigns =
      assigns
      |> assign(:canvas_slides, slides)
      |> assign(:preview_slide, preview_slide)
      |> assign(:slide_supports_body?, slide_supports_body?(slide))
      |> assign(:artifacts_ready?, client_artifacts_ready?(assigns.asset))
      |> assign(
        :slide_form,
        to_form(
          %{
            "title" => slide_value(slide, "title"),
            "body" => slide_value(slide, "body")
          },
          as: :slide
        )
      )

    ~H"""
    <article id={@id} class={output_asset_card_class(@selected, @wide, @asset)}>
      <video
        :if={video_asset?(@asset)}
        id={"guided-video-preview-#{@asset.id}"}
        data-browser-frame-video-url={client_video_url(@asset)}
        controls
        playsinline
        preload="metadata"
        class={[
          "h-[70vh] max-h-[42rem] w-auto max-w-full rounded-2xl border border-base-content/10 bg-slate-950 object-contain",
          @wide && "lg:col-start-1 lg:row-start-1"
        ]}
      >
      </video>
      <canvas
        :if={not video_asset?(@asset)}
        id={"guided-output-preview-#{@asset.id}"}
        width="1080"
        height="1350"
        phx-update="ignore"
        aria-label={@asset.title}
        class={[asset_image_class(@asset), @wide && "lg:col-start-1 lg:row-start-1"]}
      >
      </canvas>
      <div
        id={"curated-carousel-slides-#{@asset.id}"}
        data-slides={Jason.encode!(@canvas_slides)}
        data-selected-indexes={Jason.encode!(carousel_selected_slide_indexes(@asset))}
        data-preview-slide={@preview_slide}
        data-main-preview-id={"guided-output-preview-#{@asset.id}"}
        data-video-preview-id={
          if(browser_canvas_video?(@asset),
            do: "guided-video-preview-#{@asset.id}",
            else: ""
          )
        }
        data-style={@asset.style}
        data-video-frame={if(browser_canvas_video?(@asset), do: "true", else: "false")}
        data-cover-image-url={@cover_image_url}
        data-logo-src="/images/rg_logo.webp"
        data-upload-url={client_artifact_upload_url(@asset)}
        data-asset-id={@asset.id}
        data-auto-save={if(@auto_save, do: "true", else: "false")}
        data-renderer-version={ArtifactStore.renderer_version()}
        data-artifacts-ready={if(@artifacts_ready?, do: "true", else: "false")}
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
              Browser-rendered media
            </p>
            <p
              :if={@asset.kind == "curated_carousel"}
              class="mt-1 text-xs leading-5 text-base-content/60"
            >
              Choose the images to publish. Click in the order you want, then refine it below. The RationalGrid CTA is always last.
            </p>
            <p
              :if={browser_canvas_video?(@asset)}
              class="mt-1 text-xs leading-5 text-base-content/60"
            >
              These Canvas frames are the finished visual source used to package the video.
            </p>
            <p
              data-browser-render-status
              class="mt-1 text-xs font-semibold text-emerald-700 dark:text-emerald-200"
            >
              Preparing editable preview…
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
              Save finished assets
            </button>
          </div>
        </div>

        <div class="grid grid-cols-2 gap-2 sm:grid-cols-4">
          <div :for={index <- canvas_slide_indexes(@asset)} class="min-w-0">
            <button
              id={"curated-carousel-slide-#{@asset.id}-#{index}"}
              type="button"
              phx-click="preview_carousel_slide"
              phx-value-asset-id={@asset.id}
              phx-value-slide-index={index}
              data-carousel-preview
              data-preview-target={"guided-output-preview-#{@asset.id}"}
              data-preview-canvas={"canvas-curated-carousel-slide-#{@asset.id}-#{index}"}
              aria-label={"Preview carousel slide #{index}"}
              class={[
                carousel_slide_link_class(@asset, index),
                @preview_slide == index && "ring-2 ring-sky-400/80"
              ]}
            >
              <canvas
                id={"canvas-curated-carousel-slide-#{@asset.id}-#{index}"}
                width="1080"
                height={if(browser_canvas_video?(@asset), do: 1920, else: 1350)}
                data-canvas-slide
                data-slide-index={index}
                phx-update="ignore"
                aria-label={"Browser-rendered carousel slide #{index}"}
                class={[
                  "w-full bg-base-200 object-cover",
                  if(browser_canvas_video?(@asset),
                    do: "aspect-[9/16]",
                    else: "aspect-[4/5]"
                  )
                ]}
              >
              </canvas>
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

        <.form
          for={@slide_form}
          id={"asset-slide-form-#{@asset.id}-#{@preview_slide}"}
          phx-change="save_asset_slide"
          phx-value-asset-id={@asset.id}
          phx-value-slide-index={@preview_slide}
          class="grid gap-3 rounded-2xl border border-base-content/10 bg-base-100/80 p-4"
        >
          <div>
            <p class="text-xs font-bold uppercase tracking-[0.16em] text-base-content/55">
              Edit slide {@preview_slide}
            </p>
            <p class="mt-1 text-xs text-base-content/50">
              Text reflows and resizes in the canvas as you type. Save the finished assets after editing.
            </p>
          </div>
          <.input
            id={"asset-slide-title-#{@asset.id}-#{@preview_slide}"}
            field={@slide_form[:title]}
            type="textarea"
            label={if(@slide_supports_body?, do: "Headline", else: "Main text")}
            rows="3"
            phx-debounce="300"
          />
          <.input
            :if={@slide_supports_body?}
            id={"asset-slide-body-#{@asset.id}-#{@preview_slide}"}
            field={@slide_form[:body]}
            type="textarea"
            label="Supporting text"
            rows="6"
            phx-debounce="300"
          />
          <p :if={@slide_supports_body?} class="-mt-1 text-xs leading-5 text-base-content/50">
            Use blank lines, <span class="font-semibold">## headings</span>, <span class="font-semibold">- lists</span>, or <span class="font-semibold">&gt; quotes</span>. Capitalization is preserved exactly as entered.
          </p>
        </.form>

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
          :if={@artifacts_ready?}
          href={client_asset_url(@asset, @preview_slide)}
          target="_blank"
          rel="noopener noreferrer"
          class="inline-flex items-center rounded-full bg-base-content px-3 py-1.5 text-xs font-semibold text-base-100 transition hover:-translate-y-0.5"
        >
          Open saved {media_label(@asset)} <.icon name="hero-arrow-up-right" class="ml-1 size-3" />
        </a>
        <span
          :if={not @artifacts_ready?}
          class="inline-flex items-center rounded-full border border-base-content/15 px-3 py-1.5 text-xs font-semibold text-base-content/50"
        >
          Save finished assets to open this file
        </span>
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
          disabled={not @item.editable?}
        />
      </.form>

      <p
        :if={not @item.editable?}
        class="mt-2 text-xs font-semibold text-base-content/50"
      >
        Scheduled and published copy is locked. Create a new draft to revise it.
      </p>

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
              :if={@item.approvable?}
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
    selected_group_id = candidate_group_dom_id(candidate_group_key(candidate))
    expanded_thread_ids = MapSet.put(socket.assigns.expanded_thread_ids, selected_group_id)

    visible_candidates =
      visible_thread_candidates(candidates, socket.assigns.candidate_filter, selected_keys)

    groups =
      candidate_groups(visible_candidates, selected_keys, candidates, expanded_thread_ids)

    selected_group = Enum.find(groups, &(&1.dom_id == selected_group_id))

    socket
    |> assign(:selected_keys, selected_keys)
    |> assign(:selected_order, selected_order)
    |> assign(:selected_count, MapSet.size(selected_keys))
    |> assign(:expanded_thread_ids, expanded_thread_ids)
    |> update_candidate_group_stream(selected_group, groups)
    |> stream(:selected_aspects, Workflow.selected_candidates(candidates, selected_order),
      reset: true
    )
    |> persist_studio_state()
  end

  defp update_candidate_group_stream(socket, nil, groups),
    do: stream(socket, :candidate_groups, groups, reset: true)

  defp update_candidate_group_stream(socket, group, _groups),
    do: stream_insert(socket, :candidate_groups, group)

  defp persist_studio_state(socket) do
    state = %{
      "selected_keys" => socket.assigns.selected_order,
      "selected_style" => socket.assigns.selected_style,
      "selected_format" => socket.assigns.selected_format,
      "content_mode" => socket.assigns.content_mode,
      "selected_platforms" => socket.assigns.selected_platforms,
      "candidate_filter" => socket.assigns.candidate_filter
    }

    case Campaigns.save_guided_studio_state(socket.assigns.campaign, state) do
      {:ok, campaign} -> assign(socket, :campaign, campaign)
      {:error, _changeset} -> socket
    end
  end

  defp put_content_mode(socket, mode) do
    socket
    |> assign(:content_mode, mode)
    |> assign(:selected_format, format_for_content_mode(mode))
    |> assign(:selected_platforms, platforms_for_mode(mode))
  end

  defp format_for_content_mode("video"), do: "story_video"
  defp format_for_content_mode("bundle"), do: "combined_carousel"
  defp format_for_content_mode("long_form"), do: "long_form"
  defp format_for_content_mode(_mode), do: "portrait"

  defp content_mode_for_assets(assets) do
    video? = Enum.any?(assets, &video_asset?/1)
    visual? = Enum.any?(assets, &(not video_asset?(&1)))

    cond do
      video? and visual? -> "bundle"
      video? -> "video"
      Enum.any?(assets, &(&1.kind == "long_form_post")) -> "long_form"
      true -> "text"
    end
  end

  defp requested_review_platforms(%{"platform" => platforms}, available_platforms)
       when is_binary(platforms) do
    requested = platforms |> String.split(",", trim: true) |> MapSet.new()
    Enum.filter(available_platforms, &MapSet.member?(requested, &1))
  end

  defp requested_review_platforms(_params, _available_platforms), do: []

  defp start_package_generation(socket, content_mode) do
    selected_candidates =
      socket.assigns.all_candidates
      |> Workflow.selected_candidates(socket.assigns.selected_order)
      |> maybe_text_quote_candidates(content_mode, socket.assigns.all_candidates)

    format =
      case content_mode do
        "text" -> "portrait"
        "bundle" -> "combined_carousel"
        "long_form" -> "long_form"
        _ -> socket.assigns.selected_format
      end

    campaign = socket.assigns.campaign
    style = socket.assigns.selected_style

    socket
    |> assign(:generation_in_progress?, true)
    |> assign(:generation_error, nil)
    |> start_async(:generate_package, fn ->
      Workflow.generate(campaign, selected_candidates, style: style, format: format)
    end)
  end

  defp existing_companion_carousel(socket) do
    video_source_ids =
      socket.assigns.output_asset_ids
      |> Enum.map(&Campaigns.get_media_asset/1)
      |> Enum.filter(&match?(%MediaAsset{}, &1))
      |> Enum.filter(&video_asset?/1)
      |> MapSet.new(& &1.source_id)

    socket.assigns.campaign
    |> Campaigns.list_media_assets()
    |> Enum.find(fn asset ->
      asset.kind == "curated_carousel" and MapSet.member?(video_source_ids, asset.source_id)
    end)
  end

  defp restored_selected_keys(candidates, state) do
    keys = Map.get(state, "selected_keys")

    if is_list(keys) and keys != [] do
      candidates_by_key = Map.new(candidates, &{&1.key, &1})

      keys
      |> Enum.map(&restored_candidate_key(&1, candidates, candidates_by_key))
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()
    else
      Workflow.default_selection(candidates)
    end
  end

  defp restored_candidate_key(key, _candidates, candidates_by_key)
       when is_map_key(candidates_by_key, key),
       do: key

  defp restored_candidate_key("key_node:" <> node_id, candidates, _candidates_by_key) do
    case Enum.find(candidates, &(&1.type == "question" and &1.node_id == node_id)) do
      %{key: key} -> key
      nil -> nil
    end
  end

  defp restored_candidate_key(_key, _candidates, _candidates_by_key), do: nil

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
      socket =
        if step == "curate" do
          assign(socket, :candidate_filter, "all")
        else
          socket
        end

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
      |> rehydrate_step(step)
    else
      put_flash(socket, :error, step_error(step))
    end
  end

  defp rehydrate_step(socket, "curate") do
    visible_candidates =
      visible_thread_candidates(
        socket.assigns.all_candidates,
        socket.assigns.candidate_filter,
        socket.assigns.selected_keys
      )

    stream(
      socket,
      :candidate_groups,
      candidate_groups(
        visible_candidates,
        socket.assigns.selected_keys,
        socket.assigns.all_candidates,
        socket.assigns.expanded_thread_ids
      ),
      reset: true
    )
  end

  defp rehydrate_step(socket, "design") do
    photos =
      socket.assigns.pexels_by_id
      |> Map.values()
      |> Enum.sort_by(&(Map.get(&1, :id) || Map.get(&1, "id")))

    stream(socket, :pexels_photos, photos, reset: true)
  end

  defp rehydrate_step(socket, "review") do
    assets =
      socket.assigns.output_asset_ids
      |> Enum.sort()
      |> Enum.map(&Campaigns.get_media_asset/1)
      |> Enum.filter(&match?(%MediaAsset{}, &1))
      |> Enum.filter(&(&1.campaign_id == socket.assigns.campaign.id))

    socket
    |> stream(:output_assets, assets, reset: true)
    |> refresh_review_drafts()
  end

  defp rehydrate_step(socket, _step), do: socket

  defp complete_generation(socket, %{assets: [], errors: errors}) do
    {:noreply,
     socket
     |> assign(:generation_error, generation_error(errors))
     |> put_flash(:error, "No assets could be generated. Review the selection and try again.")}
  end

  defp complete_generation(socket, %{assets: assets, errors: errors}) do
    output_asset_ids = assets |> Enum.map(& &1.id) |> MapSet.new()

    available_platforms = platforms_for_assets(assets)

    selected_platforms =
      Enum.filter(socket.assigns.selected_platforms, &(&1 in available_platforms))

    selected_platforms =
      if selected_platforms == [], do: available_platforms, else: selected_platforms

    Campaigns.ensure_post_drafts_for_platforms(
      socket.assigns.campaign,
      assets,
      selected_platforms,
      refresh: true
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
    pending_drafts = Enum.filter(drafts, &PostDraft.schedulable?/1)
    schedulable_drafts = schedulable_drafts(pending_drafts)

    bulk_schedule_ready? =
      schedulable_drafts != [] and
        (socket.assigns.content_mode != "bundle" or
           length(schedulable_drafts) == length(pending_drafts))

    socket
    |> assign(:preview_mode?, preview_mode?)
    |> assign(:review_draft_count, length(drafts))
    |> assign(:review_pending_count, length(pending_drafts))
    |> assign(:review_schedulable_count, length(schedulable_drafts))
    |> assign(:bulk_schedule_ready?, bulk_schedule_ready?)
    |> stream(:review_drafts, Enum.map(drafts, &draft_item/1), reset: true)
  end

  defp schedule_bulk_drafts(socket, drafts, scheduled_for) do
    results = Enum.map(drafts, &Campaigns.schedule_post_draft(&1.id, scheduled_for))
    scheduled_count = Enum.count(results, &match?({:ok, _draft}, &1))
    failed_count = length(results) - scheduled_count
    socket = refresh_review_drafts(socket)

    if failed_count == 0 do
      {:noreply,
       put_flash(
         socket,
         :info,
         "Scheduled #{scheduled_count} #{if(scheduled_count == 1, do: "post", else: "posts")} through Buffer."
       )}
    else
      {:noreply,
       put_flash(
         socket,
         :error,
         "Scheduled #{scheduled_count} posts; #{failed_count} could not be scheduled. Check Buffer connections."
       )}
    end
  end

  defp schedulable_drafts(drafts) do
    Enum.filter(drafts, fn draft ->
      PostDraft.schedulable?(draft) and
        Buffer.account_for(draft.platform) != nil and
        client_artifacts_ready?(draft.media_asset) and
        if draft.platform in Platforms.video_ids(),
          do: video_asset?(draft.media_asset),
          else: not video_asset?(draft.media_asset)
    end)
  end

  defp client_artifacts_ready?(%MediaAsset{} = asset) do
    ArtifactStore.ready?(asset, Campaigns.media_asset_slide_indexes(asset))
  end

  defp client_artifacts_ready?(nil), do: true

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
    package_draft?(socket, draft) and PostDraft.editable?(draft)
  end

  defp schedulable_draft?(socket, %PostDraft{} = draft) do
    package_draft?(socket, draft) and PostDraft.schedulable?(draft)
  end

  defp package_draft?(socket, %PostDraft{} = draft) do
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
      editable?: PostDraft.editable?(draft),
      approvable?: PostDraft.approvable?(draft),
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

  defp initial_expanded_thread_ids(candidates, _selected_keys) do
    candidates
    |> Enum.map(&candidate_group_key/1)
    |> Enum.reject(&(&1 == "grid"))
    |> Enum.map(&candidate_group_dom_id/1)
    |> MapSet.new()
  end

  defp visible_thread_candidates(candidates, "with_highlights", _selected_keys) do
    highlighted_groups =
      candidates
      |> Enum.filter(&(&1.type == "highlight"))
      |> MapSet.new(&candidate_group_key/1)

    Enum.filter(candidates, &MapSet.member?(highlighted_groups, candidate_group_key(&1)))
  end

  defp visible_thread_candidates(candidates, "selected", selected_keys) do
    selected_groups =
      candidates
      |> Enum.filter(&MapSet.member?(selected_keys, &1.key))
      |> MapSet.new(&candidate_group_key/1)

    Enum.filter(candidates, &MapSet.member?(selected_groups, candidate_group_key(&1)))
  end

  defp visible_thread_candidates(candidates, _filter, _selected_keys), do: candidates

  defp toggle_map_set_member(set, value) do
    if MapSet.member?(set, value), do: MapSet.delete(set, value), else: MapSet.put(set, value)
  end

  defp candidate_groups(candidates, selected_keys, all_candidates, expanded_thread_ids) do
    candidates = candidate_items(candidates, selected_keys)

    all_group_keys =
      all_candidates
      |> Enum.map(&candidate_group_key/1)
      |> Enum.uniq()

    thread_numbers =
      all_group_keys
      |> Enum.filter(&String.starts_with?(&1, "node:"))
      |> Enum.with_index(1)
      |> Map.new()

    group_keys =
      all_group_keys
      |> Enum.filter(fn group_key ->
        Enum.any?(candidates, fn candidate -> candidate_group_key(candidate) == group_key end)
      end)

    group_keys =
      group_keys ++
        (candidates
         |> Enum.map(&candidate_group_key/1)
         |> Enum.uniq()
         |> Enum.reject(&(&1 in group_keys)))

    group_keys
    |> Enum.sort_by(&candidate_group_display_order(&1, thread_numbers))
    |> Enum.map(fn group_key ->
      group_candidates = Enum.filter(candidates, &(candidate_group_key(&1) == group_key))

      all_group_candidates =
        Enum.filter(all_candidates, &(candidate_group_key(&1) == group_key))

      node_id = group_node_id(group_key)
      prompt_candidate = candidate_group_prompt(group_candidates, group_key, node_id)

      continues_from_thread_id =
        prompt_candidate && prompt_candidate.continues_from_thread_id

      body_candidates =
        case prompt_candidate do
          nil -> group_candidates
          prompt -> Enum.reject(group_candidates, &(&1.key == prompt.key))
        end

      %{
        dom_id: candidate_group_dom_id(group_key),
        kind: candidate_group_kind(group_key),
        label: candidate_group_label(group_key, thread_numbers),
        title: candidate_group_title(all_group_candidates, node_id),
        continues_from_label: continuation_thread_label(continues_from_thread_id, thread_numbers),
        continues_from_dom_id: continuation_thread_dom_id(continues_from_thread_id),
        prompt_candidate: prompt_candidate,
        body_candidates: body_candidates,
        expandable?: body_candidates != [],
        selected_count: Enum.count(group_candidates, & &1.selected?),
        answer_count: Enum.count(all_group_candidates, &answer_candidate?/1),
        highlight_count: Enum.count(all_group_candidates, &(&1.type == "highlight")),
        follow_up_count:
          Enum.count(all_group_candidates, fn candidate ->
            candidate.type == "question" and
              (is_nil(prompt_candidate) or candidate.key != prompt_candidate.key)
          end),
        option_count: length(all_group_candidates),
        expanded?: MapSet.member?(expanded_thread_ids, candidate_group_dom_id(group_key))
      }
    end)
  end

  defp candidate_group_prompt(candidates, "grid", _node_id), do: List.first(candidates)

  defp candidate_group_prompt(candidates, "node:" <> _thread_id, node_id) do
    Enum.find(candidates, fn candidate ->
      candidate.node_id == node_id and
        (candidate.type == "question" or candidate.node_class in ["origin", "question", "user"])
    end)
  end

  defp candidate_group_prompt(_candidates, _group_key, _node_id), do: nil

  defp continuation_thread_label(nil, _thread_numbers), do: nil

  defp continuation_thread_label(thread_id, thread_numbers) do
    case Map.get(thread_numbers, "node:#{thread_id}") do
      nil -> nil
      thread_number -> "Story thread #{thread_number}"
    end
  end

  defp continuation_thread_dom_id(nil), do: nil
  defp continuation_thread_dom_id(thread_id), do: candidate_group_dom_id("node:#{thread_id}")

  defp answer_candidate?(candidate),
    do: candidate.type == "key_node" and candidate.node_class == "answer"

  defp candidate_group_display_order("grid", _thread_numbers), do: {0, 0}

  defp candidate_group_display_order("node:" <> _node_id = group_key, thread_numbers),
    do: {1, Map.get(thread_numbers, group_key, 0)}

  defp candidate_group_display_order(_group_key, _thread_numbers), do: {2, 0}

  defp candidate_group_key(%{thread_id: thread_id})
       when is_binary(thread_id) and thread_id != "",
       do: "node:#{thread_id}"

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

  defp candidate_group_kind("grid"), do: "overview"
  defp candidate_group_kind("node:" <> _node_id), do: "thread"
  defp candidate_group_kind(_group_key), do: "other"

  defp candidate_group_label("node:" <> _node_id = group_key, thread_numbers),
    do: "Story thread #{Map.fetch!(thread_numbers, group_key)}"

  defp candidate_group_label("grid", _thread_numbers), do: "Optional opening"
  defp candidate_group_label(_group_key, _thread_numbers), do: "Other moments"

  defp candidate_group_title(candidates, node_id) when is_binary(node_id) do
    prompt =
      Enum.find(candidates, fn candidate ->
        candidate.node_id == node_id and
          (candidate.type == "question" or candidate.node_class in ["origin", "question", "user"])
      end)

    answer =
      Enum.find(candidates, fn candidate ->
        candidate.type == "key_node" and candidate.node_class == "answer"
      end)

    case prompt || answer || List.first(candidates) do
      %{title: title} -> title
      nil -> "Story thread #{node_id}"
    end
  end

  defp candidate_group_title([%{title: title} | _candidates], _node_id), do: title
  defp candidate_group_title([], _node_id), do: "Other moments"

  defp pexels_orientation(_format), do: "portrait"

  defp pexels_error_message(:not_configured),
    do: "Export PEXELS_API_KEY and restart the Phoenix server before searching."

  defp pexels_error_message(:invalid_query), do: "Enter a search term."

  defp pexels_error_message({:api_error, _status, message}),
    do: "Pexels could not complete the search: #{message}"

  defp pexels_error_message({:http_error, status}),
    do: "Pexels returned HTTP #{status}. Try again shortly."

  defp pexels_error_message(_reason), do: "Pexels search is unavailable right now."

  defp pexels_cover_url(background, "pexels") when is_map(background) do
    background["portrait_url"] || background["original_url"] || background["landscape_url"]
  end

  defp pexels_cover_url(_background, _mode), do: nil

  defp platforms_for_mode("text"), do: Platforms.text_ids()
  defp platforms_for_mode("bundle"), do: Platforms.ids()
  defp platforms_for_mode("long_form"), do: Platforms.long_form_ids()
  defp platforms_for_mode("video"), do: Platforms.video_ids()

  defp platforms_for_assets(assets) do
    assets
    |> Enum.flat_map(fn asset ->
      cond do
        video_asset?(asset) ->
          Platforms.video_ids()

        is_list(asset.recommended_platforms) and asset.recommended_platforms != [] ->
          asset.recommended_platforms

        true ->
          Platforms.text_ids()
      end
    end)
    |> Enum.uniq()
    |> then(fn platforms ->
      Enum.filter(Platforms.ids(), &(&1 in platforms))
    end)
  end

  defp destination_summary(platforms) do
    cond do
      platforms == Platforms.text_ids() ->
        "Text cards will be posted to X, LinkedIn, and Facebook with the same copy."

      platforms == Platforms.long_form_ids() ->
        "The full selected text and cover image will be posted to LinkedIn and Facebook."

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

      platforms == Platforms.long_form_ids() ->
        "Publish LinkedIn and Facebook posts at (UTC)"

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

      platforms == Platforms.long_form_ids() ->
        "LinkedIn and Facebook use the text Buffer accounts."

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
    with {:ok, asset} <- review_output_asset(socket, asset_id),
         true <- asset.kind in ["curated_carousel", "curated_carousel_video"] do
      {:ok, asset}
    else
      _error -> {:error, :not_in_package}
    end
  end

  defp review_output_asset(socket, asset_id) do
    case parse_asset_id(asset_id) do
      id when is_integer(id) ->
        if MapSet.member?(socket.assigns.output_asset_ids, id) do
          asset = Campaigns.get_media_asset!(id)

          if asset.campaign_id == socket.assigns.campaign.id do
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
         kind: kind,
         metadata: metadata
       })
       when kind in ["curated_carousel_video", "key_node_video"] do
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
  defp step_error("review"), do: "Create a package before opening review."
  defp step_error(_step), do: "That stage is not available yet."

  defp step_available?(_current_step, "curate", _selected_count, _output_count), do: true

  defp step_available?(_current_step, "design", selected_count, _output_count),
    do: selected_count > 0

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

  defp candidate_group_class(kind, selected_count) do
    [
      "overflow-hidden rounded-3xl border transition",
      kind == "overview" && "bg-base-200/45 p-4 md:p-5",
      kind != "overview" && "bg-base-200/35",
      if(selected_count > 0,
        do: "border-orange-500/35 shadow-lg shadow-orange-950/5",
        else: "border-base-content/10"
      )
    ]
  end

  defp signal_select_button_class(selected?) do
    [
      "inline-flex shrink-0 items-center justify-center gap-1.5 rounded-xl border px-3 py-2 text-xs font-bold transition hover:-translate-y-0.5",
      if(selected?,
        do: "border-orange-500 bg-orange-500 text-white shadow-md shadow-orange-950/15",
        else:
          "border-base-content/15 bg-base-100 text-base-content/60 hover:border-orange-500/40 hover:text-orange-700"
      )
    ]
  end

  defp thread_candidate_class(candidate) do
    [
      "rounded-2xl border p-3.5 transition hover:-translate-y-0.5 hover:shadow-md md:p-4",
      candidate.type == "highlight" && "border-violet-500/15 bg-violet-500/5 md:ml-6",
      candidate.type == "question" && "border-sky-500/15 bg-sky-500/5 md:ml-6",
      candidate.type == "key_node" && "border-emerald-500/15 bg-emerald-500/5",
      candidate.type == "grid" && "border-base-content/10 bg-base-100",
      candidate.selected? && "ring-2 ring-orange-500/45 shadow-md shadow-orange-950/5"
    ]
  end

  defp thread_candidate_icon_class("question"),
    do:
      "grid size-9 shrink-0 place-items-center rounded-xl bg-sky-500/10 text-sky-700 dark:text-sky-200"

  defp thread_candidate_icon_class("highlight"),
    do:
      "grid size-9 shrink-0 place-items-center rounded-xl bg-violet-500/10 text-violet-700 dark:text-violet-200"

  defp thread_candidate_icon_class("key_node"),
    do:
      "grid size-9 shrink-0 place-items-center rounded-xl bg-emerald-500/10 text-emerald-700 dark:text-emerald-200"

  defp thread_candidate_icon_class(_type),
    do: "grid size-9 shrink-0 place-items-center rounded-xl bg-base-200 text-base-content/55"

  defp candidate_type_class("question"),
    do:
      "inline-flex items-center gap-1.5 rounded-full bg-sky-500/10 px-2.5 py-1 text-[0.65rem] font-bold uppercase tracking-wide text-sky-700 dark:text-sky-200"

  defp candidate_type_class("highlight"),
    do:
      "inline-flex items-center gap-1.5 rounded-full bg-violet-500/10 px-2.5 py-1 text-[0.65rem] font-bold uppercase tracking-wide text-violet-700 dark:text-violet-200"

  defp candidate_type_class("key_node"),
    do:
      "inline-flex items-center gap-1.5 rounded-full bg-emerald-500/10 px-2.5 py-1 text-[0.65rem] font-bold uppercase tracking-wide text-emerald-700 dark:text-emerald-200"

  defp candidate_type_class(_type),
    do:
      "inline-flex items-center gap-1.5 rounded-full bg-base-200 px-2.5 py-1 text-[0.65rem] font-bold uppercase tracking-wide text-base-content/55"

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
  defp candidate_icon("key_node"), do: "hero-document-text"
  defp candidate_icon(_type), do: "hero-squares-2x2"

  defp candidate_type_description("question"), do: "Conversation starter"
  defp candidate_type_description("highlight"), do: "Human-selected passage"
  defp candidate_type_description("key_node"), do: "Structured reading sequence"
  defp candidate_type_description("grid"), do: "Whole-grid introduction"
  defp candidate_type_description(_type), do: "Shareable moment"

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

  defp platform_button_class(selected?) do
    [
      "flex items-center justify-between gap-3 rounded-2xl border px-4 py-3 text-left text-sm font-semibold transition hover:-translate-y-0.5",
      if(selected?,
        do: "border-sky-500/50 bg-sky-500/10 text-sky-800 shadow-sm dark:text-sky-100",
        else: "border-base-content/10 bg-base-100 text-base-content/65 hover:bg-base-200"
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
      (wide? and canvas_rendered_asset?(asset)) &&
        "grid gap-4 lg:grid-cols-[minmax(18rem,28rem)_minmax(0,1fr)] lg:items-start",
      if(selected?,
        do: "border-orange-500/50 bg-orange-500/8 shadow-lg",
        else: "border-base-content/10 bg-base-100"
      )
    ]
  end

  defp canvas_slide_indexes(%MediaAsset{kind: "curated_carousel", metadata: metadata}) do
    count = Map.get(metadata || %{}, "slide_count", 1)
    Enum.to_list(1..max(count, 1))
  end

  defp canvas_slide_indexes(%MediaAsset{} = asset),
    do: Campaigns.media_asset_slide_indexes(asset)

  defp canvas_rendered_asset?(%MediaAsset{}), do: true

  defp browser_canvas_video?(%MediaAsset{} = asset), do: video_asset?(asset)

  defp client_artifact_upload_url(%MediaAsset{id: id}),
    do: "/api/media-assets/#{id}/artifacts"

  defp client_video_url(%MediaAsset{id: id}), do: "/media-assets/#{id}/artifact.mp4"

  defp client_asset_url(%MediaAsset{} = asset, slide_index) do
    if video_asset?(asset),
      do: client_video_url(asset),
      else: Campaigns.media_asset_artifact_url(asset, slide_index)
  end

  defp canvas_slides(campaign, %MediaAsset{kind: "key_node_video"} = asset) do
    case Map.get(asset.metadata || %{}, "slides", []) do
      [] ->
        case ShareCard.find_key_node(campaign, asset.node_id) do
          node when is_map(node) -> ShareCard.node_short_video_slides(campaign, node)
          _node -> []
        end

      slides ->
        slides
    end
  end

  defp canvas_slides(_campaign, %MediaAsset{} = asset) do
    case Map.get(asset.metadata || %{}, "slides", []) do
      [] ->
        [
          %{
            "kind" => default_slide_kind(asset),
            "label" => "",
            "title" => asset.text || asset.title,
            "body" => if(asset.text == asset.title, do: "", else: asset.text || "")
          }
        ]

      slides ->
        slides
    end
  end

  defp default_slide_kind(%MediaAsset{kind: "highlight_card"}), do: "highlight"
  defp default_slide_kind(%MediaAsset{kind: "question_quote_card"}), do: "quote"
  defp default_slide_kind(%MediaAsset{kind: "long_form_post"}), do: "cover"
  defp default_slide_kind(%MediaAsset{}), do: "node_text"

  defp slide_value(slide, key) when is_map(slide) do
    atom_key = if(key == "title", do: :title, else: :body)
    Map.get(slide, key) || Map.get(slide, atom_key) || ""
  end

  defp slide_supports_body?(slide) when is_map(slide) do
    kind = Map.get(slide, "kind") || Map.get(slide, :kind)
    kind not in ["quote", "highlight"]
  end

  defp asset_image_class(_asset),
    do: "aspect-[4/5] w-full rounded-2xl border border-base-content/10 bg-base-200 object-contain"

  defp asset_kind_label(%MediaAsset{kind: "curated_carousel", metadata: metadata}) do
    slides = Map.get(metadata || %{}, "slides", [])

    selected =
      ShareCard.curated_carousel_selected_slide_indexes(
        slides,
        Map.get(metadata || %{}, "selected_slide_indexes")
      )

    "Carousel · #{length(selected)} images · CTA final"
  end

  defp asset_kind_label(%MediaAsset{kind: "curated_carousel_video"} = asset),
    do: "Story Short · #{video_duration_seconds(asset)}s · 1080 × 1920"

  defp asset_kind_label(%MediaAsset{kind: "key_node_carousel_slide", metadata: metadata}),
    do: "Carousel · slide #{Map.get(metadata, "slide_index")}"

  defp asset_kind_label(%MediaAsset{kind: "key_node_video"} = asset),
    do: "Short video · #{video_duration_seconds(asset)}s · 1080 × 1920"

  defp asset_kind_label(%MediaAsset{kind: "question_video"}),
    do: "Question Short · 6s · 1080 × 1920"

  defp asset_kind_label(%MediaAsset{kind: "highlight_video"}),
    do: "Highlight Reel · 6s · 1080 × 1920"

  defp asset_kind_label(%MediaAsset{kind: "key_node_card", metadata: %{"format" => "portrait"}}),
    do: "Portrait card · 1080 × 1350"

  defp asset_kind_label(%MediaAsset{kind: "key_node_card", metadata: %{"format" => "linkedin"}}),
    do: "LinkedIn explainer · 1200 × 1200"

  defp asset_kind_label(%MediaAsset{metadata: %{"format" => "portrait"}}),
    do: "Portrait card · 1080 × 1350"

  defp asset_kind_label(%MediaAsset{metadata: %{"format" => "linkedin"}}),
    do: "LinkedIn quote · 1200 × 1200"

  defp asset_kind_label(%MediaAsset{kind: kind}),
    do: kind |> String.replace("_", " ") |> String.capitalize()

  defp video_duration_seconds(%MediaAsset{} = asset) do
    CarouselVideo.asset_duration_seconds(asset, carousel_selected_slide_indexes(asset))
  end

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
