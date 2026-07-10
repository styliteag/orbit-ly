defmodule OrbitlyWeb.UserAuth do
  @moduledoc """
  Session-based authentication (plain Phoenix, phx.gen.auth model): plugs for
  the controller pipeline and `on_mount` hooks for LiveViews. Replaces the
  AshAuthentication.Phoenix wiring.
  """

  use OrbitlyWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias Orbitly.Accounts

  @doc """
  Logs the user in: mints a session token, renews the session (fixation
  defense) and redirects to the stored return path or the dashboard.
  """
  def log_in_user(conn, user, _params \\ %{}) do
    token = Accounts.generate_user_session_token(user)
    user_return_to = get_session(conn, :user_return_to)

    conn
    |> renew_session()
    |> put_token_in_session(token)
    |> redirect(to: user_return_to || signed_in_path(conn))
  end

  @doc "Logs the user out: deletes the session token and disconnects live sessions."
  def log_out_user(conn) do
    user_token = get_session(conn, :user_token)
    user_token && Accounts.delete_user_session_token(user_token)

    if live_socket_id = get_session(conn, :live_socket_id) do
      OrbitlyWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> renew_session()
    |> redirect(to: ~p"/")
  end

  defp renew_session(conn) do
    delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  defp put_token_in_session(conn, token) do
    conn
    |> put_session(:user_token, token)
    |> put_session(:live_socket_id, "users_sessions:#{Base.url_encode64(token)}")
  end

  @doc "Plug: assigns `:current_user` from the session token."
  def fetch_current_user(conn, _opts) do
    user_token = get_session(conn, :user_token)
    user = user_token && Accounts.get_user_by_session_token(user_token)
    assign(conn, :current_user, user)
  end

  @doc "Plug: redirects logged-in users away from auth-only pages (sign-in)."
  def redirect_if_user_is_authenticated(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
      |> redirect(to: signed_in_path(conn))
      |> halt()
    else
      conn
    end
  end

  @doc "Plug: requires an authenticated user, else redirects to sign-in."
  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, "You must log in to access this page.")
      |> maybe_store_return_to()
      |> redirect(to: ~p"/sign-in")
      |> halt()
    end
  end

  defp maybe_store_return_to(%{method: "GET"} = conn),
    do: put_session(conn, :user_return_to, current_path(conn))

  defp maybe_store_return_to(conn), do: conn

  defp signed_in_path(_conn), do: ~p"/links"

  ## LiveView on_mount hooks

  def on_mount(:mount_current_user, _params, session, socket) do
    {:cont, mount_current_user(socket, session)}
  end

  # Kept for compatibility with the old hook name.
  def on_mount(:current_user, _params, session, socket) do
    {:cont, mount_current_user(socket, session)}
  end

  def on_mount(:live_user_optional, _params, session, socket) do
    {:cont, mount_current_user(socket, session)}
  end

  def on_mount(:live_user_required, _params, session, socket) do
    socket = mount_current_user(socket, session)

    if socket.assigns.current_user do
      {:cont, socket}
    else
      {:halt,
       socket
       |> Phoenix.LiveView.put_flash(:error, "You must log in to access this page.")
       |> Phoenix.LiveView.redirect(to: ~p"/sign-in")}
    end
  end

  def on_mount(:live_admin_required, _params, session, socket) do
    socket = mount_current_user(socket, session)

    case socket.assigns.current_user do
      %{admin: true} -> {:cont, socket}
      %{} -> {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/links")}
      _ -> {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/sign-in")}
    end
  end

  def on_mount(:live_no_user, _params, session, socket) do
    socket = mount_current_user(socket, session)

    if socket.assigns.current_user do
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/")}
    else
      {:cont, socket}
    end
  end

  defp mount_current_user(socket, session) do
    Phoenix.Component.assign_new(socket, :current_user, fn ->
      if token = session["user_token"] do
        Accounts.get_user_by_session_token(token)
      end
    end)
  end
end
