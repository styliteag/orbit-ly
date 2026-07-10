defmodule Orbitly.Repo.Migrations.CreateInitialSchema do
  @moduledoc """
  Single consolidated schema for a fresh install (plain Ecto — no Ash). Replaces
  the original AshSqlite-generated migration chain; there is no data to preserve.
  """

  use Ecto.Migration

  def change do
    # Users: admin-created accounts, Bcrypt passwords, no timestamps.
    create table(:users, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :email, :string, null: false
      add :hashed_password, :string, null: false
      add :confirmed_at, :utc_datetime_usec
      add :admin, :boolean, null: false, default: false
    end

    create unique_index(:users, [:email])

    # Session and password-reset tokens (opaque; reset tokens stored hashed).
    create table(:users_tokens, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :token, :binary, null: false
      add :context, :string, null: false
      add :sent_to, :string

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:users_tokens, [:user_id])
    create unique_index(:users_tokens, [:context, :token])

    # Redirect hostnames (admin-managed; exactly one primary sentinel row).
    create table(:domains, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :hostname, :string, null: false
      add :is_primary, :boolean, null: false, default: false
      add :active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:domains, [:hostname])

    # Short links: slug on a domain → target URL, owned by one user.
    create table(:links, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :slug, :string, null: false
      add :target_url, :string, null: false
      add :description, :string
      add :expires_at, :utc_datetime
      add :password_hash, :string
      add :domain_id, references(:domains, type: :uuid, on_delete: :delete_all), null: false
      add :owner_id, references(:users, type: :uuid, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:links, [:domain_id, :slug])

    # Raw click events (ADR-0005), written in batches; 12-month retention.
    create table(:click_events, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :link_id, references(:links, type: :uuid, on_delete: :delete_all), null: false
      add :occurred_at, :utc_datetime_usec, null: false
      add :ip, :string
      add :user_agent, :string
      add :referrer, :string
    end

    create index(:click_events, [:link_id])
  end
end
