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
    alias Orbitly.Accounts

    if Accounts.get_user_by_email(email) do
      :exists
    else
      {:ok, user} = Accounts.admin_create_user(%{email: email, password: password})
      {:ok, _} = Accounts.set_admin(user, true)
      :created
    end
  end

  @doc """
  Imports links from a Kutt instance into orbit-ly (see `Orbitly.KuttImport`),
  reading KUTT_API_URL / KUTT_API_KEY and the optional KUTT_DOMAIN from the
  environment. All links are assigned to the current admin on the primary
  domain. Idempotent: existing slugs are skipped.

  This is the prod entry point (`bin/import_kutt`). In dev, prefer the arg-based
  mix task `just import-kutt URL KEY [DOMAIN]` (→ `mix orbitly.import_kutt`).
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

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_all_started(:bcrypt_elixir)
    Application.ensure_loaded(@app)
  end
end
