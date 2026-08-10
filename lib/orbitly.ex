defmodule Orbitly do
  @moduledoc """
  Orbitly keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  @doc """
  The running application version (from `VERSION` via `mix.exs`) — logged at
  boot and used wherever the release has to identify itself.
  """
  def version, do: :orbitly |> Application.spec(:vsn) |> to_string()
end
