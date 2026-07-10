defmodule OrbitlyWeb.UserSessionController do
  use OrbitlyWeb, :controller

  alias Orbitly.Accounts
  alias OrbitlyWeb.UserAuth

  def create(conn, %{"user" => %{"email" => email, "password" => password} = params}) do
    if user = Accounts.get_user_by_email_and_password(email, password) do
      conn
      |> put_flash(:info, "You are now signed in")
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
