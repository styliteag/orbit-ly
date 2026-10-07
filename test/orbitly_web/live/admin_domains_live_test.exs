defmodule OrbitlyWeb.AdminDomainsLiveTest do
  use OrbitlyWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Orbitly.Fixtures

  test "redirects non-admin users to their links", %{conn: conn} do
    user = registered_user_fixture()

    assert {:error, {:redirect, %{to: "/links"}}} =
             conn |> log_in(user) |> live(~p"/admin/domains")
  end

  test "admin adds a redirect domain (never primary)", %{conn: conn} do
    admin = registered_admin_fixture()

    {:ok, view, _html} = conn |> log_in(admin) |> live(~p"/admin/domains")

    view
    |> form("#domain-form", %{"form" => %{"hostname" => "NEW.Example"}})
    |> render_submit()

    html = render(view)
    assert html =~ "new.example"

    domains = Orbitly.Shortener.list_domains()
    new_domain = Enum.find(domains, &(&1.hostname == "new.example"))
    refute new_domain.is_primary
  end

  test "the primary domain is read-only — no make-primary, deactivate or delete",
       %{conn: conn} do
    admin = registered_admin_fixture()
    primary = domain_fixture(%{hostname: "primary.example", is_primary: true})

    {:ok, view, _html} = conn |> log_in(admin) |> live(~p"/admin/domains")

    refute has_element?(view, ~s{[phx-click="make-primary"]})
    refute has_element?(view, ~s{#domain-#{primary.id} [phx-click="delete"]})
    refute has_element?(view, ~s{#domain-#{primary.id} [phx-click="toggle-active"]})
  end

  test "admin adds an alias of another domain, shown with its target", %{conn: conn} do
    admin = registered_admin_fixture()
    target = domain_fixture(%{hostname: "stylite.io"})

    {:ok, view, _html} = conn |> log_in(admin) |> live(~p"/admin/domains")

    view
    |> form("#domain-form", %{"form" => %{"hostname" => "stylite.de", "alias_of_id" => target.id}})
    |> render_submit()

    alias_domain = Enum.find(Orbitly.Shortener.list_domains(), &(&1.hostname == "stylite.de"))
    assert alias_domain.alias_of_id == target.id
    assert view |> element("#domain-#{alias_domain.id}") |> render() =~ "alias of stylite.io"
  end

  test "the alias picker offers only non-alias domains", %{conn: conn} do
    admin = registered_admin_fixture()
    target = domain_fixture(%{hostname: "stylite.io"})
    domain_fixture(%{hostname: "stylite.de", alias_of_id: target.id})

    {:ok, view, _html} = conn |> log_in(admin) |> live(~p"/admin/domains")

    assert has_element?(view, ~s{#domain-form select option[value="#{target.id}"]})
    refute view |> element("#domain-form select") |> render() =~ "stylite.de"
  end
end
