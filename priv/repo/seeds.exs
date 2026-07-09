# Seeds. Runs via `mix ash.setup` (aliased in mix.exs) in every environment,
# therefore everything below must be idempotent and dev-only where noted.

require Ash.Query

# Dev only (dev_routes is set exclusively in config/dev.exs): a ready-to-use
# admin account, so `docker compose up` gives a working instance without manual
# setup. The primary domain (localhost in dev) is created by
# `Orbitly.Shortener.PrimaryDomain` at boot from :main_domain, not here. NOT for
# production — production admins are created via the `bin/create_admin` task.
if Application.get_env(:orbitly, :dev_routes) do
  admin_email = "admin@localhost"
  admin_password = "orbitly-dev-password"

  unless Orbitly.Accounts.User
         |> Ash.Query.filter(email == ^admin_email)
         |> Ash.exists?(authorize?: false) do
    Ash.Seed.seed!(Orbitly.Accounts.User, %{
      email: admin_email,
      hashed_password: Bcrypt.hash_pwd_salt(admin_password),
      confirmed_at: DateTime.utc_now(),
      admin: true
    })

    IO.puts("Seeded dev admin: #{admin_email} / #{admin_password}")
  end
end
