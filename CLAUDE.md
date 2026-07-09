# CLAUDE.md — Stylite Orbit-ly

Multi-tenant link shortener (Phoenix + Ash + AshSqlite). Framework conventions
(Elixir/Phoenix/LiveView/Ash idioms) live in **AGENTS.md** — here only the
project delta.

## Sources of truth

- ADR numbers in code comments (`ADR-0001` …) are historical references; the ADR
  documents themselves are not in this repo.
- `docs/GLOSSARY.md`: ubiquitous language (slug, primary domain, redirect hot
  path, …).
- `docs/DOMAIN_MODEL.md`: entities, invariants, deliberate non-goals of v1 (no
  REST API, no BYOD domains, no teams, no click limit).

## Golden rule: no local Elixir (ADR-0007)

Mix NEVER runs on the host. Everything via Docker:

```sh
just dev          # server, http://localhost:4000
just test [ARGS]  # mix test in the container
just codegen NAME # mix ash.codegen after EVERY resource change
just fmt | iex | sh | migrate | setup
docker compose run --rm app mix precommit   # before every commit
```

- Dev image = `Dockerfile.dev` (elixir:1.20 + cmake for lazy_html + inotify-tools).
- `./data/` = caches (deps/_build/toolchain), gitignored; `just clean` deletes them.
- Migrations/snapshots land correctly in `priv/` on the host, even when the
  codegen log shows `_build/...` paths.
- After `just codegen`/`just migrate` with the dev server running:
  `docker compose restart app` — the server checks codegen status against its
  stale `_build` copy of `priv` and otherwise responds with 500.
- Dev login (seeds, dev only): `admin@localhost` / `orbitly-dev-password`.

## Architecture cornerstones

- **Redirect hot path NEVER goes through Ash** (ADR-0001): `OrbitlyWeb.Redirector`
  (plug in the endpoint before the router) + `RedirectCache` (ETS, read-through
  in the caller process, 60s TTL). Invalidation: the `CacheInvalidator` notifier
  fully flushes on every domain/link mutation.
- **Click events are NEVER written one by one**: only via `ClickBuffer`
  (batch `insert_all`), otherwise SQLite's single writer blocks the hot path.
- **Always pass the actor through**: ownership/admin runs through policies
  (`relates_to_actor_via(:owner)`, `admin` flag). `authorize?: false` is only
  legitimate in the hot path, in seeds and in fixtures.
- Slug rules centralized in `Orbitly.Shortener.Slug`; reserved list in
  `config/config.exs` — extend it for every new UI route (ADR-0004).
- **The primary domain is env-driven (sentinel):** exactly one `is_primary` row,
  its hostname follows `MAIN_DOMAIN` (`:orbitly, :main_domain`). `MAIN_DOMAIN`
  is the ONE source for the dashboard host — also the endpoint `url` host (no
  more `PHX_HOST`). `Orbitly.Shortener.PrimaryDomain` (supervisor child before
  the endpoint) creates it at boot or renames it in place; links are anchored to
  the row id and move with it. Off in tests (`ensure_primary_domain: false`) —
  there fixtures own the domains. The primary row is protected against deletion/
  deactivation (`Changes.ProtectPrimary`); `is_primary` is NOT in the `:create`
  accept — no more admin `make_primary`.

## AshSqlite pitfalls

- **No count aggregates** (`AggregatesNotSupported`) — use an Ecto group query
  instead, see `Shortener.click_counts/1`.
- Transient "database is locked" during parallel setup seen already; if it shows
  up in production: set `busy_timeout` in the repo config.

## Tests

- Fixtures: `Orbitly.Fixtures`. `user_fixture`/`domain_fixture`/`link_fixture` =
  `Ash.Seed` (bypasses policies, arbitrary state). For logged-in conn/LiveView
  tests ALWAYS use `registered_user_fixture` + `log_in/2` (real token metadata,
  `store_in_session` needs it).
- DB and GenServer tests `async: false` (shared sandbox; SQLite).
- Tests that trigger redirects leave events in the `ClickBuffer` — keep the setup
  pattern with `on_exit(fn -> ClickBuffer.flush_now() end)`, otherwise FK-error
  noise after rollback.
- `assert_error_sent` does not work for router 404s (Phoenix 1.8 renders without
  re-raising) — check `conn.status == 404` directly.

## Known open points (don't forget)

- Registration is hard-disabled (`RegistrationDisabled` validation) — do NOT
  accidentally remove it when touching the auth strategy.
- ALWAYS determine the client IP via `OrbitlyWeb.ClientIP.get/1`, never take the
  first `x-forwarded-for` entry (spoofable). Prod reads the IP only from XFF;
  `:trusted_proxy_hops` (env `TRUSTED_PROXY_HOPS`, default 1) must match the
  number of reverse proxies, otherwise rate limiting acts on the wrong value.
- Auth POSTs (`/auth/*`) are throttled by the `AuthRateLimit` plug (10/min/IP).
- CSP: strict Content-Security-Policy via the `ContentSecurityPolicy` plug, off
  in dev (`csp_enabled: false`, otherwise LiveReload breaks). Inline scripts need
  `nonce={assigns[:csp_nonce]}` — new inline scripts are blocked otherwise.
- Session cookie `secure: true` only in prod (`config :orbitly, :session`,
  compile-time in the endpoint).
- Create the prod admin: `bin/create_admin` with `ADMIN_EMAIL`/`ADMIN_PASSWORD`
  (idempotent, `Orbitly.Release.create_admin`). No open registration.
- GeoIP/country is DROPPED (ADR-0005 refinement) — do not add it back without a
  new decision.
- Prod deploy never rehearsed (build the release image, volume, proxy).
