defmodule Orbitly.Shortener.UserDomain do
  @moduledoc """
  Grant of one domain to one user. Only consulted when the user's
  `all_domains` flag is off (see `Orbitly.Shortener.DomainAccess`).
  """

  use Ecto.Schema

  @primary_key false
  @foreign_key_type Ecto.UUID

  schema "user_domains" do
    field :user_id, Ecto.UUID
    field :domain_id, Ecto.UUID
  end
end
