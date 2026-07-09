defmodule OrbitlyWeb.ShortUrl do
  @moduledoc """
  Builds the public short URL for a link: the environment's scheme/port
  (from the endpoint config) with the link's domain — dev yields
  http://<host>:4000/<slug>, behind the proxy https://<host>/<slug>.
  Requires the link's `domain` to be loaded.
  """

  def for_link(link) do
    base = URI.parse(OrbitlyWeb.Endpoint.url())
    URI.to_string(%{base | host: link.domain.hostname, path: "/" <> link.slug})
  end
end
