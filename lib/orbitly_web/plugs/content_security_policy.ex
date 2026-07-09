defmodule OrbitlyWeb.Plugs.ContentSecurityPolicy do
  @moduledoc """
  Sets a strict Content-Security-Policy. Scripts and styles load from the
  app's own bundle ('self'); the one inline script (theme setup in
  root.html.heex) is allowed via a per-request nonce assigned as
  `:csp_nonce`. Inline styles are permitted because LiveView transitions and
  utility classes emit them — far lower risk than inline scripts.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    nonce = 18 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
    conn = assign(conn, :csp_nonce, nonce)

    # Disabled in dev (config/dev.exs) so Phoenix LiveReload's injected
    # iframe/inline script keeps working; enforced everywhere else.
    if Application.get_env(:orbitly, :csp_enabled, true) do
      put_resp_header(conn, "content-security-policy", policy(nonce))
    else
      conn
    end
  end

  defp policy(nonce) do
    Enum.join(
      [
        "default-src 'self'",
        "script-src 'self' 'nonce-#{nonce}'",
        "style-src 'self' 'unsafe-inline'",
        "img-src 'self' data:",
        "font-src 'self' data:",
        "connect-src 'self'",
        "base-uri 'self'",
        "form-action 'self'",
        "frame-ancestors 'none'",
        "object-src 'none'"
      ],
      "; "
    )
  end
end
