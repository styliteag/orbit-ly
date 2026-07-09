defmodule Orbitly.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :orbitly

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Creates the instance admin from ADMIN_EMAIL / ADMIN_PASSWORD (ADR-0006).
  There is no open registration, so this is the production bootstrap.
  Idempotent: does nothing if the account already exists.
  """
  def create_admin do
    load_app()

    email = System.get_env("ADMIN_EMAIL") || raise "environment variable ADMIN_EMAIL is missing"

    password =
      System.get_env("ADMIN_PASSWORD") || raise "environment variable ADMIN_PASSWORD is missing"

    {:ok, result, _} =
      Ecto.Migrator.with_repo(hd(repos()), fn _repo -> upsert_admin(email, password) end)

    case result do
      :created -> IO.puts("Created instance admin: #{email}")
      :exists -> IO.puts("Admin #{email} already exists — nothing to do")
    end
  end

  @doc false
  def upsert_admin(email, password) do
    import Ecto.Query

    alias Orbitly.Accounts.User

    if Orbitly.Repo.exists?(from(u in User, where: u.email == ^email)) do
      :exists
    else
      user =
        User
        |> Ash.Changeset.for_create(:admin_create, %{email: email, password: password},
          authorize?: false
        )
        |> Ash.create!()

      {1, _} =
        Orbitly.Repo.update_all(from(u in User, where: u.id == ^user.id), set: [admin: true])

      :created
    end
  end

  @doc """
  Imports links from a Kutt instance into orbit-ly (see `Orbitly.KuttImport`).
  Reads KUTT_API_URL / KUTT_API_KEY and the optional KUTT_DOMAIN from the
  environment. All links are assigned to the current admin on the primary
  domain. Idempotent: existing slugs are skipped.
  """
  def import_kutt do
    {:ok, _apps} = Application.ensure_all_started(@app)

    api_url =
      System.get_env("KUTT_API_URL") || raise "environment variable KUTT_API_URL is missing"

    api_key =
      System.get_env("KUTT_API_KEY") || raise "environment variable KUTT_API_KEY is missing"

    Orbitly.KuttImport.run(
      client: Orbitly.KuttImport.ApiClient,
      config: %{api_url: String.trim_trailing(api_url, "/"), api_key: api_key},
      domain: System.get_env("KUTT_DOMAIN")
    )
    |> Orbitly.KuttImport.Report.print()
  end

  @doc """
  Creates a redirect domain from DOMAIN_HOSTNAME (ADR-0003). Primary by default
  — the primary domain serves the dashboard (ADR-0004); set DOMAIN_PRIMARY=false
  to add a plain redirect domain. Goes through the real create action, so the
  hostname is normalized and validated (unlike a raw Ash.Seed).
  Idempotent: does nothing if the hostname already exists.
  """
  def create_domain do
    load_app()

    hostname =
      System.get_env("DOMAIN_HOSTNAME") || raise "environment variable DOMAIN_HOSTNAME is missing"

    is_primary = System.get_env("DOMAIN_PRIMARY", "true") != "false"

    {:ok, result, _} =
      Ecto.Migrator.with_repo(hd(repos()), fn _repo -> upsert_domain(hostname, is_primary) end)

    case result do
      {:created, name} ->
        IO.puts("Created domain: #{name}#{if is_primary, do: " (primary)", else: ""}")

      {:exists, name} ->
        IO.puts("Domain #{name} already exists — nothing to do")
    end
  end

  @doc false
  def upsert_domain(hostname, is_primary) do
    import Ecto.Query

    alias Orbitly.Shortener.Domain

    normalized = hostname |> String.trim() |> String.downcase()

    if Orbitly.Repo.exists?(from(d in Domain, where: d.hostname == ^normalized)) do
      {:exists, normalized}
    else
      domain =
        Domain
        |> Ash.Changeset.for_create(
          :create,
          %{hostname: hostname, is_primary: is_primary, active: true},
          authorize?: false
        )
        |> Ash.create!()

      {:created, domain.hostname}
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_all_started(:ash)
    Application.ensure_loaded(@app)
  end
end
