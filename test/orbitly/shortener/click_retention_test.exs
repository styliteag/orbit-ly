defmodule Orbitly.Shortener.ClickRetentionTest do
  use Orbitly.DataCase, async: false

  import Orbitly.Fixtures

  alias Orbitly.Shortener
  alias Orbitly.Shortener.{ClickEvent, ClickRetention}

  test "purges events older than 12 months, keeps younger ones" do
    user = user_fixture()
    domain = domain_fixture()
    link = link_fixture(user, domain)
    admin = admin_fixture()

    old = DateTime.shift(DateTime.utc_now(), month: -13)
    fresh = DateTime.shift(DateTime.utc_now(), month: -11)

    for occurred_at <- [old, fresh] do
      Ash.Seed.seed!(ClickEvent, %{
        link_id: link.id,
        occurred_at: occurred_at,
        ip: "203.0.113.1"
      })
    end

    assert {:ok, 1} = ClickRetention.purge_now()

    assert {:ok, [event]} = Shortener.list_click_events(actor: admin)
    assert DateTime.compare(event.occurred_at, fresh) == :eq
  end

  test "purging with nothing to delete is a no-op" do
    assert {:ok, 0} = ClickRetention.purge_now()
  end
end
