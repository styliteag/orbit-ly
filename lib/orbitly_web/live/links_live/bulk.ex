defmodule OrbitlyWeb.LinksLive.Bulk do
  @moduledoc """
  Multi-select pieces of the links page: the per-row checkbox, the select-all
  checkbox for the current page and the action bar that appears once something
  is selected (delete for everyone, reassign for admins).

  Design-neutral like `LinksLive.Shared` — semantic daisyUI classes only. The
  event names (`toggle-select`, `toggle-select-page`, `clear-selection`,
  `bulk-delete`, `bulk-reassign`) and the `bulk-bar` / `bulk-reassign-form` ids
  are part of the LiveView contract across all three designs.
  """

  use OrbitlyWeb, :html

  @doc "Checkbox for one row."
  attr :link, :map, required: true
  attr :selected, :any, required: true

  def row_checkbox(assigns) do
    ~H"""
    <input
      type="checkbox"
      class="checkbox checkbox-sm checkbox-primary shrink-0"
      checked={MapSet.member?(@selected, @link.id)}
      phx-click="toggle-select"
      phx-value-id={@link.id}
      aria-label={"Select #{@link.domain.hostname}/#{@link.slug}"}
    />
    """
  end

  @doc "Select/deselect every link on the current page."
  attr :visible, :list, required: true
  attr :selected, :any, required: true

  def select_all_checkbox(assigns) do
    ~H"""
    <input
      type="checkbox"
      class="checkbox checkbox-sm checkbox-primary"
      checked={all_selected?(@visible, @selected)}
      phx-click="toggle-select-page"
      title="Select all on this page"
      aria-label="Select all on this page"
    />
    """
  end

  @doc """
  Action bar for the current selection. Hidden while nothing is selected.
  Reassignment is admin-only — a normal user must not see the account list
  (no open registration, ADR-0006).
  """
  attr :selected, :any, required: true
  attr :users, :list, required: true
  attr :current_user, :map, required: true
  attr :class, :string, default: nil

  def bulk_bar(assigns) do
    assigns = assign(assigns, :count, MapSet.size(assigns.selected))

    ~H"""
    <div
      :if={@count > 0}
      id="bulk-bar"
      class={["flex flex-wrap items-center gap-3 bg-base-300/60", @class]}
    >
      <span class="text-sm font-semibold tabular-nums">
        {@count} selected
      </span>
      <button type="button" class="btn btn-xs btn-ghost" phx-click="clear-selection">
        Clear
      </button>

      <form
        :if={@current_user.admin}
        id="bulk-reassign-form"
        phx-submit="bulk-reassign"
        class="flex items-center gap-2"
      >
        <select name="owner_id" class="select select-xs w-56" aria-label="New owner">
          <option value="">Reassign to…</option>
          <option :for={user <- @users} value={user.id}>{user.email}</option>
        </select>
        <button type="submit" class="btn btn-xs" phx-disable-with="Moving…">
          <.icon name="hero-arrow-right-circle" class="w-3.5 h-3.5" /> Reassign
        </button>
      </form>

      <button
        type="button"
        class="btn btn-xs btn-error ml-auto"
        phx-click="bulk-delete"
        phx-disable-with="Deleting…"
        data-confirm={"Delete #{@count} selected link(s)? This cannot be undone."}
      >
        <.icon name="hero-trash" class="w-3.5 h-3.5" /> Delete selected
      </button>
    </div>
    """
  end

  defp all_selected?([], _selected), do: false
  defp all_selected?(visible, selected), do: Enum.all?(visible, &MapSet.member?(selected, &1.id))
end
