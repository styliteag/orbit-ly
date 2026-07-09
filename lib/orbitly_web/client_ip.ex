defmodule OrbitlyWeb.ClientIP do
  @moduledoc """
  Resolves the real client IP behind the trusted reverse proxy (ADR-0003).

  In production `conn.remote_ip` is the proxy/container address — the client
  IP is only in `x-forwarded-for`. That header is client-controllable at its
  *left* end, so taking the first entry is spoofable. We instead take the
  entry the trusted proxy appended: with `trusted_proxy_hops` proxies in
  front of the app, the real client is the `hops`-th entry from the right.

  A single trusted proxy that appends (`X-Forwarded-For: <spoofed>, <real>`)
  or replaces the header both yield the real client as the last entry, which
  the client cannot forge. Set `:trusted_proxy_hops` to match the deployment.
  """

  import Plug.Conn, only: [get_req_header: 2]

  @spec get(Plug.Conn.t()) :: String.t()
  def get(conn) do
    hops = Application.get_env(:orbitly, :trusted_proxy_hops, 1)

    case get_req_header(conn, "x-forwarded-for") do
      [forwarded | _] -> from_forwarded(forwarded, hops) || peer(conn)
      [] -> peer(conn)
    end
  end

  defp from_forwarded(forwarded, hops) do
    entries =
      forwarded
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    # real client sits `hops` positions from the right; clamp to the first
    # entry if the header is shorter than expected
    index = max(length(entries) - hops, 0)
    Enum.at(entries, index)
  end

  defp peer(conn), do: conn.remote_ip |> :inet.ntoa() |> to_string()
end
