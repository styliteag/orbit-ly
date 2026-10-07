defmodule Orbitly.Shortener.DomainAliasTest do
  use Orbitly.DataCase, async: false

  import Orbitly.Fixtures

  alias Orbitly.Repo
  alias Orbitly.Shortener
  alias Orbitly.Shortener.Domain

  setup do
    %{
      admin: admin_fixture(),
      user: user_fixture(),
      target: domain_fixture(%{hostname: "stylite.io"})
    }
  end

  describe "creating an alias" do
    test "admin creates an alias of another domain", ctx do
      assert {:ok, domain} =
               Shortener.create_domain(
                 %{hostname: "stylite.de", alias_of_id: ctx.target.id},
                 ctx.admin
               )

      assert domain.alias_of_id == ctx.target.id
    end

    test "a blank alias_of_id creates a plain domain", ctx do
      assert {:ok, domain} =
               Shortener.create_domain(
                 %{"hostname" => "plain.example", "alias_of_id" => ""},
                 ctx.admin
               )

      assert is_nil(domain.alias_of_id)
    end

    test "an alias of an alias is rejected (no chains)", ctx do
      alias_domain = domain_fixture(%{hostname: "stylite.de", alias_of_id: ctx.target.id})

      assert {:error, %Ecto.Changeset{} = cs} =
               Shortener.create_domain(
                 %{hostname: "stylite.ch", alias_of_id: alias_domain.id},
                 ctx.admin
               )

      assert %{alias_of_id: [_]} = errors_on(cs)
    end

    test "an unknown alias target is rejected", ctx do
      assert {:error, %Ecto.Changeset{} = cs} =
               Shortener.create_domain(
                 %{hostname: "stylite.de", alias_of_id: Ecto.UUID.generate()},
                 ctx.admin
               )

      assert %{alias_of_id: [_]} = errors_on(cs)
    end
  end

  describe "turning an existing domain into an alias" do
    test "a domain cannot alias itself", ctx do
      assert {:error, %Ecto.Changeset{}} =
               Shortener.update_domain(ctx.target, %{alias_of_id: ctx.target.id}, ctx.admin)
    end

    test "the primary domain can never be an alias", ctx do
      primary = domain_fixture(%{hostname: "primary.example", is_primary: true})

      assert {:error, %Ecto.Changeset{}} =
               Shortener.update_domain(primary, %{alias_of_id: ctx.target.id}, ctx.admin)
    end

    test "a domain with its own links cannot become an alias", ctx do
      other = domain_fixture(%{hostname: "other.example"})
      link_fixture(ctx.user, other)

      assert {:error, %Ecto.Changeset{} = cs} =
               Shortener.update_domain(other, %{alias_of_id: ctx.target.id}, ctx.admin)

      assert %{alias_of_id: [_]} = errors_on(cs)
    end

    test "a domain that has aliases cannot become an alias itself", ctx do
      domain_fixture(%{hostname: "stylite.de", alias_of_id: ctx.target.id})
      other = domain_fixture(%{hostname: "other.example"})

      assert {:error, %Ecto.Changeset{}} =
               Shortener.update_domain(ctx.target, %{alias_of_id: other.id}, ctx.admin)
    end

    test "an empty domain becomes an alias and can be detached again", ctx do
      other = domain_fixture(%{hostname: "other.example"})

      assert {:ok, aliased} =
               Shortener.update_domain(other, %{alias_of_id: ctx.target.id}, ctx.admin)

      assert aliased.alias_of_id == ctx.target.id

      assert {:ok, detached} = Shortener.update_domain(aliased, %{alias_of_id: nil}, ctx.admin)
      assert is_nil(detached.alias_of_id)
    end
  end

  describe "links on an alias" do
    test "creating a link on an alias domain is refused", ctx do
      alias_domain = domain_fixture(%{hostname: "stylite.de", alias_of_id: ctx.target.id})

      assert {:error, %Ecto.Changeset{} = cs} =
               Shortener.create_link(
                 %{target_url: "https://example.org", domain_id: alias_domain.id, slug: "x1"},
                 ctx.user
               )

      assert %{domain_id: [_]} = errors_on(cs)
    end

    test "duplicating onto an alias domain is refused", ctx do
      alias_domain = domain_fixture(%{hostname: "stylite.de", alias_of_id: ctx.target.id})
      link = link_fixture(ctx.user, ctx.target)

      assert {:error, :invalid_domain} =
               Shortener.duplicate_links([link.id], alias_domain.id, ctx.user)
    end
  end

  test "deleting the target keeps the alias as a plain domain", ctx do
    alias_domain = domain_fixture(%{hostname: "stylite.de", alias_of_id: ctx.target.id})

    assert :ok = Shortener.delete_domain(ctx.target, ctx.admin)

    assert %Domain{alias_of_id: nil} = Repo.get!(Domain, alias_domain.id)
  end
end
