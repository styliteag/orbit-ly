defmodule OrbitlyWeb.AdminUsersLive do
  @moduledoc """
  Instance-admin user management (ADR-0006): create accounts with an initial
  password, grant/revoke admin, delete, and set each user's domain access
  (all domains or a granted list) plus their default domain. Open
  registration stays disabled.
  """

  use OrbitlyWeb, :live_view

  on_mount {OrbitlyWeb.UserAuth, :live_admin_required}

  alias Orbitly.Accounts
  alias Orbitly.Accounts.User
  alias Orbitly.Shortener

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Users")
     |> load_domains()
     |> load_users()
     |> assign_new_form()}
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    changeset = Accounts.change_user_admin_create(params) |> Map.put(:action, :validate)
    {:noreply, assign(socket, :form, to_form(changeset, as: "form"))}
  end

  def handle_event("save", %{"form" => params}, socket) do
    case Accounts.admin_create_user(params) do
      {:ok, user} ->
        {:noreply,
         socket
         |> put_flash(:info, "User #{user.email} created")
         |> load_users()
         |> assign_new_form()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: "form"))}
    end
  end

  def handle_event("toggle-admin", %{"id" => id}, socket) do
    with %User{} = user <- find(socket, id),
         false <- me?(socket, user),
         {:ok, _} <- Accounts.set_admin(user, !user.admin) do
      {:noreply, load_users(socket)}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not update user")}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    with %User{} = user <- find(socket, id),
         false <- me?(socket, user),
         {:ok, _} <- Accounts.delete_user(user) do
      {:noreply, socket |> put_flash(:info, "User deleted") |> load_users()}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not delete user")}
    end
  end

  def handle_event("save-domain-access", %{"access" => params}, socket) do
    attrs = %{
      all_domains: params["all_domains"],
      domain_ids: List.wrap(params["domain_ids"]),
      default_domain_id: params["default_domain_id"]
    }

    with %User{} = user <- find(socket, params["user_id"]),
         {:ok, _} <- Shortener.set_domain_access(user, attrs, socket.assigns.current_user) do
      {:noreply, socket |> put_flash(:info, "Domain access saved") |> load_users()}
    else
      {:error, :invalid_domain} ->
        {:noreply, put_flash(socket, :error, "Default domain is not available to this user")}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not update domain access")}
    end
  end

  defp find(socket, id), do: Enum.find(socket.assigns.users, &(&1.id == id))
  defp me?(socket, user), do: user.id == socket.assigns.current_user.id

  defp load_users(socket) do
    socket
    |> assign(:users, Enum.sort_by(Accounts.list_users(), &to_string(&1.email)))
    |> assign(:grants, Shortener.grants_by_user())
  end

  # Grantable domains: every non-alias domain (aliases follow their target).
  defp load_domains(socket) do
    domains =
      Shortener.list_domains()
      |> Enum.filter(&is_nil(&1.alias_of_id))
      |> Enum.sort_by(&{!&1.is_primary, &1.hostname})

    assign(socket, :domains, domains)
  end

  defp access_label(%User{admin: true}, _grants), do: nil
  defp access_label(%User{all_domains: true}, _grants), do: nil

  defp access_label(user, grants) do
    case length(Map.get(grants, user.id, [])) do
      1 -> "1 domain"
      n -> "#{n} domains"
    end
  end

  defp assign_new_form(socket) do
    changeset = Accounts.change_user_admin_create()
    assign(socket, :form, to_form(changeset, as: "form"))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="space-y-8">
        <.header>
          Users
          <:subtitle>Accounts are created here — open registration is disabled</:subtitle>
        </.header>

        <.form for={@form} id="user-form" phx-change="validate" phx-submit="save">
          <div class="flex flex-col sm:flex-row gap-2 items-start">
            <div class="flex-1 w-full">
              <.input field={@form[:email]} placeholder="user@example.com" class="input w-full" />
            </div>
            <div class="flex-1 w-full">
              <.input
                type="password"
                field={@form[:password]}
                placeholder="Initial password (min. 8 chars)"
                class="input w-full"
              />
            </div>
            <.button phx-disable-with="Creating…" class="btn btn-primary">
              <.icon name="hero-user-plus" class="w-4 h-4" /> Create user
            </.button>
          </div>
        </.form>

        <div class="space-y-2">
          <div
            :for={user <- @users}
            id={"user-#{user.id}"}
            class="card bg-base-100 border border-base-200 shadow-sm"
          >
            <div class="card-body py-3 px-4 sm:flex-row sm:items-center gap-3">
              <div class="min-w-0 flex-1 flex items-center gap-2">
                <span class="font-semibold truncate">{user.email}</span>
                <span :if={user.admin} class="badge badge-primary badge-sm">admin</span>
                <span :if={user.id == @current_user.id} class="badge badge-ghost badge-sm">you</span>
                <span
                  :if={label = access_label(user, @grants)}
                  class="badge badge-warning badge-sm"
                  title="Restricted domain access"
                >
                  {label}
                </span>
              </div>

              <div :if={user.id != @current_user.id} class="flex items-center gap-2 shrink-0">
                <button
                  type="button"
                  class="btn btn-ghost btn-xs"
                  phx-click="toggle-admin"
                  phx-value-id={user.id}
                >
                  {if user.admin, do: "Revoke admin", else: "Make admin"}
                </button>
                <button
                  type="button"
                  class="btn btn-ghost btn-xs text-error"
                  title="Delete user"
                  phx-click="delete"
                  phx-value-id={user.id}
                  data-confirm="Delete this user and all their links?"
                >
                  <.icon name="hero-trash" class="w-4 h-4" />
                </button>
              </div>
            </div>
            <.domain_access user={user} domains={@domains} granted={Map.get(@grants, user.id, [])} />
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :user, User, required: true
  attr :domains, :list, required: true
  attr :granted, :list, required: true

  defp domain_access(assigns) do
    ~H"""
    <details class="px-4 pb-3">
      <summary class="cursor-pointer text-sm opacity-70">Domains</summary>
      <form id={"domain-access-#{@user.id}"} phx-submit="save-domain-access" class="space-y-3 pt-2">
        <input type="hidden" name="access[user_id]" value={@user.id} />

        <p :if={@user.admin} class="text-xs opacity-60">Admins may always use every domain.</p>

        <div :if={!@user.admin} class="space-y-1">
          <label class="flex items-center gap-2 text-sm">
            <input type="hidden" name="access[all_domains]" value="false" />
            <input
              type="checkbox"
              class="checkbox checkbox-sm"
              name="access[all_domains]"
              value="true"
              checked={@user.all_domains}
            /> All domains (including future ones)
          </label>
          <input type="hidden" name="access[domain_ids][]" value="" />
          <label :for={domain <- @domains} class="flex items-center gap-2 text-sm pl-6">
            <input
              type="checkbox"
              class="checkbox checkbox-xs"
              name="access[domain_ids][]"
              value={domain.id}
              checked={domain.id in @granted}
            />
            {domain.hostname}
            <span :if={!domain.active} class="badge badge-warning badge-xs">inactive</span>
          </label>
        </div>

        <label class="flex items-center gap-2 text-sm">
          Default domain
          <select name="access[default_domain_id]" class="select select-sm">
            <option value="">Automatic</option>
            <option
              :for={domain <- @domains}
              value={domain.id}
              selected={domain.id == @user.default_domain_id}
            >
              {domain.hostname}
            </option>
          </select>
        </label>

        <button type="submit" class="btn btn-primary btn-xs">Save domain access</button>
      </form>
    </details>
    """
  end
end
