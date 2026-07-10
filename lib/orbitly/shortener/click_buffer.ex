defmodule Orbitly.Shortener.ClickBuffer do
  @moduledoc """
  Buffers click events and writes them in batches (ADR-0005/0008): keeps
  SQLite's single-writer bottleneck away from the redirect hot path. Admission
  is capped across both the process mailbox and in-memory buffer; excess events
  are deliberately dropped while redirects keep working. Events are flushed
  every second, when the buffer is full, and on shutdown.
  """

  use GenServer

  require Logger

  @flush_interval_ms 1_000
  @max_buffer 500
  @default_max_pending 5_000
  @stats_table :orbitly_click_buffer_stats
  @max_ip_bytes 64
  @max_user_agent_bytes 512
  @max_referrer_bytes 1_024

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Best-effort admission from the hot path; returns :dropped at capacity."
  def record(event) when is_map(event) do
    pending = :ets.update_counter(@stats_table, :pending, {2, 1})
    max_pending = :ets.lookup_element(@stats_table, :max_pending, 2)

    if pending <= max_pending do
      GenServer.cast(__MODULE__, {:record, normalize_event(event)})
      :ok
    else
      :ets.update_counter(@stats_table, :pending, {2, -1})
      :ets.update_counter(@stats_table, :dropped, {2, 1})
      :telemetry.execute([:orbitly, :click_buffer, :drop], %{count: 1}, %{reason: :capacity})
      :dropped
    end
  end

  @doc "Synchronous flush — for tests and controlled shutdown."
  def flush_now, do: GenServer.call(__MODULE__, :flush)

  @doc false
  def pending_count, do: :ets.lookup_element(@stats_table, :pending, 2)

  @doc false
  def dropped_count, do: :ets.lookup_element(@stats_table, :dropped, 2)

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    max_pending =
      Keyword.get(
        opts,
        :max_pending,
        Application.get_env(:orbitly, :click_buffer_max_pending, @default_max_pending)
      )

    :ets.new(@stats_table, [:named_table, :public, :set, write_concurrency: true])

    :ets.insert(@stats_table, [
      {:pending, 0},
      {:dropped, 0},
      {:max_pending, max(max_pending, 1)}
    ])

    schedule_flush()
    {:ok, %{buffer: []}}
  end

  @impl true
  def handle_cast({:record, event}, %{buffer: buffer} = state) do
    buffer = [event | buffer]

    if length(buffer) >= @max_buffer do
      {:noreply, %{state | buffer: flush_and_release(buffer)}}
    else
      {:noreply, %{state | buffer: buffer}}
    end
  end

  @impl true
  def handle_call(:flush, _from, %{buffer: buffer} = state) do
    {:reply, :ok, %{state | buffer: flush_and_release(buffer)}}
  end

  @impl true
  def handle_info(:flush, %{buffer: buffer} = state) do
    schedule_flush()
    {:noreply, %{state | buffer: flush_and_release(buffer)}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{buffer: buffer}) do
    do_flush(buffer)
    :ok
  end

  defp schedule_flush, do: Process.send_after(self(), :flush, @flush_interval_ms)

  defp flush_and_release(buffer) do
    result = do_flush(buffer)
    release_slots(length(buffer))
    result
  end

  defp release_slots(0), do: :ok
  defp release_slots(count), do: :ets.update_counter(@stats_table, :pending, {2, -count})

  defp do_flush([]), do: []

  defp do_flush(buffer) do
    entries =
      buffer
      |> Enum.reverse()
      |> Enum.map(&Map.put(&1, :id, Ecto.UUID.generate()))

    Orbitly.Repo.insert_all(Orbitly.Shortener.ClickEvent, entries)
    []
  rescue
    exception ->
      Logger.error(
        "click flush failed, dropping #{length(buffer)} events: " <>
          Exception.message(exception)
      )

      []
  end

  defp normalize_event(event) do
    event
    |> Map.update(:ip, nil, &truncate(&1, @max_ip_bytes))
    |> Map.update(:user_agent, nil, &truncate(&1, @max_user_agent_bytes))
    |> Map.update(:referrer, nil, &truncate(&1, @max_referrer_bytes))
  end

  defp truncate(nil, _max_bytes), do: nil

  defp truncate(value, max_bytes) when is_binary(value) do
    value = String.replace_invalid(value, "")

    if byte_size(value) <= max_bytes do
      value
    else
      value
      |> binary_part(0, max_bytes)
      |> String.replace_invalid("")
    end
  end

  defp truncate(value, _max_bytes), do: to_string(value)
end
