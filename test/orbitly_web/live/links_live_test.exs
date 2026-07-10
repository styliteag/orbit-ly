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
      end
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

  test "admin sees owner attribution", %{conn: conn, user: user, domain: domain} do
    link_fixture(user, domain, %{slug: "owned"})
    admin = registered_admin_fixture()

    {:ok, _view, html} = conn |> log_in(admin) |> live(~p"/links")

    assert html =~ "by #{user.email}"
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
