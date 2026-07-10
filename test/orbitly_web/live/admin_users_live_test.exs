defmodule OrbitlyWeb.AdminUsersLiveTest do
  use OrbitlyWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Orbitly.Fixtures

  test "redirects non-admin users", %{conn: conn} do
    user = registered_user_fixture()

    assert {:error, {:redirect, %{to: "/links"}}} =
             conn |> log_in(user) |> live(~p"/admin/users")
  end

  test "admin creates, promotes and deletes users", %{conn: conn} do
    admin = registered_admin_fixture()
    victim = registered_user_fixture(%{email: "victim@example.com"})

    {:ok, view, html} = conn |> log_in(admin) |> live(~p"/admin/users")
    assert html =~ "victim@example.com"

    view
    |> form("#user-form", %{
      "form" => %{"email" => "fresh@example.com", "password" => "fresh-password"}
    })
    |> render_submit()

    assert render(view) =~ "fresh@example.com"

    view
    |> element(~s{[phx-click="toggle-admin"][phx-value-id="#{victim.id}"]})
    |> render_click()

    users = Orbitly.Accounts.list_users()
    assert Enum.find(users, &(&1.id == victim.id)).admin

    view
    |> element(~s{[phx-click="delete"][phx-value-id="#{victim.id}"]})
    |> render_click()

    refute render(view) =~ "victim@example.com"
  end

  test "admin cannot delete or demote themselves via the UI", %{conn: conn} do
    admin = registered_admin_fixture()

    {:ok, view, _html} = conn |> log_in(admin) |> live(~p"/admin/users")

    refute has_element?(view, ~s{[phx-click="delete"][phx-value-id="#{admin.id}"]})
    refute has_element?(view, ~s{[phx-click="toggle-admin"][phx-value-id="#{admin.id}"]})
  end
end
