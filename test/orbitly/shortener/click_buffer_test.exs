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

  test "record/1 drops excess events instead of growing its mailbox without bound", ctx do
    pid = Process.whereis(ClickBuffer)
    dropped_before = ClickBuffer.dropped_count()

    :sys.suspend(pid)

    results =
      try do
        for i <- 1..24 do
          ClickBuffer.record(event(ctx.link, %{ip: "203.0.113.#{i}"}))
        end
      after
        :sys.resume(pid)
      end

    assert Enum.count(results, &(&1 == :ok)) == 8
    assert Enum.count(results, &(&1 == :dropped)) == 16

    ClickBuffer.flush_now()

    assert length(Shortener.list_click_events(ctx.admin)) == 8
    assert ClickBuffer.pending_count() == 0
    assert ClickBuffer.dropped_count() - dropped_before == 16
  end

  test "record/1 bounds attacker-controlled request metadata before persistence", ctx do
    assert :ok =
             ClickBuffer.record(
               event(ctx.link, %{
                 ip: String.duplicate("1", 200),
                 user_agent: String.duplicate("u", 2_000),
                 referrer: String.duplicate("r", 4_000)
               })
             )

    ClickBuffer.flush_now()

    assert [event] = Shortener.list_click_events(ctx.admin)
    assert byte_size(event.ip) == 64
    assert byte_size(event.user_agent) == 512
    assert byte_size(event.referrer) == 1_024
  end
end
