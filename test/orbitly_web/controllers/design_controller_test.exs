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

  test "each design defaults to its own mode", %{conn: conn} do
    assert get(conn, ~p"/sign-in") |> html_response(200) =~ ~s(data-theme="orbit-dark")

    conn = put(conn, ~p"/design/bench")
    assert get(conn, ~p"/sign-in") |> html_response(200) =~ ~s(data-theme="bench-light")
  end

  test "PUT /design-mode/:mode overrides the mode for any design", %{conn: conn} do
    conn = put(conn, ~p"/design-mode/light")
    assert conn.resp_cookies["orbitly_mode"].value == "light"
    assert get(conn, ~p"/sign-in") |> html_response(200) =~ ~s(data-theme="orbit-light")

    conn = put(conn, ~p"/design/soft")
    conn = put(conn, ~p"/design-mode/dark")
    assert get(conn, ~p"/sign-in") |> html_response(200) =~ ~s(data-theme="soft-dark")
  end

  test "an invalid mode is ignored", %{conn: conn} do
    conn = put(conn, ~p"/design-mode/neon")

    assert redirected_to(conn) == "/"
    refute Map.has_key?(conn.resp_cookies, "orbitly_mode")
    assert get(conn, ~p"/sign-in") |> html_response(200) =~ ~s(data-theme="orbit-dark")
  end
end
