defmodule OrbitlyWeb.Plugs.ContentSecurityPolicyTest do
  # csp_enabled is true in test config; the browser pipeline runs the plug.
  use OrbitlyWeb.ConnCase, async: true

  test "sets a strict CSP header with a per-request script nonce", %{conn: conn} do
    conn = get(conn, ~p"/sign-in")

    [csp] = get_resp_header(conn, "content-security-policy")

    assert csp =~ "default-src 'self'"
    assert csp =~ "object-src 'none'"
    assert csp =~ "frame-ancestors 'none'"
    assert csp =~ ~r/script-src 'self' 'nonce-[A-Za-z0-9_-]+'/
  end

  test "the nonce changes between requests", %{conn: conn} do
    nonce = fn c ->
      [csp] = get_resp_header(get(c, ~p"/sign-in"), "content-security-policy")
      csp
    end

    refute nonce.(conn) == nonce.(build_conn())
  end

  # The design/theme is server-rendered as a data-theme attribute (no inline
  # script needed since the theme toggle became the design switcher). Any new
  # inline script must carry nonce={assigns[:csp_nonce]} — see CLAUDE.md.
  test "the root layout ships no inline script", %{conn: conn} do
    conn = get(conn, ~p"/sign-in")
    html = html_response(conn, 200)

    assert html =~ ~s(data-theme="orbit")
    refute html =~ ~r/<script(?![^>]*src=)[^>]*>/
  end
end
