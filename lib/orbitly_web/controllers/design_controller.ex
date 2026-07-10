defmodule OrbitlyWeb.DesignController do
  @moduledoc """
  Persists the user's design choice (see `OrbitlyWeb.Design`) in a year-long
  cookie plus the session, then sends them back where they came from. A full
  redirect (instead of a LiveView event) keeps the mechanism identical for
  static and live pages and lets the root layout render the right theme
  without any client-side script.
  """

  use OrbitlyWeb, :controller

  alias OrbitlyWeb.Design

  @design_cookie "orbitly_design"
  @mode_cookie "orbitly_mode"
  @max_age 60 * 60 * 24 * 365

  def update(conn, %{"design" => design}) do
    design = Design.validate(design)

    conn
    |> put_resp_cookie(@design_cookie, design, max_age: @max_age, same_site: "Lax")
    |> put_session(:design, design)
    |> redirect(to: return_path(conn))
  end

  def update_mode(conn, %{"mode" => mode}) do
    case Design.validate_mode(mode) do
      nil ->
        redirect(conn, to: return_path(conn))

      mode ->
        conn
        |> put_resp_cookie(@mode_cookie, mode, max_age: @max_age, same_site: "Lax")
        |> redirect(to: return_path(conn))
    end
  end

  # Only follow local paths from the referer; anything else goes home.
  # Rejects "//host" and backslashes (browsers normalize "\" to "/", which
  # would turn "/\evil.com" into a protocol-relative redirect).
  defp return_path(conn) do
    with [referer] <- get_req_header(conn, "referer"),
         %URI{path: path} when is_binary(path) <- URI.parse(referer),
         true <- String.starts_with?(path, "/"),
         false <- String.starts_with?(path, "//"),
         false <- String.contains?(path, "\\") do
      path
    else
      _ -> ~p"/"
    end
  end
end
