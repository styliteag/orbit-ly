defmodule OrbitlyWeb.LinkStatsLiveTest do
  use OrbitlyWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Orbitly.Fixtures

  setup do
    user = registered_user_fixture()
    domain = domain_fixture(%{hostname: "go.example"})
    link = link_fixture(user, domain, %{slug: "stats-me"})

    Ash.Seed.seed!(Orbitly.Shortener.ClickEvent, %{
      link_id: link.id,
      occurred_at: DateTime.utc_now(),
      referrer: "https://news.example/",
      user_agent: "Mozilla/5.0 Chrome/126.0 Safari/537.36"
    })

    %{user: user, link: link}
  end

  test "owner sees totals, referrers and browsers", %{conn: conn, user: user, link: link} do
    {:ok, _view, html} = conn |> log_in(user) |> live(~p"/links/#{link.id}/stats")

    assert html =~ "go.example/stats-me"
    assert html =~ "Total clicks"
    assert html =~ "https://news.example/"
    assert html =~ "Chrome"
  end

  test "other users are redirected away", %{conn: conn, link: link} do
    other = registered_user_fixture()

    assert {:error, {:live_redirect, %{to: "/links"}}} =
             conn |> log_in(other) |> live(~p"/links/#{link.id}/stats")
  end
end
