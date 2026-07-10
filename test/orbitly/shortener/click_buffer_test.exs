defmodule Orbitly.Shortener.ClickBufferTest do
  use Orbitly.DataCase, async: false

  import Orbitly.Fixtures

  alias Orbitly.Shortener
  alias Orbitly.Shortener.ClickBuffer

  setup do
    # drain leftovers from other tests before this test's assertions
    ClickBuffer.flush_now()

    user = user_fixture()
    domain = domain_fixture()
    link = link_fixture(user, domain)

    %{user: user, domain: domain, link: link, admin: admin_fixture()}
  end

  defp event(link, attrs \\ %{}) do
    Map.merge(
      %{
        link_id: link.id,
        occurred_at: DateTime.utc_now(),
        ip: "203.0.113.7",
        user_agent: "ExUnit",
        referrer: "https://referrer.example/"
      },
      attrs
    )
  end

  test "record/1 buffers and flush_now/0 persists in one batch", ctx do
    for i <- 1..3, do: ClickBuffer.record(event(ctx.link, %{ip: "203.0.113.#{i}"}))

    ClickBuffer.flush_now()

    events = Shortener.list_click_events(ctx.admin)
    assert length(events) == 3
    assert Enum.all?(events, &(&1.link_id == ctx.link.id))
  end

  test "flushing an empty buffer is a no-op", ctx do
    assert :ok = ClickBuffer.flush_now()
    assert [] = Shortener.list_click_events(ctx.admin)
  end

  test "owners only read events of their own links, admins read all", ctx do
    other = user_fixture()
    other_link = link_fixture(other, ctx.domain)

    ClickBuffer.record(event(ctx.link))
    ClickBuffer.record(event(other_link))
    ClickBuffer.flush_now()

    assert [own_event] = Shortener.list_click_events(ctx.user)
    assert own_event.link_id == ctx.link.id

    all = Shortener.list_click_events(ctx.admin)
    assert length(all) == 2
  end
end
