defmodule OrbitlyWeb.UserLoginLive do
  use OrbitlyWeb, :live_view

  on_mount {OrbitlyWeb.UserAuth, :live_no_user}

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="mx-auto max-w-sm space-y-6 pt-12">
        <.header>
          Sign in
          <:subtitle>Stylite Orbit-ly</:subtitle>
        </.header>

        <.form for={@form} id="login_form" action={~p"/session"} phx-update="ignore" class="space-y-4">
          <.input field={@form[:email]} type="email" label="Email" autocomplete="username" required />
          <.input
            field={@form[:password]}
            type="password"
            label="Password"
            autocomplete="current-password"
            required
          />
          <.button phx-disable-with="Signing in…" class="btn btn-primary w-full">
            Sign in <span aria-hidden="true">→</span>
          </.button>
        </.form>

        <p class="text-center text-sm opacity-70">
          <.link href={~p"/reset"} class="link link-hover">Forgot your password?</.link>
        </p>
      </div>
    </Layouts.app>
    """
  end

  def mount(_params, _session, socket) do
    email = Phoenix.Flash.get(socket.assigns.flash, :email)
    form = to_form(%{"email" => email}, as: "user")
    {:ok, assign(socket, form: form), temporary_assigns: [form: form]}
  end
end
