defmodule Orbitly.Shortener.ClickRetention do
  @moduledoc """
  Deletes raw click events older than 12 months (ADR-0005). This is a GDPR
  obligation, not an optimization — the retention window is the documented
  legal basis for keeping full IPs. Runs shortly after boot and then daily.
  """

  use GenServer

  require Logger

  import Ecto.Query

  @retention_months 12
  @startup_delay :timer.seconds(60)
  @interval :timer.hours(24)

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Synchronous purge — for tests and manual runs."
  def purge_now, do: GenServer.call(__MODULE__, :purge)

  @impl true
  def init(_opts) do
    Process.send_after(self(), :purge, @startup_delay)
    {:ok, %{}}
  end

  @impl true
  def handle_call(:purge, _from, state), do: {:reply, purge(), state}

  @impl true
  def handle_info(:purge, state) do
    purge()
    Process.send_after(self(), :purge, @interval)
    {:noreply, state}
  end

  defp purge do
    cutoff = DateTime.shift(DateTime.utc_now(), month: -@retention_months)

    {deleted, _} =
      Orbitly.Repo.delete_all(
        from(c in Orbitly.Shortener.ClickEvent, where: c.occurred_at < ^cutoff)
      )

    if deleted > 0, do: Logger.info("click retention: deleted #{deleted} events")
    {:ok, deleted}
  rescue
    exception ->
      Logger.error("click retention purge failed: " <> Exception.message(exception))
      {:error, exception}
  end
end
