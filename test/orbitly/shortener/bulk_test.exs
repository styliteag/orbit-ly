defmodule Orbitly.Shortener.BulkTest do
  use Orbitly.DataCase, async: false

  import Orbitly.Fixtures

  alias Orbitly.Shortener
  alias Orbitly.Shortener.ClickEvent

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
end
