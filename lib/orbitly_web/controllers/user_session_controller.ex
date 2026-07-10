defmodule OrbitlyWeb.UserSessionController do
  use OrbitlyWeb, :controller

  alias Orbitly.Accounts
  alias OrbitlyWeb.UserAuth

  # Re-login after a self-service password change (UserSettingsLive posts
  # here via phx-trigger-action because the change drops all tokens).
  def create(conn, %{"_action" => "password-updated"} = params) do
    conn
    |> put_session(:user_return_to, ~p"/settings")
    |> do_create(params, "Password updated successfully")
  end

  def create(conn, params) do
    do_create(conn, params, "You are now signed in")
  end

  defp do_create(conn, %{"user" => %{"email" => email, "password" => password} = params}, info) do
    if user = Accounts.get_user_by_email_and_password(email, password) do
      conn
      |> put_flash(:info, info)
      |> UserAuth.log_in_user(user, params)
    else
      conn
      |> put_flash(:error, "Incorrect email or password")
      |> redirect(to: ~p"/sign-in")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "You are now signed out")
    |> UserAuth.log_out_user()
  end
end
