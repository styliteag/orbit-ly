defmodule Orbitly.Shortener.DomainTest do
  use Orbitly.DataCase, async: false

  import Orbitly.Fixtures

  alias Orbitly.Shortener

  setup do
    %{admin: admin_fixture(), user: user_fixture()}
  end

  describe "create" do
    test "admin creates a domain, hostname is normalized", %{admin: admin} do
      assert {:ok, domain} = Shortener.create_domain(%{hostname: "  GO.Example  "}, admin)

      assert domain.hostname == "go.example"
      assert domain.active
      refute domain.is_primary
    end

    test "single-label hostnames are allowed for development", %{admin: admin} do
      assert {:ok, domain} = Shortener.create_domain(%{hostname: "localhost"}, admin)
      assert domain.hostname == "localhost"
    end

    test "non-admin users are forbidden", %{user: user} do
      assert {:error, :unauthorized} =
               Shortener.create_domain(%{hostname: "go.example"}, user)
    end

    test "invalid hostnames are rejected", %{admin: admin} do
      for hostname <- ["not a host", "-bad.example", "bad-.example", ""] do
        assert {:error, %Ecto.Changeset{}} =
                 Shortener.create_domain(%{hostname: hostname}, admin),
               "expected invalid: #{inspect(hostname)}"
      end
    end

    test "duplicate hostnames are rejected", %{admin: admin} do
      assert {:ok, _} = Shortener.create_domain(%{hostname: "go.example"}, admin)

      assert {:error, %Ecto.Changeset{}} =
               Shortener.create_domain(%{hostname: "go.example"}, admin)
    end
  end

  describe "read" do
    test "listing returns created domains", %{admin: admin} do
      {:ok, _} = Shortener.create_domain(%{hostname: "go.example"}, admin)

      assert [domain] = Shortener.list_domains()
      assert domain.hostname == "go.example"
    end
  end

  describe "primary domain is protected" do
    test "cannot be deleted", %{admin: admin} do
      primary = domain_fixture(%{hostname: "primary.example", is_primary: true})

      assert {:error, :primary_protected} = Shortener.delete_domain(primary, admin)
    end

    test "cannot be deactivated", %{admin: admin} do
      primary = domain_fixture(%{hostname: "primary.example", is_primary: true})

      assert {:error, %Ecto.Changeset{}} =
               Shortener.update_domain(primary, %{active: false}, admin)
    end

    test "redirect domains stay deletable and deactivatable", %{admin: admin} do
      domain = domain_fixture(%{hostname: "redirect.example"})

      assert {:ok, deactivated} = Shortener.update_domain(domain, %{active: false}, admin)

      refute deactivated.active
      assert :ok = Shortener.delete_domain(deactivated, admin)
    end
  end
end
