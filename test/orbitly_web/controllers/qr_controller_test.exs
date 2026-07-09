defmodule OrbitlyWeb.QrControllerTest do
  use OrbitlyWeb.ConnCase, async: false

  import Orbitly.Fixtures

  setup do
    user = registered_user_fixture()
    domain = domain_fixture(%{hostname: "go.example"})
    link = link_fixture(user, domain, %{slug: "qr-me"})

    %{user: user, link: link}
  end

  test "owner gets an SVG containing the QR code", %{conn: conn, user: user, link: link} do
    conn = conn |> log_in(user) |> get(~p"/qr/#{link.id}")

    assert conn.status == 200
    assert response_content_type(conn, :svg) =~ "image/svg+xml"
    assert conn.resp_body =~ "<svg"
  end

  test "other users get 404", %{conn: conn, link: link} do
    other = registered_user_fixture()

    conn = conn |> log_in(other) |> get(~p"/qr/#{link.id}")

    assert conn.status == 404
  end

  test "anonymous visitors get 404", %{conn: conn, link: link} do
    conn = get(conn, ~p"/qr/#{link.id}")

    assert conn.status == 404
  end
end
