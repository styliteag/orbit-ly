defmodule Orbitly.Shortener.Link do
  @moduledoc """
  Maps a slug on a domain to a target URL.

  Owned by exactly one user; slugs are unique per (domain, slug) across all
  users (ADR-0002/0003). Optional time-based expiry (expired links answer
  410, ADR "Ablauf") and optional password protection.

  Slug resolution and password hashing depend on the Repo / the actor and live
  in `Orbitly.Shortener`; the changesets here take already-resolved values.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Orbitly.Shortener.Slug

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime_usec]

  schema "links" do
    # "" is the stored form of the domain-root link, "*" the catch-all.
    field :slug, :string
    field :target_url, :string
    field :description, :string
    field :expires_at, :utc_datetime
    field :password_hash, :string, redact: true
    field :owner_id, Ecto.UUID
    # Owner lives in Accounts (still Ash); the context attaches it here for
    # display instead of a cross-framework Ecto preload.
    field :owner, :map, virtual: true

    belongs_to :domain, Orbitly.Shortener.Domain
    has_many :click_events, Orbitly.Shortener.ClickEvent

    timestamps()
  end

  @doc """
  Create changeset. `slug`, `owner_id` and `password_hash` are derived by the
  context and passed in `attrs` already resolved.
  """
  def create_changeset(link, attrs) do
    link
    |> cast(attrs, [:target_url, :description, :expires_at, :domain_id, :owner_id, :password_hash])
    # slug is resolved (custom, special or generated) by the context; set it via
    # put_change so the root link's stored "" survives cast's empty-value pruning.
    |> put_slug(attrs)
    |> validate_required([:target_url, :domain_id, :owner_id])
    |> validate_length(:description, max: 500)
    |> validate_slug()
    |> validate_target_url()
    # ecto_sqlite3 derives the constraint name from the columns, not the index'
    # actual name (links_unique_slug_per_domain_index).
    |> unique_constraint(:slug, name: "links_domain_id_slug_index")
    |> foreign_key_constraint(:domain_id)
    |> foreign_key_constraint(:owner_id)
  end

  defp put_slug(changeset, attrs) do
    case Map.fetch(attrs, :slug) do
      {:ok, slug} when is_binary(slug) -> put_change(changeset, :slug, slug)
      _ -> changeset
    end
  end

  @doc """
  Update changeset. Slug, domain and owner are immutable; `password_hash` is
  derived by the context (`nil` clears protection, absent leaves it untouched).
  """
  def update_changeset(link, attrs) do
    link
    |> cast(attrs, [:target_url, :description, :expires_at, :password_hash])
    |> validate_required([:target_url])
    |> validate_length(:description, max: 500)
    |> validate_target_url()
  end

  defp validate_slug(changeset) do
    case get_field(changeset, :slug) do
      slug when is_binary(slug) ->
        cond do
          Slug.special?(slug) ->
            changeset

          not Slug.valid_format?(slug) ->
            add_error(
              changeset,
              :slug,
              "must be 1-64 characters of letters, digits, dash or underscore"
            )

          Slug.reserved?(slug) ->
            add_error(changeset, :slug, "is reserved")

          true ->
            changeset
        end

      _ ->
        changeset
    end
  end

  defp validate_target_url(changeset) do
    if changed?(changeset, :target_url) do
      case URI.new(get_change(changeset, :target_url) || "") do
        {:ok, %URI{scheme: scheme, host: host}}
        when scheme in ["http", "https"] and is_binary(host) and host != "" ->
          changeset

        _ ->
          add_error(changeset, :target_url, "must be a valid http(s) URL")
      end
    else
      changeset
    end
  end
end
