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

  describe "per_bucket/2" do
    test "buckets the short ranges by day and fills gaps", %{link: link, other_link: other} do
      seed_click(link, %{})
      seed_click(link, %{occurred_at: DateTime.add(DateTime.utc_now(), -3, :day)})
      seed_click(other, %{})

      assert %{granularity: :day, points: points} = ClickStats.per_bucket(link.id, "30d")

      assert length(points) == 30
      assert List.last(points) == {Date.utc_today(), 1}
      assert {Date.add(Date.utc_today(), -3), 1} in points
      assert {Date.add(Date.utc_today(), -1), 0} in points
    end

    test "buckets a year by month, gaps included", %{link: link} do
      seed_click(link, %{})
      seed_click(link, %{occurred_at: DateTime.shift(DateTime.utc_now(), month: -5)})

      assert %{granularity: :month, points: points} = ClickStats.per_bucket(link.id, "12m")

      assert length(points) == 12
      assert Enum.all?(points, fn {date, _} -> date.day == 1 end)
      assert List.last(points) == {Date.beginning_of_month(Date.utc_today()), 1}

      five_back = Date.utc_today() |> Date.shift(month: -5) |> Date.beginning_of_month()
      assert {five_back, 1} in points
    end

    test "the all-time range starts at the first click", %{link: link} do
      seed_click(link, %{occurred_at: DateTime.shift(DateTime.utc_now(), month: -2)})
      seed_click(link, %{})

      assert %{granularity: :month, points: points} = ClickStats.per_bucket(link.id, "all")

      assert length(points) == 3
      assert {_first_month, 1} = List.first(points)
      assert {_this_month, 1} = List.last(points)
    end

    test "an empty all-time range still returns a usable window", %{link: link} do
      assert %{granularity: :month, points: points} = ClickStats.per_bucket(link.id, "all")

      assert points != []
      assert Enum.all?(points, fn {_date, count} -> count == 0 end)
    end

    test "counts several links together", %{link: link, other_link: other} do
      seed_click(link, %{})
      seed_click(other, %{})

      assert %{points: points} = ClickStats.per_bucket([link.id, other.id], "30d")
      assert List.last(points) == {Date.utc_today(), 2}
    end

    test "an unknown range falls back to the default", %{link: link} do
      assert ClickStats.per_bucket(link.id, "bogus") == ClickStats.per_bucket(link.id, "12m")
    end
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
