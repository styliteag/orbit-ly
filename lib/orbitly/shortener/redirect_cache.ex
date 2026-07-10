defmodule Orbitly.Shortener.RedirectCache do
  @moduledoc """
  ETS-backed lookup cache for the redirect hot path (ADR-0001).

  Read-through happens in the *calling* process (keeps DB access inside the
  caller's transaction/sandbox); this GenServer only owns the table. Entries
  carry a TTL as a backstop — the authoritative invalidation is a full flush
  triggered by `Orbitly.Shortener` on any domain/link mutation. Negative
  results are cached too, so unknown slugs cannot hammer the database.
  """

  use GenServer

  import Ecto.Query

  alias Orbitly.Repo
  alias Orbitly.Shortener.{Domain, Link}

  @table :orbitly_redirect_cache
  @ttl_ms 60_000

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Returns {:ok, %{id, is_primary, active}} or :not_found."
  def fetch_domain(host) when is_binary(host) do
    lookup({:domain, host}, fn -> load_domain(host) end)
  end

  @doc "Returns {:ok, %{link_id, target_url, expires_at, password_hash}} or :not_found."
  def fetch_link(host, slug) when is_binary(host) and is_binary(slug) do
    lookup({:link, host, slug}, fn -> load_link(host, slug) end)
  end

  def flush, do: :ets.delete_all_objects(@table)

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, %{}}
  end

  defp lookup(key, loader) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table, key) do
      [{^key, value, cached_at}] when now - cached_at < @ttl_ms ->
        value

      _ ->
        value = loader.()
        :ets.insert(@table, {key, value, now})
        value
    end
  end

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
          password_hash: l.password_hash
        }
      )

    case Repo.one(query) do
      nil -> :not_found
      link -> {:ok, link}
    end
  end
end
