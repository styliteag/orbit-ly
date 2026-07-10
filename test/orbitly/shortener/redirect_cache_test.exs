defmodule Orbitly.Shortener.RedirectCacheTest do
  use Orbitly.DataCase, async: false

  alias Orbitly.Shortener.RedirectCache

  setup do
    RedirectCache.flush()
    :ok
  end

  test "unique negative lookups cannot grow the cache past its configured bound" do
    for i <- 1..96 do
      assert :not_found = RedirectCache.fetch_link("missing.example", "slug-#{i}")
    end

    assert RedirectCache.size() <= 32
  end

  test "expired entries are actively removed without being read again" do
    assert :not_found = RedirectCache.fetch_domain("expired.example")
    assert RedirectCache.size() == 1

    future = System.monotonic_time(:millisecond) + :timer.minutes(2)
    assert :ok = RedirectCache.prune_now(future)
    assert RedirectCache.size() == 0
  end
end
