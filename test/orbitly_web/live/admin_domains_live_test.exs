defmodule OrbitlyWeb.AdminDomainsLiveTest do
  use OrbitlyWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Orbitly.Fixtures

  test "redirects non-admin users to their links", %{conn: conn} do
    user = registered_user_fixture()

    assert {:error, {:redirect, %{to: "/links"}}} =
             conn |> log_in(user) |> live(~p"/admin/domains")
  end

  test "admin adds a domain and makes it primary", %{conn: conn} do
    admin = registered_admin_fixture()
    old_primary = domain_fixture(%{hostname: "old.example", is_primary: true})

    {:ok, view, _html} = conn |> log_in(admin) |> live(~p"/admin/domains")

    view
    |> form("#domain-form", %{"form" => %{"hostname" => "NEW.Example"}})
    |> render_submit()

    html = render(view)
    assert html =~ "new.example"

    {:ok, domains} = Orbitly.Shortener.list_domains(actor: admin)
    new_domain = Enum.find(domains, &(&1.hostname == "new.example"))

    view
    |> element(~s{[phx-click="make-primary"][phx-value-id="#{new_domain.id}"]})
    |> render_click()

    {:ok, reloaded_old} = Ash.get(Orbitly.Shortener.Domain, old_primary.id, actor: admin)
    refute reloaded_old.is_primary
  end
end
