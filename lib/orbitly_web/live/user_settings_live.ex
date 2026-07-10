defmodule OrbitlyWeb.UserSettingsLive do
  @moduledoc """
  Self-service account settings: change password (requires the current
  password). On success all of the user's tokens are dropped
  (log-out-everywhere), so the form is re-submitted to `POST /session`
  via phx-trigger-action to mint a fresh session with the new password.
  Design/mode switching lives in the navbar gear menu, not here.
  """

  use OrbitlyWeb, :live_view

  on_mount {OrbitlyWeb.UserAuth, :live_user_required}

  alias Orbitly.Accounts
  alias Orbitly.Shortener.RateLimiter

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    {:ok,
     socket
     |> assign(:page_title, "Settings")
     |> assign(:current_email, user.email)
     |> assign(:current_password, nil)
     |> assign(:trigger_submit, false)
     |> assign(:password_form, to_form(Accounts.change_user_password(user), as: "user"))}
  end

  @impl true
  def handle_event("validate_password", params, socket) do
    %{"current_password" => current_password, "user" => user_params} = params

    password_form =
      socket.assigns.current_user
      |> Accounts.change_user_password(user_params)
      |> Map.put(:action, :validate)
      |> to_form(as: "user")

    {:noreply, assign(socket, password_form: password_form, current_password: current_password)}
  end

  def handle_event("update_password", params, socket) do
    %{"current_password" => current_password, "user" => user_params} = params
    user = socket.assigns.current_user

    # LiveView events bypass the AuthRateLimit plug (websocket, not HTTP) —
    # throttle current-password guesses here, like UserForgotPasswordLive.
    if not allow_password_change?(user) do
      {:noreply,
       put_flash(socket, :error, "Too many attempts — please wait a few minutes and try again")}
    else
      update_password(socket, user, current_password, user_params)
    end
  end

  defp allow_password_change?(user) do
    RateLimiter.allow?("password_change:" <> user.id, 5, :timer.minutes(15))
  end

  defp update_password(socket, user, current_password, user_params) do
    case Accounts.update_user_password(user, current_password, user_params) do
      {:ok, user} ->
        password_form =
          user
          |> Accounts.change_user_password(user_params)
          |> to_form(as: "user")

        {:noreply, assign(socket, trigger_submit: true, password_form: password_form)}

      {:error, changeset} ->
        {:noreply, assign(socket, password_form: to_form(changeset, as: "user"))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="mx-auto max-w-md space-y-6 pt-8">
        <header>
          <h1 class="text-2xl font-bold">Settings</h1>
          <p class="text-sm opacity-60">{@current_email}</p>
        </header>

        <section class="card bg-base-100 border border-base-200 shadow-sm">
          <div class="card-body space-y-2">
            <h2 class="card-title text-base">Change password</h2>
            <.form
              for={@password_form}
              id="password-form"
              action={~p"/session?_action=password-updated"}
              method="post"
              phx-change="validate_password"
              phx-submit="update_password"
              phx-trigger-action={@trigger_submit}
            >
              <input
                type="hidden"
                name="user[email]"
                value={@current_email}
                autocomplete="username"
              />
              <.input
                field={@password_form[:password]}
                type="password"
                label="New password"
                autocomplete="new-password"
                required
              />
              <.input
                field={@password_form[:password_confirmation]}
                type="password"
                label="Confirm new password"
                autocomplete="new-password"
                required
              />
              <.input
                field={@password_form[:current_password]}
                name="current_password"
                id="current_password_for_password"
                type="password"
                label="Current password"
                value={@current_password}
                autocomplete="current-password"
                required
              />
              <.button class="btn btn-primary mt-2" phx-disable-with="Saving…">
                Save password
              </.button>
            </.form>
            <p class="text-xs opacity-50">
              Changing the password signs out every other session of this account.
            </p>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
