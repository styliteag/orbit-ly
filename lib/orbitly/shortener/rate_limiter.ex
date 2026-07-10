defmodule Orbitly.Shortener.RateLimiter do
  @moduledoc """
  Small fixed-window rate limiter on ETS — protects credential and unlock
  flows without adding a dependency. All decisions are serialized through the
  owner GenServer so concurrent callers cannot race the limit. Entries carry
  their actual expiry and are swept only after that expiry.
  """

  use GenServer

  @table :orbitly_rate_limiter
  @sweep_interval :timer.minutes(5)
  @default_max_entries 100_000

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc """
  Counts a hit for `key` and returns whether it is still within `limit`
  hits per `window_ms`. The first hit after a window expires resets it.
  """
  def allow?(key, limit, window_ms) when limit > 0 and window_ms > 0,
    do: GenServer.call(__MODULE__, {:allow, key, limit, window_ms})

  def allow?(_key, _limit, _window_ms), do: false

  @doc "Clears the counter, e.g. after a successful unlock."
  def reset(key), do: GenServer.call(__MODULE__, {:reset, key})

  @doc false
  def clear_all, do: GenServer.call(__MODULE__, :clear_all)

  @doc false
  def prune_now(now_ms \\ System.monotonic_time(:millisecond)) do
    GenServer.call(__MODULE__, {:prune, now_ms})
  end

  @impl true
  def init(opts) do
    :ets.new(@table, [:named_table, :protected, :set, read_concurrency: true])

    max_entries =
      Keyword.get(
        opts,
        :max_entries,
        Application.get_env(:orbitly, :rate_limiter_max_entries, @default_max_entries)
      )

    schedule_sweep()
    {:ok, %{max_entries: max(max_entries, 1)}}
  end

  @impl true
  def handle_call({:allow, key, limit, window_ms}, _from, state) do
    now = System.monotonic_time(:millisecond)

    allowed? =
      case :ets.lookup(@table, key) do
        [{^key, count, expires_at}] when now < expires_at ->
          next_count = count + 1
          :ets.insert(@table, {key, next_count, expires_at})
          next_count <= limit

        [{^key, _count, _expires_at}] ->
          :ets.insert(@table, {key, 1, now + window_ms})
          true

        [] ->
          if :ets.info(@table, :size) < state.max_entries do
            :ets.insert(@table, {key, 1, now + window_ms})
            true
          else
            false
          end
      end

    {:reply, allowed?, state}
  end

  def handle_call({:reset, key}, _from, state) do
    :ets.delete(@table, key)
    {:reply, :ok, state}
  end

  def handle_call(:clear_all, _from, state) do
    :ets.delete_all_objects(@table)
    {:reply, :ok, state}
  end

  def handle_call({:prune, now_ms}, _from, state) do
    sweep(now_ms)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:sweep, state) do
    sweep(System.monotonic_time(:millisecond))
    schedule_sweep()
    {:noreply, state}
  end

  defp schedule_sweep do
    Process.send_after(self(), :sweep, @sweep_interval)
  end

  defp sweep(now_ms) do
    :ets.select_delete(@table, [{{:_, :_, :"$1"}, [{:"=<", :"$1", now_ms}], [true]}])
  end
end
