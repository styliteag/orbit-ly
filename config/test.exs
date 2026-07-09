import Config

config :orbitly,
  token_signing_secret:
    System.get_env("TOKEN_SIGNING_SECRET") || "test_only_token_signing_secret_not_for_production"

config :bcrypt_elixir, log_rounds: 1
config :ash, policies: [show_policy_breakdowns?: true], disable_async?: true

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :orbitly, Orbitly.Repo,
  database: Path.expand("../orbitly_test.db", __DIR__),
  pool_size: 5,
  pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :orbitly, OrbitlyWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base:
    System.get_env("SECRET_KEY_BASE") ||
      "test_only_secret_key_base_not_for_production_00000000000000000000000",
  server: false

# In test we don't send emails
config :orbitly, Orbitly.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Redirector: unbekannte Hosts an den Router durchreichen, damit ConnCase-Tests
# ohne Domain-Fixture funktionieren. Produktion: Default false (404, ADR-0003).
config :orbitly, serve_ui_on_unknown_hosts: true
