defmodule Orbitly.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    Logger.info("Starting Stylite Orbit-ly #{Orbitly.version()}")

    children = [
      OrbitlyWeb.Telemetry,
      Orbitly.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:orbitly, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:orbitly, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Orbitly.PubSub},
      # Owns the ETS table for the redirect hot path — must be up before the
      # endpoint accepts requests.
      Orbitly.Shortener.RedirectCache,
      Orbitly.Shortener.ClickBuffer,
      Orbitly.Shortener.ClickRetention,
      Orbitly.Shortener.RateLimiter,
      # Sync the sentinel primary domain to MAIN_DOMAIN before serving, so the
      # dashboard host is correct on the very first request after a config
      # change. Runs after migrations/RedirectCache, before the endpoint.
      Orbitly.Shortener.PrimaryDomain,
      # Start to serve requests, typically the last entry
      OrbitlyWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Orbitly.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    OrbitlyWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end
end
