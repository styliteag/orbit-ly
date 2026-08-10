# CLAUDE.md — Stylite Orbit-ly

Multi-tenant link shortener (Phoenix + Ecto on SQLite — **plain, no Ash**). Two
contexts: `Orbitly.Shortener` (domains, links, click events) and
`Orbitly.Accounts` (users + session-based auth). Framework conventions
(Elixir/Phoenix/LiveView idioms) live in **AGENTS.md** — here only the project
delta.

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
just dev              # server, http://localhost:4000
just test [ARGS]      # mix test in the container
just gen-migration N  # mix ecto.gen.migration — schema changes are plain Ecto
just fmt | iex | sh | migrate | setup
docker compose run --rm app mix precommit   # before every commit
```

- Dev image = `Dockerfile.dev` (elixir:1.20 + cmake for lazy_html + inotify-tools).
- `./data/` = caches (deps/_build/toolchain), gitignored; `just clean` deletes them.
- Migrations land in `priv/repo/migrations/` on the host. After `just migrate`
  with the dev server running: `docker compose restart app` — the server holds
  the SQLite file open against its stale `_build` copy of `priv` and otherwise
  shows the pending-migration error page (`Phoenix.Ecto.CheckRepoStatus`).
- Dev login (seeds, dev only): `admin@localhost` / `orbitly-dev-password`.

## Architecture cornerstones

- **Redirect hot path NEVER goes through the context** (ADR-0001):
  `OrbitlyWeb.Redirector` (plug in the endpoint before the router) +
  `RedirectCache` (ETS, read-through in the caller process, 60s TTL; plain Ecto
  queries). Invalidation: the `Orbitly.Shortener` context flushes `RedirectCache`
  directly on every domain/link mutation.
- **Click events are NEVER written one by one**: only via `ClickBuffer`
  (batch `insert_all`), otherwise SQLite's single writer blocks the hot path.
  Stats are plain Ecto group-by queries (`ClickStats`, `Shortener.click_counts/1`).
- **Shortener authorization is explicit context scoping**: callers pass the
  acting user; `Orbitly.Shortener` enforces owner/admin via `can_access_link?`,
  `scope_links`, `admin?`, and forces `owner_id` on create (never
  mass-assignable). Data access in the hot path, seeds and fixtures bypasses
  authorization by design.
- **The links page is admin-scoped by default**: `Shortener.list_links/2` takes
  `:own` (default in `LinksLive`) or `:all`; `:own` narrows an admin to their
  own links, `:all` never widens a normal user's view. Filtering, sorting and
  paging all happen in `LinksLive.table_rows/1` — the one function the render
  path *and* the selection handlers use, so "select all on this page" can never
  drift from what is on screen.
- **Bulk link actions** (`Shortener.delete_links/2`, `reassign_links/3`) run as
  a single `delete_all` / `update_all` (SQLite has one writer — never loop per
  link) and flush `RedirectCache` once. `delete_links` pushes the id list
  through `scope_links(actor)`, so tampered ids can never reach someone else's
  link; non-UUID ids are dropped before the query. Reassigning an owner is
  admin-only (a normal user must not see the account list, ADR-0006) and is the
  only path that ever changes `owner_id` — it stays out of every changeset.
- **Auth is plain Phoenix session auth** (phx.gen.auth model, `OrbitlyWeb.UserAuth`):
  opaque session tokens in `users_tokens`, Bcrypt passwords, reset tokens stored
  SHA-256-hashed. `fetch_current_user` plug + `on_mount` hooks
  (`:mount_current_user`, `:live_user_required`, `:live_admin_required`,
  `:live_no_user`). Login = `POST /session` (`UserSessionController`), logout =
  `DELETE /sign-out`, reset LiveViews at `/reset` and `/password-reset/:token`.
  App authorization lives at the router (admin routes) + on_mount, NOT in
  `Orbitly.Accounts` (the context is unauthenticated by design).
- Slug rules centralized in `Orbitly.Shortener.Slug`; reserved list in
  `config/config.exs` — extend it for every new UI route (ADR-0004).
- **Three switchable UI designs × two modes** (`OrbitlyWeb.Design`:
  `orbit` default / `bench` / `soft`, each `light`+`dark`): design and mode
  combine into a daisyUI theme (`orbit-dark`, …) server-rendered as
  `data-theme` on `<html>` (no client theme script). Choices persist via
  `orbitly_design`/`orbitly_mode` cookies (`PUT /design/:design`,
  `PUT /design-mode/:mode`, `DesignController`); the router's `fetch_design`
  plug assigns `:design`+`:theme` and mirrors the design into the session,
  where LiveViews read it on mount. Orbit is dark-first, Bench/Soft
  light-first (`default_mode/1`). Everything sits in the navbar gear menu
  (`Layouts.settings_menu`, active entries highlighted via CSS on
  data-theme). The links page swaps its whole layout per design
  (`LinksLive.Orbit|Bench|Soft`, shared pieces in `LinksLive.Shared`,
  multi-select in `LinksLive.Bulk`, column sorting in `LinksLive.Sort`) —
  event names and ids (`link-form`, `search-form`, `advanced-options`,
  `edit-form`, `link-<id>`, `bulk-bar`, `bulk-reassign-form`,
  `toggle-select`, `toggle-select-page`, `bulk-delete`, `bulk-reassign`,
  `scope`, `sort`) are the contract; a new design must render the row
  checkbox, the bulk bar and exactly one sort control (`Sort.sort_menu` for
  list designs *or* `Sort.sort_header` cells for a table — never both, the
  selectors must stay unambiguous). Keep design layouts
  mode-agnostic (semantic classes, no hardcoded `white/...`). Fonts are
  self-hosted woff2 in `priv/static/fonts` (CSP `font-src 'self'` — never
  load font CDNs).
- **Self-service password change** at `/settings` (`UserSettingsLive`):
  requires the current password, drops all tokens (log-out-everywhere) and
  re-logs-in via phx-trigger-action `POST /session?_action=password-updated`.
  Still no open registration and no self-service email change.
- **The primary domain is env-driven (sentinel):** exactly one `is_primary` row,
  its hostname follows `MAIN_DOMAIN` (`:orbitly, :main_domain`). `MAIN_DOMAIN`
  is the ONE source for the dashboard host — also the endpoint `url` host (no
  more `PHX_HOST`). `Orbitly.Shortener.PrimaryDomain` (supervisor child before
  the endpoint) creates it at boot or renames it in place; links are anchored to
  the row id and move with it. Off in tests (`ensure_primary_domain: false`) —
  there fixtures own the domains. The primary row is protected against deletion
  (`Shortener.delete_domain` refuses it) and deactivation
  (`Domain.update_changeset`); `is_primary` is set only via
  `Domain.primary_changeset` (used by `PrimaryDomain`), never through the admin
  create/update changesets — no admin `make_primary`.

## SQLite

- Transient "database is locked" during parallel setup seen already; if it shows
  up in production, set `busy_timeout` in the repo config.
- UUID primary keys are stored as 36-char TEXT — Ecto schemas use `Ecto.UUID`.
  Email lookups are case-insensitive via an explicit `collate nocase` fragment.

## Tests

- Fixtures: `Orbitly.Fixtures`. `user_fixture`/`domain_fixture`/`link_fixture` =
  `Repo.insert!` of a struct (bypass validation for arbitrary state; `user_fixture`
  gets a fake password hash). For logged-in conn/LiveView tests use
  `registered_user_fixture` (real Bcrypt hash) + `log_in/2` (mints a real session
  token and stores it in the session).
- DB and GenServer tests `async: false` (shared sandbox; SQLite).
- Tests that trigger redirects leave events in the `ClickBuffer` — keep the setup
  pattern with `on_exit(fn -> ClickBuffer.flush_now() end)`, otherwise FK-error
  noise after rollback.
- `assert_error_sent` does not work for router 404s (Phoenix 1.8 renders without
  re-raising) — check `conn.status == 404` directly.

## Known open points (don't forget)

- No open registration (ADR-0006): there is deliberately no register route and no
  `Accounts` self-signup function — accounts are admin-created only. Do NOT add
  one when touching auth.
- ALWAYS determine the client IP via `OrbitlyWeb.ClientIP.get/1`, never take the
  first `x-forwarded-for` entry (spoofable). Prod reads the IP only from XFF;
  `:trusted_proxy_hops` (env `TRUSTED_PROXY_HOPS`, default 1) must match the
  number of reverse proxies, otherwise rate limiting acts on the wrong value.
- The `POST /session` sign-in is throttled by the `AuthRateLimit` plug (10/min/IP).
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
