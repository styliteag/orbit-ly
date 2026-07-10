defmodule OrbitlyWeb.UserSessionControllerTest do
  use OrbitlyWeb.ConnCase, async: false

  import Orbitly.Fixtures

  setup do
    %{user: registered_user_fixture()}
  end

  describe "POST /session" do
    test "logs the user in and grants access to protected pages", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/session", %{
          "user" => %{"email" => user.email, "password" => default_password()}
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/links"

      # the session now reaches an authenticated LiveView without redirecting
      conn = get(conn, ~p"/links")
      assert html_response(conn, 200) =~ "Cut your links"
    end

    test "rejects an invalid password", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/session", %{
          "user" => %{"email" => user.email, "password" => "wrong-password"}
        })

      refute get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/sign-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Incorrect email or password"
    end
  end

  describe "DELETE /sign-out" do
    test "logs the user out", %{conn: conn, user: user} do
      conn = conn |> log_in(user) |> delete(~p"/sign-out")

      refute get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"
    end

    test "succeeds even when no user is signed in", %{conn: conn} do
      conn = delete(conn, ~p"/sign-out")

      refute get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"
    end
  end
end
