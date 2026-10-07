defmodule Orbitly.Shortener.DomainAccessTest do
  use Orbitly.DataCase, async: false

  import Orbitly.Fixtures

  alias Orbitly.Accounts.User
  alias Orbitly.Repo
  alias Orbitly.Shortener

  setup do
    a = domain_fixture(%{hostname: "a.example"})
    b = domain_fixture(%{hostname: "b.example"})
    %{admin: admin_fixture(), user: user_fixture(), a: a, b: b}
  end

  defp hostnames(domains), do: domains |> Enum.map(& &1.hostname) |> Enum.sort()

  defp restrict!(ctx, user, domain_ids) do
    {:ok, user} =
      Shortener.set_domain_access(user, %{all_domains: false, domain_ids: domain_ids}, ctx.admin)

    user
  end

  describe "usable_domains/1" do
    test "a new user may use every active non-alias domain", ctx do
      inactive = domain_fixture(%{hostname: "off.example", active: false})
      domain_fixture(%{hostname: "alias.example", alias_of_id: ctx.a.id})

      assert hostnames(Shortener.usable_domains(ctx.user)) == ["a.example", "b.example"]
      refute inactive.id in Enum.map(Shortener.usable_domains(ctx.user), & &1.id)
    end

    test "a restricted user only sees the granted domains", ctx do
      user = restrict!(ctx, ctx.user, [ctx.a.id])

      assert hostnames(Shortener.usable_domains(user)) == ["a.example"]
      assert Shortener.granted_domain_ids(user) == [ctx.a.id]
    end

    test "a restricted user with no grants sees nothing", ctx do
      user = restrict!(ctx, ctx.user, [])

      assert Shortener.usable_domains(user) == []
    end

    test "a stale caller struct cannot outlive a revocation", ctx do
      stale = ctx.user
      restrict!(ctx, ctx.user, [ctx.a.id])

      assert stale.all_domains
      assert hostnames(Shortener.usable_domains(stale)) == ["a.example"]
    end

    test "admins always see every domain, even when restricted", ctx do
      admin = restrict!(ctx, ctx.admin, [ctx.a.id])

      assert hostnames(Shortener.usable_domains(admin)) == ["a.example", "b.example"]
    end
  end

  describe "set_domain_access/3" do
    test "only admins may change domain access", ctx do
      assert {:error, :unauthorized} =
               Shortener.set_domain_access(
                 ctx.user,
                 %{all_domains: false, domain_ids: []},
                 ctx.user
               )
    end

    test "re-granting all domains keeps the list but lifts the restriction", ctx do
      user = restrict!(ctx, ctx.user, [ctx.a.id])

      {:ok, user} =
        Shortener.set_domain_access(user, %{all_domains: true, domain_ids: [ctx.a.id]}, ctx.admin)

      assert user.all_domains
      assert hostnames(Shortener.usable_domains(user)) == ["a.example", "b.example"]
    end

    test "tampered and unknown ids are dropped", ctx do
      user = restrict!(ctx, ctx.user, [ctx.a.id, "nope", Ecto.UUID.generate()])

      assert Shortener.granted_domain_ids(user) == [ctx.a.id]
    end

    test "deleting a domain removes its grants", ctx do
      user = restrict!(ctx, ctx.user, [ctx.a.id])

      :ok = Shortener.delete_domain(ctx.a, ctx.admin)

      assert Shortener.granted_domain_ids(user) == []
    end
  end

  describe "default domain" do
    test "a user sets their own default domain", ctx do
      assert {:ok, user} = Shortener.set_default_domain(ctx.user, ctx.b.id, ctx.user)
      assert user.default_domain_id == ctx.b.id
      assert Shortener.default_domain_id(user, Shortener.usable_domains(user)) == ctx.b.id
    end

    test "an admin sets it for another user", ctx do
      assert {:ok, user} = Shortener.set_default_domain(ctx.user, ctx.b.id, ctx.admin)
      assert user.default_domain_id == ctx.b.id
    end

    test "another normal user cannot set it", ctx do
      other = user_fixture()

      assert {:error, :unauthorized} = Shortener.set_default_domain(ctx.user, ctx.b.id, other)
    end

    test "only a usable domain can be the default", ctx do
      user = restrict!(ctx, ctx.user, [ctx.a.id])

      assert {:error, :invalid_domain} = Shortener.set_default_domain(user, ctx.b.id, user)
      assert {:error, :invalid_domain} = Shortener.set_default_domain(user, "nope", user)
    end

    test "nil clears the default", ctx do
      {:ok, user} = Shortener.set_default_domain(ctx.user, ctx.b.id, ctx.user)

      assert {:ok, %User{default_domain_id: nil}} = Shortener.set_default_domain(user, nil, user)
    end

    test "a revoked default falls back to the first usable domain", ctx do
      {:ok, user} = Shortener.set_default_domain(ctx.user, ctx.b.id, ctx.user)
      user = restrict!(ctx, user, [ctx.a.id])

      assert Shortener.default_domain_id(user, Shortener.usable_domains(user)) == ctx.a.id
    end

    test "without a default the primary domain comes first", ctx do
      primary = domain_fixture(%{hostname: "z-primary.example", is_primary: true})

      assert Shortener.default_domain_id(ctx.user, Shortener.usable_domains(ctx.user)) ==
               primary.id
    end

    test "deleting the default domain clears it", ctx do
      {:ok, user} = Shortener.set_default_domain(ctx.user, ctx.b.id, ctx.user)

      :ok = Shortener.delete_domain(ctx.b, ctx.admin)

      assert is_nil(Repo.get!(User, user.id).default_domain_id)
    end
  end

  describe "enforcement" do
    test "a restricted user cannot create a link on another domain", ctx do
      user = restrict!(ctx, ctx.user, [ctx.a.id])

      assert {:error, %Ecto.Changeset{} = cs} =
               Shortener.create_link(
                 %{target_url: "https://example.org", domain_id: ctx.b.id, slug: "x1"},
                 user
               )

      assert %{domain_id: [_]} = errors_on(cs)

      assert {:ok, _} =
               Shortener.create_link(
                 %{target_url: "https://example.org", domain_id: ctx.a.id, slug: "x1"},
                 user
               )
    end

    test "a restricted user cannot duplicate onto another domain", ctx do
      link = link_fixture(ctx.user, ctx.a)
      user = restrict!(ctx, ctx.user, [ctx.a.id])

      assert {:error, :invalid_domain} = Shortener.duplicate_links([link.id], ctx.b.id, user)
    end

    test "links on a revoked domain stay editable", ctx do
      link = link_fixture(ctx.user, ctx.b)
      user = restrict!(ctx, ctx.user, [ctx.a.id])

      assert {:ok, updated} =
               Shortener.update_link(link, %{target_url: "https://example.org/new"}, user)

      assert updated.target_url == "https://example.org/new"
    end
  end
end
