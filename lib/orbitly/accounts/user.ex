defmodule Orbitly.Accounts.User do
  @moduledoc """
  Instance user (ADR-0006). Accounts are admin-created (no open registration);
  `admin` grants full access to domains, users and all links. Plain Ecto +
  Bcrypt — the `users` table has no timestamps.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID

  schema "users" do
    field :email, :string
    field :hashed_password, :string, redact: true
    field :password, :string, virtual: true, redact: true
    field :confirmed_at, :utc_datetime_usec
    field :admin, :boolean, default: false
  end

  @doc """
  Admin-created account: email + initial password. Admin-created accounts are
  trusted, so they are confirmed immediately (no email round-trip).
  """
  def admin_create_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email, :password])
    |> validate_email()
    |> validate_password(opts)
    |> put_change(:confirmed_at, DateTime.utc_now())
  end

  @doc "New password (password reset). Requires a matching confirmation."
  def password_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:password])
    |> validate_confirmation(:password, message: "does not match password")
    |> validate_password(opts)
  end

  defp validate_email(changeset) do
    changeset
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/, message: "must be a valid email")
    |> validate_length(:email, max: 160)
    |> update_change(:email, &String.downcase(String.trim(&1)))
    |> unsafe_validate_unique(:email, Orbitly.Repo)
    |> unique_constraint(:email)
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password])
    # 72 bytes is Bcrypt's input limit.
    |> validate_length(:password, min: 8, max: 72, count: :bytes)
    |> maybe_hash_password(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  @doc "Verifies `password` against the stored hash; runs a dummy check for a missing user (timing)."
  def valid_password?(%__MODULE__{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed_password)
  end

  def valid_password?(_user, _password) do
    Bcrypt.no_user_verify()
    false
  end
end
