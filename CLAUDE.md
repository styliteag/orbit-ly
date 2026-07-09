# CLAUDE.md — Stylite Orbit-ly

Mandantenfähiger Linkshortener (Phoenix + Ash + AshSqlite). Framework-Konventionen
(Elixir/Phoenix/LiveView/Ash-Idiome) stehen in **AGENTS.md** — hier nur das
Projekt-Delta.

## Quellen der Wahrheit

- ADR-Nummern in Code-Kommentaren (`ADR-0001` …) sind historische Referenzen;
  die ADR-Dokumente selbst liegen nicht in diesem Repo.
- `docs/GLOSSAR.md`: Ubiquitous Language (Slug, Hauptdomain, Redirect-Hotpath, …).
- `docs/DOMAENENMODELL.md`: Entitäten, Invarianten, bewusste Nicht-Ziele von v1
  (keine REST-API, keine BYOD-Domains, keine Teams, kein Klick-Limit).

## Goldene Regel: kein lokales Elixir (ADR-0007)

Mix läuft NIE auf dem Host. Alles über Docker:

```sh
just dev          # Server, http://localhost:4000
just test [ARGS]  # mix test im Container
just codegen NAME # mix ash.codegen nach JEDER Resource-Änderung
just fmt | iex | sh | migrate | setup
docker compose run --rm app mix precommit   # vor jedem Commit
```

- Dev-Image = `Dockerfile.dev` (elixir:1.20 + cmake für lazy_html + inotify-tools).
- `./data/` = Caches (deps/_build/toolchain), gitignored; `just clean` löscht sie.
- Migrationen/Snapshots landen korrekt in `priv/` auf dem Host, auch wenn das
  Codegen-Log `_build/...`-Pfade anzeigt.
- Nach `just codegen`/`just migrate` bei laufendem Dev-Server:
  `docker compose restart app` — der Server prüft Codegen-Status gegen seine
  veraltete `_build`-Kopie von `priv` und antwortet sonst mit 500.
- Dev-Login (Seeds, nur dev): `admin@localhost` / `orbitly-dev-password`.

## Architektur-Eckpfeiler

- **Redirect-Hotpath läuft NIE durch Ash** (ADR-0001): `OrbitlyWeb.Redirector`
  (Plug im Endpoint vor dem Router) + `RedirectCache` (ETS, Read-through im
  Caller-Prozess, 60s-TTL). Invalidierung: `CacheInvalidator`-Notifier flusht
  bei jeder Domain/Link-Mutation komplett.
- **Klick-Events werden NIE einzeln geschrieben**: nur über `ClickBuffer`
  (Batch-`insert_all`), sonst blockiert SQLites Single-Writer den Hotpath.
- **Actor immer durchreichen**: Ownership/Admin läuft über Policies
  (`relates_to_actor_via(:owner)`, `admin`-Flag). `authorize?: false` ist nur im
  Hotpath, in Seeds und in Fixtures legitim.
- Slug-Regeln zentral in `Orbitly.Shortener.Slug`; Reserved-Liste in
  `config/config.exs` — bei jeder neuen UI-Route ergänzen (ADR-0004).

## AshSqlite-Fallstricke

- **Keine count-Aggregate** (`AggregatesNotSupported`) — stattdessen
  Ecto-Gruppenquery, siehe `Shortener.click_counts/1`.
- Transientes „database is locked" bei parallelem Setup schon gesehen; falls es
  im Betrieb auftaucht: `busy_timeout` in der Repo-Config setzen.

## Tests

- Fixtures: `Orbitly.Fixtures`. `user_fixture`/`domain_fixture`/`link_fixture` =
  `Ash.Seed` (umgeht Policies, beliebiger Zustand). Für eingeloggte
  Conn/LiveView-Tests IMMER `registered_user_fixture` + `log_in/2` (echtes
  Token-Metadata, `store_in_session` braucht es).
- DB- und GenServer-Tests `async: false` (shared Sandbox; SQLite).
- Tests, die Redirects auslösen, hinterlassen Events im `ClickBuffer` — das
  Setup-Muster mit `on_exit(fn -> ClickBuffer.flush_now() end)` beibehalten,
  sonst FK-Fehler-Lärm nach Rollback.
- `assert_error_sent` funktioniert nicht für Router-404s (Phoenix 1.8 rendert
  ohne Re-Raise) — direkt `conn.status == 404` prüfen.

## Bekannte offene Punkte (nicht vergessen)

- Registrierung ist hart deaktiviert (`RegistrationDisabled`-Validation) —
  beim Anfassen der Auth-Strategie NICHT versehentlich entfernen.
- Client-IP IMMER über `OrbitlyWeb.ClientIP.get/1` ermitteln, nie den ersten
  `x-forwarded-for`-Eintrag nehmen (spoofbar). Prod liest die IP nur aus XFF;
  `:trusted_proxy_hops` (ENV `TRUSTED_PROXY_HOPS`, Default 1) muss zur Anzahl
  der Reverse-Proxies passen, sonst greift Rate-Limiting am falschen Wert.
- Auth-POSTs (`/auth/*`) sind per `AuthRateLimit`-Plug gedrosselt (10/min/IP).
  Session-Cookie hat noch kein `secure`-Flag (LOW, `force_ssl` mildert); CSP
  fehlt noch (Sobelow). Beides offen.
- GeoIP/Land ist GESTRICHEN (ADR-0005-Präzisierung) — nicht wieder einbauen
  ohne neue Entscheidung.
- Prod-Deploy noch nie durchgespielt (Release-Image bauen, Volume, Proxy).
