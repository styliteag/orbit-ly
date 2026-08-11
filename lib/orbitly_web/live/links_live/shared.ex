defmodule OrbitlyWeb.LinksLive.Shared do
  @moduledoc """
  Function components shared by the three links-page designs
  (`OrbitlyWeb.LinksLive.Orbit` / `Bench` / `Soft`). Everything here is
  design-neutral: it uses daisyUI semantic classes, so each theme restyles
  it via its tokens. Event names and element ids are part of the LiveView
  contract (`LinksLive` handlers + tests) — keep them stable across designs.
  """

  use OrbitlyWeb, :html

  alias OrbitlyWeb.LinksLive.Bulk
  alias Phoenix.LiveView.JS

  def short_url(link), do: OrbitlyWeb.ShortUrl.for_link(link)

  @doc "Advanced-options toggle + collapsible field grid for the create form."
  attr :form, Phoenix.HTML.Form, required: true
  attr :domains, :list, required: true
  attr :show_advanced, :boolean, required: true

  def advanced_section(assigns) do
    ~H"""
    <label class="flex items-center gap-2 cursor-pointer w-fit">
      <input
        type="checkbox"
        class="checkbox checkbox-primary checkbox-sm"
        checked={@show_advanced}
        phx-click="toggle-advanced"
      />
      <span class="text-sm">Show advanced options</span>
    </label>

    <div
      id="advanced-options"
      class={[
        "grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3",
        !@show_advanced && "hidden"
      ]}
    >
      <.input
        type="select"
        field={@form[:domain_id]}
        label="Domain:"
        options={Enum.map(@domains, &{&1.hostname, &1.id})}
      />
      <.input
        field={@form[:slug]}
        label="Custom address:"
        placeholder="my-slug  ( / = root, /* = catch-all )"
      />
      <.input type="password" field={@form[:password]} label="Password:" placeholder="Password…" />
      <div class="flex gap-2 items-end">
        <div class="flex-1">
          <label class="label text-sm font-semibold" for="expire_amount">Expire in:</label>
          <input
            type="number"
            min="1"
            id="expire_amount"
            name="form[expire_amount]"
            placeholder="2"
            class="input w-full"
          />
        </div>
        <select name="form[expire_unit]" class="select w-32" id="expire_unit">
          <option value="minutes">minutes</option>
          <option value="hours">hours</option>
          <option value="days" selected>days</option>
        </select>
      </div>
      <div class="flex items-end">
        <.input
          type="checkbox"
          field={@form[:interstitial]}
          label="Preview page before redirect"
        />
      </div>
      <div class="sm:col-span-2">
        <.input field={@form[:description]} label="Description:" placeholder="Description…" />
      </div>
    </div>
    """
  end

  @doc "Search box, result count, page-size buttons and pager."
  attr :search, :string, required: true
  attr :total, :integer, required: true
  attr :filtered_count, :integer, required: true
  attr :page, :integer, required: true
  attr :max_page, :integer, required: true
  attr :page_size, :integer, required: true
  attr :visible, :list, required: true
  attr :selected, :any, required: true
  attr :scope, :string, required: true
  attr :current_user, :map, required: true
  attr :class, :string, default: nil

  def list_controls(assigns) do
    ~H"""
    <div class={["flex flex-wrap items-center justify-between gap-3", @class]}>
      <div class="flex items-center gap-3">
        <Bulk.select_all_checkbox visible={@visible} selected={@selected} />
        <form id="search-form" phx-change="search" phx-submit="search">
          <input
            type="search"
            name="q"
            value={@search}
            placeholder="Search…"
            phx-debounce="200"
            class="input input-sm w-56"
          />
        </form>
      </div>
      <div class="flex items-center gap-3 text-sm">
        <div :if={@current_user.admin} class="join">
          <button
            :for={{value, label} <- [{"own", "My links"}, {"all", "All users"}]}
            type="button"
            class={["join-item btn btn-xs", @scope == value && "btn-active"]}
            phx-click="scope"
            phx-value-scope={value}
          >
            {label}
          </button>
        </div>
        <span :if={@search == ""} class="opacity-60">Total links: <b>{@total}</b></span>
        <span :if={@search != ""} class="opacity-60">
          <b>{@filtered_count}</b> of {@total} links
        </span>
        <div class="join">
          <button
            :for={size <- [10, 20, 50]}
            type="button"
            class={["join-item btn btn-xs", @page_size == size && "btn-active"]}
            phx-click="page-size"
            phx-value-size={size}
          >
            {size}
          </button>
        </div>
        <div class="join">
          <button
            type="button"
            class="join-item btn btn-xs"
            disabled={@page <= 1}
            phx-click="page"
            phx-value-dir="prev"
            aria-label="Previous page"
          >
            <.icon name="hero-chevron-left" class="w-3 h-3" />
          </button>
          <span class="join-item btn btn-xs no-animation pointer-events-none tabular-nums">
            {@page}/{@max_page}
          </span>
          <button
            type="button"
            class="join-item btn btn-xs"
            disabled={@page >= @max_page}
            phx-click="page"
            phx-value-dir="next"
            aria-label="Next page"
          >
            <.icon name="hero-chevron-right" class="w-3 h-3" />
          </button>
        </div>
      </div>
    </div>
    """
  end

  @doc "Copy-to-clipboard button (icon flips via .copied, see app.js/app.css)."
  attr :text, :string, required: true
  attr :class, :string, default: nil

  def copy_button(assigns) do
    ~H"""
    <button
      type="button"
      class={["btn btn-ghost btn-xs text-success", @class]}
      title="Copy to clipboard"
      aria-label="Copy short link"
      phx-click={JS.dispatch("phx:copy", detail: %{text: @text})}
    >
      <.icon name="hero-clipboard-document" class="w-4 h-4 copy-idle" />
      <.icon name="hero-check" class="w-4 h-4 copy-done hidden" />
    </button>
    """
  end

  @doc "Password-lock, preview and expiry badges for a link."
  attr :link, :map, required: true

  def link_badges(assigns) do
    ~H"""
    <.icon :if={@link.password_hash} name="hero-lock-closed" class="w-3.5 h-3.5 opacity-50" />
    <span :if={@link.interstitial} title="Shows a preview page before redirecting">
      <.icon name="hero-eye" class="w-3.5 h-3.5 opacity-50" />
    </span>
    <span :if={@link.expires_at} class="text-xs opacity-50" title={@link.expires_at}>
      {OrbitlyWeb.RelativeTime.until(@link.expires_at)}
    </span>
    """
  end

  @doc """
  Owner attribution (admins only) and description line. Designs with a real
  owner column pass `show_owner={false}` so the email is not printed twice.
  """
  attr :link, :map, required: true
  attr :current_user, :map, required: true
  attr :show_owner, :boolean, default: true

  def owner_line(assigns) do
    assigns = assign(assigns, :with_owner, assigns.show_owner and assigns.current_user.admin)

    ~H"""
    <p class="text-xs opacity-60 truncate">
      <span :if={@with_owner}>by {@link.owner.email}</span>
      <span :if={@with_owner && @link.description}>·</span>
      {@link.description}
    </p>
    """
  end

  @doc "Stats / QR / edit / delete action cluster for a row."
  attr :link, :map, required: true

  attr :list_query, :string,
    default: "",
    doc: "current list state (scope, sorting, …) so the stats page can come back to it"

  def row_actions(assigns) do
    ~H"""
    <div class="whitespace-nowrap text-right">
      <.link
        navigate={stats_path(@link, @list_query)}
        class="btn btn-ghost btn-xs"
        title="Statistics"
        aria-label="Statistics"
      >
        <.icon name="hero-chart-pie" class="w-4 h-4 text-secondary" />
      </.link>
      <a
        href={~p"/qr/#{@link.id}"}
        target="_blank"
        rel="noopener"
        class="btn btn-ghost btn-xs"
        title="QR code"
        aria-label="QR code"
      >
        <.icon name="hero-qr-code" class="w-4 h-4" />
      </a>
      <button
        type="button"
        class="btn btn-ghost btn-xs"
        title="Edit"
        aria-label="Edit"
        phx-click="edit"
        phx-value-id={@link.id}
      >
        <.icon name="hero-pencil" class="w-4 h-4 text-warning" />
      </button>
      <button
        type="button"
        class="btn btn-ghost btn-xs"
        title="Duplicate to another domain"
        aria-label="Duplicate"
        phx-click="row-duplicate"
        phx-value-id={@link.id}
      >
        <.icon name="hero-document-duplicate" class="w-4 h-4 text-info" />
      </button>
      <button
        type="button"
        class="btn btn-ghost btn-xs"
        title="Delete"
        aria-label="Delete"
        phx-click="delete"
        phx-value-id={@link.id}
        data-confirm="Delete this link?"
      >
        <.icon name="hero-trash" class="w-4 h-4 text-error" />
      </button>
    </div>
    """
  end

  @doc """
  Inline "duplicate to another domain" panel — rendered full-width below the row
  (like `edit_panel`) so the domain picker is not squeezed into the narrow
  actions column. Submits one id to the same `duplicate_links/3` as the bulk bar.
  """
  attr :link, :map, required: true
  attr :domains, :list, required: true

  def duplicate_panel(assigns) do
    ~H"""
    <form
      id={"duplicate-form-#{@link.id}"}
      phx-submit="row-duplicate-submit"
      class="flex flex-wrap items-center gap-2 py-3"
    >
      <input type="hidden" name="link_id" value={@link.id} />
      <span class="text-sm font-semibold">Duplicate to:</span>
      <select name="domain_id" class="select select-sm w-56" aria-label="Duplicate to domain">
        <option value="">Choose a domain…</option>
        <option :for={domain <- @domains} value={domain.id}>{domain.hostname}</option>
      </select>
      <button type="submit" class="btn btn-sm btn-primary" phx-disable-with="Duplicating…">
        <.icon name="hero-document-duplicate" class="w-4 h-4" /> Duplicate
      </button>
      <button type="button" class="btn btn-sm btn-ghost" phx-click="cancel-duplicate">
        Cancel
      </button>
    </form>
    """
  end

  @doc "Inline edit form (target, password, expiry, preview, description)."
  attr :edit_form, Phoenix.HTML.Form, required: true

  def edit_panel(assigns) do
    ~H"""
    <.form
      for={@edit_form}
      id="edit-form"
      phx-change="edit-validate"
      phx-submit="update"
      class="space-y-3 py-2"
    >
      <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
        <.input field={@edit_form[:target_url]} label="Target:" />
        <.input
          type="password"
          field={@edit_form[:password]}
          label="Password:"
          placeholder="unchanged"
        />
        <div class="flex gap-2 items-end">
          <div class="flex-1">
            <label class="label text-sm font-semibold" for="edit_expire_amount">
              Expire in:
            </label>
            <input
              type="number"
              min="1"
              id="edit_expire_amount"
              name="edit[expire_amount]"
              placeholder="unchanged"
              class="input w-full"
            />
          </div>
          <select name="edit[expire_unit]" class="select w-32">
            <option value="minutes">minutes</option>
            <option value="hours">hours</option>
            <option value="days" selected>days</option>
          </select>
        </div>
        <div class="flex items-end">
          <.input
            type="checkbox"
            field={@edit_form[:interstitial]}
            label="Preview page before redirect"
          />
        </div>
        <div class="sm:col-span-2">
          <.input field={@edit_form[:description]} label="Description:" />
        </div>
      </div>
      <div class="flex gap-2">
        <button type="button" class="btn btn-sm" phx-click="cancel-edit">
          Close
        </button>
        <.button class="btn btn-primary btn-sm" phx-disable-with="Updating…">
          <.icon name="hero-arrow-path" class="w-4 h-4" /> Update
        </.button>
      </div>
    </.form>
    """
  end

  defp stats_path(link, ""), do: ~p"/links/#{link.id}/stats"
  defp stats_path(link, list_query), do: ~p"/links/#{link.id}/stats?back=#{list_query}"

  @doc "Empty-state copy shared by all designs."
  def empty_text(""), do: "No links yet — shorten your first one above."
  def empty_text(_search), do: "No links match your search."
end
