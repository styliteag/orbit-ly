defmodule OrbitlyWeb.DesignControllerTest do
  use OrbitlyWeb.ConnCase, async: false

  test "PUT /design/:design sets cookie and session and redirects back", %{conn: conn} do
    conn =
      conn
      |> put_req_header("referer", "http://localhost/links")
      |> put(~p"/design/bench")

    assert redirected_to(conn) == "/links"
    assert conn.resp_cookies["orbitly_design"].value == "bench"
    assert get_session(conn, :design) == "bench"
  end

  test "invalid design falls back to the default", %{conn: conn} do
    conn = put(conn, ~p"/design/purple-unicorn")

    assert redirected_to(conn) == "/"
    assert conn.resp_cookies["orbitly_design"].value == "orbit"
  end

  test "external referers are not followed", %{conn: conn} do
    conn =
      conn
      |> put_req_header("referer", "https://evil.example//phish")
      |> put(~p"/design/soft")

    assert redirected_to(conn) == "/"
  end

  test "backslash referer paths are not followed", %{conn: conn} do
    conn =
      conn
      |> put_req_header("referer", "http://localhost/\\evil.example")
      |> put(~p"/design/soft")

    assert redirected_to(conn) == "/"
  end

  test "design cookie is picked up on later requests", %{conn: conn} do
    conn = put(conn, ~p"/design/soft")
    conn = get(conn, ~p"/sign-in")

    assert get_session(conn, :design) == "soft"
    assert conn.assigns.design == "soft"
  end
end
