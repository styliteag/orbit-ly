defmodule Orbitly.Shortener.RedirectCache do
  @moduledoc """
  ETS-backed lookup cache for the redirect hot path (ADR-0001).

  Read-through happens in the *calling* process (keeps DB access inside the
  caller's transaction/sandbox). Hits read ETS directly; misses are inserted
  through the owner GenServer so it can enforce a hard entry bound. Entries
  carry a TTL and are actively swept. The authoritative invalidation remains a
  full flush triggered by `Orbitly.Shortener` on any domain/link mutation.
  """

  use GenServer

  import Ecto.Query

  alias Orbitly.Repo
  alias Orbitly.Shortener.{Domain, Link}

  @table :orbitly_redirect_cache
  @ttl_ms 60_000
  @sweep_interval_ms 60_000
  @default_max_entries 10_000

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Returns {:ok, %{id, is_primary, active}} or :not_found."
  def fetch_domain(host) when is_binary(host) do
    lookup({:domain, host}, fn -> load_domain(host) end)
  end

  @doc "Returns {:ok, %{link_id, target_url, expires_at, password_hash, interstitial}} or :not_found."
  def fetch_link(host, slug) when is_binary(host) and is_binary(slug) do
    lookup({:link, host, slug}, fn -> load_link(host, slug) end)
  end

  def flush, do: GenServer.call(__MODULE__, :flush)

  @doc false
  def size, do: :ets.info(@table, :size)

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
        Application.get_env(:orbitly, :redirect_cache_max_entries, @default_max_entries)
      )

    schedule_sweep()
    {:ok, %{queue: :queue.new(), max_entries: max(max_entries, 1)}}
  end

  @impl true
  def handle_call({:put, key, value, cached_at}, _from, state) do
    :ets.insert(@table, {key, value, cached_at})

    state =
      state
      |> Map.update!(:queue, &:queue.in({key, cached_at}, &1))
      |> trim_to_bound()

    {:reply, value, state}
  end

  def handle_call(:flush, _from, state) do
    :ets.delete_all_objects(@table)
    {:reply, :ok, %{state | queue: :queue.new()}}
  end

  def handle_call({:prune, now_ms}, _from, state) do
    {:reply, :ok, prune_expired(state, now_ms)}
  end

  @impl true
  def handle_info(:sweep, state) do
    schedule_sweep()
    {:noreply, prune_expired(state, System.monotonic_time(:millisecond))}
  end

  defp lookup(key, loader) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table, key) do
      [{^key, value, cached_at}] when now - cached_at < @ttl_ms ->
        value

      _ ->
        value = loader.()
        GenServer.call(__MODULE__, {:put, key, value, now})
    end
  end

  defp trim_to_bound(state) do
    if :ets.info(@table, :size) > state.max_entries do
      case :queue.out(state.queue) do
        {{:value, {key, cached_at}}, queue} ->
          delete_if_current(key, cached_at)
          trim_to_bound(%{state | queue: queue})

        {:empty, _queue} ->
          state
      end
    else
      state
    end
  end

  defp delete_if_current(key, cached_at) do
    case :ets.lookup(@table, key) do
      [{^key, _value, ^cached_at}] -> :ets.delete(@table, key)
      _ -> true
    end
  end

  defp prune_expired(state, now_ms) do
    cutoff = now_ms - @ttl_ms

    :ets.select_delete(@table, [
      {{:"$1", :"$2", :"$3"}, [{:"=<", :"$3", cutoff}], [true]}
    ])

    %{state | queue: rebuild_queue()}
  end

  defp rebuild_queue do
    @table
    |> :ets.tab2list()
    |> Enum.sort_by(&elem(&1, 2))
    |> Enum.reduce(:queue.new(), fn {key, _value, cached_at}, queue ->
      :queue.in({key, cached_at}, queue)
    end)
  end

  defp schedule_sweep, do: Process.send_after(self(), :sweep, @sweep_interval_ms)

  defp load_domain(host) do
    case Repo.one(from(d in Domain, where: d.hostname == ^host)) do
      %Domain{} = domain ->
        {:ok, %{id: domain.id, is_primary: domain.is_primary, active: domain.active}}

      nil ->
        :not_found
    end
  end

  defp load_link(host, slug) do
    query =
      from(l in Link,
        join: d in Domain,
        on: d.id == l.domain_id,
        where: l.slug == ^slug and d.hostname == ^host and d.active == true,
        select: %{
          link_id: l.id,
          target_url: l.target_url,
          expires_at: l.expires_at,
          password_hash: l.password_hash,
          interstitial: l.interstitial
        }
      )

    case Repo.one(query) do
      nil -> :not_found
      link -> {:ok, link}
    end
  end
end
