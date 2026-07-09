defmodule OrbitlyWeb.LinksLive do
  @moduledoc """
  kutt-style link management: hero shorten form with collapsible advanced
  options (custom slug, expiry as a duration, password, description),
  searchable/paginated table with inline editing. Admins see all links
  with their owners (policy-scoped); users see their own.
  """

  use OrbitlyWeb, :live_view

  on_mount {OrbitlyWeb.LiveUserAuth, :live_user_required}

  alias Orbitly.Shortener
  alias Orbitly.Shortener.Link
  alias OrbitlyWeb.RelativeTime
  alias Phoenix.LiveView.JS

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Links")
     |> assign(:show_advanced, false)
     |> assign(:search, "")
     |> assign(:page, 1)
     |> assign(:page_size, 20)
     |> assign(:edit_id, nil)
     |> assign(:edit_form, nil)
     |> load_domains()
     |> load_links()
     |> assign_new_form()}
  end

  # --- create form ---

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    {:noreply,
     assign(socket, :form, AshPhoenix.Form.validate(socket.assigns.form, clean_params(params)))}
  end

  def handle_event("save", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: clean_params(params)) do
      {:ok, link} ->
        {:noreply,
         socket
         |> put_flash(:info, "Link /#{link.slug} created")
         |> load_links()
         |> assign_new_form()}

      {:error, form} ->
        {:noreply, assign(socket, :form, form)}
    end
  end

  def handle_event("toggle-advanced", _params, socket) do
    {:noreply, assign(socket, :show_advanced, !socket.assigns.show_advanced)}
  end

  # --- table controls ---

  def handle_event("search", %{"q" => query}, socket) do
    {:noreply, socket |> assign(:search, query) |> assign(:page, 1)}
  end

  def handle_event("page-size", %{"size" => size}, socket) do
    {:noreply, socket |> assign(:page_size, String.to_integer(size)) |> assign(:page, 1)}
  end

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
        form =
          AshPhoenix.Form.for_update(link, :update,
            actor: socket.assigns.current_user,
            as: "edit"
          )

        {:noreply, socket |> assign(:edit_id, id) |> assign(:edit_form, to_form(form))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("cancel-edit", _params, socket) do
    {:noreply, socket |> assign(:edit_id, nil) |> assign(:edit_form, nil)}
  end

  def handle_event("edit-validate", %{"edit" => params}, socket) do
    {:noreply,
     assign(
       socket,
       :edit_form,
       AshPhoenix.Form.validate(socket.assigns.edit_form, clean_params(params))
     )}
  end

  def handle_event("update", %{"edit" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.edit_form, params: clean_params(params)) do
      {:ok, link} ->
        {:noreply,
         socket
         |> put_flash(:info, "Link /#{link.slug} updated")
         |> assign(:edit_id, nil)
         |> assign(:edit_form, nil)
         |> load_links()}

      {:error, form} ->
        {:noreply, assign(socket, :edit_form, form)}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    with %Link{} = link <- Enum.find(socket.assigns.links, &(&1.id == id)),
         :ok <- Shortener.destroy_link(link, actor: socket.assigns.current_user) do
      {:noreply, socket |> put_flash(:info, "Link deleted") |> load_links()}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not delete link")}
    end
  end

  # --- data ---

  defp load_domains(socket) do
    {:ok, domains} = Shortener.list_domains(actor: socket.assigns.current_user)
    assign(socket, :domains, Enum.filter(domains, & &1.active))
  end

  defp load_links(socket) do
    {:ok, links} =
      Shortener.list_links(actor: socket.assigns.current_user, load: [:domain, :owner])

    links = Enum.sort_by(links, & &1.inserted_at, {:desc, DateTime})

    socket
    |> assign(:links, links)
    |> assign(:click_counts, Shortener.click_counts(Enum.map(links, & &1.id)))
  end

  defp assign_new_form(socket) do
    form =
      AshPhoenix.Form.for_create(Link, :create,
        actor: socket.assigns.current_user,
        as: "form"
      )

    assign(socket, :form, to_form(form))
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

  defp short_url(link), do: OrbitlyWeb.ShortUrl.for_link(link)

  # --- render ---

  @impl true
  def render(assigns) do
    filtered = filtered_links(assigns.links, assigns.search)

    assigns =
      assigns
      |> assign(:total, length(assigns.links))
      |> assign(:visible, paged(filtered, assigns.page, assigns.page_size))
      |> assign(:max_page, max_page(filtered, assigns.page_size))

    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="space-y-12">
        <section class="text-center pt-8">
          <h1 class="text-4xl font-bold">
            Cut your links <span class="underline decoration-dotted decoration-primary">shorter</span>.
          </h1>
        </section>

        <.form for={@form} id="link-form" phx-change="validate" phx-submit="save" class="space-y-4">
          <div class="relative">
            <.input
              field={@form[:target_url]}
              placeholder="Paste your long URL"
              class="input input-lg w-full !rounded-full shadow-lg pr-16 pl-6"
            />
            <button
              type="submit"
              class="btn btn-primary btn-circle absolute right-2 top-1/2 -translate-y-1/2"
              title="Shorten"
              phx-disable-with="…"
            >
              <.icon name="hero-paper-airplane" class="w-5 h-5" />
            </button>
          </div>

          <label class="flex items-center gap-2 cursor-pointer w-fit">
            <input
              type="checkbox"
              class="checkbox checkbox-primary checkbox-sm"
              checked={@show_advanced}
              phx-click="toggle-advanced"
            />
            <span class="text-sm">Show advanced options</span>
          </label>

          <div class={[
            "grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3",
            !@show_advanced && "hidden"
          ]}>
            <.input
              type="select"
              field={@form[:domain_id]}
              label="Domain:"
              options={Enum.map(@domains, &{&1.hostname, &1.id})}
              prompt="Choose a domain"
            />
            <.input
              field={@form[:slug]}
              label="Custom address:"
              placeholder="my-slug  ( / = root, /* = catch-all )"
            />
            <.input
              type="password"
              field={@form[:password]}
              label="Password:"
              placeholder="Password…"
            />
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
            <div class="sm:col-span-2">
              <.input
                field={@form[:description]}
                label="Description:"
                placeholder="Description…"
              />
            </div>
          </div>
        </.form>

        <section class="space-y-3">
          <h2 class="text-xl font-semibold">Recent shortened links.</h2>

          <div class="card bg-base-100 border border-base-200 shadow-sm">
            <div class="card-body p-0">
              <div class="flex flex-wrap items-center justify-between gap-3 p-4">
                <form id="search-form" phx-change="search" onsubmit="return false">
                  <input
                    type="search"
                    name="q"
                    value={@search}
                    placeholder="Search…"
                    phx-debounce="200"
                    class="input input-sm w-56"
                  />
                </form>
                <div class="flex items-center gap-3 text-sm">
                  <span class="opacity-60">Total links: <b>{@total}</b></span>
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
                    >
                      <.icon name="hero-chevron-left" class="w-3 h-3" />
                    </button>
                    <button
                      type="button"
                      class="join-item btn btn-xs"
                      disabled={@page >= @max_page}
                      phx-click="page"
                      phx-value-dir="next"
                    >
                      <.icon name="hero-chevron-right" class="w-3 h-3" />
                    </button>
                  </div>
                </div>
              </div>

              <table class="table">
                <thead>
                  <tr class="bg-base-200/50">
                    <th>Original URL</th>
                    <th>Created at</th>
                    <th>Short link</th>
                    <th class="text-right">Views</th>
                    <th></th>
                  </tr>
                </thead>
                <tbody>
                  <tr :if={@visible == []}>
                    <td colspan="5" class="text-center opacity-60 py-8">
                      {if @search == "",
                        do: "No links yet — shorten your first one above.",
                        else: "No links match your search."}
                    </td>
                  </tr>
                  <%= for link <- @visible do %>
                    <tr id={"link-#{link.id}"}>
                      <td class="max-w-md">
                        <a
                          href={link.target_url}
                          target="_blank"
                          rel="noopener"
                          class="text-primary hover:underline block truncate"
                        >
                          {link.target_url}
                        </a>
                        <p class="text-xs opacity-60 truncate">
                          <span :if={@current_user.admin}>by {link.owner.email}</span>
                          <span :if={@current_user.admin && link.description}>·</span>
                          {link.description}
                        </p>
                      </td>
                      <td class="whitespace-nowrap" title={link.inserted_at}>
                        {RelativeTime.ago(link.inserted_at)}
                      </td>
                      <td class="whitespace-nowrap">
                        <div class="flex items-center gap-1">
                          <button
                            type="button"
                            class="btn btn-ghost btn-xs text-success"
                            title="Copy to clipboard"
                            phx-click={JS.dispatch("phx:copy", detail: %{text: short_url(link)})}
                          >
                            <.icon name="hero-clipboard-document" class="w-4 h-4" />
                          </button>
                          <a
                            href={short_url(link)}
                            target="_blank"
                            rel="noopener"
                            class="text-primary hover:underline"
                          >
                            {link.domain.hostname}/{link.slug}
                          </a>
                          <.icon
                            :if={link.password_hash}
                            name="hero-lock-closed"
                            class="w-3.5 h-3.5 opacity-50"
                          />
                          <span
                            :if={link.expires_at}
                            class="text-xs opacity-50"
                            title={link.expires_at}
                          >
                            {RelativeTime.until(link.expires_at)}
                          </span>
                        </div>
                      </td>
                      <td class="text-right font-semibold">{Map.get(@click_counts, link.id, 0)}</td>
                      <td class="whitespace-nowrap text-right">
                        <.link
                          navigate={~p"/links/#{link.id}/stats"}
                          class="btn btn-ghost btn-xs"
                          title="Statistics"
                        >
                          <.icon name="hero-chart-pie" class="w-4 h-4 text-secondary" />
                        </.link>
                        <a
                          href={~p"/qr/#{link.id}"}
                          target="_blank"
                          rel="noopener"
                          class="btn btn-ghost btn-xs"
                          title="QR code"
                        >
                          <.icon name="hero-qr-code" class="w-4 h-4" />
                        </a>
                        <button
                          type="button"
                          class="btn btn-ghost btn-xs"
                          title="Edit"
                          phx-click="edit"
                          phx-value-id={link.id}
                        >
                          <.icon name="hero-pencil" class="w-4 h-4 text-warning" />
                        </button>
                        <button
                          type="button"
                          class="btn btn-ghost btn-xs"
                          title="Delete"
                          phx-click="delete"
                          phx-value-id={link.id}
                          data-confirm="Delete this link?"
                        >
                          <.icon name="hero-trash" class="w-4 h-4 text-error" />
                        </button>
                      </td>
                    </tr>
                    <tr :if={@edit_id == link.id} id={"edit-#{link.id}"}>
                      <td colspan="5" class="bg-base-200/30">
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
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
