# Stylite Orbit-ly

Multi-tenant link shortener (similar to [kutt](https://github.com/thedevs-network/kutt)),
built with Phoenix + [Ash Framework](https://ash-hq.org) on SQLite.
Elixir app: `orbitly`, module namespace: `Orbitly`.

## Development (Docker only, no local Elixir)

```sh
docker compose up
```

Then: <http://localhost:4000>. Code reload works via the bind mount; deps, build
artifacts and toolchain live in Docker volumes.

`docker compose up` runs `mix setup`, which seeds a ready-to-use admin (dev
only). Sign in at <http://localhost:4000/sign-in> with:

- **Email:** `admin@localhost`
- **Password:** `orbitly-dev-password`

To import links from a Kutt instance in dev, see
[§7 Import links from Kutt](#7-import-links-from-kutt-optional):
`just import-kutt <URL> <KEY> [DOMAIN] [OWNER-EMAIL]`.

Tests:

```sh
docker compose run --rm app sh -c "mix setup && mix test"
```

## Custom-domain redirects (root & catch-all)

Besides normal short links (`domain/slug`), an admin can add two special links
per domain — just type the matching value into the **Custom address** field of
the link form:

| Input | Result | Applies to |
| --- | --- | --- |
| `/` or `@` | **Root redirect** — `domain/` redirects | redirect domains only (the primary-domain root stays the dashboard) |
| `/*` or `*` | **Catch-all** — catches every otherwise-unmatched path, including multi-segment ones | redirect domains only |

Resolution per request: a concrete slug beats the catch-all; the root tries the
root link first, then the catch-all; nothing matches → 404. Both inherit expiry
date, password protection and click statistics like normal links. In the link
list they appear as `domain/` and `domain/*`. At most one of each per domain.

## Deployment (Docker behind Traefik)

The multi-stage `Dockerfile` builds a Mix release. Run as **one** container
behind an external Traefik (TLS termination). Template:
[`compose.prod.yml`](compose.prod.yml). Configuration exclusively via environment
variables (`config/runtime.exs`).

> **SQLite = single-writer.** Run exactly **one** app instance — no replicas, no
> horizontal scaling. The DB file (incl. `-wal`/`-shm`) must live on a persistent
> volume.

### 1. Get the image

CI builds an **amd64** image on every tag to `ghcr.io/styliteag/orbit-ly:<version>`
(+ `:latest`). For arm64 or a local build: `just publish all` (see
`build-and-push.sh`).

### 2. Secrets & `.env`

`compose.prod.yml` reads the values from a `.env` next to it. Copy the template
and fill it in (the `.env` itself is gitignored):

```sh
cp .env.example .env
# set MAIN_DOMAIN and SMTP credentials, then generate the app secret:
echo "SECRET_KEY_BASE=$(openssl rand -base64 64 | tr -d '\n')" >> .env
```

| Variable | Required | Default | Meaning |
| --- | --- | --- | --- |
| `DATABASE_PATH` | yes | — | SQLite file, set to `/data/orbitly.db` in the compose file |
| `SECRET_KEY_BASE` | yes | — | cookie/session signature, ≥ 64 characters |
| `MAIN_DOMAIN` | yes | — | primary domain = dashboard host. Set as the primary domain's hostname at boot |
| `SMTP_RELAY` | yes | — | SMTP relay hostname, without scheme |
| `SMTP_USERNAME` | no | — | SMTP account username; unset = relay without authentication |
| `SMTP_PASSWORD` | no | — | SMTP account password; must be set together with `SMTP_USERNAME` |
| `MAIL_FROM` | yes | — | sender email address for password resets |
| `MAIL_FROM_NAME` | no | `Orbit-ly` | sender display name |
| `SMTP_PORT` | no | `587` | SMTP submission port (`25` for the typical internal relay) |
| `SMTP_TLS` | no | `always` | `always` (STARTTLS enforced + certificate verified), `if_available`, `never` |
| `PORT` | no | `4000` | HTTP port inside the container (Traefik points here) |
| `POOL_SIZE` | no | `10` | DB connection pool |
| `TRUSTED_PROXY_HOPS` | no | `1` | number of reverse proxies (Traefik = 1; a CDN/LB in front → increase) |

By default the mailer enforces authenticated STARTTLS and verifies the relay's
TLS certificate; most providers expose this on port 587. Set `SMTP_USERNAME` and
`SMTP_PASSWORD` together — setting only one aborts the boot, leaving both unset
switches the mailer to `auth: :never` for an internal relay that does not offer
AUTH. Such a relay usually listens on port 25 and often has no publicly
verifiable certificate, so it needs `SMTP_PORT=25` and `SMTP_TLS=if_available`
(or `never`). With `never` the mail — including the reset link — crosses the
network in cleartext; only do that inside a trusted network. Configure SPF and
DKIM for the `MAIL_FROM` domain at the mail provider. Before go-live, request a
password reset against the deployed instance and verify both delivery and the
reset link.

### 3. Migrations

Run **automatically on container start** — `Orbitly.Application` has an
`Ecto.Migrator` in the supervisor that, in a release (environment variable
`RELEASE_NAME` set), runs pending migrations before the endpoint. Creates the DB
file on first start. No separate step needed.

Manually (e.g. a dry-run check without starting the server) still works:

```sh
docker compose -f compose.prod.yml run --rm app /app/bin/migrate
```

### 4. Create the first admin

There is **no** open registration. The release task `bin/create_admin` creates
the instance admin (idempotent, reads `ADMIN_EMAIL`/`ADMIN_PASSWORD`):

```sh
docker compose -f compose.prod.yml run --rm \
  -e ADMIN_EMAIL=admin@example.com \
  -e ADMIN_PASSWORD='PLEASE-CHANGE' \
  app /app/bin/create_admin
```

The **primary domain** needs no task: it comes from `MAIN_DOMAIN` and is synced
into the DB as the primary domain on container start (created or renamed).
Changing `MAIN_DOMAIN` later moves the dashboard **and** all links living on it
to the new domain — just redeploy, no further step. Add further redirect domains
in the admin UI.

Then `docker compose -f compose.prod.yml up -d`, log in at `https://$MAIN_DOMAIN`;
add more domains and users in the admin UI.

### 5. Traefik routing

The app serves **multiple** hostnames: the dashboard on `MAIN_DOMAIN` and every
redirect domain. Unknown hosts → 404 (ADR-0003). Two models (labels in
`compose.prod.yml`):

- **Concrete hosts** (recommended): `Host(...)` list, per-host ACME certificates
  automatically. For a new domain: add a label + `docker compose up -d`.
- **Catch-all** (`HostRegexp(`^.+$`)`): catches all hosts, but needs a matching
  certificate (wildcard via DNS-01 or a default cert), because ACME issues
  nothing on-demand for unknown hosts.

Traefik terminates TLS and forwards to port `4000` (http); an HTTP→HTTPS redirect
is preconfigured as middleware. `TRUSTED_PROXY_HOPS` must match the proxy chain,
otherwise click IP and auth rate limit act on the wrong `x-forwarded-for` entry.

### 6. Upgrade

```sh
# .env: bump ORBITLY_VERSION
docker compose -f compose.prod.yml pull
docker compose -f compose.prod.yml up -d   # migrations run automatically on start
```

### 7. Import links from Kutt (optional)

`bin/import_kutt` fetches the links of a Kutt instance via its API and creates
them on the primary domain (or `KUTT_DOMAIN`) for the current admin — or, with
`KUTT_OWNER`, for that account (email, case-insensitive; the account must exist,
there is no self-signup). Idempotent — can be run multiple times.

```sh
docker compose -f compose.prod.yml run --rm \
  -e KUTT_API_URL=http://kutt.intern:3000 \
  -e KUTT_API_KEY=<kutt-api-key> \
  -e KUTT_OWNER=user@example.com \
  app /app/bin/import_kutt
```

In dev: `just import-kutt http://localhost:3000 <KEY> [domain] [owner-email]`.

Links already imported onto the wrong account can be moved afterwards: select
them on `/links` as an admin and use **Reassign**.

Limits (imposed by Kutt's API): only the API-key user's links; **no password
hashes** — protected links come in without a password and are listed at the end
(set them anew); click history is **synthesized** (one event per counted visit,
spread evenly over the link's lifetime, placeholder user agent, no IP). Reserved
slugs (`admin`, `stats`, …) get a suffix, already-existing slugs are skipped.

### Cutting a release

`VERSION` is the version source for Mix and images. `just release
[major|minor|patch]` (→ `release.sh`) bumps the version, adds a dated section to
`CHANGELOG.md`, commits, tags and pushes. The tag triggers
`.github/workflows/release.yml` (builds + pushes the image, creates the GitHub
release).

## Documentation

- [Domain model](docs/DOMAIN_MODEL.md) — entities, invariants, flows
- [Glossary](docs/GLOSSARY.md) — ubiquitous language

Core decisions: tenant = single user, shared domains (wildcard only at the
proxy), redirect hot path as its own plug with an ETS cache bypassing Ash, no
open registration, raw click data kept for 12 months.

## License

Source-available under the [Business Source License 1.1](LICENSE). Self-hosting
and modification allowed; hosting as a service for third parties or reselling
needs a commercial license. Each version turns into GPL v3.0 automatically four
years after release. Plain-text summary: [LICENSING.md](LICENSING.md). Commercial
license: office@stylite.de.
