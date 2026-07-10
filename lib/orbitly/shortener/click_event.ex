defmodule Orbitly.Shortener.ClickEvent do
  @moduledoc """
  Raw click record (ADR-0005): full IP and user agent, kept for 12 months.

  Writes happen exclusively through `Orbitly.Shortener.ClickBuffer` via
  batched `Repo.insert_all` — there is deliberately no create changeset here,
  the hot path must not pay per-click overhead. Reads/aggregations go through
  `Orbitly.Shortener.ClickStats` and the owner/admin-scoped context functions.
  """

  use Ecto.Schema

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID

  schema "click_events" do
    field :occurred_at, :utc_datetime_usec
    field :ip, :string
    field :user_agent, :string
    field :referrer, :string

    belongs_to :link, Orbitly.Shortener.Link
  end
end
