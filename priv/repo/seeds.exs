# Seeds. Runs via `mix ecto.setup` in every environment, therefore everything
# below must be idempotent and dev-only where noted.

# Dev only (dev_routes is set exclusively in config/dev.exs): a ready-to-use
# admin account, so `docker compose up` gives a working instance without manual
# setup. The primary domain (localhost in dev) is created by
# `Orbitly.Shortener.PrimaryDomain` at boot from :main_domain, not here. NOT for
# production — production admins are created via the `bin/create_admin` task.
if Application.get_env(:orbitly, :dev_routes) do
  # Dev login credentials: sign in at /sign-in with this email + password.
  # "orbitly-dev-password" is the password.
  admin_email = "admin@localhost"
  admin_password = "orbitly-dev-password"

  unless Orbitly.Accounts.get_user_by_email(admin_email) do
    {:ok, user} =
      Orbitly.Accounts.admin_create_user(%{email: admin_email, password: admin_password})

    {:ok, _} = Orbitly.Accounts.set_admin(user, true)

    IO.puts("Seeded dev admin: #{admin_email} / #{admin_password}")
  end
end
