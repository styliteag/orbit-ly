defmodule Orbitly.Fixtures do
  @moduledoc """
  Test fixtures. User/token live in Accounts (Ash) and are seeded via
  `Ash.Seed`; domains and links are plain Ecto and inserted directly — both
  bypass actions, validations and policies on purpose so tests can set up
  arbitrary state.
  """

  import Ecto.Query, only: [from: 2]

  alias Orbitly.Accounts.User
  alias Orbitly.Repo
  alias Orbitly.Shortener.{Domain, Link}

  def user_fixture(attrs \\ %{}) do
    Ash.Seed.seed!(
      User,
      Map.merge(
        %{
          email: "user#{System.unique_integer([:positive])}@example.com",
          hashed_password: "$2b$04$not-a-real-hash-for-tests",
          confirmed_at: DateTime.utc_now(),
          admin: false
        },
        attrs
      )
    )
  end

  def admin_fixture(attrs \\ %{}), do: user_fixture(Map.merge(%{admin: true}, attrs))

  @default_password "test-password-1234"

  def default_password, do: @default_password

  @doc """
  User created through the real admin_create action; `log_in/2` signs in via
  the password strategy, which mints and stores the session token. Use for
  LiveView/controller tests with a session.
  """
  def registered_user_fixture(attrs \\ %{}) do
    email = attrs[:email] || "user#{System.unique_integer([:positive])}@example.com"
    password = attrs[:password] || @default_password

    user =
      User
      |> Ash.Changeset.for_create(
        :admin_create,
        %{email: email, password: password},
        authorize?: false
      )
      |> Ash.create!()

    if attrs[:admin] do
      {1, _} =
        Orbitly.Repo.update_all(
          from(u in User, where: u.id == ^user.id),
          set: [admin: true]
        )

      %{user | admin: true}
    else
      user
    end
  end

  def registered_admin_fixture(attrs \\ %{}),
    do: registered_user_fixture(Map.put(attrs, :admin, true))

  def log_in(conn, user, password \\ @default_password) do
    signed_in =
      User
      |> Ash.Query.for_read(
        :sign_in_with_password,
        %{email: to_string(user.email), password: password},
        authorize?: false
      )
      |> Ash.read_one!()

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> AshAuthentication.Plug.Helpers.store_in_session(signed_in)
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
