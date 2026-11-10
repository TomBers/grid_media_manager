defmodule GridMediaManagerWeb.ExplorationLive do
  use GridMediaManagerWeb, :live_view
  alias GridMediaManager.RationalGrid.{Accounts, Exploration, Explorations}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Process.send_after(self(), :refresh, 3_000)

    {:ok,
     socket
     |> stream_configure(:nodes, dom_id: fn node -> "exploration-node-#{node["id"]}" end)
     |> assign(:form, to_form(Exploration.proposal_changeset(%Exploration{}, %{})))
     |> assign(:theme_form, to_form(%{"theme" => ""}, as: :recommendation))
     |> assign(:recommending?, false)
     |> assign(:selected, nil)
     |> assign(:outcome_count, 0)
     |> refresh()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, socket |> assign(:selected_id, params["id"]) |> refresh()}
  end

  @impl true
  def handle_event("propose", %{"exploration" => attrs}, socket) do
    evidence = %{feedback: GridMediaManager.Social.Performance.editorial_feedback()}

    case Explorations.propose(attrs, evidence) do
      {:ok, e} ->
        {:noreply, push_patch(socket, to: ~p"/explorations/#{e.id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, Explorations.error_message(reason))}
    end
  end

  def handle_event("recommend", %{"recommendation" => %{"theme" => theme}}, socket) do
    {:noreply,
     socket
     |> assign(:recommending?, true)
     |> start_async(:recommend, fn -> Explorations.recommend(theme) end)}
  end

  def handle_event("start", _, %{assigns: %{selected: e}} = socket) do
    Explorations.start(e.id)
    {:noreply, refresh(socket)}
  end

  def handle_event("retry", _, %{assigns: %{selected: e}} = socket) do
    Explorations.retry(e.id)
    {:noreply, refresh(socket)}
  end

  def handle_event("campaign", _, %{assigns: %{selected: e}} = socket) do
    case Explorations.create_campaign(e.id) do
      {:ok, campaign} ->
        {:noreply, push_navigate(socket, to: ~p"/campaigns/#{campaign.id}/studio")}

      _ ->
        {:noreply, put_flash(socket, :error, "The completed grid is not ready to import.")}
    end
  end

  @impl true
  def handle_async(:recommend, {:ok, {:ok, e}}, socket) do
    {:noreply,
     socket |> assign(:recommending?, false) |> push_patch(to: ~p"/explorations/#{e.id}")}
  end

  def handle_async(:recommend, _, socket) do
    {:noreply,
     socket
     |> assign(:recommending?, false)
     |> put_flash(
       :error,
       "Could not recommend a question. Check the editorial model configuration or enter your own proposal."
     )}
  end

  @impl true
  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, 3_000)
    {:noreply, refresh(socket)}
  end

  defp refresh(socket) do
    e = if socket.assigns[:selected_id], do: Explorations.get!(socket.assigns.selected_id)
    nodes = if e, do: get_in(e.payload, ["graph", "nodes"]) || [], else: []

    socket
    |> assign(:connection, Accounts.connection())
    |> assign(:selected, e)
    |> assign(:outcome_count, if(e, do: length(Explorations.outcomes(e)), else: 0))
    |> stream(:explorations, Explorations.list(), reset: true)
    |> stream(:nodes, nodes, reset: true)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto max-w-7xl px-4 py-10 sm:px-6 lg:px-8">
        <div class="flex flex-wrap items-start justify-between gap-6">
          <div>
            <p class="text-xs font-bold uppercase tracking-[0.2em] text-indigo-600">
              The next question
            </p>
            <h1 class="mt-3 text-4xl font-semibold tracking-tight">
              Explore what your audience cares about.
            </h1>
            <p class="mt-4 max-w-2xl leading-7 text-base-content/65">
              Use publishing results to choose a question, explore it in RationalGrid, then review the completed grid before creating a campaign.
            </p>
          </div>
          <div
            id="rationalgrid-connection"
            class="rounded-2xl border border-base-content/10 bg-base-200/40 p-4"
          >
            <p class="text-sm font-semibold">
              RationalGrid · {if @connection,
                do: String.replace(@connection.status, "_", " "),
                else: "disconnected"}
            </p>
            <p class="mt-1 text-xs text-base-content/55">Shared publishing studio account</p>
            <.link
              :if={!@connection || @connection.status != "connected"}
              id="connect-rationalgrid"
              href={~p"/rationalgrid/connect"}
              method="post"
              class="mt-3 inline-flex rounded-xl bg-indigo-600 px-4 py-2 text-sm font-semibold text-white transition hover:bg-indigo-500"
            >
              Connect RationalGrid
            </.link>
            <.link
              :if={@connection && @connection.status == "connected"}
              id="reauthorize-rationalgrid"
              href={~p"/rationalgrid/connect"}
              method="post"
              class="mt-3 mr-3 inline-flex text-sm underline"
            >
              Reauthorize
            </.link>
            <.link
              :if={@connection && @connection.status == "connected"}
              id="disconnect-rationalgrid"
              href={~p"/rationalgrid/disconnect"}
              method="delete"
              class="mt-3 inline-flex text-sm underline"
            >
              Disconnect account
            </.link>
          </div>
        </div>

        <div class="mt-8 grid gap-6 lg:grid-cols-[minmax(0,0.8fr)_minmax(0,1.2fr)]">
          <div class="space-y-6">
            <section class="rounded-3xl border border-indigo-500/20 bg-indigo-500/5 p-6">
              <h2 class="text-xl font-semibold">Let the editorial desk propose</h2>
              <p class="mt-2 text-sm leading-6 text-base-content/65">
                Considers strong and weak results, sample size and freshness. It may propose a new question or a specific question beneath an existing private-grid node.
              </p>
              <.form
                for={@theme_form}
                id="exploration-recommend-form"
                phx-submit="recommend"
                class="mt-5"
              >
                <.input
                  field={@theme_form[:theme]}
                  label="Editorial theme (optional)"
                  placeholder="A tension, topic or audience"
                />
                <button
                  id="recommend-exploration"
                  disabled={@recommending? || !@connection || @connection.status != "connected"}
                  class="mt-3 rounded-xl bg-indigo-600 px-4 py-3 text-sm font-semibold text-white transition hover:bg-indigo-500 disabled:opacity-40"
                >
                  {if @recommending?, do: "Considering the evidence…", else: "Recommend a question"}
                </button>
              </.form>
            </section>
            <section class="rounded-3xl border border-base-content/10 p-6">
              <h2 class="text-xl font-semibold">Bring your own question</h2>
              <.form
                for={@form}
                id="exploration-proposal-form"
                phx-submit="propose"
                class="mt-5 space-y-4"
              >
                <.input
                  field={@form[:question]}
                  type="textarea"
                  label="Question"
                  required
                  maxlength="4000"
                />
                <.input
                  field={@form[:rationale]}
                  type="textarea"
                  label="Why explore this?"
                  required
                  maxlength="2000"
                />
                <button
                  id="save-exploration-proposal"
                  class="rounded-xl bg-base-content px-4 py-3 text-sm font-semibold text-base-100 transition hover:opacity-80"
                >
                  Save proposal
                </button>
              </.form>
            </section>
            <section>
              <h2 class="mb-3 text-sm font-semibold text-base-content/60">Recent explorations</h2>
              <div id="exploration-list" phx-update="stream" class="space-y-2">
                <p id="no-explorations" class="hidden text-sm text-base-content/50 only:block">
                  Your proposals will appear here.
                </p>
                <.link
                  :for={{id, e} <- @streams.explorations}
                  id={id}
                  patch={~p"/explorations/#{e.id}"}
                  class="block rounded-2xl border border-base-content/10 p-4 transition hover:border-indigo-500/40 hover:bg-indigo-500/5"
                >
                  <span class="block font-medium">{e.question}</span>
                  <span class="mt-1 block text-xs uppercase tracking-wider text-base-content/50">
                    {String.replace(e.status, "_", " ")}
                  </span>
                </.link>
              </div>
            </section>
          </div>
          <section
            id="exploration-review"
            class="min-w-0 rounded-3xl border border-base-content/10 bg-base-200/20 p-6 sm:p-8"
          >
            <%= if @selected do %>
              <p
                id="exploration-status"
                role="status"
                class="text-xs font-bold uppercase tracking-widest text-indigo-600"
              >
                {String.replace(@selected.status, "_", " ")}
              </p>
              <h2 class="mt-3 text-2xl font-semibold tracking-tight">{@selected.question}</h2>
              <p class="mt-4 whitespace-pre-wrap text-sm leading-7 text-base-content/70">
                {@selected.rationale}
              </p>
              <p :if={@selected.tool == "add_grid_idea"} id="exploration-target" class="mt-4 text-sm">
                Append a question to private grid {@selected.arguments["grid_id"]}, node {@selected.arguments[
                  "parent_node_id"
                ]}.
              </p>
              <p
                :if={@selected.error}
                id="exploration-error"
                class="mt-5 rounded-xl bg-amber-500/10 p-4 text-sm"
              >
                {@selected.error}
              </p>
              <div class="mt-6 flex flex-wrap gap-3">
                <button
                  :if={@selected.status == "proposed"}
                  id="start-exploration"
                  phx-click="start"
                  class="rounded-xl bg-indigo-600 px-5 py-3 text-sm font-semibold text-white transition hover:bg-indigo-500"
                >
                  {if @selected.tool == "explore_question",
                    do: "Generate private grid",
                    else: "Run private-grid improvement"}
                </button>
                <button
                  :if={@selected.status in ["retry", "needs_access"]}
                  id="retry-exploration"
                  phx-click="retry"
                  class="rounded-xl border border-base-content/20 px-5 py-3 text-sm font-semibold"
                >
                  Resume request
                </button>
                <button
                  :if={@selected.status == "review"}
                  id="create-exploration-campaign"
                  phx-click="campaign"
                  class="rounded-xl bg-indigo-600 px-5 py-3 text-sm font-semibold text-white transition hover:bg-indigo-500"
                >
                  Create campaign from this grid
                </button>
                <.link
                  :if={@selected.campaign_id}
                  id="open-exploration-campaign"
                  navigate={~p"/campaigns/#{@selected.campaign_id}/studio"}
                  class="rounded-xl bg-indigo-600 px-5 py-3 text-sm font-semibold text-white"
                >
                  Open campaign
                </.link>
                <a
                  :if={get_in(@selected.result, ["grid", "url"])}
                  id="exploration-source"
                  href={get_in(@selected.result, ["grid", "url"])}
                  target="_blank"
                  rel="noopener noreferrer"
                  class="rounded-xl border border-base-content/15 px-5 py-3 text-sm font-semibold"
                >
                  Open source grid <.icon name="hero-arrow-up-right" class="ml-1 size-4" />
                </a>
              </div>
              <p
                :if={@selected.status in ["queued", "generating"]}
                class="mt-5 text-sm text-base-content/60"
              >
                RationalGrid is working in the background. You can leave this page and return.
              </p>
              <p
                :if={@selected.result["exploration"]}
                id="exploration-progress"
                class="mt-4 text-sm text-base-content/60"
              >
                {@selected.result["exploration"]["stage"]} · {@selected.result["exploration"][
                  "completed_steps"
                ]} / {@selected.result["exploration"]["total_steps"]} steps
              </p>
              <p
                :if={@selected.campaign_id}
                id="exploration-outcomes"
                class="mt-4 text-sm text-base-content/60"
              >
                {@outcome_count} subsequent posts with mature performance evidence.
              </p>
              <div id="exploration-nodes" phx-update="stream" class="mt-8 space-y-4">
                <article
                  :for={{id, node} <- @streams.nodes}
                  id={id}
                  class="rounded-2xl border border-base-content/10 bg-base-100 p-5"
                >
                  <p class="text-xs font-semibold uppercase tracking-wider text-base-content/45">
                    {node["class"]}
                  </p>
                  <p class="mt-3 whitespace-pre-wrap break-words text-sm leading-7">
                    {node["content"]}
                  </p>
                </article>
              </div>
              <details id="exploration-evidence" class="mt-6 border-t border-base-content/10 pt-5">
                <summary class="cursor-pointer text-sm font-semibold">
                  Supporting performance evidence
                </summary>
                <pre class="mt-4 max-h-96 overflow-auto whitespace-pre-wrap break-words text-xs leading-6">{Jason.encode!(@selected.evidence, pretty: true)}</pre>
              </details>
            <% else %>
              <.icon name="hero-sparkles" class="size-8 text-indigo-500" />
              <h2 class="mt-4 text-2xl font-semibold">A question comes before a campaign.</h2>
              <p class="mt-3 leading-7 text-base-content/60">
                Select a proposal to inspect its reasoning and evidence. New explorations create private grids with an opening answer, a test, a deeper branch and a synthesis.
              </p>
            <% end %>
          </section>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
