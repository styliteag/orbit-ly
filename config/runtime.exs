import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/orbitly start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :orbitly, OrbitlyWeb.Endpoint, server: true
end

config :orbitly, OrbitlyWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :orbitly, OrbitlyWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$",
        # Gettext translations
        ~r"priv/gettext/.*\.po$",
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/orbitly_web/router\.ex$",
        ~r"lib/orbitly_web/(controllers|live|components)/.*\.(ex|heex)$"
      ]
    ]
end

if config_env() == :prod do
  database_path =
    System.get_env("DATABASE_PATH") ||
      raise """
      environment variable DATABASE_PATH is missing.
      For example: /etc/orbitly/orbitly.db
      """

  config :orbitly, Orbitly.Repo,
    database: database_path,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  # Primary domain = dashboard host. Single source for the hostname;
  # PrimaryDomain reconciles the sentinel row against it at boot.
  main_domain =
    System.get_env("MAIN_DOMAIN") ||
      raise """
      environment variable MAIN_DOMAIN is missing.
      Set it to the dashboard/primary hostname, e.g. go.example.com
      """

  config :orbitly, :main_domain, main_domain

  config :orbitly, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :orbitly, OrbitlyWeb.Endpoint,
    url: [host: main_domain, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # Number of trusted reverse proxies in front of the app. The real client
  # IP is read this many entries from the right of x-forwarded-for, so a
  # client cannot spoof it (ADR-0003, OrbitlyWeb.ClientIP). One proxy = 1.
  config :orbitly,
    trusted_proxy_hops: String.to_integer(System.get_env("TRUSTED_PROXY_HOPS") || "1")

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :orbitly, OrbitlyWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :orbitly, OrbitlyWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  fetch_nonempty_env = fn name ->
    case System.get_env(name) do
      value when is_binary(value) ->
        if String.trim(value) == "" do
          raise "environment variable #{name} must not be empty"
        else
          value
        end

      nil ->
        raise "environment variable #{name} is missing"
    end
  end

  # Optional variables are treated as unset when they are empty or blank, so a
  # `KEY=` line in an .env file means "not configured" instead of "empty value".
  fetch_optional_env = fn name ->
    case System.get_env(name) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          trimmed -> trimmed
        end

      nil ->
        nil
    end
  end

  smtp_relay = fetch_nonempty_env.("SMTP_RELAY")
  smtp_username = fetch_optional_env.("SMTP_USERNAME")
  smtp_password = fetch_optional_env.("SMTP_PASSWORD")
  mail_from = fetch_nonempty_env.("MAIL_FROM")

  # Both or neither — a half-configured pair would silently deliver
  # unauthenticated instead of surfacing the missing value.
  if is_nil(smtp_username) != is_nil(smtp_password) do
    raise "SMTP_USERNAME and SMTP_PASSWORD must be set together " <>
            "(leave both unset for a relay without authentication)"
  end

  smtp_port =
    case Integer.parse(System.get_env("SMTP_PORT", "587")) do
      {port, ""} when port in 1..65_535 -> port
      _ -> raise "environment variable SMTP_PORT must be an integer between 1 and 65535"
    end

  smtp_tls =
    case System.get_env("SMTP_TLS", "always") do
      "always" -> :always
      "if_available" -> :if_available
      "never" -> :never
      _ -> raise "environment variable SMTP_TLS must be always, if_available or never"
    end

  smtp_auth = if smtp_username, do: :always, else: :never

  smtp_credentials =
    if smtp_username, do: [username: smtp_username, password: smtp_password], else: []

  config :orbitly,
         Orbitly.Mailer,
         [
           adapter: Swoosh.Adapters.SMTP,
           relay: smtp_relay,
           port: smtp_port,
           ssl: false,
           tls: smtp_tls,
           auth: smtp_auth,
           retries: 2,
           tls_options: [
             verify: :verify_peer,
             cacerts: :public_key.cacerts_get(),
             server_name_indication: String.to_charlist(smtp_relay)
           ]
         ] ++ smtp_credentials

  config :orbitly, :mailer_from, {System.get_env("MAIL_FROM_NAME", "Orbit-ly"), mail_from}
end
