defmodule OrbitlyWeb.LinksLive do
  @moduledoc """
  kutt-style link management: hero shorten form with collapsible advanced
  options (custom slug, expiry as a duration, password, description),
  searchable/paginated table with inline editing. Admins see all links
  with their owners (policy-scoped); users see their own.

  Rendering is delegated to one of three switchable designs (see
  `OrbitlyWeb.Design`): `LinksLive.Orbit` (default), `LinksLive.Bench`,
  `LinksLive.Soft`. All designs share this module's events and ids
  (`link-form`, `search-form`, `advanced-options`, `edit-form`,
  `link-<id>` rows) — the design only changes markup.
  """

  use OrbitlyWeb, :live_view

  on_mount {OrbitlyWeb.UserAuth, :live_user_required}

  alias Orbitly.Shortener
  alias Orbitly.Shortener.Link

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Links")
     |> assign(:design, OrbitlyWeb.Design.validate(session["design"]))
     |> assign(:show_advanced, false)
     |> assign(:search, "")
     |> assign(:page, 1)
     |> assign(:page_size, 20)
     |> assign(:edit_id, nil)
     |> assign(:edit_link, nil)
     |> assign(:edit_form, nil)
     |> load_domains()
     |> load_links()
     |> assign_new_form()}
  end

  # --- create form ---

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    changeset =
      %Link{}
      |> Shortener.change_link(clean_params(params), socket.assigns.current_user)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, as: "form"))}
  end

  def handle_event("save", %{"form" => params}, socket) do
    case Shortener.create_link(clean_params(params), socket.assigns.current_user) do
      {:ok, link} ->
        {:noreply,
         socket
         |> put_flash(:info, "Link /#{link.slug} created")
         |> load_links()
         |> assign_new_form()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:form, to_form(changeset, as: "form"))
         |> maybe_show_advanced(changeset)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not create link")}
    end
  end

  def handle_event("toggle-advanced", _params, socket) do
    {:noreply, assign(socket, :show_advanced, !socket.assigns.show_advanced)}
  end

  # --- table controls ---

  def handle_event("search", %{"q" => query}, socket) do
    {:noreply, socket |> assign(:search, query) |> assign(:page, 1)}
  end

  def handle_event("page-size", %{"size" => size}, socket) when size in ~w(10 20 50) do
    {:noreply, socket |> assign(:page_size, String.to_integer(size)) |> assign(:page, 1)}
  end

  def handle_event("page-size", _params, socket), do: {:noreply, socket}

  def handle_event("page", %{"dir" => dir}, socket) do
    delta = if dir == "next", do: 1, else: -1

    max_page =
      socket.assigns.links
      |> filtered_links(socket.assigns.search)
      |> max_page(socket.assigns.page_size)

    {:noreply,
     assign(socket, :page, socket.assigns.page |> Kernel.+(delta) |> max(1) |> min(max_page))}
  end

  # --- inline edit ---

  def handle_event("edit", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.links, &(&1.id == id)) do
      %Link{} = link ->
        changeset = Shortener.change_link_update(link)

        {:noreply,
         socket
         |> assign(:edit_id, id)
         |> assign(:edit_link, link)
         |> assign(:edit_form, to_form(changeset, as: "edit"))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("cancel-edit", _params, socket) do
    {:noreply,
     socket |> assign(:edit_id, nil) |> assign(:edit_link, nil) |> assign(:edit_form, nil)}
  end

  def handle_event("edit-validate", %{"edit" => params}, socket) do
    changeset =
      socket.assigns.edit_link
      |> Shortener.change_link_update(clean_params(params))
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :edit_form, to_form(changeset, as: "edit"))}
  end

  def handle_event("update", %{"edit" => params}, socket) do
    case Shortener.update_link(
           socket.assigns.edit_link,
           clean_params(params),
           socket.assigns.current_user
         ) do
      {:ok, link} ->
        {:noreply,
         socket
         |> put_flash(:info, "Link /#{link.slug} updated")
         |> assign(:edit_id, nil)
         |> assign(:edit_link, nil)
         |> assign(:edit_form, nil)
         |> load_links()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :edit_form, to_form(changeset, as: "edit"))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not update link")}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    with %Link{} = link <- Enum.find(socket.assigns.links, &(&1.id == id)),
         :ok <- Shortener.delete_link(link, socket.assigns.current_user) do
      {:noreply, socket |> put_flash(:info, "Link deleted") |> load_links()}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not delete link")}
    end
  end

  # --- data ---

  defp load_domains(socket) do
    domains =
      Shortener.list_domains()
      |> Enum.filter(& &1.active)
      |> Enum.sort_by(&{!&1.is_primary, &1.hostname})

    default_domain_id =
      case domains do
        [first | _] -> first.id
        [] -> nil
      end

    socket
    |> assign(:domains, domains)
    |> assign(:default_domain_id, default_domain_id)
  end

  defp load_links(socket) do
    links =
      socket.assigns.current_user
      |> Shortener.list_links()
      |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})

    socket
    |> assign(:links, links)
    |> assign(:click_counts, Shortener.click_counts(Enum.map(links, & &1.id)))
  end

  defp assign_new_form(socket) do
    changeset =
      Shortener.change_link(
        %Link{domain_id: socket.assigns.default_domain_id},
        %{},
        socket.assigns.current_user
      )

    assign(socket, :form, to_form(changeset, as: "form"))
  end

  # Errors on fields that live inside the collapsed advanced section would be
  # invisible otherwise — expand the section so the user can see them.
  @advanced_fields [:slug, :domain_id, :password, :expires_at, :description]

  defp maybe_show_advanced(socket, changeset) do
    if Enum.any?(Keyword.keys(changeset.errors), &(&1 in @advanced_fields)) do
      assign(socket, :show_advanced, true)
    else
      socket
    end
  end

  # Drops the duration fields and, when a duration is given, computes
  # expires_at from it ("Expire in: 2 hours" instead of a datetime picker).
  defp clean_params(params) do
    {amount, params} = Map.pop(params, "expire_amount")
    {unit, params} = Map.pop(params, "expire_unit")
    params = Map.reject(params, fn {_key, value} -> value == "" end)

    case Integer.parse(to_string(amount || "")) do
      {n, ""} when n > 0 ->
        expires_at = DateTime.add(DateTime.utc_now(), n * unit_seconds(unit))
        Map.put(params, "expires_at", DateTime.to_iso8601(expires_at))

      _ ->
        params
    end
  end

  defp unit_seconds("minutes"), do: 60
  defp unit_seconds("hours"), do: 3600
  defp unit_seconds(_days), do: 86_400

  defp filtered_links(links, search) do
    query = search |> String.trim() |> String.downcase()

    if query == "" do
      links
    else
      Enum.filter(links, fn link ->
        [
          link.slug,
          link.target_url,
          link.description,
          link.domain.hostname,
          to_string(link.owner.email)
        ]
        |> Enum.any?(&(&1 && String.contains?(String.downcase(to_string(&1)), query)))
      end)
    end
  end

  defp paged(links, page, size), do: Enum.slice(links, (page - 1) * size, size)
  defp max_page(links, size), do: links |> length() |> Kernel./(size) |> ceil() |> max(1)

  # --- render ---

  @impl true
  def render(assigns) do
    assigns = derive_table_assigns(assigns)

    case assigns.design do
      "bench" -> OrbitlyWeb.LinksLive.Bench.page(assigns)
      "soft" -> OrbitlyWeb.LinksLive.Soft.page(assigns)
      _orbit -> OrbitlyWeb.LinksLive.Orbit.page(assigns)
    end
  end

  defp derive_table_assigns(assigns) do
    filtered = filtered_links(assigns.links, assigns.search)
    max_page = max_page(filtered, assigns.page_size)
    # Deleting or filtering can leave the cursor past the last page.
    page = min(assigns.page, max_page)

    assigns
    |> assign(:total, length(assigns.links))
    |> assign(:filtered_count, length(filtered))
    |> assign(:page, page)
    |> assign(:visible, paged(filtered, page, assigns.page_size))
    |> assign(:max_page, max_page)
  end
end
