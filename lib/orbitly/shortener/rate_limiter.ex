defmodule Orbitly.Shortener.RateLimiter do
  @moduledoc """
  Small fixed-window rate limiter on ETS — protects the password-unlock
  form against brute force without adding a dependency. Counters live in
  a public table (callers increment atomically); this GenServer owns the
  table and sweeps expired windows periodically.
  """

  use GenServer

  @table :orbitly_rate_limiter
  @sweep_interval :timer.minutes(5)

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc """
  Counts a hit for `key` and returns whether it is still within `limit`
  hits per `window_ms`. The first hit after a window expires resets it.
  """
  def allow?(key, limit, window_ms) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table, key) do
      [{^key, count, started}] when now - started < window_ms ->
        :ets.update_counter(@table, key, {2, 1})
        count < limit

      _ ->
        :ets.insert(@table, {key, 1, now})
        true
    end
  end

  @doc "Clears the counter, e.g. after a successful unlock."
  def reset(key), do: :ets.delete(@table, key)

  @doc false
  def clear_all, do: :ets.delete_all_objects(@table)

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
    schedule_sweep()
    {:ok, %{}}
  end

  @impl true
  def handle_info({:sweep, max_age_ms}, state) do
    sweep(max_age_ms)
    schedule_sweep()
    {:noreply, state}
  end

  defp schedule_sweep do
    # entries older than the sweep interval belong to expired windows for
    # any realistic window size used in this app
    Process.send_after(self(), {:sweep, @sweep_interval}, @sweep_interval)
  end

  defp sweep(max_age_ms) do
    cutoff = System.monotonic_time(:millisecond) - max_age_ms
    :ets.select_delete(@table, [{{:_, :_, :"$1"}, [{:<, :"$1", cutoff}], [true]}])
  end
end
