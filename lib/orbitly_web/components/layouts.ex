defmodule OrbitlyWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use OrbitlyWeb, :html

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
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  attr :current_user, :map, default: nil, doc: "the signed-in user shown in the navbar"

  attr :wide, :boolean,
    default: false,
    doc: "widens the content column for table-heavy pages"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="navbar bg-base-100 border-b border-base-200 px-4 sm:px-6 lg:px-8">
      <div class="flex-1">
        <a href="/" class="flex w-fit items-center gap-2 text-lg font-bold">
          <.icon name="hero-link" class="w-5 h-5 text-primary" />
          <span>Stylite <span class="text-primary">Orbit-ly</span></span>
        </a>
      </div>
      <div class="flex-none flex items-center gap-2">
        <span
          id="app-version"
          class="hidden md:inline whitespace-nowrap rounded-md px-2 py-1 text-xs font-medium text-base-content/55"
          title="Application version"
        >
          v{app_version()}
        </span>
        <.link
          id="github-repository-link"
          href="https://github.com/styliteag/orbit-ly"
          target="_blank"
          rel="noopener noreferrer"
          class="btn btn-ghost btn-sm hidden lg:inline-flex"
        >
          github/styliteag/orbit-ly
        </.link>
        <%= if @current_user do %>
          <.link navigate={~p"/links"} class="btn btn-ghost btn-sm">My links</.link>
          <div :if={@current_user.admin} class="dropdown dropdown-end">
            <div
              tabindex="0"
              role="button"
              class="btn btn-sm rounded-full bg-violet-600 hover:bg-violet-700 text-white border-none px-4"
            >
              <.icon name="hero-shield-check" class="w-4 h-4" /> Admin
            </div>
            <ul
              tabindex="0"
              class="dropdown-content menu bg-base-100 rounded-box z-10 mt-2 w-44 p-2 shadow-lg border border-base-200"
            >
              <li><.link navigate={~p"/admin/domains"}>Domains</.link></li>
              <li><.link navigate={~p"/admin/users"}>Users</.link></li>
            </ul>
          </div>
        <% end %>
        <.settings_menu current_user={@current_user} />
      </div>
    </header>

    <main class="px-4 py-10 sm:px-6 lg:px-8">
      <div class={["mx-auto space-y-4", (@wide && "max-w-6xl") || "max-w-4xl"]}>
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  defp app_version do
    case Application.spec(:orbitly, :vsn) do
      nil -> "dev"
      version -> to_string(version)
    end
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
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
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
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
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
  Settings gear menu: design and light/dark mode for everyone, account
  entries (change password, log out) when signed in. Design/mode buttons do
  a full-page PUT so the server re-renders with the chosen theme; the
  active entries are highlighted purely via CSS against the root data-theme
  attribute (`.design-menu` rules in app.css), so no assign plumbing is
  needed on other pages.
  """
  attr :current_user, :map, default: nil

  def settings_menu(assigns) do
    ~H"""
    <div class="dropdown dropdown-end">
      <div
        tabindex="0"
        role="button"
        class="btn btn-ghost btn-sm btn-circle"
        title="Settings"
        aria-label="Settings"
      >
        <.icon name="hero-cog-6-tooth" class="w-5 h-5" />
      </div>
      <ul
        tabindex="0"
        class="dropdown-content menu design-menu bg-base-100 rounded-box z-10 mt-2 w-56 p-2 shadow-lg border border-base-200"
      >
        <li :if={@current_user} class="menu-title truncate">{@current_user.email}</li>
        <li class="menu-title">Design</li>
        <li :for={design <- OrbitlyWeb.Design.all()}>
          <.link href={~p"/design/#{design}"} method="put" data-design-choice={design}>
            {OrbitlyWeb.Design.name(design)}
          </.link>
        </li>
        <li class="menu-title">Mode</li>
        <li :for={mode <- OrbitlyWeb.Design.modes()}>
          <.link href={~p"/design-mode/#{mode}"} method="put" data-mode-choice={mode}>
            <.icon
              name={if mode == "dark", do: "hero-moon-micro", else: "hero-sun-micro"}
              class="size-4"
            />
            {OrbitlyWeb.Design.mode_name(mode)}
          </.link>
        </li>
        <%= if @current_user do %>
          <li class="menu-title">Account</li>
          <li>
            <.link navigate={~p"/settings"}>
              <.icon name="hero-key" class="size-4" /> Change password
            </.link>
          </li>
          <li>
            <.link href={~p"/sign-out"} method="delete">
              <.icon name="hero-arrow-right-start-on-rectangle" class="size-4" /> Log out
            </.link>
          </li>
        <% end %>
      </ul>
    </div>
    """
  end
end
