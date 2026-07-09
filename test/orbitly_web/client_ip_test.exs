defmodule OrbitlyWeb.ClientIPTest do
  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn

  alias OrbitlyWeb.ClientIP

  defp conn_with(xff, remote_ip \\ {10, 0, 0, 1}) do
    conn = %{conn(:get, "/") | remote_ip: remote_ip}

    case xff do
      nil -> conn
      value -> put_req_header(conn, "x-forwarded-for", value)
    end
  end

  test "falls back to the peer address when no XFF header is present" do
    assert ClientIP.get(conn_with(nil, {203, 0, 113, 9})) == "203.0.113.9"
  end

  test "with one trusted hop, takes the last (proxy-appended) entry" do
    # attacker-controlled first entry, real client appended by the proxy
    assert ClientIP.get(conn_with("1.2.3.4, 198.51.100.5")) == "198.51.100.5"
  end

  test "a single-entry header (proxy replaced it) is used directly" do
    assert ClientIP.get(conn_with("198.51.100.7")) == "198.51.100.7"
  end

  test "spoofing extra left entries does not change the result" do
    assert ClientIP.get(conn_with("9.9.9.9, 8.8.8.8, 198.51.100.5")) == "198.51.100.5"
  end
end
