defmodule GridMediaManagerWeb.ArticleStudioLive do
  use GridMediaManagerWeb, :live_view

  alias GridMediaManager.Articles

  @example "https://rationalgrid.ai/g/borges-and-infinity-9d9c28?node=1"
  @brief "Follow the highlighted passages into Kafka, idealism, and Cantor. Preserve the original wording, qualifications, and opposing interpretations."

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Article studio", draft: nil, generating?: false, error: nil)
     |> assign(:form, article_form(%{"source" => @example, "brief" => @brief}))
     |> stream(:drafts, Articles.list_drafts())
     |> stream(:directions, [])
     |> stream(:highlights, [])
     |> stream(:sections, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    case params do
      %{"id" => id} ->
        case Articles.get_draft(id) do
          nil ->
            {:noreply,
             socket
             |> put_flash(:error, "That article draft was not found.")
             |> push_navigate(to: ~p"/articles")}

          draft ->
            {:noreply, load_draft(socket, draft)}
        end

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("generate", _params, %{assigns: %{generating?: true}} = socket),
    do: {:noreply, socket}

  def handle_event("generate", %{"article" => params}, socket) do
    form = article_form(params, :validate)

    if form.source.valid? do
      source = Ecto.Changeset.get_field(form.source, :source)
      brief = Ecto.Changeset.get_field(form.source, :brief) || ""

      {:noreply,
       socket
       |> assign(form: form, generating?: true, error: nil)
       |> start_async(:generate_article, fn -> Articles.generate(source, brief) end)}
    else
      {:noreply, assign(socket, :form, form)}
    end
  end

  @impl true
  def handle_async(:generate_article, {:ok, {:ok, draft}}, socket) do
    {:noreply,
     socket
     |> assign(:generating?, false)
     |> stream_insert(:drafts, draft, at: 0)
     |> put_flash(:info, "Article saved. Follow the map to explore each direction.")
     |> push_navigate(to: ~p"/articles/#{draft.id}")}
  end

  def handle_async(:generate_article, {:ok, {:error, reason}}, socket) do
    {:noreply, assign(socket, generating?: false, error: error_message(reason))}
  end

  def handle_async(:generate_article, {:exit, _reason}, socket) do
    {:noreply, assign(socket, generating?: false, error: error_message(:generation_failed))}
  end

  defp load_draft(socket, draft) do
    source_passages? = draft.content["mode"] == "source_passages"

    used_ids =
      draft.content["sections"]
      |> Enum.flat_map(&(&1["passages"] || []))
      |> Enum.map(& &1["id"])
      |> MapSet.new()

    highlights =
      Enum.map(draft.graph["highlights"] || [], fn highlight ->
        Map.merge(highlight, %{
          id: highlight["id"],
          used?: Enum.any?(highlight["passage_ids"], &MapSet.member?(used_ids, &1))
        })
      end)

    sections =
      Articles.reading_sections(draft)
      |> Enum.with_index(1)
      |> Enum.map(fn {section, index} ->
        Map.merge(section, %{
          id: index,
          nodes:
            Enum.map(section["node_ids"], fn id ->
              Enum.find(draft.graph["nodes"], &(&1["id"] == id))
            end)
        })
      end)

    socket
    |> assign(
      draft: draft,
      page_title: draft.content["title"],
      markdown: Articles.markdown(draft),
      article_html: GridMediaManager.Articles.HTML.body(draft),
      words: Articles.word_count(draft),
      direction_count: length(sections),
      source_passages?: source_passages?,
      highlight_count: length(highlights),
      used_highlight_count: Enum.count(highlights, & &1.used?),
      form: article_form(%{"source" => draft.source_url, "brief" => draft.brief || ""})
    )
    |> stream(:directions, sections, reset: true)
    |> stream(:sections, sections, reset: true)
    |> stream(:highlights, highlights, reset: true)
  end

  defp article_form(params, action \\ nil) do
    {%{}, %{source: :string, brief: :string}}
    |> Ecto.Changeset.cast(params, [:source, :brief])
    |> Ecto.Changeset.validate_required([:source])
    |> Ecto.Changeset.validate_length(:source, max: 2048)
    |> Ecto.Changeset.validate_length(:brief, max: 2000)
    |> Map.put(:action, action)
    |> to_form(as: :article)
  end

  defp paragraphs(text), do: String.split(text, ~r/\n\s*\n/, trim: true)

  defp node_label(node),
    do:
      node["content"]
      |> String.split("\n")
      |> hd()
      |> String.trim_leading("#")
      |> String.trim()
      |> String.slice(0, 140)

  defp error_message(:blank), do: "Enter a grid URL or slug."
  defp error_message(:invalid), do: "Enter a valid RationalGrid URL or slug."
  defp error_message(:untrusted_origin), do: "Use a RationalGrid URL or slug."
  defp error_message(:empty_graph), do: "This grid has no readable nodes yet. Try another grid."

  defp error_message(:graph_too_large),
    do: "This first version supports up to 100 nodes and 150,000 characters. Try a smaller grid."

  defp error_message(:openai_not_configured),
    do: "Add OPENAI_API_KEY to enable article generation."

  defp error_message(:invalid_routes),
    do: "The draft included a route that does not exist in the grid. Please generate again."

  defp error_message(:invalid_selection),
    do: "The editor selected a passage outside its source route. Please assemble again."

  defp error_message({:http_error, status}),
    do: "The grid could not be loaded (HTTP #{status}). Check the URL and promotion API access."

  defp error_message(_),
    do:
      "We could not finish this draft. Please try again. Your saved articles are still available."

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto max-w-7xl px-4 py-10 sm:px-6 lg:px-8">
        <div class="mb-8 flex flex-wrap items-end justify-between gap-4">
          <div>
            <p class="mb-3 flex items-center gap-2 text-xs font-bold uppercase tracking-[0.22em] text-orange-600 dark:text-orange-300">
              <.icon name="hero-document-text" class="size-4" /> From graph to story
            </p>
            <h1 class="font-serif text-4xl tracking-tight sm:text-5xl">
              Article studio<span class="text-orange-500">.</span>
            </h1>
            <p class="mt-3 max-w-2xl text-base-content/60">
              The grid’s own words. Its highlights. A reading path through the ideas.
            </p>
          </div>
          <span class="rounded-full border border-base-content/15 px-3 py-1 text-xs text-base-content/60">
            Experimental · saved drafts
          </span>
        </div>

        <details
          id="article-controls"
          class="mb-8 rounded-2xl border border-base-content/10 bg-base-200/50"
          open={is_nil(@draft)}
        >
          <summary class="cursor-pointer px-6 py-4 text-sm font-semibold">
            {if @draft, do: "Select passages · assemble another version", else: "Start with a grid"}
          </summary>
          <.form
            for={@form}
            id="article-form"
            phx-submit="generate"
            class="grid gap-5 border-t border-base-content/10 p-6 lg:grid-cols-[1fr_1.2fr_auto] lg:items-end"
          >
            <.input
              field={@form[:source]}
              label="RationalGrid URL or slug"
              placeholder="https://rationalgrid.ai/g/…"
              disabled={@generating?}
            />
            <.input
              field={@form[:brief]}
              type="textarea"
              rows="3"
              label="Selection guidance"
              placeholder="Which existing threads should the selection follow?"
              disabled={@generating?}
            />
            <button
              id="generate-article"
              type="submit"
              disabled={@generating?}
              class="mb-2 inline-flex items-center justify-center gap-2 rounded-xl bg-orange-600 px-5 py-3 text-sm font-bold text-white transition hover:bg-orange-700 disabled:cursor-wait disabled:opacity-60"
            >
              <.icon
                name={if @generating?, do: "hero-arrow-path", else: "hero-sparkles"}
                class={if @generating?, do: "size-4 animate-spin", else: "size-4"}
              />
              {if @generating?, do: "Selecting passages…", else: "Assemble article"}
            </button>
          </.form>
        </details>

        <div
          :if={@error}
          id="article-error"
          role="alert"
          class="mb-6 rounded-xl border border-red-500/20 bg-red-500/10 p-4 text-sm text-red-700 dark:text-red-200"
        >
          {@error}
        </div>
        <div
          :if={@generating?}
          id="article-progress"
          role="status"
          class="mb-8 rounded-2xl border border-orange-500/20 bg-orange-500/5 p-6"
        >
          <p class="font-semibold">
            Reading highlights, following branches, selecting original passages.
          </p>
          <p class="mt-2 text-sm text-base-content/60">
            This usually takes a minute or two. Keep this page open; the finished draft will be saved automatically.
          </p>
        </div>

        <div
          :if={is_nil(@draft) and not @generating?}
          id="article-empty"
          class="mb-10 grid gap-8 rounded-3xl border border-base-content/10 p-8 sm:p-12 lg:grid-cols-[1.3fr_1fr]"
        >
          <div>
            <p class="text-xs font-bold uppercase tracking-widest text-base-content/45">
              First exploration
            </p>
            <h2 class="mt-4 max-w-lg font-serif text-4xl leading-tight">
              Borges opens a door.<br /><span class="text-base-content/50">Where does it lead?</span>
            </h2>
            <p class="mt-5 max-w-lg leading-7 text-base-content/65">
              Follow the grid’s highlights into idealism, mathematics, and Kafka. Assemble its original passages into a reading path, with links back to each node.
            </p>
          </div>
          <div class="border-l border-orange-500/30 pl-6">
            <p class="mb-5 font-serif text-xl">Borges & infinity</p>
            <p class="mb-4 text-sm">
              <span class="mr-3 text-orange-500">↳</span>
              Idealism <span class="text-base-content/45">· what is real?</span>
            </p>
            <p class="mb-4 text-sm">
              <span class="mr-3 text-orange-500">↳</span>
              Formal structures <span class="text-base-content/45">· an objection</span>
            </p>
            <p class="mb-4 text-sm">
              <span class="mr-3 text-orange-500">↳</span>
              Cantor <span class="text-base-content/45">· sizes of infinity</span>
            </p>
            <p class="text-sm">
              <span class="mr-3 text-orange-500">↳</span>
              Kafka <span class="text-base-content/45">· another labyrinth</span>
            </p>
          </div>
        </div>

        <div :if={@draft} id="article-workspace">
          <section
            id="substack-export"
            class="mb-6 rounded-2xl border border-orange-500/25 bg-orange-500/5 p-5 sm:p-6"
          >
            <div class="flex flex-wrap items-start justify-between gap-5">
              <div>
                <h2 class="text-lg font-semibold">Ready for Substack</h2>
                <p class="mt-1 max-w-xl text-sm leading-6 text-base-content/65">
                  Copy the title into the title field, then copy the formatted article and paste into the post body with ⌘V or Ctrl+V.
                </p>
                <p class="mt-1 text-xs text-base-content/50">
                  Headings, emphasis, lists, quotes, and source links are included. Use normal paste to keep formatting.
                </p>
              </div>
              <button
                id="copy-article-title"
                phx-hook="CopyToClipboard"
                phx-update="ignore"
                data-copy-text={@draft.content["title"]}
                class="rounded-lg border border-base-content/15 bg-base-100 px-4 py-2 text-sm font-semibold transition hover:bg-base-200"
              >
                Copy title
              </button>
            </div>
            <div
              id="copy-article-rich"
              phx-hook="CopyArticleHTML"
              phx-update="ignore"
              data-source="article-copy-content"
              class="mt-4"
            >
              <button
                id="copy-for-substack"
                type="button"
                class="rounded-xl bg-orange-600 px-5 py-3 text-sm font-bold text-white transition hover:bg-orange-700 disabled:opacity-60"
              >
                Copy for Substack
              </button>
              <p
                id="article-copy-status"
                role="status"
                aria-live="polite"
                class="mt-2 text-sm text-base-content/65"
              >
              </p>
            </div>
            <div class="mt-3 flex flex-wrap gap-4 text-sm font-semibold">
              <a
                id="open-article-document"
                href={~p"/articles/#{@draft.id}/document"}
                target="_blank"
                rel="noopener noreferrer"
                class="hover:text-orange-600"
              >
                Open formatted document <.icon name="hero-arrow-up-right" class="size-3.5" />
              </a>
              <a
                id="download-article-html"
                href={~p"/articles/#{@draft.id}/download?format=html"}
                class="hover:text-orange-600"
              >
                Download HTML
              </a>
            </div>
            <template id="article-copy-content">{Phoenix.HTML.raw(@article_html)}</template>
          </section>
          <div
            :if={not @source_passages?}
            id="legacy-article-notice"
            class="mb-6 rounded-xl border border-amber-500/25 bg-amber-500/5 p-4 text-sm"
          >
            This earlier draft uses rewritten prose. Assemble a new version to use original passages and the grid’s highlights.
          </div>
          <div
            :if={@source_passages?}
            id="article-source-method"
            class="mb-6 rounded-xl border border-orange-500/20 bg-orange-500/5 p-4 text-sm"
          >
            Original passages, selected and ordered from the grid. Full source routes and highlights are available in the map.
            <span class="mt-1 block text-base-content/60">
              {@used_highlight_count} of {@highlight_count} grid highlights appear in this selection.
            </span>
          </div>
          <div class="mb-8 flex flex-wrap items-center justify-between gap-4 border-y border-base-content/10 py-4">
            <div class="text-xs text-base-content/55">
              Saved draft · {length(@draft.graph["nodes"])} source nodes · {@direction_count} directions · {ceil(
                @words / 220
              )} min read
            </div>
            <div class="flex flex-wrap items-center gap-3">
              <a
                id="article-source"
                href={@draft.source_url}
                target="_blank"
                rel="noopener noreferrer"
                class="text-sm font-semibold hover:text-orange-600"
              >
                Open grid <.icon name="hero-arrow-up-right" class="size-3.5" />
              </a>
            </div>
          </div>

          <div class="grid items-start gap-10 lg:grid-cols-[minmax(0,1fr)_320px] xl:gap-16">
            <article id="article-preview" class="min-w-0 max-w-3xl pb-10">
              <p class="mb-4 text-xs font-semibold uppercase tracking-[0.2em] text-orange-600 dark:text-orange-300">
                A field guide to the grid
              </p>
              <h2 class="font-serif text-4xl leading-[1.12] tracking-tight sm:text-5xl">
                {@draft.content["title"]}
              </h2>
              <p class="mt-5 font-serif text-xl leading-8 text-base-content/60">
                {@draft.content["subtitle"]}
              </p>
              <p class="mt-5 text-xs text-base-content/45">
                {if @source_passages?, do: "Original grid passages", else: "Earlier rewritten draft"} · Based on “{@draft.source_title}” · {Calendar.strftime(
                  @draft.inserted_at,
                  "%d %B %Y"
                )}
              </p>
              <div class="my-8 h-px w-16 bg-orange-500" />
              <p
                :for={paragraph <- paragraphs(@draft.content["introduction"])}
                class="mb-5 font-serif text-lg leading-8"
              >
                {paragraph}
              </p>
              <div id="article-sections" phx-update="stream">
                <section
                  :for={{id, section} <- @streams.sections}
                  id={id}
                  class="scroll-mt-28 border-t border-base-content/10 pt-8 mt-9"
                >
                  <p class="mb-3 text-xs font-bold uppercase tracking-widest text-orange-600 dark:text-orange-300">
                    {String.pad_leading(to_string(section.id), 2, "0")} / {section["relationship"]}
                  </p>
                  <h3 class="mb-5 font-serif text-3xl leading-tight">{section["title"]}</h3>
                  <%= if @source_passages? do %>
                    <div
                      :for={passage <- section.reading_passages}
                      data-passage-id={passage["id"]}
                      class="mb-5"
                    >
                      <.source_passage passage={passage} />
                    </div>
                  <% else %>
                    <p
                      :for={paragraph <- paragraphs(section["body"])}
                      class="mb-5 font-serif text-lg leading-8 text-base-content/90"
                    >
                      {paragraph}
                    </p>
                  <% end %>
                  <div
                    :if={section.reading_links != []}
                    class="mt-6 flex flex-wrap items-center gap-2 text-sm text-base-content/55"
                  >
                    <a
                      :for={link <- section.reading_links}
                      href={Articles.node_url(@draft, link.id)}
                      target="_blank"
                      rel="noopener noreferrer"
                      class="underline decoration-base-content/20 underline-offset-4 transition hover:text-orange-600"
                    >
                      {link.label} <.icon name="hero-arrow-up-right" class="size-3" />
                    </a>
                  </div>
                </section>
              </div>
              <section :if={not @source_passages?} class="mt-10 border-t border-base-content/10 pt-8">
                <h3 class="mb-5 font-serif text-3xl">Where the paths meet</h3>
                <p
                  :for={paragraph <- paragraphs(@draft.content["conclusion"])}
                  class="mb-5 font-serif text-lg leading-8"
                >
                  {paragraph}
                </p>
              </section>
              <details id="article-export" class="mt-8 rounded-xl border border-base-content/10 p-4">
                <summary class="cursor-pointer text-sm font-semibold">
                  Other formats · Markdown
                </summary>
                <div class="mt-3 flex gap-4 text-sm font-semibold">
                  <button
                    id="copy-article"
                    phx-hook="CopyToClipboard"
                    phx-update="ignore"
                    data-copy-source="#article-markdown"
                    class="hover:text-orange-600"
                  >
                    Copy Markdown
                  </button>
                  <a
                    id="download-article"
                    href={~p"/articles/#{@draft.id}/download"}
                    class="hover:text-orange-600"
                  >
                    Download .md
                  </a>
                </div>
                <.input
                  type="textarea"
                  id="article-markdown"
                  name="article_markdown"
                  value={@markdown}
                  readonly
                  rows="12"
                  class="mt-4 w-full rounded-lg border border-base-content/20 bg-base-100 p-3 font-mono text-xs leading-6"
                />
              </details>
            </article>

            <aside
              id="article-map"
              class="rounded-2xl border border-base-content/10 bg-base-200/40 p-5 lg:sticky lg:top-24 lg:max-h-[calc(100vh-7rem)] lg:overflow-y-auto"
            >
              <div class="flex items-center justify-between">
                <h2 class="font-semibold">Map of the ideas</h2>
                <.icon name="hero-share" class="size-4 text-orange-500" />
              </div>
              <p class="mb-6 mt-2 text-xs leading-5 text-base-content/55">
                Jump into the essay, or follow a numbered node back to the grid. Routes follow the original connections.
              </p>
              <div id="article-directions" phx-update="stream" class="space-y-6">
                <div
                  :for={{id, section} <- @streams.directions}
                  id={id}
                  class="border-l-2 border-orange-500/35 pl-4"
                >
                  <p class="mb-1 text-[10px] font-bold uppercase tracking-widest text-base-content/45">
                    {section["relationship"]}
                  </p>
                  <a
                    href={"#sections-#{section.id}"}
                    class="font-serif text-lg leading-6 transition hover:text-orange-600"
                  >
                    {section["title"]}
                  </a>
                  <p class="mt-2 text-xs leading-5 text-base-content/60">{section["summary"]}</p>
                  <div class="mt-3 flex flex-wrap items-center gap-1">
                    <%= for {node, index} <- Enum.with_index(section.nodes) do %>
                      <span :if={index > 0} aria-hidden="true" class="text-base-content/30">→</span>
                      <a
                        href={Articles.node_url(@draft, node["id"])}
                        title={node_label(node)}
                        aria-label={"Node #{node["id"]}: #{node_label(node)}"}
                        target="_blank"
                        rel="noopener noreferrer"
                        class="grid size-7 place-items-center rounded-full border border-base-content/15 bg-base-100 text-xs transition hover:border-orange-500 hover:text-orange-600"
                      >
                        {node["id"]}
                      </a>
                    <% end %>
                  </div>
                  <details class="mt-3">
                    <summary class="cursor-pointer text-xs text-base-content/50 hover:text-orange-600">
                      Source notes
                    </summary>
                    <p
                      :for={node <- section.nodes}
                      class="mt-2 text-xs leading-5 text-base-content/60"
                    >
                      <span class="font-semibold">{node["id"]} · {node["class"]}</span>
                      <br />{node_label(node)}
                    </p>
                  </details>
                </div>
              </div>
              <details
                :if={@source_passages?}
                id="article-highlights"
                class="mt-6 border-t border-base-content/10 pt-4"
                open
              >
                <summary class="cursor-pointer text-sm font-semibold">
                  Grid highlights · {@highlight_count}
                </summary>
                <p
                  :if={@highlight_count == 0}
                  id="article-no-highlights"
                  class="mt-3 text-xs leading-5 text-base-content/60"
                >
                  No highlights were returned. The selection follows the node headings, questions, and branches.
                </p>
                <div id="article-highlight-list" phx-update="stream">
                  <div
                    :for={{id, highlight} <- @streams.highlights}
                    id={id}
                    class="mt-4 border-l-2 border-amber-400/60 pl-3 text-xs leading-5"
                  >
                    <p>{highlight["text"]}</p>
                    <p :if={highlight["note"]} class="mt-2 text-base-content/60">
                      Highlight note: {highlight["note"]}
                    </p>
                    <a
                      href={Articles.node_url(@draft, highlight["node_id"])}
                      target="_blank"
                      rel="noopener noreferrer"
                      class="mt-1 inline-block font-semibold hover:text-orange-600"
                    >
                      Node {highlight["node_id"]}
                    </a>
                    <p class="text-base-content/50">
                      <%= cond do %>
                        <% highlight.used? -> %>
                          Included in this selection
                        <% highlight["passage_ids"] == [] -> %>
                          Not matched to the current node text
                        <% true -> %>
                          Available in the source
                      <% end %>
                    </p>
                  </div>
                </div>
              </details>
            </aside>
          </div>
        </div>

        <section class="mt-10 border-t border-base-content/10 pt-6">
          <h2 class="mb-4 text-sm font-semibold">Recent article drafts</h2>
          <div
            id="article-drafts"
            phx-update="stream"
            class="grid gap-3 sm:grid-cols-2 lg:grid-cols-3"
          >
            <p id="no-article-drafts" class="hidden text-sm text-base-content/50 only:block">
              Your first article will appear here once generated.
            </p>
            <.link
              :for={{id, draft} <- @streams.drafts}
              id={id}
              navigate={~p"/articles/#{draft.id}"}
              class="rounded-xl border border-base-content/10 p-4 transition hover:border-orange-500/50 hover:bg-base-200"
            >
              <span class="block font-serif text-lg">{draft.content["title"]}</span>
              <span class="mt-2 block text-xs text-base-content/50">
                {draft.source_title} · {Calendar.strftime(draft.inserted_at, "%d %b · %H:%M")}
              </span>
            </.link>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end

  attr :passage, :map, required: true

  defp source_passage(assigns) do
    assigns = assign(assigns, :html, GridMediaManager.Articles.HTML.passage(assigns.passage, 4))

    ~H"""
    <div class="article-prose font-serif text-lg leading-8 text-base-content/90">
      {Phoenix.HTML.raw(@html)}
    </div>
    """
  end
end
