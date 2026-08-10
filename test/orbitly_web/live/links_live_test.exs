defmodule OrbitlyWeb.LinksLiveTest do
  use OrbitlyWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Orbitly.Fixtures

  setup do
    %{user: registered_user_fixture(), domain: domain_fixture(%{hostname: "go.example"})}
  end

  test "redirects anonymous visitors to sign-in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/links")
  end

  test "creates a link through the form", %{conn: conn, user: user, domain: domain} do
    {:ok, view, _html} = conn |> log_in(user) |> live(~p"/links")

    view
    |> form("#link-form", %{
      "form" => %{
        "domain_id" => domain.id,
        "slug" => "my-live-slug",
        "target_url" => "https://example.org/target"
      }
    })
    |> render_submit()

    html = render(view)
    assert html =~ "go.example/my-live-slug"
    assert html =~ "https://example.org/target"
  end

  test "shows validation errors without creating anything", %{
    conn: conn,
    user: user,
    domain: domain
  } do
    {:ok, view, _html} = conn |> log_in(user) |> live(~p"/links")

    view
    |> form("#link-form", %{
      "form" => %{"domain_id" => domain.id, "slug" => "admin", "target_url" => "https://x.org/"}
    })
    |> render_submit()

    assert render(view) =~ "is reserved"
    assert [] = Orbitly.Shortener.list_links(user)
  end

  test "creates a link with description and duration-based expiry", %{
    conn: conn,
    user: user,
    domain: domain
  } do
    {:ok, view, _html} = conn |> log_in(user) |> live(~p"/links")

    view
    |> form("#link-form", %{
      "form" => %{
        "domain_id" => domain.id,
        "slug" => "expiring",
        "target_url" => "https://example.org/x",
        "description" => "Kampagnen-Link",
        "expire_amount" => "2",
        "expire_unit" => "hours"
      }
    })
    |> render_submit()

    assert render(view) =~ "Kampagnen-Link"

    [link] = Orbitly.Shortener.list_links(user)
    assert link.description == "Kampagnen-Link"

    diff = DateTime.diff(link.expires_at, DateTime.utc_now())
    assert_in_delta diff, 2 * 3600, 60
  end

  test "shortens with only a URL using the default domain", %{conn: conn, user: user} do
    {:ok, view, _html} = conn |> log_in(user) |> live(~p"/links")

    view
    |> form("#link-form", %{"form" => %{"target_url" => "https://example.org/quick"}})
    |> render_submit()

    assert [link] = Orbitly.Shortener.list_links(user)
    assert link.target_url == "https://example.org/quick"
    assert render(view) =~ "go.example/#{link.slug}"
  end

  test "expands advanced options when a save error hits a hidden field", %{
    conn: conn,
    user: user,
    domain: domain
  } do
    link_fixture(user, domain, %{slug: "taken"})

    {:ok, view, _html} = conn |> log_in(user) |> live(~p"/links")
    assert view |> element("#advanced-options") |> render() =~ "hidden"

    view
    |> form("#link-form", %{
      "form" => %{"domain_id" => domain.id, "slug" => "taken", "target_url" => "https://x.org/"}
    })
    |> render_submit()

    refute view |> element("#advanced-options") |> render() =~ "hidden"
    assert render(view) =~ "has already been taken"
  end

  test "search filters the table", %{conn: conn, user: user, domain: domain} do
    link_fixture(user, domain, %{slug: "apple", target_url: "https://apple.example/"})
    link_fixture(user, domain, %{slug: "banana", target_url: "https://banana.example/"})

    {:ok, view, _html} = conn |> log_in(user) |> live(~p"/links")

    html = view |> element("form[phx-change=search]") |> render_change(%{"q" => "banana"})

    assert html =~ "banana"
    refute html =~ "apple.example"
  end

  test "pagination slices the table", %{conn: conn, user: user, domain: domain} do
    for i <- 1..12, do: link_fixture(user, domain, %{slug: "bulk-#{i}"})

    {:ok, view, _html} = conn |> log_in(user) |> live(~p"/links")

    html = view |> element(~s{[phx-click="page-size"][phx-value-size="10"]}) |> render_click()
    assert count_rows(html) == 10

    html_page2 = view |> element(~s{[phx-click="page"][phx-value-dir="next"]}) |> render_click()
    assert count_rows(html_page2) == 2
  end

  test "pressing enter in the search box filters instead of reloading", %{
    conn: conn,
    user: user,
    domain: domain
  } do
    link_fixture(user, domain, %{slug: "apple", target_url: "https://apple.example/"})
    link_fixture(user, domain, %{slug: "banana", target_url: "https://banana.example/"})

    {:ok, view, _html} = conn |> log_in(user) |> live(~p"/links")

    html = view |> form("#search-form") |> render_submit(%{"q" => "banana"})

    assert html =~ "banana"
    refute html =~ "apple.example"
  end

  test "ignores tampered page-size payloads", %{conn: conn, user: user, domain: domain} do
    link_fixture(user, domain, %{slug: "steady"})

    {:ok, view, _html} = conn |> log_in(user) |> live(~p"/links")

    assert render_click(view, "page-size", %{"size" => "-5"}) =~ "steady"
    assert render_click(view, "page-size", %{"size" => "bogus"}) =~ "steady"
  end

  test "clamps the page when the last page empties", %{conn: conn, user: user, domain: domain} do
    for i <- 1..11, do: link_fixture(user, domain, %{slug: "bulk-#{i}"})

    {:ok, view, _html} = conn |> log_in(user) |> live(~p"/links")

    view |> element(~s{[phx-click="page-size"][phx-value-size="10"]}) |> render_click()
    html_page2 = view |> element(~s{[phx-click="page"][phx-value-dir="next"]}) |> render_click()
    [_, id] = Regex.run(~r/id="link-([0-9a-f-]{36})"/, html_page2)

    view |> element(~s{[phx-click="delete"][phx-value-id="#{id}"]}) |> render_click()

    html = render(view)
    assert count_rows(html) == 10
    refute html =~ "No links yet"
  end

  defp count_rows(html), do: html |> String.split("data-link-row") |> length() |> Kernel.-(1)

  describe "designs" do
    test "renders the Orbit design by default", %{conn: conn, user: user} do
      {:ok, _view, html} = conn |> log_in(user) |> live(~p"/links")

      assert html =~ ~s(data-design="orbit")
    end

    test "renders the Bench design after switching", %{conn: conn, user: user, domain: domain} do
      link_fixture(user, domain, %{slug: "benchy"})

      conn = conn |> log_in(user) |> put(~p"/design/bench")
      {:ok, _view, html} = live(conn, ~p"/links")

      assert html =~ ~s(data-design="bench")
      assert html =~ "shorten:"
      assert html =~ "benchy"
    end

    test "renders the Soft design after switching", %{conn: conn, user: user} do
      conn = conn |> log_in(user) |> put(~p"/design/soft")
      {:ok, _view, html} = live(conn, ~p"/links")

      assert html =~ ~s(data-design="soft")
      assert html =~ "Make it"
    end

    test "admin controls exist in every design", %{conn: conn, domain: domain} do
      admin = registered_admin_fixture()
      link = link_fixture(admin, domain, %{slug: "admin-owned"})

      for design <- ~w(orbit bench soft) do
        conn = conn |> log_in(admin) |> put(~p"/design/#{design}")
        {:ok, view, html} = live(conn, ~p"/links")

        assert html =~ "admin-owned"
        assert has_element?(view, ~s{[phx-click="scope"][phx-value-scope="own"]})
        assert has_element?(view, ~s{[phx-click="scope"][phx-value-scope="all"]})
        assert has_element?(view, ~s{[phx-click="sort"][phx-value-field="owner"]})
        assert has_element?(view, ~s{[phx-click="toggle-select"][phx-value-id="#{link.id}"]})
      end
    end

    test "the sort header shares the row grid in the list designs", %{
      conn: conn,
      user: user,
      domain: domain
    } do
      link_fixture(user, domain, %{slug: "aligned"})

      for design <- ~w(orbit soft) do
        conn = conn |> log_in(user) |> put(~p"/design/#{design}")
        {:ok, _view, html} = live(conn, ~p"/links")

        grid = "links-grid-#{design}"

        # header + one row must use the exact same track template, otherwise
        # the sort buttons drift away from the columns they sort
        assert html |> String.split(grid) |> length() >= 3, "#{design}: grid not reused"
      end
    end

    test "core actions exist in every design", %{conn: conn, user: user, domain: domain} do
      link = link_fixture(user, domain, %{slug: "everywhere"})

      for design <- ~w(orbit bench soft) do
        conn = conn |> log_in(user) |> put(~p"/design/#{design}")
        {:ok, view, html} = live(conn, ~p"/links")

        assert html =~ "everywhere"
        assert has_element?(view, "#link-form")
        assert has_element?(view, "#search-form")
        assert has_element?(view, "#advanced-options")
        assert has_element?(view, ~s{[phx-click="edit"][phx-value-id="#{link.id}"]})
        assert has_element?(view, ~s{[phx-click="delete"][phx-value-id="#{link.id}"]})
        assert has_element?(view, ~s{[phx-click="toggle-select"][phx-value-id="#{link.id}"]})
        assert has_element?(view, ~s{[phx-click="toggle-select-page"]})

        for field <- ~w(short target created clicks) do
          assert has_element?(view, ~s{[phx-click="sort"][phx-value-field="#{field}"]})
        end

        view
        |> element(~s{[phx-click="toggle-select"][phx-value-id="#{link.id}"]})
        |> render_click()

        assert has_element?(view, "#bulk-bar")
        assert has_element?(view, ~s{[phx-click="bulk-delete"]})
      end
    end
  end

  describe "bulk actions" do
    test "deletes the selected links", %{conn: conn, user: user, domain: domain} do
      a = link_fixture(user, domain, %{slug: "bulk-a"})
      b = link_fixture(user, domain, %{slug: "bulk-b"})
      keep = link_fixture(user, domain, %{slug: "bulk-keep"})

      {:ok, view, _html} = conn |> log_in(user) |> live(~p"/links")

      for id <- [a.id, b.id] do
        view |> element(~s{[phx-click="toggle-select"][phx-value-id="#{id}"]}) |> render_click()
      end

      assert render(view) =~ "2 selected"

      view |> element(~s{[phx-click="bulk-delete"]}) |> render_click()

      html = render(view)
      assert html =~ "2 links deleted"
      refute html =~ "bulk-a"
      refute html =~ "bulk-b"

      assert [survivor] = Orbitly.Shortener.list_links(user)
      assert survivor.id == keep.id
    end

    test "the bar disappears once the selection is empty", %{
      conn: conn,
      user: user,
      domain: domain
    } do
      link = link_fixture(user, domain, %{slug: "toggle-me"})

      {:ok, view, _html} = conn |> log_in(user) |> live(~p"/links")
      refute has_element?(view, "#bulk-bar")

      view
      |> element(~s{[phx-click="toggle-select"][phx-value-id="#{link.id}"]})
      |> render_click()

      assert has_element?(view, "#bulk-bar")

      view |> element(~s{[phx-click="clear-selection"]}) |> render_click()
      refute has_element?(view, "#bulk-bar")
    end

    test "select-all only takes the current page", %{conn: conn, user: user, domain: domain} do
      for i <- 1..12, do: link_fixture(user, domain, %{slug: "page-#{i}"})

      {:ok, view, _html} = conn |> log_in(user) |> live(~p"/links")

      view |> element(~s{[phx-click="page-size"][phx-value-size="10"]}) |> render_click()
      html = view |> element(~s{[phx-click="toggle-select-page"]}) |> render_click()

      assert html =~ "10 selected"

      view |> element(~s{[phx-click="bulk-delete"]}) |> render_click()
      assert length(Orbitly.Shortener.list_links(user)) == 2
    end

    test "select-all toggles the page off again", %{conn: conn, user: user, domain: domain} do
      link_fixture(user, domain, %{slug: "one"})

      {:ok, view, _html} = conn |> log_in(user) |> live(~p"/links")

      assert view |> element(~s{[phx-click="toggle-select-page"]}) |> render_click() =~
               "1 selected"

      view |> element(~s{[phx-click="toggle-select-page"]}) |> render_click()
      refute has_element?(view, "#bulk-bar")
    end

    test "a search that hides a selected link drops it from the selection", %{
      conn: conn,
      user: user,
      domain: domain
    } do
      apple = link_fixture(user, domain, %{slug: "apple", target_url: "https://apple.example/"})
      link_fixture(user, domain, %{slug: "banana", target_url: "https://banana.example/"})

      {:ok, view, _html} = conn |> log_in(user) |> live(~p"/links")

      view
      |> element(~s{[phx-click="toggle-select"][phx-value-id="#{apple.id}"]})
      |> render_click()

      assert render(view) =~ "1 selected"

      view |> form("#search-form") |> render_change(%{"q" => "banana"})
      refute has_element?(view, "#bulk-bar")

      assert length(Orbitly.Shortener.list_links(user)) == 2
    end

    test "paging away from a selected link drops it from the selection", %{
      conn: conn,
      user: user,
      domain: domain
    } do
      for i <- 1..12, do: link_fixture(user, domain, %{slug: "paged-#{i}"})

      {:ok, view, _html} = conn |> log_in(user) |> live(~p"/links")

      view |> element(~s{[phx-click="page-size"][phx-value-size="10"]}) |> render_click()

      assert view |> element(~s{[phx-click="toggle-select-page"]}) |> render_click() =~
               "10 selected"

      view |> element(~s{[phx-click="page"][phx-value-dir="next"]}) |> render_click()
      refute has_element?(view, "#bulk-bar")
    end

    test "a normal user gets no reassign form", %{conn: conn, user: user, domain: domain} do
      link = link_fixture(user, domain, %{slug: "mine"})

      {:ok, view, _html} = conn |> log_in(user) |> live(~p"/links")

      view
      |> element(~s{[phx-click="toggle-select"][phx-value-id="#{link.id}"]})
      |> render_click()

      assert has_element?(view, "#bulk-bar")
      refute has_element?(view, "#bulk-reassign-form")
    end

    test "a tampered reassign event from a normal user is refused", %{
      conn: conn,
      user: user,
      domain: domain
    } do
      link = link_fixture(user, domain, %{slug: "not-yours"})
      other = registered_user_fixture()

      {:ok, view, _html} = conn |> log_in(user) |> live(~p"/links")

      view
      |> element(~s{[phx-click="toggle-select"][phx-value-id="#{link.id}"]})
      |> render_click()

      assert render_submit(view, "bulk-reassign", %{"owner_id" => other.id}) =~
               "Not allowed to reassign links"

      assert [unchanged] = Orbitly.Shortener.list_links(user)
      assert unchanged.owner_id == user.id
    end

    test "an admin reassigns selected links to another user", %{
      conn: conn,
      user: user,
      domain: domain
    } do
      link = link_fixture(user, domain, %{slug: "handover"})
      admin = registered_admin_fixture()
      target = registered_user_fixture()

      {:ok, view, _html} = conn |> log_in(admin) |> live(~p"/links")
      view |> element(~s{[phx-click="scope"][phx-value-scope="all"]}) |> render_click()

      view
      |> element(~s{[phx-click="toggle-select"][phx-value-id="#{link.id}"]})
      |> render_click()

      assert has_element?(view, "#bulk-reassign-form")

      html =
        view
        |> form("#bulk-reassign-form", %{"owner_id" => target.id})
        |> render_submit()

      assert html =~ "1 link moved to #{target.email}"
      assert html =~ "by #{target.email}"

      assert [] = Orbitly.Shortener.list_links(user)
      assert [moved] = Orbitly.Shortener.list_links(target)
      assert moved.id == link.id
    end

    test "reassign without a target user complains instead of moving", %{
      conn: conn,
      user: user,
      domain: domain
    } do
      link = link_fixture(user, domain, %{slug: "stay"})
      admin = registered_admin_fixture()

      {:ok, view, _html} = conn |> log_in(admin) |> live(~p"/links")
      view |> element(~s{[phx-click="scope"][phx-value-scope="all"]}) |> render_click()

      view
      |> element(~s{[phx-click="toggle-select"][phx-value-id="#{link.id}"]})
      |> render_click()

      assert view |> form("#bulk-reassign-form", %{"owner_id" => ""}) |> render_submit() =~
               "Pick a user to reassign to"

      assert [unchanged] = Orbitly.Shortener.list_links(user)
      assert unchanged.owner_id == user.id
    end
  end

  test "inline edit updates target and description", %{conn: conn, user: user, domain: domain} do
    link = link_fixture(user, domain, %{slug: "editable", target_url: "https://old.example/"})

    {:ok, view, _html} = conn |> log_in(user) |> live(~p"/links")

    view
    |> element(~s{[phx-click="edit"][phx-value-id="#{link.id}"]})
    |> render_click()

    view
    |> form("#edit-form", %{
      "edit" => %{"target_url" => "https://new.example/", "description" => "renamed"}
    })
    |> render_submit()

    html = render(view)
    assert html =~ "https://new.example/"
    assert html =~ "renamed"

    [updated] = Orbitly.Shortener.list_links(user)
    assert updated.target_url == "https://new.example/"
    assert updated.description == "renamed"
  end

  describe "admin scope" do
    test "an admin starts on their own links only", %{conn: conn, user: user, domain: domain} do
      link_fixture(user, domain, %{slug: "someone-elses"})
      admin = registered_admin_fixture()
      link_fixture(admin, domain, %{slug: "my-own"})

      {:ok, _view, html} = conn |> log_in(admin) |> live(~p"/links")

      assert html =~ "my-own"
      refute html =~ "someone-elses"
    end

    test "switching to all users shows foreign links with their owner", %{
      conn: conn,
      user: user,
      domain: domain
    } do
      link_fixture(user, domain, %{slug: "someone-elses"})
      admin = registered_admin_fixture()

      {:ok, view, _html} = conn |> log_in(admin) |> live(~p"/links")

      html = view |> element(~s{[phx-click="scope"][phx-value-scope="all"]}) |> render_click()

      assert html =~ "someone-elses"
      assert html =~ user.email

      html = view |> element(~s{[phx-click="scope"][phx-value-scope="own"]}) |> render_click()
      refute html =~ "someone-elses"
    end

    test "a normal user gets no scope toggle", %{conn: conn, user: user} do
      {:ok, view, _html} = conn |> log_in(user) |> live(~p"/links")

      refute has_element?(view, ~s{[phx-click="scope"]})
    end

    test "narrowing the scope drops foreign links from the selection", %{
      conn: conn,
      user: user,
      domain: domain
    } do
      link = link_fixture(user, domain, %{slug: "foreign"})
      admin = registered_admin_fixture()

      {:ok, view, _html} = conn |> log_in(admin) |> live(~p"/links")
      view |> element(~s{[phx-click="scope"][phx-value-scope="all"]}) |> render_click()

      view
      |> element(~s{[phx-click="toggle-select"][phx-value-id="#{link.id}"]})
      |> render_click()

      assert has_element?(view, "#bulk-bar")

      view |> element(~s{[phx-click="scope"][phx-value-scope="own"]}) |> render_click()
      refute has_element?(view, "#bulk-bar")

      assert [untouched] = Orbitly.Shortener.list_links(user)
      assert untouched.id == link.id
    end

    test "ignores a tampered scope payload", %{conn: conn, user: user, domain: domain} do
      link_fixture(user, domain, %{slug: "steady"})
      admin = registered_admin_fixture()

      {:ok, view, _html} = conn |> log_in(admin) |> live(~p"/links")

      refute render_click(view, "scope", %{"scope" => "everything"}) =~ "steady"
    end
  end

  describe "sorting" do
    setup %{user: user, domain: domain} do
      old = link_fixture(user, domain, %{slug: "aaa-old", target_url: "https://zzz.example/"})
      new = link_fixture(user, domain, %{slug: "zzz-new", target_url: "https://aaa.example/"})

      %{old: old, new: new}
    end

    test "defaults to newest first and flips on a second click", %{
      conn: conn,
      user: user,
      old: old,
      new: new
    } do
      {:ok, view, _html} = conn |> log_in(user) |> live(~p"/links")

      assert first_row_id(render(view)) == new.id

      html = view |> element(~s{[phx-click="sort"][phx-value-field="created"]}) |> render_click()
      assert first_row_id(html) == old.id
    end

    test "sorts by short link and by target", %{conn: conn, user: user, old: old, new: new} do
      {:ok, view, _html} = conn |> log_in(user) |> live(~p"/links")

      html = view |> element(~s{[phx-click="sort"][phx-value-field="short"]}) |> render_click()
      assert first_row_id(html) == old.id

      html = view |> element(~s{[phx-click="sort"][phx-value-field="target"]}) |> render_click()
      assert first_row_id(html) == new.id
    end

    test "sorts by clicks", %{conn: conn, user: user, old: old} do
      for _ <- 1..3 do
        Orbitly.Repo.insert!(
          struct(Orbitly.Shortener.ClickEvent, %{
            link_id: old.id,
            occurred_at: DateTime.utc_now(),
            ip: "203.0.113.5"
          })
        )
      end

      {:ok, view, _html} = conn |> log_in(user) |> live(~p"/links")

      html = view |> element(~s{[phx-click="sort"][phx-value-field="clicks"]}) |> render_click()
      assert first_row_id(html) == old.id
    end

    test "an admin can sort by owner", %{conn: conn, domain: domain} do
      admin = registered_admin_fixture(%{email: "zzz-admin@example.com"})
      early = registered_user_fixture(%{email: "aaa-user@example.com"})
      early_link = link_fixture(early, domain, %{slug: "early-owner"})
      link_fixture(admin, domain, %{slug: "late-owner"})

      {:ok, view, _html} = conn |> log_in(admin) |> live(~p"/links")
      view |> element(~s{[phx-click="scope"][phx-value-scope="all"]}) |> render_click()

      html = view |> element(~s{[phx-click="sort"][phx-value-field="owner"]}) |> render_click()
      assert first_row_id(html) == early_link.id
    end

    test "a normal user gets no owner sort", %{conn: conn, user: user} do
      {:ok, view, _html} = conn |> log_in(user) |> live(~p"/links")

      refute has_element?(view, ~s{[phx-click="sort"][phx-value-field="owner"]})
    end

    test "ignores a tampered sort field", %{conn: conn, user: user, new: new} do
      {:ok, view, _html} = conn |> log_in(user) |> live(~p"/links")

      assert first_row_id(render_click(view, "sort", %{"field" => "owner_id; drop"})) == new.id
    end

    test "select-all takes the sorted page, not the unsorted one", %{
      conn: conn,
      user: user,
      domain: domain
    } do
      for i <- 1..10, do: link_fixture(user, domain, %{slug: "filler-#{i}"})

      {:ok, view, _html} = conn |> log_in(user) |> live(~p"/links")

      view |> element(~s{[phx-click="page-size"][phx-value-size="10"]}) |> render_click()
      view |> element(~s{[phx-click="sort"][phx-value-field="short"]}) |> render_click()
      view |> element(~s{[phx-click="toggle-select-page"]}) |> render_click()
      view |> element(~s{[phx-click="bulk-delete"]}) |> render_click()

      # Sorted by slug ascending, the first page ends at filler-8.
      remaining = user |> Orbitly.Shortener.list_links() |> Enum.map(& &1.slug) |> Enum.sort()
      assert remaining == ["filler-9", "zzz-new"]
    end
  end

  describe "list state in the URL" do
    test "sorting and scope end up in the query string", %{conn: conn, domain: domain} do
      admin = registered_admin_fixture()
      link_fixture(admin, domain, %{slug: "keeps-state"})

      {:ok, view, _html} = conn |> log_in(admin) |> live(~p"/links")

      view |> element(~s{[phx-click="scope"][phx-value-scope="all"]}) |> render_click()
      view |> element(~s{[phx-click="sort"][phx-value-field="owner"]}) |> render_click()

      assert_patched(view, ~p"/links?dir=asc&scope=all&sort=owner")
    end

    test "a plain /links stays free of default parameters", %{conn: conn, user: user} do
      {:ok, view, _html} = conn |> log_in(user) |> live(~p"/links")

      view |> element(~s{[phx-click="page-size"][phx-value-size="10"]}) |> render_click()

      assert_patched(view, ~p"/links?size=10")
    end

    test "mounting with parameters restores the view", %{conn: conn, user: user, domain: domain} do
      link_fixture(user, domain, %{slug: "aaa"})
      link_fixture(user, domain, %{slug: "zzz"})
      admin = registered_admin_fixture()

      {:ok, _view, html} =
        conn |> log_in(admin) |> live(~p"/links?scope=all&sort=short&dir=asc")

      assert first_row_id(html) == Orbitly.Shortener.list_links(user) |> row_id_of("aaa")
    end

    test "ignores tampered parameters", %{conn: conn, user: user, domain: domain} do
      link_fixture(user, domain, %{slug: "steady"})

      {:ok, _view, html} =
        conn |> log_in(user) |> live(~p"/links?scope=everything&sort=owner_id&size=999&page=-3")

      assert html =~ "steady"
      # falls back to the defaults instead of blowing up
      assert html =~ "Total links: <b>1</b>"
    end

    test "the stats page returns to the list it came from", %{conn: conn, domain: domain} do
      admin = registered_admin_fixture()
      link = link_fixture(admin, domain, %{slug: "roundtrip"})

      conn = log_in(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/links?scope=all&sort=owner&dir=asc")

      {:ok, stats, _html} =
        view
        |> element(~s{a[href*="/links/#{link.id}/stats"]})
        |> render_click()
        |> follow_redirect(conn)

      assert stats |> element(~s{a[href*="/links?"]}) |> render() =~ "scope=all"
    end
  end

  defp row_id_of(links, slug), do: Enum.find(links, &(&1.slug == slug)).id

  defp first_row_id(html) do
    [_, id] = Regex.run(~r/id="link-([0-9a-f-]{36})"/, html)
    id
  end

  test "deletes an own link", %{conn: conn, user: user, domain: domain} do
    link = link_fixture(user, domain, %{slug: "kill-me"})

    {:ok, view, html} = conn |> log_in(user) |> live(~p"/links")
    assert html =~ "kill-me"

    view
    |> element(~s{[phx-click="delete"][phx-value-id="#{link.id}"]})
    |> render_click()

    refute render(view) =~ "kill-me"
  end
end
