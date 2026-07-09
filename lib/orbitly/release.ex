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
