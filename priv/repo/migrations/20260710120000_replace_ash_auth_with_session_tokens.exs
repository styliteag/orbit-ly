defmodule Orbitly.Repo.Migrations.ReplaceAshAuthWithSessionTokens do
  @moduledoc """
  Drops the AshAuthentication JWT/JTI `tokens` table and introduces the plain
  Phoenix `users_tokens` table (opaque, hashed session and password-reset
  tokens). Existing sessions are invalidated by design. The `users` table is
  unchanged.
  """

  use Ecto.Migration

  def up do
    drop table(:tokens)

    create table(:users_tokens, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :token, :binary, null: false
      add :context, :string, null: false
      add :sent_to, :string
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:users_tokens, [:user_id])
    create unique_index(:users_tokens, [:context, :token])
  end

  def down do
    drop table(:users_tokens)

    create table(:tokens, primary_key: false) do
      add :jti, :text, null: false, primary_key: true
      add :subject, :text, null: false
      add :expires_at, :text, null: false
      add :purpose, :text, null: false
      add :extra_data, :text
      add :created_at, :text, null: false
      add :updated_at, :text, null: false
    end
  end
end
