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
                 ctx.user
               )

      assert link.slug == "my-slug"
      assert link.owner_id == ctx.user.id
      assert is_nil(link.password_hash)
    end

    test "generates a valid 7-char slug when none is given", ctx do
      assert {:ok, link} =
               Shortener.create_link(
                 %{target_url: "https://example.com", domain_id: ctx.domain.id},
                 ctx.user
               )

      assert String.length(link.slug) == 7
      assert Slug.valid_format?(link.slug)
    end

    test "a root sentinel (/ or @) stores an empty slug", ctx do
      for sentinel <- ["/", "@"] do
        domain = domain_fixture()

        assert {:ok, link} =
                 Shortener.create_link(
                   %{slug: sentinel, target_url: "https://root.example", domain_id: domain.id},
                   ctx.user
                 )

        assert link.slug == ""
      end
    end

    test "a catch-all sentinel (/* or *) stores a star slug", ctx do
      for sentinel <- ["/*", "*"] do
        domain = domain_fixture()

        assert {:ok, link} =
                 Shortener.create_link(
                   %{
                     slug: sentinel,
                     target_url: "https://fallback.example",
                     domain_id: domain.id
                   },
                   ctx.user
                 )

        assert link.slug == "*"
      end
    end

    test "at most one root and one catch-all per domain", ctx do
      root = %{slug: "/", target_url: "https://a", domain_id: ctx.domain.id}
      catchall = %{slug: "/*", target_url: "https://b", domain_id: ctx.domain.id}

      assert {:ok, _} = Shortener.create_link(root, ctx.user)
      assert {:error, %Ecto.Changeset{}} = Shortener.create_link(root, ctx.user)

      assert {:ok, _} = Shortener.create_link(catchall, ctx.user)
      assert {:error, %Ecto.Changeset{}} = Shortener.create_link(catchall, ctx.user)
    end

    test "rejects reserved slugs", ctx do
      assert {:error, %Ecto.Changeset{}} =
               Shortener.create_link(
                 %{slug: "admin", target_url: "https://example.com", domain_id: ctx.domain.id},
                 ctx.user
               )
    end

    test "rejects malformed slugs", ctx do
      for slug <- ["a b", "ä", "a/b", String.duplicate("x", 65)] do
        assert {:error, %Ecto.Changeset{}} =
                 Shortener.create_link(
                   %{slug: slug, target_url: "https://example.com", domain_id: ctx.domain.id},
                   ctx.user
                 ),
               "expected invalid: #{inspect(slug)}"
      end
    end

    test "rejects non-http(s) or hostless target URLs", ctx do
      for url <- ["ftp://example.com", "https://", "not a url", ""] do
        assert {:error, %Ecto.Changeset{}} =
                 Shortener.create_link(
                   %{slug: "ok-slug", target_url: url, domain_id: ctx.domain.id},
                   ctx.user
                 ),
               "expected invalid: #{inspect(url)}"
      end
    end

    test "slug must be unique per domain, may repeat on another domain", ctx do
      other_domain = domain_fixture()

      assert {:ok, _} =
               Shortener.create_link(
                 %{slug: "taken", target_url: "https://example.com", domain_id: ctx.domain.id},
                 ctx.user
               )

      assert {:error, %Ecto.Changeset{}} =
               Shortener.create_link(
                 %{slug: "taken", target_url: "https://example.com", domain_id: ctx.domain.id},
                 ctx.other
               )

      assert {:ok, _} =
               Shortener.create_link(
                 %{slug: "taken", target_url: "https://example.com", domain_id: other_domain.id},
                 ctx.user
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
                 ctx.user
               )

      assert Bcrypt.verify_pass("hunter22", link.password_hash)
    end
  end

  describe "authorization" do
    test "owners only see their own links, admins see all", ctx do
      link_fixture(ctx.user, ctx.domain)
      link_fixture(ctx.other, ctx.domain)

      assert user_links = Shortener.list_links(ctx.user)
      assert length(user_links) == 1

      assert all_links = Shortener.list_links(ctx.admin)
      assert length(all_links) == 2
    end

    test "only the owner or an admin may update", ctx do
      link = link_fixture(ctx.user, ctx.domain)

      assert {:error, :unauthorized} =
               Shortener.update_link(link, %{target_url: "https://evil.example"}, ctx.other)

      assert {:ok, updated} =
               Shortener.update_link(link, %{target_url: "https://new.example"}, ctx.user)

      assert updated.target_url == "https://new.example"

      assert {:ok, _} =
               Shortener.update_link(updated, %{target_url: "https://admin.example"}, ctx.admin)
    end

    test "owner can destroy their link", ctx do
      link = link_fixture(ctx.user, ctx.domain)

      assert :ok = Shortener.delete_link(link, ctx.user)
      assert [] = Shortener.list_links(ctx.user)
    end
  end
end
