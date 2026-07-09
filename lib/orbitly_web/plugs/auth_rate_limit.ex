defmodule OrbitlyWeb.Plugs.AuthRateLimit do
  @moduledoc """
  Throttles credential-submitting requests (sign-in, password-reset request)
  per client IP. Guards the AshAuthentication controller endpoints under
  `/auth`, which are the surface a scripted brute-force / e-mail-bomb attack
  hits. Only mutating methods are limited so page loads are unaffected.
  """

  import Plug.Conn

  alias Orbitly.Shortener.RateLimiter
  alias OrbitlyWeb.ClientIP

  @limit 10
  @window_ms :timer.minutes(1)

  def init(opts), do: opts

  def call(%{method: method} = conn, _opts) when method in ["POST", "PUT", "PATCH"] do
    key = {:auth, ClientIP.get(conn), Enum.take(conn.path_info, 4)}

    if RateLimiter.allow?(key, @limit, @window_ms) do
      conn
    else
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(429, "Too Many Requests")
      |> halt()
    end
  end

  def call(conn, _opts), do: conn
end
