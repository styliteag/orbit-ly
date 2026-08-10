defmodule OrbitlyWeb.LinksLive do
  @moduledoc """
  kutt-style link management: hero shorten form with collapsible advanced
  options (custom slug, expiry as a duration, password, description),
  searchable/sortable/paginated table with inline editing and multi-select.
  A user sees their own links; an admin starts on their own too and widens to
  every user's links with the scope toggle (owner column and owner sort are
  admin-only).

  Rendering is delegated to one of three switchable designs (see
  `OrbitlyWeb.Design`): `LinksLive.Orbit` (default), `LinksLive.Bench`,
  `LinksLive.Soft`. All designs share this module's events and ids
  (`link-form`, `search-form`, `advanced-options`, `edit-form`,
  `link-<id>` rows, `bulk-bar`, plus the `scope` and `sort` events) — the
  design only changes markup.
  """

  use OrbitlyWeb, :live_view

  on_mount {OrbitlyWeb.UserAuth, :live_user_required}

  alias Orbitly.Accounts
  alias Orbitly.Shortener
  alias Orbitly.Shortener.Link

  # Client-supplied sort values are matched against this list — never converted
  # to an atom.
  @sort_fields ~w(short target owner created clicks)

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Links")
     |> assign(:design, OrbitlyWeb.Design.validate(session["design"]))
     |> assign(:show_advanced, false)
     |> assign(:edit_id, nil)
     |> assign(:edit_link, nil)
     |> assign(:edit_form, nil)
     |> assign(:selected, MapSet.new())
     |> load_domains()
     |> load_reassign_targets()
     |> assign_new_form()}
  end

  # Scope, sorting, search and paging live in the URL, so they survive a visit
  # to a link's stats page and the browser's back button.
  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:scope, param(params, "scope", ~w(own all), "own"))
     |> assign(:sort_by, param(params, "sort", @sort_fields, "created"))
     |> assign(:sort_dir, if(params["dir"] == "asc", do: :asc, else: :desc))
     |> assign(:search, to_string(params["q"]))
     |> assign(:page_size, params |> param("size", ~w(10 20 50), "20") |> String.to_integer())
     |> assign(:page, page_param(params))
     |> load_links()
     |> prune_selection()}
  end

  defp param(params, key, allowed, default) do
    value = params[key]
    if value in allowed, do: value, else: default
  end

  defp page_param(params) do
    case Integer.parse(to_string(params["page"])) do
      {page, ""} when page > 0 -> page
      _ -> 1
    end
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
    {:noreply, patch(socket, %{"q" => query, "page" => 1})}
  end

  def handle_event("page-size", %{"size" => size}, socket) when size in ~w(10 20 50) do
    {:noreply, patch(socket, %{"size" => size, "page" => 1})}
  end

  def handle_event("page-size", _params, socket), do: {:noreply, socket}

  def handle_event("scope", %{"scope" => scope}, socket) when scope in ~w(own all) do
    {:noreply, patch(socket, %{"scope" => scope, "page" => 1})}
  end

  def handle_event("scope", _params, socket), do: {:noreply, socket}

  def handle_event("sort", %{"field" => field}, socket) when field in @sort_fields do
    dir = next_sort_dir(socket.assigns, field)

    {:noreply, patch(socket, %{"sort" => field, "dir" => dir, "page" => 1})}
  end

  def handle_event("sort", _params, socket), do: {:noreply, socket}

  def handle_event("page", %{"dir" => dir}, socket) do
    delta = if dir == "next", do: 1, else: -1

    max_page =
      socket.assigns.links
      |> filtered_links(socket.assigns.search)
      |> max_page(socket.assigns.page_size)

    page = socket.assigns.page |> Kernel.+(delta) |> max(1) |> min(max_page)

    {:noreply, patch(socket, %{"page" => page})}
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

  # --- bulk selection ---

  def handle_event("toggle-select", %{"id" => id}, socket) do
    selected = socket.assigns.selected

    selected =
      if MapSet.member?(selected, id),
        do: MapSet.delete(selected, id),
        else: MapSet.put(selected, id)

    {:noreply, assign(socket, :selected, selected)}
  end

  def handle_event("toggle-select-page", _params, socket) do
    ids = socket.assigns |> visible_links() |> Enum.map(& &1.id)
    selected = socket.assigns.selected

    selected =
      if ids != [] and Enum.all?(ids, &MapSet.member?(selected, &1)) do
        Enum.reduce(ids, selected, fn id, acc -> MapSet.delete(acc, id) end)
      else
        Enum.reduce(ids, selected, fn id, acc -> MapSet.put(acc, id) end)
      end

    {:noreply, assign(socket, :selected, selected)}
  end

  def handle_event("clear-selection", _params, socket) do
    {:noreply, assign(socket, :selected, MapSet.new())}
  end

  def handle_event("bulk-delete", _params, socket) do
    ids = MapSet.to_list(socket.assigns.selected)

    case Shortener.delete_links(ids, socket.assigns.current_user) do
      {:ok, count} ->
        {:noreply,
         socket
         |> put_flash(:info, "#{count} #{pluralize(count, "link")} deleted")
         |> assign(:selected, MapSet.new())
         |> load_links()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete the selected links")}
    end
  end

  def handle_event("bulk-reassign", %{"owner_id" => ""}, socket) do
    {:noreply, put_flash(socket, :error, "Pick a user to reassign to")}
  end

  def handle_event("bulk-reassign", %{"owner_id" => owner_id}, socket) do
    ids = MapSet.to_list(socket.assigns.selected)

    case Shortener.reassign_links(ids, owner_id, socket.assigns.current_user) do
      {:ok, count} ->
        # Refresh first: the target may have been created after this mount.
        socket = load_reassign_targets(socket)

        {:noreply,
         socket
         |> put_flash(
           :info,
           "#{count} #{pluralize(count, "link")} moved to #{owner_email(socket, owner_id)}"
         )
         |> assign(:selected, MapSet.new())
         |> load_links()}

      {:error, :invalid_owner} ->
        {:noreply, put_flash(socket, :error, "Unknown user")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Not allowed to reassign links")}
    end
  end

  # A destructive action must never act on rows the user cannot see: searching
  # or paging away from a selected row drops it from the selection.
  defp prune_selection(socket) do
    visible_ids = socket.assigns |> visible_links() |> MapSet.new(& &1.id)
    assign(socket, :selected, MapSet.intersection(socket.assigns.selected, visible_ids))
  end

  defp pluralize(1, word), do: word
  defp pluralize(_count, word), do: word <> "s"

  defp owner_email(socket, owner_id) do
    case Enum.find(socket.assigns.users, &(&1.id == owner_id)) do
      %{email: email} -> email
      _ -> "another user"
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

  # Reassignment is admin-only, so only an admin ever gets the account list.
  defp load_reassign_targets(socket) do
    users =
      if socket.assigns.current_user.admin do
        Enum.map(Accounts.list_users(), &%{id: &1.id, email: &1.email})
      else
        []
      end

    assign(socket, :users, users)
  end

  defp load_links(socket) do
    # Ordering is the table's business (`sort_links/4`), not the query's.
    links = Shortener.list_links(socket.assigns.current_user, scope(socket.assigns.scope))

    live_ids = MapSet.new(links, & &1.id)

    socket
    |> assign(:links, links)
    # Deleted or reassigned-away links must not linger in the selection.
    |> assign(:selected, MapSet.intersection(socket.assigns.selected, live_ids))
    |> assign(:click_counts, Shortener.click_counts(Enum.map(links, & &1.id)))
  end

  defp scope("all"), do: :all
  defp scope(_own), do: :own

  ## -- list state in the URL ------------------------------------------------

  # Only non-default values end up in the query string, so a plain /links stays
  # a plain /links.
  @defaults %{
    "scope" => "own",
    "sort" => "created",
    "dir" => "desc",
    "q" => "",
    "size" => "20",
    "page" => "1"
  }

  defp list_params(assigns, overrides \\ %{}) do
    %{
      "scope" => assigns.scope,
      "sort" => assigns.sort_by,
      "dir" => to_string(assigns.sort_dir),
      "q" => assigns.search,
      "size" => to_string(assigns.page_size),
      "page" => to_string(assigns.page)
    }
    |> Map.merge(Map.new(overrides, fn {key, value} -> {key, to_string(value)} end))
    |> Enum.reject(fn {key, value} -> value == @defaults[key] end)
    |> Map.new()
  end

  defp patch(socket, overrides) do
    push_patch(socket, to: ~p"/links?#{list_params(socket.assigns, overrides)}")
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

  # The single source for "which rows are on screen": the render path and the
  # selection handlers must never derive different sets, otherwise "select all"
  # picks rows the user is not looking at.
  defp table_rows(assigns) do
    filtered =
      assigns.links
      |> filtered_links(assigns.search)
      |> sort_links(assigns.sort_by, assigns.sort_dir, assigns.click_counts)

    max_page = max_page(filtered, assigns.page_size)
    # Deleting, filtering or re-sorting can leave the cursor past the last page.
    page = min(assigns.page, max_page)

    %{
      filtered: filtered,
      page: page,
      max_page: max_page,
      visible: paged(filtered, page, assigns.page_size)
    }
  end

  defp visible_links(assigns), do: table_rows(assigns).visible

  defp sort_links(links, sort_by, sort_dir, click_counts) do
    Enum.sort_by(links, &sort_key(&1, sort_by, click_counts), sort_dir)
  end

  defp sort_key(link, "short", _counts),
    do: {String.downcase(link.domain.hostname), String.downcase(link.slug)}

  defp sort_key(link, "target", _counts), do: String.downcase(to_string(link.target_url))
  defp sort_key(link, "owner", _counts), do: String.downcase(owner_email_of(link))
  defp sort_key(link, "clicks", counts), do: Map.get(counts, link.id, 0)
  defp sort_key(link, _created, _counts), do: DateTime.to_unix(link.inserted_at, :microsecond)

  defp owner_email_of(%{owner: %{email: email}}) when is_binary(email), do: email
  defp owner_email_of(_link), do: ""

  # Clicking the active column flips the direction; a new column starts with the
  # direction that is useful there (newest / most clicks first, text A→Z).
  defp next_sort_dir(%{sort_by: field, sort_dir: :desc}, field), do: :asc
  defp next_sort_dir(%{sort_by: field}, field), do: :desc
  defp next_sort_dir(_assigns, field) when field in ~w(created clicks), do: :desc
  defp next_sort_dir(_assigns, _field), do: :asc

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
    rows = table_rows(assigns)

    assigns
    |> assign(:total, length(assigns.links))
    # Carried into the stats page so its Back link returns to this exact list.
    |> assign(:list_query, URI.encode_query(list_params(assigns)))
    |> assign(:filtered_count, length(rows.filtered))
    |> assign(:page, rows.page)
    |> assign(:visible, rows.visible)
    |> assign(:max_page, rows.max_page)
  end
end
