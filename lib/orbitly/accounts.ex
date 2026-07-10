defmodule Orbitly.Accounts do
  @moduledoc """
  User accounts and authentication (plain Phoenix / Ecto, phx.gen.auth model).

  There is no open registration (ADR-0006): accounts are created by an instance
  admin (or the release bootstrap). Authorization is enforced at the web layer
  (`OrbitlyWeb.UserAuth` plugs / on_mount, admin-only routes), not here.
  """

  import Ecto.Query

  alias Orbitly.Repo
  alias Orbitly.Accounts.{User, UserNotifier, UserToken}

  ## Lookups

  @doc "Case-insensitive lookup by email."
  def get_user_by_email(email) when is_binary(email) do
    Repo.one(from(u in User, where: fragment("? = ? collate nocase", u.email, ^email)))
  end

  @doc "Returns the user if the email/password pair is valid, else nil."
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = get_user_by_email(email)
    if User.valid_password?(user, password), do: user
  end

  def get_user!(id), do: Repo.get!(User, id)

  def list_users, do: Repo.all(from(u in User, order_by: [asc: u.email]))

  ## User management (admin-driven)

  @doc "Creates an account with an initial password (admin action). Not admin by default."
  def admin_create_user(attrs) do
    %User{}
    |> User.admin_create_changeset(attrs)
    |> Repo.insert()
  end

  @doc "Grants or revokes the instance-admin flag."
  def set_admin(%User{} = user, admin) when is_boolean(admin) do
    user
    |> Ecto.Changeset.change(admin: admin)
    |> Repo.update()
  end

  @doc "Deletes a user (their links cascade via the DB foreign key)."
  def delete_user(%User{} = user), do: Repo.delete(user)

  @doc "Blank admin-create changeset for the admin form."
  def change_user_admin_create(attrs \\ %{}), do: User.admin_create_changeset(%User{}, attrs)

  ## Session tokens

  @doc "Mints and stores an opaque session token, returning the raw token."
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc "Returns the user for a valid session token, or nil."
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc "Deletes the given session token."
  def delete_user_session_token(token) do
    Repo.delete_all(UserToken.by_token_and_context_query(token, "session"))
    :ok
  end

  ## Password reset

  @doc """
  Delivers reset instructions. `reset_url_fun` receives the encoded token and
  returns the full reset URL.
  """
  def deliver_user_reset_password_instructions(%User{} = user, reset_url_fun)
      when is_function(reset_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "reset_password")
    Repo.insert!(user_token)
    UserNotifier.deliver_reset_password_instructions(user, reset_url_fun.(encoded_token))
  end

  @doc "Returns the user for a valid, unexpired reset token, or nil."
  def get_user_by_reset_password_token(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "reset_password"),
         %User{} = user <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc "Resets the password and, per log-out-everywhere, drops all of the user's tokens."
  def reset_user_password(user, attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.password_changeset(user, attrs))
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  @doc "Password changeset for the reset form (no hashing during validation)."
  def change_user_password(user, attrs \\ %{}) do
    User.password_changeset(user, attrs, hash_password: false)
  end

  @doc """
  Self-service password change: requires the current password, then updates
  the hash and, per log-out-everywhere, drops all of the user's tokens.
  """
  def update_user_password(user, current_password, attrs) do
    changeset =
      user
      |> User.password_changeset(attrs)
      |> User.validate_current_password(current_password)

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end
end
