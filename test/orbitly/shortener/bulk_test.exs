defmodule Orbitly.Shortener.BulkTest do
  use Orbitly.DataCase, async: false

  import Orbitly.Fixtures

  alias Orbitly.Shortener
  alias Orbitly.Shortener.{ClickEvent, RedirectCache}

  setup do
    %{
      user: user_fixture(),
      other: user_fixture(),
      admin: admin_fixture(),
      domain: domain_fixture()
    }
  end

  describe "delete_links/2" do
    test "deletes several own links at once", ctx do
      a = link_fixture(ctx.user, ctx.domain)
      b = link_fixture(ctx.user, ctx.domain)
      keep = link_fixture(ctx.user, ctx.domain)

      assert {:ok, 2} = Shortener.delete_links([a.id, b.id], ctx.user)
      assert [remaining] = Shortener.list_links(ctx.user)
      assert remaining.id == keep.id
    end

    test "never touches another user's links", ctx do
      mine = link_fixture(ctx.user, ctx.domain)
      theirs = link_fixture(ctx.other, ctx.domain)

      assert {:ok, 1} = Shortener.delete_links([mine.id, theirs.id], ctx.user)
      assert [survivor] = Shortener.list_links(ctx.other)
      assert survivor.id == theirs.id
    end

    test "an admin may delete across owners", ctx do
      mine = link_fixture(ctx.user, ctx.domain)
      theirs = link_fixture(ctx.other, ctx.domain)

      assert {:ok, 2} = Shortener.delete_links([mine.id, theirs.id], ctx.admin)
      assert [] = Shortener.list_links(ctx.admin)
    end

    test "deletes the click events of the deleted links", ctx do
      link = link_fixture(ctx.user, ctx.domain)

      Repo.insert!(
        struct(ClickEvent, %{
          link_id: link.id,
          occurred_at: DateTime.utc_now(),
          ip: "203.0.113.1"
        })
      )

      assert {:ok, 1} = Shortener.delete_links([link.id], ctx.user)
      assert [] = Shortener.list_click_events(ctx.admin)
    end

    test "rejects an anonymous caller", ctx do
      link = link_fixture(ctx.user, ctx.domain)

      assert {:error, :unauthorized} = Shortener.delete_links([link.id], nil)
      assert [_] = Shortener.list_links(ctx.user)
    end

    test "ignores malformed and unknown ids", ctx do
      link = link_fixture(ctx.user, ctx.domain)

      assert {:ok, 0} = Shortener.delete_links(["not-a-uuid", Ecto.UUID.generate()], ctx.user)
      assert {:ok, 1} = Shortener.delete_links([link.id, "not-a-uuid"], ctx.user)
    end

    test "an empty id list is a no-op", ctx do
      assert {:ok, 0} = Shortener.delete_links([], ctx.user)
    end
  end

  describe "reassign_links/3" do
    test "an admin moves links to another owner", ctx do
      a = link_fixture(ctx.user, ctx.domain)
      b = link_fixture(ctx.user, ctx.domain)

      assert {:ok, 2} = Shortener.reassign_links([a.id, b.id], ctx.other.id, ctx.admin)

      assert [] = Shortener.list_links(ctx.user)
      assert length(Shortener.list_links(ctx.other)) == 2
    end

    test "a non-admin may not reassign, not even their own links", ctx do
      link = link_fixture(ctx.user, ctx.domain)

      assert {:error, :unauthorized} =
               Shortener.reassign_links([link.id], ctx.other.id, ctx.user)

      assert [unchanged] = Shortener.list_links(ctx.user)
      assert unchanged.owner_id == ctx.user.id
    end

    test "rejects an anonymous caller", ctx do
      link = link_fixture(ctx.user, ctx.domain)

      assert {:error, :unauthorized} = Shortener.reassign_links([link.id], ctx.other.id, nil)
    end

    test "rejects an unknown target owner", ctx do
      link = link_fixture(ctx.user, ctx.domain)

      assert {:error, :invalid_owner} =
               Shortener.reassign_links([link.id], Ecto.UUID.generate(), ctx.admin)

      assert [unchanged] = Shortener.list_links(ctx.user)
      assert unchanged.owner_id == ctx.user.id
    end

    test "rejects a malformed target owner id", ctx do
      link = link_fixture(ctx.user, ctx.domain)

      assert {:error, :invalid_owner} = Shortener.reassign_links([link.id], "nope", ctx.admin)
    end

    test "ignores malformed and unknown link ids", ctx do
      assert {:ok, 0} =
               Shortener.reassign_links(["not-a-uuid"], ctx.other.id, ctx.admin)
    end

    test "bumps updated_at", ctx do
      link = link_fixture(ctx.user, ctx.domain)

      assert {:ok, 1} = Shortener.reassign_links([link.id], ctx.other.id, ctx.admin)

      assert [moved] = Shortener.list_links(ctx.other)
      assert DateTime.compare(moved.updated_at, link.updated_at) == :gt
    end
  end

  describe "duplicate_links/3" do
    test "copies the links onto the target domain, leaving the originals", ctx do
      target = domain_fixture()
      link = link_fixture(ctx.user, ctx.domain, %{slug: "keep"})

      assert {:ok, 1, 0} = Shortener.duplicate_links([link.id], target.id, ctx.user)

      links = Shortener.list_links(ctx.user)
      assert length(links) == 2
      assert Enum.count(links, &(&1.domain_id == ctx.domain.id)) == 1
      assert Enum.count(links, &(&1.domain_id == target.id)) == 1
      assert Enum.all?(links, &(&1.slug == "keep"))
    end

    test "the copy is a new row, not a moved one", ctx do
      target = domain_fixture()
      link = link_fixture(ctx.user, ctx.domain, %{slug: "dup"})

      assert {:ok, 1, 0} = Shortener.duplicate_links([link.id], target.id, ctx.user)

      copy = Enum.find(Shortener.list_links(ctx.user), &(&1.domain_id == target.id))
      refute copy.id == link.id
    end

    test "skips slugs already present on the target domain", ctx do
      target = domain_fixture()
      a = link_fixture(ctx.user, ctx.domain, %{slug: "free"})
      b = link_fixture(ctx.user, ctx.domain, %{slug: "taken"})
      _clash = link_fixture(ctx.user, target, %{slug: "taken"})

      assert {:ok, 1, 1} = Shortener.duplicate_links([a.id, b.id], target.id, ctx.user)
      assert Enum.count(Shortener.list_links(ctx.user), &(&1.domain_id == target.id)) == 2
    end

    test "carries password protection and expiry over to the copy", ctx do
      target = domain_fixture()
      expires = DateTime.add(DateTime.utc_now(), 3600, :second)

      link =
        link_fixture(ctx.user, ctx.domain, %{
          slug: "secret",
          password_hash: "$2b$fakehash",
          expires_at: expires
        })

      assert {:ok, 1, 0} = Shortener.duplicate_links([link.id], target.id, ctx.user)

      copy = Enum.find(Shortener.list_links(ctx.user), &(&1.domain_id == target.id))
      assert copy.password_hash == "$2b$fakehash"
      assert copy.expires_at
    end

    test "keeps the original owner when an admin duplicates another user's link", ctx do
      target = domain_fixture()
      link = link_fixture(ctx.other, ctx.domain, %{slug: "theirs"})

      assert {:ok, 1, 0} = Shortener.duplicate_links([link.id], target.id, ctx.admin)

      copy = Enum.find(Shortener.list_links(ctx.admin), &(&1.domain_id == target.id))
      assert copy.owner_id == ctx.other.id
    end

    test "does not copy the click history", ctx do
      target = domain_fixture()
      link = link_fixture(ctx.user, ctx.domain, %{slug: "clicked"})

      Repo.insert!(
        struct(ClickEvent, %{
          link_id: link.id,
          occurred_at: DateTime.utc_now(),
          ip: "203.0.113.9"
        })
      )

      assert {:ok, 1, 0} = Shortener.duplicate_links([link.id], target.id, ctx.user)
      assert length(Shortener.list_click_events(ctx.admin)) == 1
    end

    test "the copy resolves on the redirect hot path", ctx do
      target = domain_fixture()
      link = link_fixture(ctx.user, ctx.domain, %{slug: "hot"})

      assert {:ok, 1, 0} = Shortener.duplicate_links([link.id], target.id, ctx.user)

      assert {:ok, resolved} = RedirectCache.fetch_link(target.hostname, "hot")
      assert resolved.target_url == link.target_url
    end

    test "never copies another user's link", ctx do
      target = domain_fixture()
      mine = link_fixture(ctx.user, ctx.domain, %{slug: "mine"})
      theirs = link_fixture(ctx.other, ctx.domain, %{slug: "theirs"})

      assert {:ok, 1, 0} = Shortener.duplicate_links([mine.id, theirs.id], target.id, ctx.user)
      assert Enum.count(Shortener.list_links(ctx.user), &(&1.domain_id == target.id)) == 1
    end

    test "a normal user may duplicate their own links", ctx do
      target = domain_fixture()
      link = link_fixture(ctx.user, ctx.domain, %{slug: "ok"})

      assert {:ok, 1, 0} = Shortener.duplicate_links([link.id], target.id, ctx.user)
    end

    test "rejects an anonymous caller", ctx do
      target = domain_fixture()
      link = link_fixture(ctx.user, ctx.domain)

      assert {:error, :unauthorized} = Shortener.duplicate_links([link.id], target.id, nil)
    end

    test "rejects an unknown target domain", ctx do
      link = link_fixture(ctx.user, ctx.domain)

      assert {:error, :invalid_domain} =
               Shortener.duplicate_links([link.id], Ecto.UUID.generate(), ctx.user)
    end

    test "rejects an inactive target domain", ctx do
      target = domain_fixture(%{active: false})
      link = link_fixture(ctx.user, ctx.domain)

      assert {:error, :invalid_domain} =
               Shortener.duplicate_links([link.id], target.id, ctx.user)
    end

    test "rejects a malformed target domain id", ctx do
      link = link_fixture(ctx.user, ctx.domain)

      assert {:error, :invalid_domain} = Shortener.duplicate_links([link.id], "nope", ctx.user)
    end

    test "ignores malformed and unknown link ids", ctx do
      target = domain_fixture()

      assert {:ok, 0, 0} =
               Shortener.duplicate_links(
                 ["not-a-uuid", Ecto.UUID.generate()],
                 target.id,
                 ctx.user
               )
    end
  end
end
