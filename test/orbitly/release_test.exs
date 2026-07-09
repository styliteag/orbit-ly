defmodule Orbitly.ReleaseTest do
  use Orbitly.DataCase, async: false

  require Ash.Query

  alias Orbitly.Accounts.User
  alias Orbitly.Release

  test "upsert_admin creates a confirmed admin that can sign in" do
    assert :created = Release.upsert_admin("boss@example.com", "bootstrap-password")

    {:ok, user} =
      User
      |> Ash.Query.for_read(:sign_in_with_password,
        email: "boss@example.com",
        password: "bootstrap-password"
      )
      |> Ash.read_one(authorize?: false)

    assert user.admin
    assert user.confirmed_at
  end

  test "upsert_admin is idempotent" do
    assert :created = Release.upsert_admin("boss@example.com", "bootstrap-password")
    assert :exists = Release.upsert_admin("boss@example.com", "other-password")

    assert {:ok, [_only_one]} =
             User
             |> Ash.Query.filter(email == "boss@example.com")
             |> Ash.read(authorize?: false)
  end
end
