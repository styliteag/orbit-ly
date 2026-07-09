defmodule OrbitlyWeb.Redirector do
  @moduledoc """
  Redirect hot path (ADR-0001/0003/0004), placed in the endpoint just before
  the router.

  - Host unknown/inactive: pass to the router when `:serve_ui_on_unknown_hosts`
    is set (dev/test), otherwise plain 404 (prod, ADR-0003).
  - Known host, single-segment non-reserved GET/HEAD path: resolve the slug.
    Expired links answer 410; password-protected links render an unlock form
    (POST to the same path, no session needed).
  - Everything else passes to the router on the primary domain (UI) and 404s
    on pure redirect hosts.
  """

  import Plug.Conn

  alias Orbitly.Shortener.{ClickBuffer, RateLimiter, RedirectCache, Slug}

  # brute-force window for the unlock form, per client IP and slug
  @unlock_attempts 5
  @unlock_window_ms :timer.minutes(1)

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case RedirectCache.fetch_domain(conn.host) do
      {:ok, %{active: true} = domain} -> handle_known_host(conn, domain)
      _ -> unknown_host(conn)
    end
  end

  defp handle_known_host(%{method: method} = conn, domain)
       when method in ["GET", "HEAD", "POST"] do
    case candidate_slugs(conn.path_info, domain) do
      [] -> pass_or_404(conn, domain)
      slugs -> resolve(conn, domain, slugs)
    end
  end

  defp handle_known_host(conn, domain), do: pass_or_404(conn, domain)

  # Stored slugs to try, in priority order. Special links live on custom
  # (non-primary) domains only: the root is `""`, the catch-all is `"*"`. The
  # primary domain keeps its mixed UI/redirect behaviour — only real slugs
  # resolve there, everything else falls through to the router.
  defp candidate_slugs([], %{is_primary: false}), do: ["", "*"]

  defp candidate_slugs([segment], %{is_primary: primary?}) do
    cond do
      Slug.valid_format?(segment) and not Slug.reserved?(segment) ->
        if primary?, do: [segment], else: [segment, "*"]

      primary? ->
        []

      true ->
        ["*"]
    end
  end

  defp candidate_slugs(_multi_segment, %{is_primary: false}), do: ["*"]
  defp candidate_slugs(_path, _domain), do: []

  defp resolve(conn, domain, slugs) do
    case first_link(conn.host, slugs) do
      :not_found ->
        pass_or_404(conn, domain)

      {:ok, link} ->
        cond do
          expired?(link) -> gone(conn)
          is_binary(link.password_hash) -> unlock(conn, domain, link)
          conn.method == "POST" -> pass_or_404(conn, domain)
          true -> redirect_to_target(conn, link)
        end
    end
  end

  defp first_link(_host, []), do: :not_found

  defp first_link(host, [slug | rest]) do
    case RedirectCache.fetch_link(host, slug) do
      {:ok, link} -> {:ok, link}
      :not_found -> first_link(host, rest)
    end
  end

  defp expired?(%{expires_at: nil}), do: false

  defp expired?(%{expires_at: expires_at}),
    do: DateTime.compare(expires_at, DateTime.utc_now()) != :gt

  # Password-protected link: GET renders the unlock form, POST verifies.
  defp unlock(%{method: "POST"} = conn, _domain, link) do
    rate_key = {:unlock, client_ip(conn), link.link_id}

    cond do
      not RateLimiter.allow?(rate_key, @unlock_attempts, @unlock_window_ms) ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(429, "Too Many Requests")
        |> halt()

      Bcrypt.verify_pass(conn.body_params["password"] || "", link.password_hash) ->
        RateLimiter.reset(rate_key)
        redirect_to_target(conn, link)

      true ->
        password_form(conn, 401, wrong_password: true)
    end
  end

  defp unlock(conn, _domain, _link), do: password_form(conn, 200, wrong_password: false)

  defp redirect_to_target(conn, link) do
    track_click(conn, link)

    conn
    |> put_resp_header("location", link.target_url)
    |> put_resp_header("cache-control", "no-store")
    |> send_resp(302, "")
    |> halt()
  end

  defp track_click(conn, link) do
    ClickBuffer.record(%{
      link_id: link.link_id,
      occurred_at: DateTime.utc_now(),
      ip: client_ip(conn),
      user_agent: first_header(conn, "user-agent"),
      referrer: first_header(conn, "referer")
    })
  end

  defp client_ip(conn), do: OrbitlyWeb.ClientIP.get(conn)

  defp first_header(conn, name) do
    case get_req_header(conn, name) do
      [value | _] -> value
      [] -> nil
    end
  end

  defp pass_or_404(conn, %{is_primary: true}), do: conn
  defp pass_or_404(conn, _domain), do: not_found(conn)

  defp unknown_host(conn) do
    if Application.get_env(:orbitly, :serve_ui_on_unknown_hosts, false) do
      conn
    else
      not_found(conn)
    end
  end

  defp not_found(conn) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(404, "Not Found")
    |> halt()
  end

  defp gone(conn) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(410, "Gone")
    |> halt()
  end

  defp password_form(conn, status, wrong_password: wrong?) do
    error = if wrong?, do: "<p>Wrong password, try again.</p>", else: ""

    body = """
    <!DOCTYPE html>
    <html>
      <head><meta charset="utf-8"><title>Password required</title></head>
      <body>
        <h1>This link is password-protected</h1>
        #{error}
        <form method="post">
          <input type="password" name="password" autofocus required>
          <button type="submit">Unlock</button>
        </form>
      </body>
    </html>
    """

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(status, body)
    |> halt()
  end
end
