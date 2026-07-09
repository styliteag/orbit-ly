defmodule OrbitlyWeb.QrController do
  @moduledoc """
  Serves a QR code (SVG) for a link's short URL. Authorization runs through
  Ash policies via the actor — owners and admins only, everyone else 404.
  """

  use OrbitlyWeb, :controller

  def show(conn, %{"id" => id}) do
    with %{} = user <- conn.assigns[:current_user],
         {:ok, link} <- Ash.get(Orbitly.Shortener.Link, id, actor: user, load: [:domain]) do
      svg =
        link
        |> OrbitlyWeb.ShortUrl.for_link()
        |> EQRCode.encode()
        |> EQRCode.svg(width: 264)

      conn
      |> put_resp_content_type("image/svg+xml")
      |> put_resp_header("content-disposition", ~s(inline; filename="#{link.slug}-qr.svg"))
      |> send_resp(200, svg)
    else
      _ ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(404, "Not Found")
    end
  end
end
