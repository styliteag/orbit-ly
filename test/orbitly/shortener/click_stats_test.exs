defmodule Orbitly.Shortener.ClickStatsTest do
  use Orbitly.DataCase, async: false

  import Orbitly.Fixtures

  alias Orbitly.Shortener.{ClickEvent, ClickStats}

  setup do
    user = user_fixture()
    domain = domain_fixture()
    link = link_fixture(user, domain)

    %{link: link, other_link: link_fixture(user, domain)}
  end

  defp seed_click(link, attrs) do
    Repo.insert!(
      struct(
        ClickEvent,
        Map.merge(%{link_id: link.id, occurred_at: DateTime.utc_now(), ip: "203.0.113.1"}, attrs)
      )
    )
  end

  test "total/1 counts only the given link", %{link: link, other_link: other} do
    seed_click(link, %{})
    seed_click(link, %{})
    seed_click(other, %{})

    assert ClickStats.total(link.id) == 2
  end

  test "per_day/2 buckets by day and fills gaps with zero", %{link: link} do
    seed_click(link, %{})
    seed_click(link, %{})
    seed_click(link, %{occurred_at: DateTime.add(DateTime.utc_now(), -2, :day)})

    per_day = ClickStats.per_day(link.id, 7)

    assert length(per_day) == 7
    assert {Date.utc_today(), 2} == List.last(per_day)
    assert {Date.add(Date.utc_today(), -2), 1} in per_day
    assert {Date.add(Date.utc_today(), -1), 0} in per_day
  end

  test "top_referrers/2 groups, orders and labels direct traffic", %{link: link} do
    for _ <- 1..3, do: seed_click(link, %{referrer: "https://a.example/"})
    seed_click(link, %{referrer: "https://b.example/"})
    for _ <- 1..2, do: seed_click(link, %{referrer: nil})

    assert [{"https://a.example/", 3}, {"(direct)", 2}, {"https://b.example/", 1}] =
             ClickStats.top_referrers(link.id)
  end

  test "browsers/1 maps user agents to coarse families", %{link: link} do
    seed_click(link, %{user_agent: "Mozilla/5.0 ... Chrome/126.0 Safari/537.36"})
    seed_click(link, %{user_agent: "Mozilla/5.0 ... Chrome/126.0 Safari/537.36 Edg/126.0"})
    seed_click(link, %{user_agent: "Mozilla/5.0 ... Gecko/20100101 Firefox/128.0"})
    seed_click(link, %{user_agent: "Mozilla/5.0 ... Version/17.5 Safari/605.1.15"})
    seed_click(link, %{user_agent: "curl/8.6.0"})
    seed_click(link, %{user_agent: nil})

    browsers = Map.new(ClickStats.browsers(link.id))

    assert browsers == %{
             "Chrome" => 1,
             "Edge" => 1,
             "Firefox" => 1,
             "Safari" => 1,
             "Bot" => 1,
             "Unknown" => 1
           }
  end
end
