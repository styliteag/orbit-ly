defmodule Orbitly.Shortener.LinkTest do
  use Orbitly.DataCase, async: false

  import Orbitly.Fixtures

  alias Orbitly.Shortener
  alias Orbitly.Shortener.Slug

  setup do
    %{
      user: user_fixture(),
      other: user_fixture(),
      admin: admin_fixture(),
      domain: domain_fixture()
    }
  end

  describe "create" do
    test "creates a link with a custom slug, owned by the actor", ctx do
      assert {:ok, link} =
               Shortener.create_link(
                 %{slug: "my-slug", target_url: "https://example.com", domain_id: ctx.domain.id},
                 actor: ctx.user
               )

      assert link.slug == "my-slug"
      assert link.owner_id == ctx.user.id
      assert is_nil(link.password_hash)
    end

    test "generates a valid 7-char slug when none is given", ctx do
      assert {:ok, link} =
               Shortener.create_link(
                 %{target_url: "https://example.com", domain_id: ctx.domain.id},
                 actor: ctx.user
               )

      assert String.length(link.slug) == 7
      assert Slug.valid_format?(link.slug)
    end

    test "rejects reserved slugs", ctx do
      assert {:error, %Ash.Error.Invalid{}} =
               Shortener.create_link(
                 %{slug: "admin", target_url: "https://example.com", domain_id: ctx.domain.id},
                 actor: ctx.user
               )
    end

    test "rejects malformed slugs", ctx do
      for slug <- ["a b", "ä", "a/b", String.duplicate("x", 65)] do
        assert {:error, %Ash.Error.Invalid{}} =
                 Shortener.create_link(
                   %{slug: slug, target_url: "https://example.com", domain_id: ctx.domain.id},
                   actor: ctx.user
                 ),
               "expected invalid: #{inspect(slug)}"
      end
    end

    test "rejects non-http(s) or hostless target URLs", ctx do
      for url <- ["ftp://example.com", "https://", "not a url", ""] do
        assert {:error, %Ash.Error.Invalid{}} =
                 Shortener.create_link(
                   %{slug: "ok-slug", target_url: url, domain_id: ctx.domain.id},
                   actor: ctx.user
                 ),
               "expected invalid: #{inspect(url)}"
      end
    end

    test "slug must be unique per domain, may repeat on another domain", ctx do
      other_domain = domain_fixture()

      assert {:ok, _} =
               Shortener.create_link(
                 %{slug: "taken", target_url: "https://example.com", domain_id: ctx.domain.id},
                 actor: ctx.user
               )

      assert {:error, %Ash.Error.Invalid{}} =
               Shortener.create_link(
                 %{slug: "taken", target_url: "https://example.com", domain_id: ctx.domain.id},
                 actor: ctx.other
               )

      assert {:ok, _} =
               Shortener.create_link(
                 %{slug: "taken", target_url: "https://example.com", domain_id: other_domain.id},
                 actor: ctx.user
               )
    end

    test "password argument stores a verifiable hash", ctx do
      assert {:ok, link} =
               Shortener.create_link(
                 %{
                   slug: "secret",
                   target_url: "https://example.com",
                   domain_id: ctx.domain.id,
                   password: "hunter22"
                 },
                 actor: ctx.user
               )

      assert Bcrypt.verify_pass("hunter22", link.password_hash)
    end
  end

  describe "authorization" do
    test "owners only see their own links, admins see all", ctx do
      link_fixture(ctx.user, ctx.domain)
      link_fixture(ctx.other, ctx.domain)

      assert {:ok, user_links} = Shortener.list_links(actor: ctx.user)
      assert length(user_links) == 1

      assert {:ok, all_links} = Shortener.list_links(actor: ctx.admin)
      assert length(all_links) == 2
    end

    test "only the owner or an admin may update", ctx do
      link = link_fixture(ctx.user, ctx.domain)

      assert {:error, %Ash.Error.Forbidden{}} =
               Shortener.update_link(link, %{target_url: "https://evil.example"},
                 actor: ctx.other
               )

      assert {:ok, updated} =
               Shortener.update_link(link, %{target_url: "https://new.example"}, actor: ctx.user)

      assert updated.target_url == "https://new.example"

      assert {:ok, _} =
               Shortener.update_link(updated, %{target_url: "https://admin.example"},
                 actor: ctx.admin
               )
    end

    test "owner can destroy their link", ctx do
      link = link_fixture(ctx.user, ctx.domain)

      assert :ok = Shortener.destroy_link(link, actor: ctx.user)
      assert {:ok, []} = Shortener.list_links(actor: ctx.user)
    end
  end
end
