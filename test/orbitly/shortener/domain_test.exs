defmodule Orbitly.Shortener.DomainTest do
  use Orbitly.DataCase, async: false

  import Orbitly.Fixtures

  alias Orbitly.Shortener

  setup do
    %{admin: admin_fixture(), user: user_fixture()}
  end

  describe "create" do
    test "admin creates a domain, hostname is normalized", %{admin: admin} do
      assert {:ok, domain} =
               Shortener.create_domain(%{hostname: "  GO.Example  "}, actor: admin)

      assert domain.hostname == "go.example"
      assert domain.active
      refute domain.is_primary
    end

    test "single-label hostnames are allowed for development", %{admin: admin} do
      assert {:ok, domain} = Shortener.create_domain(%{hostname: "localhost"}, actor: admin)
      assert domain.hostname == "localhost"
    end

    test "non-admin users are forbidden", %{user: user} do
      assert {:error, %Ash.Error.Forbidden{}} =
               Shortener.create_domain(%{hostname: "go.example"}, actor: user)
    end

    test "invalid hostnames are rejected", %{admin: admin} do
      for hostname <- ["not a host", "-bad.example", "bad-.example", ""] do
        assert {:error, %Ash.Error.Invalid{}} =
                 Shortener.create_domain(%{hostname: hostname}, actor: admin),
               "expected invalid: #{inspect(hostname)}"
      end
    end

    test "duplicate hostnames are rejected", %{admin: admin} do
      assert {:ok, _} = Shortener.create_domain(%{hostname: "go.example"}, actor: admin)

      assert {:error, %Ash.Error.Invalid{}} =
               Shortener.create_domain(%{hostname: "go.example"}, actor: admin)
    end
  end

  describe "read" do
    test "any signed-in user can list domains", %{admin: admin, user: user} do
      {:ok, _} = Shortener.create_domain(%{hostname: "go.example"}, actor: admin)

      assert {:ok, [domain]} = Shortener.list_domains(actor: user)
      assert domain.hostname == "go.example"
    end
  end

  describe "primary domain is protected" do
    test "cannot be deleted", %{admin: admin} do
      primary = domain_fixture(%{hostname: "primary.example", is_primary: true})

      assert {:error, %Ash.Error.Invalid{}} =
               Shortener.destroy_domain(primary, actor: admin)
    end

    test "cannot be deactivated", %{admin: admin} do
      primary = domain_fixture(%{hostname: "primary.example", is_primary: true})

      assert {:error, %Ash.Error.Invalid{}} =
               Shortener.update_domain(primary, %{active: false}, actor: admin)
    end

    test "redirect domains stay deletable and deactivatable", %{admin: admin} do
      domain = domain_fixture(%{hostname: "redirect.example"})

      assert {:ok, deactivated} =
               Shortener.update_domain(domain, %{active: false}, actor: admin)

      refute deactivated.active
      assert :ok = Shortener.destroy_domain(deactivated, actor: admin)
    end
  end
end
