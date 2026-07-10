defmodule Orbitly.Shortener.ClickBuffer do
  @moduledoc """
  Buffers click events and writes them in batches (ADR-0005/0008): keeps
  SQLite's single-writer bottleneck away from the redirect hot path. Events
  are flushed every second, when the buffer is full, and on shutdown. A
  failed flush is logged and dropped — losing a batch of click stats must
  never take the redirect path down with it.
  """

  use GenServer

  require Logger

  @flush_interval_ms 1_000
  @max_buffer 500

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Fire-and-forget from the hot path."
  def record(event) when is_map(event), do: GenServer.cast(__MODULE__, {:record, event})

  @doc "Synchronous flush — for tests and controlled shutdown."
  def flush_now, do: GenServer.call(__MODULE__, :flush)

  @impl true
  def init(_opts) do
    Process.flag(:trap_exit, true)
    schedule_flush()
    {:ok, %{buffer: []}}
  end

  @impl true
  def handle_cast({:record, event}, %{buffer: buffer} = state) do
    buffer = [event | buffer]

    if length(buffer) >= @max_buffer do
      {:noreply, %{state | buffer: do_flush(buffer)}}
    else
      {:noreply, %{state | buffer: buffer}}
    end
  end

  @impl true
  def handle_call(:flush, _from, %{buffer: buffer} = state) do
    {:reply, :ok, %{state | buffer: do_flush(buffer)}}
  end

  @impl true
  def handle_info(:flush, %{buffer: buffer} = state) do
    schedule_flush()
    {:noreply, %{state | buffer: do_flush(buffer)}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{buffer: buffer}) do
    do_flush(buffer)
    :ok
  end

  defp schedule_flush, do: Process.send_after(self(), :flush, @flush_interval_ms)

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
end
