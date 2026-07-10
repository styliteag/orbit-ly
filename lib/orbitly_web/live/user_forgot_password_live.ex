defmodule OrbitlyWeb.UserForgotPasswordLive do
  use OrbitlyWeb, :live_view

  on_mount {OrbitlyWeb.UserAuth, :live_no_user}

  alias Orbitly.Accounts
  alias Orbitly.Shortener.RateLimiter

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="mx-auto max-w-sm space-y-6 pt-12">
        <.header>
          Forgot your password?
          <:subtitle>We'll send a reset link to your inbox</:subtitle>
        </.header>

        <.form for={@form} id="reset_password_form" phx-submit="send_email" class="space-y-4">
          <.input field={@form[:email]} type="email" label="Email" required />
          <.button phx-disable-with="Sending…" class="btn btn-primary w-full">
            Send reset instructions
          </.button>
        </.form>

        <p class="text-center text-sm opacity-70">
          <.link href={~p"/sign-in"} class="link link-hover">Back to sign in</.link>
        </p>
      </div>
    </Layouts.app>
    """
  end

  def mount(_params, _session, socket) do
    {:ok, assign(socket, form: to_form(%{}, as: "user"))}
  end

  def handle_event("send_email", %{"user" => %{"email" => email}}, socket) do
    # Reset requests run over the LiveView socket, so the AuthRateLimit HTTP plug
    # cannot see them — throttle per target address here (caps e-mail flooding
    # and users_tokens growth). The response is generic either way, so this leaks
    # nothing about which addresses exist.
    if allow_reset?(email) do
      if user = Accounts.get_user_by_email(email) do
        Accounts.deliver_user_reset_password_instructions(
          user,
          &url(~p"/password-reset/#{&1}")
        )
      end
    end

    info =
      "If your email is in our system, you will receive password reset instructions shortly."

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> redirect(to: ~p"/")}
  end

  defp allow_reset?(email) do
    key = "password_reset:" <> String.downcase(String.trim(to_string(email)))
    RateLimiter.allow?(key, 3, :timer.minutes(60))
  end
end
