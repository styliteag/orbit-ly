defmodule Orbitly.Shortener.RedirectCache do
  @moduledoc """
  ETS-backed lookup cache for the redirect hot path (ADR-0001).

  Read-through happens in the *calling* process (keeps DB access inside the
  caller's transaction/sandbox); this GenServer only owns the table. Entries
  carry a TTL as a backstop — the authoritative invalidation is a full flush
  triggered by `Orbitly.Shortener.CacheInvalidator` on any mutation. Negative
  results are cached too, so unknown slugs cannot hammer the database.
  """

  use GenServer

  require Ash.Query

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
    Domain
    |> Ash.Query.filter(hostname == ^host)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, %Domain{} = domain} ->
        {:ok, %{id: domain.id, is_primary: domain.is_primary, active: domain.active}}

      _ ->
        :not_found
    end
  end

  defp load_link(host, slug) do
    Link
    |> Ash.Query.filter(slug == ^slug and domain.hostname == ^host and domain.active == true)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, %Link{} = link} ->
        {:ok,
         %{
           link_id: link.id,
           target_url: link.target_url,
           expires_at: link.expires_at,
           password_hash: link.password_hash
         }}

      _ ->
        :not_found
    end
  end
end
