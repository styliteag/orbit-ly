defmodule Orbitly.AccountsTest do
  use Orbitly.DataCase, async: false

  import Orbitly.Fixtures

  alias Orbitly.Accounts
  alias Orbitly.Accounts.User

  describe "admin_create_user/1" do
    test "creates a confirmed, non-admin account with a downcased email" do
      assert {:ok, user} =
               Accounts.admin_create_user(%{
                 email: "New@Example.com",
                 password: "initial-password"
               })

      assert user.email == "new@example.com"
      refute user.admin
      assert user.confirmed_at
      assert is_binary(user.hashed_password)
    end

    test "rejects a short password" do
      assert {:error, changeset} =
               Accounts.admin_create_user(%{email: "x@example.com", password: "short"})

      assert "should be at least 8 byte(s)" in errors_on(changeset).password
    end

    test "rejects an invalid email" do
      assert {:error, changeset} =
               Accounts.admin_create_user(%{email: "not-an-email", password: "initial-password"})

      refute Enum.empty?(errors_on(changeset).email)
    end

    test "rejects a duplicate email case-insensitively" do
      {:ok, _} =
        Accounts.admin_create_user(%{email: "dup@example.com", password: "initial-password"})

      assert {:error, changeset} =
               Accounts.admin_create_user(%{
                 email: "DUP@example.com",
                 password: "initial-password"
               })

      assert "has already been taken" in errors_on(changeset).email
    end
  end

  describe "get_user_by_email_and_password/2" do
    setup do
      {:ok, user} =
        Accounts.admin_create_user(%{email: "auth@example.com", password: "the-password"})

      %{user: user}
    end

    test "returns the user for valid, case-insensitive credentials", %{user: user} do
      assert %User{id: id} =
               Accounts.get_user_by_email_and_password("Auth@Example.com", "the-password")

      assert id == user.id
    end

    test "returns nil for a wrong password" do
      refute Accounts.get_user_by_email_and_password("auth@example.com", "wrong")
    end

    test "returns nil for an unknown email" do
      refute Accounts.get_user_by_email_and_password("nobody@example.com", "the-password")
    end
  end

  describe "set_admin/2 and delete_user/1" do
    test "grants and revokes the admin flag" do
      user = user_fixture()

      assert {:ok, promoted} = Accounts.set_admin(user, true)
      assert promoted.admin

      assert {:ok, demoted} = Accounts.set_admin(promoted, false)
      refute demoted.admin
    end

    test "deleting a user cascades to their links" do
      admin = admin_fixture()
      user = user_fixture()
      domain = domain_fixture()
      link_fixture(user, domain)

      assert {:ok, _} = Accounts.delete_user(user)
      assert [] = Orbitly.Shortener.list_links(admin)
    end
  end

  describe "list_users/0" do
    test "returns every user" do
      admin = admin_fixture()
      user = user_fixture()

      ids = Accounts.list_users() |> Enum.map(& &1.id) |> Enum.sort()
      assert ids == Enum.sort([admin.id, user.id])
    end
  end

  describe "session tokens" do
    test "generate then fetch round-trips the user" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)

      assert %User{id: id} = Accounts.get_user_by_session_token(token)
      assert id == user.id
    end

    test "deleting the token invalidates the session" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)

      Accounts.delete_user_session_token(token)
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "update_user_password/3" do
    setup do
      %{user: registered_user_fixture()}
    end

    test "updates the password and drops all tokens", %{user: user} do
      token = Accounts.generate_user_session_token(user)

      assert {:ok, updated} =
               Accounts.update_user_password(user, default_password(), %{
                 password: "brand-new-password",
                 password_confirmation: "brand-new-password"
               })

      assert Accounts.get_user_by_email_and_password(updated.email, "brand-new-password")
      refute Accounts.get_user_by_session_token(token)
    end

    test "rejects a wrong current password", %{user: user} do
      assert {:error, changeset} =
               Accounts.update_user_password(user, "wrong-current", %{
                 password: "brand-new-password",
                 password_confirmation: "brand-new-password"
               })

      assert %{current_password: ["is not valid"]} = errors_on(changeset)
      assert Accounts.get_user_by_email_and_password(user.email, default_password())
    end

    test "validates the new password", %{user: user} do
      assert {:error, changeset} =
               Accounts.update_user_password(user, default_password(), %{
                 password: "short",
                 password_confirmation: "mismatch"
               })

      errors = errors_on(changeset)
      assert "should be at least 8 byte(s)" in errors.password
      assert "does not match password" in errors.password_confirmation
    end
  end

  describe "password reset" do
    test "reset resets the password and drops all sessions (log-out-everywhere)" do
      {:ok, user} =
        Accounts.admin_create_user(%{email: "reset@example.com", password: "old-password"})

      session = Accounts.generate_user_session_token(user)
      reset_token = capture_reset_token(user)

      assert %User{id: id} = Accounts.get_user_by_reset_password_token(reset_token)
      assert id == user.id

      assert {:ok, _} =
               Accounts.reset_user_password(user, %{
                 password: "new-password-123",
                 password_confirmation: "new-password-123"
               })

      assert Accounts.get_user_by_email_and_password("reset@example.com", "new-password-123")
      refute Accounts.get_user_by_email_and_password("reset@example.com", "old-password")
      refute Accounts.get_user_by_session_token(session)
    end

    test "an invalid reset token yields no user" do
      refute Accounts.get_user_by_reset_password_token("not-a-real-token")
    end
  end

  defp capture_reset_token(user) do
    ref = make_ref()
    parent = self()

    Accounts.deliver_user_reset_password_instructions(user, fn token ->
      send(parent, {ref, token})
      "http://localhost/password-reset/#{token}"
    end)

    receive do
      {^ref, token} -> token
    after
      200 -> flunk("no reset token was delivered")
    end
  end
end
