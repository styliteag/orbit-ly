defmodule OrbitlyWeb.DomainAccessLiveTest do
  use OrbitlyWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Orbitly.Fixtures

  alias Orbitly.Accounts
  alias Orbitly.Shortener

  setup do
    %{
      admin: registered_admin_fixture(),
      user: registered_user_fixture(%{email: "member@example.com"}),
      a: domain_fixture(%{hostname: "a.example"}),
      b: domain_fixture(%{hostname: "b.example"})
    }
  end

  describe "admin users page" do
    test "admin restricts a user to one domain and sets their default", ctx do
      {:ok, view, _html} = ctx.conn |> log_in(ctx.admin) |> live(~p"/admin/users")

      view
      |> form("#domain-access-#{ctx.user.id}", %{
        "access" => %{
          "all_domains" => "false",
          "domain_ids" => [ctx.a.id],
          "default_domain_id" => ctx.a.id
        }
      })
      |> render_submit()

      user = Accounts.get_user!(ctx.user.id)
      refute user.all_domains
      assert user.default_domain_id == ctx.a.id
      assert Shortener.granted_domain_ids(user) == [ctx.a.id]
      assert view |> element("#user-#{ctx.user.id}") |> render() =~ "1 domain"
    end

    test "a default outside the granted domains is rejected", ctx do
      {:ok, view, _html} = ctx.conn |> log_in(ctx.admin) |> live(~p"/admin/users")

      view
      |> form("#domain-access-#{ctx.user.id}", %{
        "access" => %{
          "all_domains" => "false",
          "domain_ids" => [ctx.a.id],
          "default_domain_id" => ctx.b.id
        }
      })
      |> render_submit()

      assert render(view) =~ "Default domain is not available to this user"
      assert is_nil(Accounts.get_user!(ctx.user.id).default_domain_id)
    end
  end

  describe "settings page" do
    test "a user picks a default domain among their usable ones", ctx do
      {:ok, _} =
        Shortener.set_domain_access(
          ctx.user,
          %{all_domains: false, domain_ids: [ctx.a.id, ctx.b.id]},
          ctx.admin
        )

      {:ok, view, _html} = ctx.conn |> log_in(ctx.user) |> live(~p"/settings")

      view
      |> form("#default-domain-form", %{"default" => %{"domain_id" => ctx.b.id}})
      |> render_submit()

      assert Accounts.get_user!(ctx.user.id).default_domain_id == ctx.b.id
      assert render(view) =~ "Default domain saved"
    end
  end

  describe "links page" do
    test "offers only usable domains and preselects the default", ctx do
      {:ok, user} =
        Shortener.set_domain_access(
          ctx.user,
          %{all_domains: false, domain_ids: [ctx.a.id, ctx.b.id]},
          ctx.admin
        )

      {:ok, _} = Shortener.set_default_domain(user, ctx.b.id, user)
      other = domain_fixture(%{hostname: "c.example"})

      {:ok, view, _html} = ctx.conn |> log_in(ctx.user) |> live(~p"/links")

      assert has_element?(view, ~s{#link-form option[value="#{ctx.b.id}"][selected]})
      refute has_element?(view, ~s{#link-form option[value="#{other.id}"]})
    end
  end
end
