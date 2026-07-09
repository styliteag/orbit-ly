defmodule Orbitly.AccountsTest do
  use Orbitly.DataCase, async: false

  import Orbitly.Fixtures

  alias Orbitly.Accounts
  alias Orbitly.Accounts.User

  setup do
    %{admin: admin_fixture(), user: user_fixture()}
  end

  describe "admin_create" do
    test "admin creates a confirmed account that can sign in", %{admin: admin} do
      assert {:ok, user} =
               Accounts.admin_create_user(
                 %{email: "new@example.com", password: "initial-password"},
                 actor: admin
               )

      assert to_string(user.email) == "new@example.com"
      refute user.admin
      assert user.confirmed_at

      assert {:ok, %User{}} =
               User
               |> Ash.Query.for_read(
                 :sign_in_with_password,
                 %{email: "new@example.com", password: "initial-password"},
                 authorize?: false
               )
               |> Ash.read_one()
    end

    test "non-admins are forbidden", %{user: user} do
      assert {:error, %Ash.Error.Forbidden{}} =
               Accounts.admin_create_user(
                 %{email: "x@example.com", password: "some-password"},
                 actor: user
               )
    end
  end

  describe "open registration (ADR-0006)" do
    test "register_with_password always fails, even unauthenticated" do
      assert {:error, %Ash.Error.Invalid{} = error} =
               User
               |> Ash.Changeset.for_create(
                 :register_with_password,
                 %{
                   email: "intruder@example.com",
                   password: "password123",
                   password_confirmation: "password123"
                 },
                 authorize?: false
               )
               |> Ash.create()

      assert Exception.message(error) =~ "registration is disabled"
    end
  end

  describe "set_admin / destroy" do
    test "admin grants and revokes the admin flag", %{admin: admin, user: user} do
      assert {:ok, promoted} = Accounts.set_admin(user, %{admin: true}, actor: admin)
      assert promoted.admin

      assert {:ok, demoted} = Accounts.set_admin(promoted, %{admin: false}, actor: admin)
      refute demoted.admin
    end

    test "non-admins may neither promote nor delete", %{user: user} do
      other = user_fixture()

      assert {:error, %Ash.Error.Forbidden{}} =
               Accounts.set_admin(other, %{admin: true}, actor: user)

      assert {:error, %Ash.Error.Forbidden{}} = Accounts.destroy_user(other, actor: user)
    end

    test "admin deletes a user together with their links", %{admin: admin, user: user} do
      domain = domain_fixture()
      link_fixture(user, domain)

      assert :ok = Accounts.destroy_user(user, actor: admin)
      assert {:ok, []} = Orbitly.Shortener.list_links(actor: admin)
    end
  end

  describe "read policies" do
    test "admins list all users, users only themselves", %{admin: admin, user: user} do
      assert {:ok, users} = Accounts.list_users(actor: admin)
      assert length(users) == 2

      assert {:ok, [own]} = Accounts.list_users(actor: user)
      assert own.id == user.id
    end
  end
end
