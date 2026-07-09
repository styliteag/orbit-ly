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

  require Ash.Query
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
    Domain
    |> Ash.Query.filter(is_primary == true)
    |> Ash.read_one!(authorize?: false)
  end

  # is_primary is not part of the public :create action (admins must not mint a
  # second primary), so the create action validates/normalizes the hostname and
  # the flag is set directly afterwards.
  defp create_primary!(hostname) do
    guard_free!(hostname, nil)

    domain =
      Domain
      |> Ash.Changeset.for_create(:create, %{hostname: hostname}, authorize?: false)
      |> Ash.create!()

    {1, _} =
      Repo.update_all(from(d in Domain, where: d.id == ^domain.id), set: [is_primary: true])

    RedirectCache.flush()
    %{domain | is_primary: true}
  end

  defp rename_primary!(domain, hostname) do
    guard_free!(hostname, domain.id)

    updated =
      domain
      |> Ash.Changeset.for_update(:update, %{hostname: hostname}, authorize?: false)
      |> Ash.update!()

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
