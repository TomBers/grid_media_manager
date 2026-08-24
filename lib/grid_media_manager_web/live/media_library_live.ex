defmodule GridMediaManagerWeb.MediaLibraryLive do
  use GridMediaManagerWeb, :live_view

  alias GridMediaManager.Campaigns
  alias GridMediaManager.Campaigns.MediaAsset
  alias GridMediaManager.Promotion.ArtifactStore

  @impl true
  def mount(_params, _session, socket) do
    assets = Campaigns.list_uploaded_media_assets()

    {:ok,
     socket
     |> assign(:page_title, "Uploaded media inspector")
     |> assign(:asset_count, length(assets))
     |> assign(:frame_count, Enum.sum(Enum.map(assets, &uploaded_frame_count/1)))
     |> assign(:video_count, Enum.count(assets, &(&1.mime_type == "video/mp4")))
     |> stream(:uploaded_assets, assets)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <main
        id="media-library"
        class="min-h-[calc(100vh-5rem)] bg-base-200/35 px-4 py-8 sm:px-6 lg:px-8"
      >
        <div class="mx-auto max-w-7xl">
          <header class="overflow-hidden rounded-[2rem] border border-base-content/10 bg-base-100 shadow-xl shadow-base-content/5">
            <div class="grid gap-8 p-6 sm:p-8 lg:grid-cols-[1fr_auto] lg:items-end">
              <div class="max-w-3xl">
                <p class="flex items-center gap-2 text-xs font-bold uppercase tracking-[0.2em] text-indigo-600 dark:text-indigo-300">
                  <.icon name="hero-magnifying-glass" class="size-4" /> Diagnostic archive
                </p>
                <h1 class="mt-3 text-3xl font-semibold tracking-tight text-base-content sm:text-5xl">
                  Uploaded media inspector
                </h1>
                <p class="mt-4 max-w-2xl text-sm leading-6 text-base-content/60 sm:text-base">
                  Review the exact canvas frames saved for every generated asset, including frames produced by older renderer versions.
                </p>
              </div>

              <dl id="media-library-summary" class="grid grid-cols-3 gap-2 text-center">
                <.metric label="Assets" value={@asset_count} />
                <.metric label="Frames" value={@frame_count} />
                <.metric label="Videos" value={@video_count} />
              </dl>
            </div>
          </header>

          <div id="uploaded-assets" phx-update="stream" class="mt-8 space-y-6">
            <section
              id="empty-media-library"
              class="hidden only:block rounded-[2rem] border border-dashed border-base-content/20 bg-base-100 px-6 py-16 text-center"
            >
              <span class="mx-auto grid size-14 place-items-center rounded-2xl bg-base-200 text-base-content/45">
                <.icon name="hero-photo" class="size-7" />
              </span>
              <h2 class="mt-4 text-lg font-semibold text-base-content">No uploaded frames yet</h2>
              <p class="mt-2 text-sm text-base-content/55">
                Frames appear here after an asset is saved in a campaign studio.
              </p>
            </section>

            <article
              :for={{dom_id, asset} <- @streams.uploaded_assets}
              id={dom_id}
              class="overflow-hidden rounded-[2rem] border border-base-content/10 bg-base-100 shadow-lg shadow-base-content/5"
            >
              <div class="flex flex-col gap-4 border-b border-base-content/10 p-5 sm:flex-row sm:items-start sm:justify-between sm:p-6">
                <div class="min-w-0">
                  <div class="flex flex-wrap items-center gap-2 text-xs font-bold uppercase tracking-[0.14em] text-base-content/45">
                    <span>{asset_kind(asset)}</span>
                    <span aria-hidden="true">·</span>
                    <span>{uploaded_frame_count(asset)} frames</span>
                    <span :if={video_duration(asset)} aria-hidden="true">·</span>
                    <span :if={video_duration(asset)}>{video_duration(asset)} seconds</span>
                  </div>
                  <h2 class="mt-2 text-xl font-semibold tracking-tight text-base-content">
                    {asset.title}
                  </h2>
                  <p class="mt-1 text-sm text-base-content/55">
                    {asset.campaign.title} · asset #{asset.id} · saved {Calendar.strftime(
                      asset.updated_at,
                      "%d %b %Y, %H:%M"
                    )}
                  </p>
                </div>

                <div class="flex shrink-0 flex-wrap gap-2">
                  <.link
                    id={"inspect-campaign-#{asset.id}"}
                    navigate={~p"/campaigns/#{asset.campaign_id}/studio"}
                    class="inline-flex items-center gap-2 rounded-full border border-base-content/15 px-4 py-2 text-sm font-semibold text-base-content/70 transition hover:border-base-content/30 hover:bg-base-200 hover:text-base-content"
                  >
                    Open studio <.icon name="hero-arrow-top-right-on-square" class="size-4" />
                  </.link>
                  <a
                    :if={published_url(asset)}
                    id={"open-upload-#{asset.id}"}
                    href={published_url(asset)}
                    target="_blank"
                    rel="noreferrer"
                    class="inline-flex items-center gap-2 rounded-full bg-base-content px-4 py-2 text-sm font-semibold text-base-100 transition hover:-translate-y-0.5 hover:opacity-85"
                  >
                    Uploaded file <.icon name="hero-arrow-up-right" class="size-4" />
                  </a>
                </div>
              </div>

              <div class="grid gap-4 p-5 sm:grid-cols-2 sm:p-6 lg:grid-cols-3 xl:grid-cols-4">
                <figure
                  :for={frame <- uploaded_frames(asset)}
                  id={"asset-#{asset.id}-frame-#{frame.index}"}
                  class="group overflow-hidden rounded-2xl border border-base-content/10 bg-base-200/50"
                >
                  <a
                    href={~p"/media-library/assets/#{asset.id}/frames/#{frame.index}"}
                    target="_blank"
                    class="block bg-slate-950"
                    aria-label={"Open frame #{frame.index} for #{asset.title}"}
                  >
                    <img
                      src={~p"/media-library/assets/#{asset.id}/frames/#{frame.index}"}
                      alt={"Frame #{frame.index} of #{asset.title}"}
                      loading="lazy"
                      class={[
                        "w-full object-contain transition duration-300 group-hover:scale-[1.015]",
                        if(asset.mime_type == "video/mp4", do: "aspect-[9/16]", else: "aspect-[4/5]")
                      ]}
                    />
                  </a>
                  <figcaption class="p-4">
                    <div class="flex items-center justify-between gap-3">
                      <span class="text-sm font-bold text-base-content">Frame {frame.index}</span>
                      <span class={[
                        "rounded-full px-2 py-1 text-[0.65rem] font-bold uppercase tracking-wide",
                        if(frame.current?,
                          do: "bg-emerald-500/10 text-emerald-700 dark:text-emerald-300",
                          else: "bg-amber-500/10 text-amber-700 dark:text-amber-300"
                        )
                      ]}>
                        Renderer {frame.renderer_version}
                      </span>
                    </div>
                    <p
                      :if={frame.summary != ""}
                      class="mt-2 line-clamp-3 text-xs leading-5 text-base-content/55"
                    >
                      {frame.summary}
                    </p>
                    <p class="mt-3 font-mono text-[0.65rem] text-base-content/40">
                      {format_bytes(frame.byte_size)} · {String.slice(frame.sha256, 0, 12)}
                    </p>
                  </figcaption>
                </figure>
              </div>
            </article>
          </div>
        </div>
      </main>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true

  defp metric(assigns) do
    ~H"""
    <div class="flex min-w-20 flex-col rounded-2xl border border-base-content/10 bg-base-200/60 px-3 py-3">
      <dt class="order-2 mt-0.5 text-[0.65rem] font-bold uppercase tracking-wider text-base-content/45">
        {@label}
      </dt>
      <dd class="order-1 text-2xl font-semibold tracking-tight text-base-content">{@value}</dd>
    </div>
    """
  end

  defp uploaded_frames(%MediaAsset{metadata: metadata} = asset) do
    slides = Map.get(metadata || %{}, "slides", [])

    (metadata || %{})
    |> Map.get("artifacts", %{})
    |> Enum.flat_map(fn {index, artifact} ->
      case Integer.parse(to_string(index)) do
        {index, ""} when is_map(artifact) ->
          [
            %{
              index: index,
              byte_size: Map.get(artifact, "byte_size", 0),
              sha256: Map.get(artifact, "sha256", "unknown"),
              renderer_version: Map.get(artifact, "renderer_version", "unknown"),
              current?:
                ArtifactStore.current_renderer_version?(
                  Map.get(artifact, "renderer_version", "unknown")
                ),
              summary: slides |> Enum.at(index - 1, %{}) |> slide_summary()
            }
          ]

        _invalid ->
          []
      end
    end)
    |> Enum.sort_by(& &1.index)
    |> Enum.filter(&(not is_nil(ArtifactStore.uploaded_artifact(asset, &1.index))))
  end

  defp uploaded_frame_count(%MediaAsset{} = asset), do: length(uploaded_frames(asset))

  defp slide_summary(slide) when is_map(slide) do
    [Map.get(slide, "title"), Map.get(slide, "body")]
    |> Enum.filter(&(is_binary(&1) and String.trim(&1) != ""))
    |> Enum.join(" — ")
    |> String.slice(0, 220)
  end

  defp slide_summary(_slide), do: ""

  defp asset_kind(%MediaAsset{mime_type: "video/mp4"}), do: "Video"
  defp asset_kind(%MediaAsset{kind: "curated_carousel"}), do: "Carousel"
  defp asset_kind(%MediaAsset{}), do: "Image"

  defp video_duration(%MediaAsset{mime_type: "video/mp4", metadata: metadata}) do
    case Map.get(metadata || %{}, "duration_seconds") do
      duration when is_number(duration) ->
        duration |> Kernel./(1) |> Float.round(1) |> to_string()

      duration when is_binary(duration) ->
        duration

      _missing ->
        nil
    end
  end

  defp video_duration(%MediaAsset{}), do: nil

  defp published_url(%MediaAsset{metadata: metadata}) do
    case Map.get(metadata || %{}, "published_url") do
      url when is_binary(url) and url != "" -> url
      _missing -> nil
    end
  end

  defp format_bytes(bytes) when is_integer(bytes) and bytes >= 1_000_000,
    do: "#{Float.round(bytes / 1_000_000, 1)} MB"

  defp format_bytes(bytes) when is_integer(bytes) and bytes >= 1_000,
    do: "#{Float.round(bytes / 1_000, 1)} KB"

  defp format_bytes(bytes) when is_integer(bytes), do: "#{bytes} B"
  defp format_bytes(_bytes), do: "Unknown size"
end
