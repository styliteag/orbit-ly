defmodule OrbitlyWeb.LinksLive.Sort do
  @moduledoc """
  Column sorting for the links page. Two shapes of the same contract: a
  clickable table header (`sort_header`, used by the table design) and a button
  row (`sort_menu`, used by the list/card designs) — every design emits the
  same `sort` event with a `field` value out of `fields/1`.

  Never render both in one design: the tests address the controls by
  `[phx-click="sort"][phx-value-field=…]`, which must stay unambiguous.
  """

  use OrbitlyWeb, :html

  @doc "Sortable fields as {field, label}; the owner column is admin-only."
  def fields(%{admin: true}) do
    [{"short", "Short"}, {"target", "Target"}, {"owner", "Owner"}] ++ base_fields()
  end

  def fields(_user), do: [{"short", "Short"}, {"target", "Target"}] ++ base_fields()

  defp base_fields, do: [{"created", "Age"}, {"clicks", "Hits"}]

  @doc """
  The sort buttons that belong over the leading (short link / target / owner)
  block of a row. Trailing columns get their own `sort_button`, placed by the
  design into the matching grid column.
  """
  attr :sort_by, :string, required: true
  attr :sort_dir, :atom, required: true
  attr :current_user, :map, required: true
  attr :fields, :list, required: true, doc: "field keys for this group, in order"
  attr :class, :string, default: nil

  def sort_group(assigns) do
    assigns = assign(assigns, :labelled, labelled(assigns.current_user, assigns.fields))

    ~H"""
    <div class={["flex flex-wrap items-center gap-1 text-xs", @class]}>
      <span class="opacity-60 mr-1">Sort:</span>
      <.sort_button
        :for={{field, label} <- @labelled}
        field={field}
        label={label}
        sort_by={@sort_by}
        sort_dir={@sort_dir}
      />
    </div>
    """
  end

  @doc "One sort button, for a design to place freely."
  attr :field, :string, required: true
  attr :label, :string, required: true
  attr :sort_by, :string, required: true
  attr :sort_dir, :atom, required: true
  attr :class, :string, default: nil

  def sort_button(assigns) do
    ~H"""
    <button
      type="button"
      class={["btn btn-xs btn-ghost gap-1", @sort_by == @field && "btn-active", @class]}
      phx-click="sort"
      phx-value-field={@field}
    >
      {@label}
      <.sort_arrow active={@sort_by == @field} sort_dir={@sort_dir} />
    </button>
    """
  end

  # Keeps the admin-only owner field out for everyone else.
  defp labelled(current_user, wanted) do
    allowed = fields(current_user)

    Enum.flat_map(wanted, fn field ->
      case List.keyfind(allowed, field, 0) do
        nil -> []
        pair -> [pair]
      end
    end)
  end

  @doc "One sortable table header cell."
  attr :field, :string, required: true
  attr :label, :string, required: true
  attr :sort_by, :string, required: true
  attr :sort_dir, :atom, required: true
  attr :class, :string, default: nil

  def sort_header(assigns) do
    ~H"""
    <th class={@class}>
      <button
        type="button"
        class="inline-flex items-center gap-1 text-[10px] uppercase tracking-[0.15em] hover:text-primary cursor-pointer"
        phx-click="sort"
        phx-value-field={@field}
      >
        {@label}
        <.sort_arrow active={@sort_by == @field} sort_dir={@sort_dir} />
      </button>
    </th>
    """
  end

  attr :active, :boolean, required: true
  attr :sort_dir, :atom, required: true

  defp sort_arrow(assigns) do
    ~H"""
    <.icon
      :if={@active}
      name={if @sort_dir == :asc, do: "hero-chevron-up", else: "hero-chevron-down"}
      class="w-3 h-3"
    />
    """
  end
end
