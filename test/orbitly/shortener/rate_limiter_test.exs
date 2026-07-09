defmodule Orbitly.Shortener.RateLimiterTest do
  use ExUnit.Case, async: false

  alias Orbitly.Shortener.RateLimiter

  setup do
    RateLimiter.clear_all()
    :ok
  end

  test "allows up to the limit within a window, then blocks" do
    key = {:test, "203.0.113.1", "slug"}

    for _ <- 1..5, do: assert(RateLimiter.allow?(key, 5, 60_000))
    refute RateLimiter.allow?(key, 5, 60_000)
  end

  test "an expired window starts fresh" do
    key = {:test, "203.0.113.2", "slug"}

    for _ <- 1..3, do: RateLimiter.allow?(key, 2, 30)
    refute RateLimiter.allow?(key, 2, 30)

    Process.sleep(40)
    assert RateLimiter.allow?(key, 2, 30)
  end

  test "reset clears the counter" do
    key = {:test, "203.0.113.3", "slug"}

    for _ <- 1..6, do: RateLimiter.allow?(key, 5, 60_000)
    refute RateLimiter.allow?(key, 5, 60_000)

    RateLimiter.reset(key)
    assert RateLimiter.allow?(key, 5, 60_000)
  end

  test "keys are independent" do
    refute Enum.any?(1..6, fn _ -> !RateLimiter.allow?({:a}, 10, 60_000) end)
    assert RateLimiter.allow?({:b}, 1, 60_000)
  end
end
