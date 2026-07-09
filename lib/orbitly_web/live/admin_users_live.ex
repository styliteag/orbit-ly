defmodule OrbitlyWeb.AdminUsersLive do
  @moduledoc """
  Instance-admin user management (ADR-0006): create accounts with an initial
  password, grant/revoke admin, delete. Open registration stays disabled.
  """

  use OrbitlyWeb, :live_view

  on_mount {OrbitlyWeb.LiveUserAuth, :live_admin_required}

  alias Orbitly.Accounts
  alias Orbitly.Accounts.User

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Users")
     |> load_users()
     |> assign_new_form()}
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    {:noreply, assign(socket, :form, AshPhoenix.Form.validate(socket.assigns.form, params))}
  end

  def handle_event("save", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, user} ->
        {:noreply,
         socket
         |> put_flash(:info, "User #{user.email} created")
         |> load_users()
         |> assign_new_form()}

      {:error, form} ->
        {:noreply, assign(socket, :form, form)}
    end
  end

  def handle_event("toggle-admin", %{"id" => id}, socket) do
    with %User{} = user <- find(socket, id),
         false <- me?(socket, user),
         {:ok, _} <-
           Accounts.set_admin(user, %{admin: !user.admin}, actor: socket.assigns.current_user) do
      {:noreply, load_users(socket)}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not update user")}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    with %User{} = user <- find(socket, id),
         false <- me?(socket, user),
         :ok <- Accounts.destroy_user(user, actor: socket.assigns.current_user) do
      {:noreply, socket |> put_flash(:info, "User deleted") |> load_users()}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not delete user")}
    end
  end

  defp find(socket, id), do: Enum.find(socket.assigns.users, &(&1.id == id))
  defp me?(socket, user), do: user.id == socket.assigns.current_user.id

  defp load_users(socket) do
    {:ok, users} = Accounts.list_users(actor: socket.assigns.current_user)
    assign(socket, :users, Enum.sort_by(users, &to_string(&1.email)))
  end

  defp assign_new_form(socket) do
    form =
      AshPhoenix.Form.for_create(User, :admin_create,
        actor: socket.assigns.current_user,
        as: "form"
      )

    assign(socket, :form, to_form(form))
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
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
