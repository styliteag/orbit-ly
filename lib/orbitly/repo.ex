defmodule Orbitly.Repo do
  use Ecto.Repo,
    otp_app: :orbitly,
    adapter: Ecto.Adapters.SQLite3
end
