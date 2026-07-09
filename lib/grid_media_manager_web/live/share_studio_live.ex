defmodule GridMediaManagerWeb.ShareStudioLive do
  use GridMediaManagerWeb, :live_view

  alias GridMediaManager.Campaigns
  alias GridMediaManager.Campaigns.MediaAsset
  alias GridMediaManager.Campaigns.PostDraft
  alias GridMediaManager.Social.Platforms
  alias GridMediaManager.Social.Templates

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    campaign = Campaigns.get_campaign!(id)
    media_assets = Campaigns.list_media_assets(campaign)
    selected_platform = "x"
    selected_asset_id = "all"
    drafts = list_drafts(campaign, selected_platform, selected_asset_id)

    socket =
      socket
      |> assign(:page_title, campaign.title)
      |> assign(:campaign, campaign)
      |> assign(:platforms, Platforms.all())
      |> assign(:selected_platform, selected_platform)
      |> assign(:selected_asset_id, selected_asset_id)
      |> assign(:selected_asset, nil)
      |> assign(:origin_question, Campaigns.origin_question(campaign))
      |> assign(:key_nodes, Campaigns.key_nodes(campaign) |> Enum.take(8))
      |> assign(:first_answer_excerpt, Campaigns.first_answer_excerpt(campaign))
      |> assign(:follow_up_questions, Campaigns.follow_up_questions(campaign) |> Enum.take(6))
      |> assign(:user_questions, Campaigns.user_questions(campaign) |> Enum.take(6))
      |> assign(:highlights, Campaigns.highlights(campaign) |> Enum.take(8))
      |> assign(:asset_count, length(media_assets))
      |> assign(:draft_count, Campaigns.list_post_drafts(campaign) |> length())
      |> stream_configure(:post_drafts, dom_id: &"post-draft-#{&1.id}")
      |> stream(:media_assets, media_assets)
      |> stream(:post_drafts, draft_items(drafts))

    {:ok, socket}
  end

  @impl true
  def handle_event("select_platform", %{"platform" => platform}, socket) do
    platform =
      if platform in Platforms.ids(), do: platform, else: socket.assigns.selected_platform

    {:noreply,
     socket
     |> assign(:selected_platform, platform)
     |> refresh_drafts()}
  end

  def handle_event("select_asset", %{"id" => asset_id}, socket) do
    selected_asset = selected_asset(asset_id)

    {:noreply,
     socket
     |> assign(:selected_asset_id, asset_id)
     |> assign(:selected_asset, selected_asset)
     |> refresh_drafts()}
  end

  def handle_event("save_draft", %{"id" => id, "post_draft" => %{"body" => body}}, socket) do
    draft = Campaigns.get_post_draft!(id)

    case Campaigns.update_post_draft(draft, %{body: body, status: "draft"}) do
      {:ok, _draft} ->
        draft = Campaigns.get_post_draft_with_asset!(id)
        {:noreply, stream_insert(socket, :post_drafts, draft_item(draft))}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not save draft copy.")}
    end
  end

  def handle_event("copied", %{"draft_id" => draft_id}, socket)
      when is_binary(draft_id) and draft_id != "" do
    case Campaigns.mark_post_draft_copied(draft_id) do
      {:ok, _draft} ->
        draft = Campaigns.get_post_draft_with_asset!(draft_id)
        {:noreply, stream_insert(socket, :post_drafts, draft_item(draft))}

      {:error, _changeset} ->
        {:noreply, socket}
    end
  end

  def handle_event("copied", _params, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="min-h-screen px-4 py-8 sm:px-6 lg:px-8">
        <div class="mx-auto max-w-7xl space-y-6">
          <div class="rounded-[2rem] border border-base-content/10 bg-base-100/80 p-5 shadow-xl shadow-base-content/5 backdrop-blur md:p-7">
            <div class="flex flex-col gap-5 lg:flex-row lg:items-end lg:justify-between">
              <div>
                <.link
                  navigate={~p"/"}
                  class="inline-flex items-center text-sm font-medium text-base-content/60 transition hover:text-base-content"
                >
                  <.icon name="hero-arrow-left" class="mr-2 size-4" /> Import another grid
                </.link>
                <h1 class="mt-4 max-w-4xl text-3xl font-semibold tracking-tight text-base-content text-balance sm:text-4xl">
                  {@campaign.title}
                </h1>
                <p class="mt-3 max-w-3xl text-sm leading-6 text-base-content/65 sm:text-base">
                  Review the RationalGrid source content, generate deterministic post templates, edit the draft, then copy it for manual publishing. Visual asset generation now belongs here rather than the RationalGrid API.
                </p>
              </div>

              <div class="grid grid-cols-3 gap-2 rounded-3xl border border-base-content/10 bg-base-200/50 p-2 text-center">
                <div class="rounded-2xl bg-base-100 px-4 py-3">
                  <p class="text-2xl font-semibold">{@campaign.node_count || 0}</p>
                  <p class="text-xs uppercase tracking-wide text-base-content/50">nodes</p>
                </div>
                <div class="rounded-2xl bg-base-100 px-4 py-3">
                  <p class="text-2xl font-semibold">{@asset_count}</p>
                  <p class="text-xs uppercase tracking-wide text-base-content/50">assets</p>
                </div>
                <div class="rounded-2xl bg-base-100 px-4 py-3">
                  <p class="text-2xl font-semibold">{@draft_count}</p>
                  <p class="text-xs uppercase tracking-wide text-base-content/50">drafts</p>
                </div>
              </div>
            </div>
          </div>

          <div class="grid gap-6 xl:grid-cols-[0.9fr_1.05fr_1.25fr]">
            <aside
              id="grid-summary-panel"
              class="space-y-6 rounded-[2rem] border border-base-content/10 bg-base-100/80 p-5 shadow-xl shadow-base-content/5 backdrop-blur md:p-6"
            >
              <div>
                <p class="text-xs font-semibold uppercase tracking-[0.2em] text-orange-600 dark:text-orange-300">
                  Grid context
                </p>
                <div class="mt-4 flex flex-wrap gap-2">
                  <span
                    :for={tag <- @campaign.tags}
                    class="rounded-full bg-orange-500/10 px-3 py-1 text-xs font-medium text-orange-700 dark:text-orange-200"
                  >
                    {tag}
                  </span>
                </div>
              </div>

              <div class="space-y-3 rounded-3xl bg-base-200/50 p-4">
                <a
                  id="grid-source-link"
                  href={@campaign.grid_url}
                  target="_blank"
                  rel="noopener noreferrer"
                  class="group flex items-center justify-between gap-3 rounded-2xl bg-base-100 px-4 py-3 text-sm font-medium transition hover:-translate-y-0.5 hover:shadow-md"
                >
                  <span>Open grid</span>
                  <.icon
                    name="hero-arrow-up-right"
                    class="size-4 text-base-content/40 group-hover:text-base-content"
                  />
                </a>
                <a
                  :if={@campaign.graph_url}
                  id="grid-graph-link"
                  href={@campaign.graph_url}
                  target="_blank"
                  rel="noopener noreferrer"
                  class="group flex items-center justify-between gap-3 rounded-2xl bg-base-100 px-4 py-3 text-sm font-medium transition hover:-translate-y-0.5 hover:shadow-md"
                >
                  <span>Open graph</span>
                  <.icon
                    name="hero-arrow-up-right"
                    class="size-4 text-base-content/40 group-hover:text-base-content"
                  />
                </a>
              </div>

              <div :if={@origin_question} id="origin-question-section">
                <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/50">
                  Origin question
                </h2>
                <p class="mt-3 rounded-3xl border border-base-content/10 bg-base-100 p-4 text-sm font-semibold leading-6 text-base-content/80">
                  {@origin_question}
                </p>
              </div>

              <div :if={@first_answer_excerpt} id="first-answer-excerpt-section">
                <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/50">
                  First answer excerpt
                </h2>
                <p class="mt-3 rounded-3xl border border-base-content/10 bg-base-100 p-4 text-sm leading-6 text-base-content/70">
                  {@first_answer_excerpt}
                </p>
              </div>

              <div :if={@follow_up_questions != []} id="follow-up-questions-section">
                <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/50">
                  Follow-up questions
                </h2>
                <div class="mt-3 space-y-2">
                  <p
                    :for={question <- @follow_up_questions}
                    class="rounded-2xl border border-base-content/10 bg-base-100 p-3 text-sm leading-6 text-base-content/70"
                  >
                    {question}
                  </p>
                </div>
              </div>

              <div :if={@user_questions != []} id="user-questions-section">
                <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/50">
                  User questions
                </h2>
                <div class="mt-3 space-y-2">
                  <div
                    :for={question <- @user_questions}
                    class="rounded-2xl border border-base-content/10 bg-base-100 p-3"
                  >
                    <p class="text-sm leading-6 text-base-content/70">
                      {Map.get(question, "question") || Map.get(question, :question)}
                    </p>
                    <p
                      :if={Map.get(question, "node_id") || Map.get(question, :node_id)}
                      class="mt-1 text-xs text-base-content/45"
                    >
                      node {Map.get(question, "node_id") || Map.get(question, :node_id)}
                    </p>
                  </div>
                </div>
              </div>

              <div :if={@highlights != []} id="highlights-section">
                <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/50">
                  Highlights
                </h2>
                <div class="mt-3 space-y-2">
                  <div
                    :for={highlight <- @highlights}
                    class="rounded-2xl border border-base-content/10 bg-base-100 p-3"
                  >
                    <p class="text-sm font-medium leading-6 text-base-content/75">
                      “{Map.get(highlight, "text") || Map.get(highlight, :text)}”
                    </p>
                    <p
                      :if={Map.get(highlight, "note") || Map.get(highlight, :note)}
                      class="mt-1 text-xs leading-5 text-base-content/55"
                    >
                      {Map.get(highlight, "note") || Map.get(highlight, :note)}
                    </p>
                  </div>
                </div>
              </div>

              <div id="key-nodes-section">
                <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/50">
                  Key nodes
                </h2>
                <div class="mt-3 space-y-2">
                  <div
                    :for={node <- @key_nodes}
                    class="rounded-2xl border border-base-content/10 bg-base-100 p-3"
                  >
                    <div class="flex items-center justify-between gap-3">
                      <p class="text-sm font-semibold text-base-content">
                        {Map.get(node, "title")}
                      </p>
                      <span class="rounded-full bg-base-200 px-2 py-0.5 text-[0.68rem] font-medium uppercase tracking-wide text-base-content/50">
                        {Map.get(node, "class")}
                      </span>
                    </div>
                    <p class="mt-1 text-xs leading-5 text-base-content/55">
                      {Map.get(node, "excerpt")}
                    </p>
                  </div>
                </div>
              </div>
            </aside>

            <section
              id="asset-gallery-panel"
              class="space-y-5 rounded-[2rem] border border-base-content/10 bg-base-100/80 p-5 shadow-xl shadow-base-content/5 backdrop-blur md:p-6"
            >
              <div>
                <p class="text-xs font-semibold uppercase tracking-[0.2em] text-orange-600 dark:text-orange-300">
                  Share assets
                </p>
                <h2 class="mt-2 text-xl font-semibold text-base-content">
                  Choose the visual context
                </h2>
                <p class="mt-1 text-sm text-base-content/60">
                  RationalGrid now returns source content only. Generated cards and image exports will be produced here.
                </p>
              </div>

              <div class="grid grid-cols-2 gap-2">
                <button
                  id="show-all-drafts-button"
                  type="button"
                  phx-click="select_asset"
                  phx-value-id="all"
                  class={asset_filter_class(@selected_asset_id == "all")}
                >
                  All drafts
                </button>
                <button
                  id="show-campaign-drafts-button"
                  type="button"
                  phx-click="select_asset"
                  phx-value-id="campaign"
                  class={asset_filter_class(@selected_asset_id == "campaign")}
                >
                  Campaign-level
                </button>
              </div>

              <div id="media-assets" phx-update="stream" class="space-y-4">
                <div
                  id="empty-media-assets"
                  class="hidden rounded-3xl border border-dashed border-base-content/20 bg-base-200/40 p-5 text-sm text-base-content/60 only:block"
                >
                  No generated assets yet. This app now owns share-card/image generation from the grid content payload.
                </div>

                <article
                  :for={{id, asset} <- @streams.media_assets}
                  id={id}
                  class={asset_card_class(@selected_asset_id == Integer.to_string(asset.id))}
                >
                  <button
                    id={"select-asset-#{asset.id}"}
                    type="button"
                    phx-click="select_asset"
                    phx-value-id={asset.id}
                    class="block w-full text-left"
                  >
                    <img
                      src={asset.url}
                      alt={asset.title}
                      loading="lazy"
                      class="aspect-[1.91/1] w-full rounded-2xl border border-base-content/10 bg-base-200 object-contain"
                    />
                  </button>
                  <div class="mt-3 text-left">
                    <div class="flex items-start justify-between gap-3">
                      <div>
                        <p class="text-sm font-semibold text-base-content">{asset.title}</p>
                        <p class="text-xs text-base-content/50">{asset.kind}</p>
                      </div>
                      <span
                        :if={asset.highlight_id}
                        class="rounded-full bg-base-200 px-2 py-1 text-xs text-base-content/60"
                      >
                        #{asset.highlight_id}
                      </span>
                    </div>
                    <p :if={asset.text} class="mt-2 text-sm leading-5 text-base-content/65">
                      “{asset.text}”
                    </p>
                    <div class="mt-3 flex flex-wrap gap-1.5">
                      <span
                        :for={platform <- asset.recommended_platforms}
                        class="rounded-full bg-base-200 px-2 py-0.5 text-[0.68rem] font-medium uppercase tracking-wide text-base-content/55"
                      >
                        {platform}
                      </span>
                    </div>
                    <div class="mt-3 flex gap-2">
                      <a
                        href={asset.url}
                        target="_blank"
                        rel="noopener noreferrer"
                        class="inline-flex items-center rounded-full bg-base-content px-3 py-1.5 text-xs font-semibold text-base-100 transition hover:-translate-y-0.5"
                      >
                        Open asset
                      </a>
                      <button
                        id={"copy-asset-url-#{asset.id}"}
                        type="button"
                        phx-hook="CopyToClipboard"
                        phx-update="ignore"
                        data-copy-text={asset.url}
                        class="inline-flex items-center rounded-full border border-base-content/15 px-3 py-1.5 text-xs font-semibold text-base-content/70 transition hover:-translate-y-0.5 hover:bg-base-200"
                      >
                        Copy URL
                      </button>
                    </div>
                  </div>
                </article>
              </div>
            </section>

            <section
              id="draft-composer-panel"
              class="space-y-5 rounded-[2rem] border border-base-content/10 bg-base-100/80 p-5 shadow-xl shadow-base-content/5 backdrop-blur md:p-6"
            >
              <div>
                <p class="text-xs font-semibold uppercase tracking-[0.2em] text-orange-600 dark:text-orange-300">
                  Post drafts
                </p>
                <h2 class="mt-2 text-xl font-semibold text-base-content">
                  Edit and copy platform-ready copy
                </h2>
                <p class="mt-1 text-sm text-base-content/60">
                  Deterministic templates only. Any edit is saved when the textarea loses focus.
                </p>
              </div>

              <div id="platform-tabs" class="grid grid-cols-2 gap-2 sm:grid-cols-5">
                <button
                  :for={platform <- @platforms}
                  id={"platform-tab-#{platform.id}"}
                  type="button"
                  phx-click="select_platform"
                  phx-value-platform={platform.id}
                  class={platform_tab_class(@selected_platform == platform.id)}
                >
                  <span class="block text-sm font-semibold">{platform.label}</span>
                  <span :if={platform.max_chars} class="block text-[0.68rem] text-current/60">
                    {platform.max_chars} chars
                  </span>
                  <span :if={is_nil(platform.max_chars)} class="block text-[0.68rem] text-current/60">
                    long-form
                  </span>
                </button>
              </div>

              <div
                :if={@selected_asset}
                class="rounded-3xl border border-orange-500/20 bg-orange-500/10 p-4 text-sm text-orange-900 dark:text-orange-100"
              >
                Drafts filtered to <span class="font-semibold">{@selected_asset.title}</span>.
              </div>

              <div id="post-drafts" phx-update="stream" class="space-y-4">
                <div
                  id="empty-post-drafts"
                  class="hidden rounded-3xl border border-dashed border-base-content/20 bg-base-200/40 p-5 text-sm text-base-content/60 only:block"
                >
                  No drafts match the current filters.
                </div>

                <article
                  :for={{id, item} <- @streams.post_drafts}
                  id={id}
                  class="rounded-3xl border border-base-content/10 bg-base-100 p-4 shadow-lg shadow-base-content/5"
                >
                  <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                    <div>
                      <div class="flex flex-wrap gap-2">
                        <span class="rounded-full bg-base-content px-2.5 py-1 text-xs font-semibold text-base-100">
                          {Platforms.label(item.draft.platform)}
                        </span>
                        <span class="rounded-full bg-base-200 px-2.5 py-1 text-xs font-semibold text-base-content/65">
                          {Templates.angle_label(item.draft.angle)}
                        </span>
                      </div>
                      <p class="mt-2 text-xs text-base-content/50">
                        {item.asset_title}
                      </p>
                    </div>
                    <p class={character_count_class(item.character_over_limit)}>
                      {item.character_count}<span :if={item.character_limit}>/{item.character_limit}</span>
                    </p>
                  </div>

                  <.form
                    for={item.form}
                    id={"draft-form-#{item.id}"}
                    phx-change="save_draft"
                    phx-value-id={item.id}
                    class="mt-4"
                  >
                    <.input
                      id={"post-draft-body-#{item.id}"}
                      field={item.form[:body]}
                      type="textarea"
                      label="Draft copy"
                      rows="8"
                      phx-debounce="blur"
                    />
                  </.form>

                  <div class="mt-3 flex flex-wrap items-center justify-between gap-3">
                    <p class="text-xs text-base-content/50">
                      Status:
                      <span class="font-medium uppercase tracking-wide">{item.draft.status}</span>
                    </p>
                    <button
                      id={"copy-draft-#{item.id}"}
                      type="button"
                      phx-hook="CopyToClipboard"
                      phx-update="ignore"
                      data-copy-text={item.draft.body}
                      data-draft-id={item.id}
                      class="inline-flex items-center rounded-2xl bg-base-content px-4 py-2 text-sm font-semibold text-base-100 shadow-lg shadow-base-content/10 transition hover:-translate-y-0.5 hover:shadow-xl"
                    >
                      Copy text
                    </button>
                  </div>
                </article>
              </div>
            </section>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp list_drafts(campaign, selected_platform, selected_asset_id) do
    Campaigns.list_post_drafts(campaign,
      platform: selected_platform,
      media_asset_id: selected_asset_id
    )
  end

  defp refresh_drafts(socket) do
    drafts =
      list_drafts(
        socket.assigns.campaign,
        socket.assigns.selected_platform,
        socket.assigns.selected_asset_id
      )

    stream(socket, :post_drafts, draft_items(drafts), reset: true)
  end

  defp selected_asset("all"), do: nil
  defp selected_asset("campaign"), do: nil

  defp selected_asset(asset_id) do
    Campaigns.get_media_asset!(asset_id)
  end

  defp draft_items(drafts), do: Enum.map(drafts, &draft_item/1)

  defp draft_item(%PostDraft{} = draft) do
    character_count = draft.body |> to_string() |> String.length()
    character_limit = Platforms.max_chars(draft.platform)

    %{
      id: draft.id,
      draft: draft,
      form: to_form(%{"body" => draft.body}, as: :post_draft),
      asset_title: asset_title(draft),
      character_count: character_count,
      character_limit: character_limit,
      character_over_limit: is_integer(character_limit) and character_count > character_limit
    }
  end

  defp asset_title(%PostDraft{media_asset: %MediaAsset{} = asset}), do: asset.title
  defp asset_title(_draft), do: "Campaign-level draft"

  defp asset_filter_class(active?) do
    [
      "rounded-2xl px-3 py-2 text-sm font-semibold transition duration-200 hover:-translate-y-0.5",
      if(active?,
        do: "bg-base-content text-base-100 shadow-lg shadow-base-content/10",
        else: "border border-base-content/10 bg-base-100 text-base-content/65 hover:bg-base-200"
      )
    ]
  end

  defp asset_card_class(active?) do
    [
      "w-full rounded-3xl border p-3 text-left transition duration-200 hover:-translate-y-0.5 hover:shadow-xl",
      if(active?,
        do: "border-orange-500/50 bg-orange-500/10 shadow-xl shadow-orange-950/10",
        else: "border-base-content/10 bg-base-100 hover:border-base-content/20"
      )
    ]
  end

  defp platform_tab_class(active?) do
    [
      "rounded-2xl px-3 py-3 text-center transition duration-200 hover:-translate-y-0.5",
      if(active?,
        do: "bg-base-content text-base-100 shadow-lg shadow-base-content/10",
        else: "border border-base-content/10 bg-base-100 text-base-content/65 hover:bg-base-200"
      )
    ]
  end

  defp character_count_class(true) do
    "rounded-full bg-red-500/10 px-3 py-1 text-xs font-semibold text-red-700 dark:text-red-200"
  end

  defp character_count_class(false) do
    "rounded-full bg-base-200 px-3 py-1 text-xs font-semibold text-base-content/55"
  end
end
