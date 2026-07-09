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

  test "the inline theme script carries the matching nonce", %{conn: conn} do
    conn = get(conn, ~p"/sign-in")
    [csp] = get_resp_header(conn, "content-security-policy")
    [_, nonce] = Regex.run(~r/'nonce-([A-Za-z0-9_-]+)'/, csp)

    assert html_response(conn, 200) =~ ~s(nonce="#{nonce}")
  end
end
