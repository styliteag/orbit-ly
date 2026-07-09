# Seeds. Runs via `mix ash.setup` (aliased in mix.exs) in every environment,
# therefore everything below must be idempotent and dev-only where noted.

require Ash.Query

# Dev only (dev_routes is set exclusively in config/dev.exs): a ready-to-use
# admin account and the localhost primary domain, so `docker compose up`
# gives a working instance without manual setup. NOT for production —
# production admins are created via a release task (to be added).
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

  unless Orbitly.Shortener.Domain
         |> Ash.Query.filter(hostname == "localhost")
         |> Ash.exists?(authorize?: false) do
    Ash.Seed.seed!(Orbitly.Shortener.Domain, %{
      hostname: "localhost",
      is_primary: true,
      active: true
    })

    IO.puts("Seeded dev primary domain: localhost")
  end
end
