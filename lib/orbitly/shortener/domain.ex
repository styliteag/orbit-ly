defmodule Orbitly.Shortener.Domain do
  @moduledoc """
  A concrete hostname links can live under (ADR-0003).

  Admin-managed and shared by all users. The wildcard at the reverse proxy
  is infrastructure only — the application only knows concrete hostnames.
  Exactly one domain is primary and serves the dashboard UI (ADR-0004).

  `is_primary` is deliberately absent from the public changesets: the primary
  is the env-driven sentinel row managed by `Orbitly.Shortener.PrimaryDomain`,
  which sets the flag through `primary_changeset/2`. Admins can only create and
  edit plain redirect domains.

  A domain can be an *alias* of another one (`alias_of_id`): it owns no links,
  every slug of its target resolves on the alias host too. Aliases never chain
  and the primary is never an alias. The checks that need the database (target
  exists and is no alias, the domain has no links/aliases) live in
  `Orbitly.Shortener`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @hostname ~r/^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*$/i

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime_usec]

  schema "domains" do
    field :hostname, :string
    field :is_primary, :boolean, default: false
    field :active, :boolean, default: true

    belongs_to :alias_of, __MODULE__
    has_many :aliases, __MODULE__, foreign_key: :alias_of_id
    has_many :links, Orbitly.Shortener.Link, foreign_key: :domain_id

    timestamps()
  end

  @doc "Admin create: plain redirect domain, never primary."
  def create_changeset(domain, attrs) do
    domain
    |> cast(attrs, [:hostname, :active, :alias_of_id])
    |> validate_alias()
    |> common_changeset()
  end

  @doc """
  Admin update. The primary must stay reachable — it can never be deactivated
  here (its hostname still follows MAIN_DOMAIN via PrimaryDomain).
  """
  def update_changeset(domain, attrs) do
    domain
    |> cast(attrs, [:hostname, :active, :alias_of_id])
    |> protect_primary_active()
    |> validate_alias()
    |> common_changeset()
  end

  @doc """
  Sets hostname (and optionally the sentinel flag) for the env-driven primary.
  Only `Orbitly.Shortener.PrimaryDomain` may use this — it is the one path
  allowed to touch `is_primary`.
  """
  def primary_changeset(domain, attrs) do
    domain
    |> cast(attrs, [:hostname, :is_primary])
    |> common_changeset()
  end

  defp common_changeset(changeset) do
    changeset
    |> normalize_hostname()
    |> validate_required([:hostname])
    |> validate_hostname()
    # ecto_sqlite3 derives the constraint name from the column, not the index'
    # actual name (domains_unique_hostname_index).
    |> unique_constraint(:hostname, name: "domains_hostname_index")
    |> foreign_key_constraint(:alias_of_id)
  end

  defp normalize_hostname(changeset) do
    case get_change(changeset, :hostname) do
      hostname when is_binary(hostname) ->
        put_change(changeset, :hostname, hostname |> String.trim() |> String.downcase())

      _ ->
        changeset
    end
  end

  # DNS-style hostname: labels of [a-z0-9-], not starting/ending with a dash,
  # joined by dots. Single-label hosts (localhost) are allowed for development.
  defp validate_hostname(changeset) do
    validate_change(changeset, :hostname, fn :hostname, hostname ->
      if is_binary(hostname) and Regex.match?(@hostname, String.trim(hostname)) do
        []
      else
        [hostname: "is not a valid hostname"]
      end
    end)
  end

  # Guards the sentinel primary: it cannot be deactivated through the admin
  # update. Redirect domains are untouched.
  defp protect_primary_active(changeset) do
    if changeset.data.is_primary and get_change(changeset, :active) == false do
      add_error(changeset, :active, "the primary domain cannot be deactivated")
    else
      changeset
    end
  end

  # Pure alias rules: never on the primary, never pointing at itself.
  defp validate_alias(changeset) do
    alias_of_id = get_field(changeset, :alias_of_id)

    cond do
      is_nil(alias_of_id) ->
        changeset

      changeset.data.is_primary ->
        add_error(changeset, :alias_of_id, "the primary domain cannot be an alias")

      alias_of_id == changeset.data.id ->
        add_error(changeset, :alias_of_id, "a domain cannot be an alias of itself")

      true ->
        changeset
    end
  end
end
