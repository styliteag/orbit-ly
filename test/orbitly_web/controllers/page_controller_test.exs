defmodule OrbitlyWeb.PageControllerTest do
  use OrbitlyWeb.ConnCase, async: false

  import Orbitly.Fixtures

  test "GET / redirects anonymous visitors to sign-in", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/sign-in"
  end

  test "GET / redirects signed-in users to their links", %{conn: conn} do
    conn = conn |> log_in(registered_user_fixture()) |> get(~p"/")
    assert redirected_to(conn) == ~p"/links"
  end
end
