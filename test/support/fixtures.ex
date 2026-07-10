defmodule Orbitly.Fixtures do
  @moduledoc """
  Test fixtures (plain Ecto). `user_fixture` inserts a struct directly (fast,
  fake password hash) for tests that never log in; `registered_user_fixture`
  goes through the real `Accounts.admin_create_user` (real hash) so `log_in/2`
  works. Domains and links are inserted directly too — all bypass validation on
  purpose so tests can set up arbitrary state.
  """

  alias Orbitly.Accounts
  alias Orbitly.Accounts.User
  alias Orbitly.Repo
  alias Orbitly.Shortener.{Domain, Link}

  def user_fixture(attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          email: "user#{System.unique_integer([:positive])}@example.com",
          hashed_password: "$2b$04$not-a-real-hash-for-tests",
          confirmed_at: DateTime.utc_now(),
          admin: false
        },
        attrs
      )

    Repo.insert!(struct(User, attrs))
  end

  def admin_fixture(attrs \\ %{}), do: user_fixture(Map.merge(%{admin: true}, attrs))

  @default_password "test-password-1234"

  def default_password, do: @default_password

  @doc """
  User created through the real admin-create path (real password hash), so
  `log_in/2` works. Use for LiveView/controller tests with a session.
  """
  def registered_user_fixture(attrs \\ %{}) do
    email = attrs[:email] || "user#{System.unique_integer([:positive])}@example.com"
    password = attrs[:password] || @default_password

    {:ok, user} = Accounts.admin_create_user(%{email: email, password: password})

    if attrs[:admin] do
      {:ok, user} = Accounts.set_admin(user, true)
      user
    else
      user
    end
  end

  def registered_admin_fixture(attrs \\ %{}),
    do: registered_user_fixture(Map.put(attrs, :admin, true))

  def log_in(conn, user, _password \\ @default_password) do
    token = Accounts.generate_user_session_token(user)

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
  end

  def domain_fixture(attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          hostname: "go#{System.unique_integer([:positive])}.example",
          is_primary: false,
          active: true
        },
        attrs
      )

    Repo.insert!(struct(Domain, attrs))
  end

  def link_fixture(owner, domain, attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          slug: "s#{System.unique_integer([:positive])}",
          target_url: "https://example.com/target",
          domain_id: domain.id,
          owner_id: owner.id
        },
        attrs
      )
      |> truncate_expires_at()

    Repo.insert!(struct(Link, attrs))
  end

  # expires_at is stored at second precision (:utc_datetime); struct inserts
  # bypass the cast that would truncate, so do it here.
  defp truncate_expires_at(%{expires_at: %DateTime{} = dt} = attrs),
    do: %{attrs | expires_at: DateTime.truncate(dt, :second)}

  defp truncate_expires_at(attrs), do: attrs
end
