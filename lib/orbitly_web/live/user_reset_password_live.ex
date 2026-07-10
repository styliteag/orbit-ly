defmodule OrbitlyWeb.UserResetPasswordLive do
  use OrbitlyWeb, :live_view

  on_mount {OrbitlyWeb.UserAuth, :live_no_user}

  alias Orbitly.Accounts

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="mx-auto max-w-sm space-y-6 pt-12">
        <.header>Reset your password</.header>

        <.form
          for={@form}
          id="reset_password_form"
          phx-change="validate"
          phx-submit="reset_password"
          class="space-y-4"
        >
          <.input field={@form[:password]} type="password" label="New password" required />
          <.input
            field={@form[:password_confirmation]}
            type="password"
            label="Confirm new password"
            required
          />
          <.button phx-disable-with="Resetting…" class="btn btn-primary w-full">
            Reset password
          </.button>
        </.form>

        <p class="text-center text-sm opacity-70">
          <.link href={~p"/sign-in"} class="link link-hover">Back to sign in</.link>
        </p>
      </div>
    </Layouts.app>
    """
  end

  def mount(%{"token" => token}, _session, socket) do
    socket = assign_user_and_token(socket, token)

    form =
      case socket.assigns do
        %{user: user} -> to_form(Accounts.change_user_password(user), as: "user")
        _ -> nil
      end

    {:ok, assign(socket, :form, form), temporary_assigns: [form: nil]}
  end

  def handle_event("validate", %{"user" => params}, socket) do
    changeset =
      socket.assigns.user
      |> Accounts.change_user_password(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: "user"))}
  end

  def handle_event("reset_password", %{"user" => params}, socket) do
    case Accounts.reset_user_password(socket.assigns.user, params) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Password reset successfully.")
         |> redirect(to: ~p"/sign-in")}

      {:error, changeset} ->
        {:noreply,
         assign(socket, form: to_form(Map.put(changeset, :action, :insert), as: "user"))}
    end
  end

  defp assign_user_and_token(socket, token) do
    if user = Accounts.get_user_by_reset_password_token(token) do
      assign(socket, user: user, token: token)
    else
      socket
      |> put_flash(:error, "Reset link is invalid or it has expired.")
      |> redirect(to: ~p"/")
    end
  end
end
