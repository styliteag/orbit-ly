defmodule Orbitly.ReleaseTest do
  use Orbitly.DataCase, async: false

  alias Orbitly.Accounts
  alias Orbitly.Release

  test "upsert_admin creates a confirmed admin that can sign in" do
    assert :created = Release.upsert_admin("boss@example.com", "bootstrap-password")

    user = Accounts.get_user_by_email_and_password("boss@example.com", "bootstrap-password")
    assert user
    assert user.admin
    assert user.confirmed_at
  end

  test "upsert_admin is idempotent" do
    assert :created = Release.upsert_admin("boss@example.com", "bootstrap-password")
    assert :exists = Release.upsert_admin("boss@example.com", "other-password")

    assert length(Accounts.list_users()) == 1
  end
end
