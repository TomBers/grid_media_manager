defmodule GridMediaManagerWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use GridMediaManagerWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="sticky top-0 z-40 border-b border-base-content/10 bg-base-100/85 px-4 py-3 backdrop-blur-xl sm:px-6 lg:px-8">
      <div class="mx-auto flex max-w-7xl items-center justify-between gap-4">
        <.link navigate={~p"/"} class="group flex items-center gap-3">
          <span class="grid size-10 place-items-center rounded-2xl bg-base-content text-sm font-black tracking-tight text-base-100 shadow-lg shadow-base-content/10 transition group-hover:-translate-y-0.5">
            RG
          </span>
          <span>
            <span class="block text-sm font-semibold leading-5 text-base-content">
              RationalGrid Publishing Studio
            </span>
            <span class="block text-xs text-base-content/55">
              Draft, design, and publish
            </span>
          </span>
        </.link>

        <nav class="flex items-center gap-3">
          <.link
            navigate={~p"/media-library"}
            class="hidden rounded-full px-3 py-2 text-sm font-medium text-base-content/65 transition hover:bg-base-200 hover:text-base-content sm:inline-flex"
          >
            Media library
          </.link>
          <.link
            navigate={~p"/"}
            class="hidden rounded-full px-3 py-2 text-sm font-medium text-base-content/65 transition hover:bg-base-200 hover:text-base-content sm:inline-flex"
          >
            Campaigns
          </.link>
          <.theme_toggle />
        </nav>
      </div>
    </header>

    <main class="min-h-screen bg-base-100">
      {render_slot(@inner_block)}
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="relative flex flex-row items-center rounded-full border-2 border-base-300 bg-base-300">
      <div class="absolute left-0 h-full w-1/3 rounded-full border border-base-200 bg-base-100 brightness-200 transition-[left] [[data-theme-choice=light]_&]:left-1/3 [[data-theme-choice=dark]_&]:left-2/3" />

      <button
        type="button"
        aria-label="Use system theme"
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        type="button"
        aria-label="Use light theme"
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        type="button"
        aria-label="Use dark theme"
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
