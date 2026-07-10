defmodule Orbitly.Shortener.PrimaryDomain do
  @moduledoc """
  Keeps the single primary domain (ADR-0003/0004) in sync with the configured
  MAIN_DOMAIN (`:orbitly, :main_domain`).

  The primary is a *sentinel* row: its id — and every link anchored to it — is
  stable across renames, only its hostname follows MAIN_DOMAIN. So changing
  MAIN_DOMAIN moves the dashboard and all its links to the new host without a
  manual step. Runs once at boot, before the endpoint serves (see
  `Orbitly.Application`); a no-op in tests, where fixtures own the domains.
  """

  import Ecto.Query

  alias Orbitly.Repo
  alias Orbitly.Shortener.{Domain, RedirectCache}

  @doc false
  def child_spec(_opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, []}, restart: :transient}
  end

  @doc false
  def start_link do
    if Application.get_env(:orbitly, :ensure_primary_domain, true) do
      ensure!(Application.fetch_env!(:orbitly, :main_domain))
    end

    # One-shot boot task: the work is done synchronously above, no process to
    # supervise afterwards.
    :ignore
  end

  @doc """
  Ensures exactly one primary domain exists with `hostname`. Creates it when
  missing, renames the existing primary in place otherwise. Raises when
  `hostname` is already taken by another (redirect) domain. Returns the
  primary domain.
  """
  def ensure!(hostname) when is_binary(hostname) do
    normalized = hostname |> String.trim() |> String.downcase()

    case primary() do
      nil -> create_primary!(normalized)
      %Domain{hostname: ^normalized} = domain -> domain
      %Domain{} = domain -> rename_primary!(domain, normalized)
    end
  end

  defp primary do
    Repo.one(from(d in Domain, where: d.is_primary == true))
  end

  # is_primary is not part of the public create/update changesets (admins must
  # not mint a second primary), so this uses the dedicated primary_changeset.
  defp create_primary!(hostname) do
    guard_free!(hostname, nil)

    domain =
      %Domain{}
      |> Domain.primary_changeset(%{hostname: hostname, is_primary: true})
      |> Repo.insert!()

    RedirectCache.flush()
    domain
  end

  defp rename_primary!(domain, hostname) do
    guard_free!(hostname, domain.id)

    updated =
      domain
      |> Domain.primary_changeset(%{hostname: hostname})
      |> Repo.update!()

    RedirectCache.flush()
    updated
  end

  defp guard_free!(hostname, allow_id) do
    base = from(d in Domain, where: d.hostname == ^hostname)
    query = if allow_id, do: from(d in base, where: d.id != ^allow_id), else: base

    if Repo.exists?(query) do
      raise """
      MAIN_DOMAIN #{hostname} is already used by another domain.
      Pick a different MAIN_DOMAIN or remove the conflicting redirect domain.
      """
    end
  end
end
