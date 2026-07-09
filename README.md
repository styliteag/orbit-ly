# Stylite Orbit-ly

Mandantenfähiger Linkshortener (ähnlich [kutt](https://github.com/thedevs-network/kutt)),
gebaut mit Phoenix + [Ash Framework](https://ash-hq.org) auf SQLite.
Elixir-App: `orbitly`, Modul-Namespace: `Orbitly`.

## Entwicklung (nur Docker, kein lokales Elixir)

```sh
docker compose up
```

Danach: <http://localhost:4000>. Code-Reload funktioniert über den Bind-Mount;
Deps, Build-Artefakte und Toolchain liegen in Docker-Volumes.

Tests:

```sh
docker compose run --rm app sh -c "mix setup && mix test"
```

## Deployment (Docker hinter Traefik)

Das Multi-Stage-`Dockerfile` baut ein Mix Release. Betrieb als **ein** Container
hinter einem externen Traefik (TLS-Terminierung). Vorlage:
[`compose.prod.yml`](compose.prod.yml). Konfiguration ausschließlich über
Umgebungsvariablen (`config/runtime.exs`).

> **SQLite = Single-Writer.** Genau **eine** app-Instanz betreiben — keine
> Replicas, kein horizontales Scaling. Die DB-Datei (inkl. `-wal`/`-shm`) muss
> auf einem persistenten Volume liegen.

### 1. Image beziehen

CI baut bei jedem Tag ein **amd64**-Image nach `ghcr.io/styliteag/orbit-ly:<version>`
(+ `:latest`). Für arm64 oder einen lokalen Build: `just publish all` (siehe
`build-and-push.sh`).

### 2. Secrets & `.env`

`compose.prod.yml` liest die Werte aus einem `.env` daneben:

```sh
cat > .env <<EOF
ORBITLY_VERSION=0.1.3
PHX_HOST=go.example.com
SECRET_KEY_BASE=$(openssl rand -base64 64 | tr -d '\n')
TOKEN_SIGNING_SECRET=$(openssl rand -base64 48 | tr -d '\n')
EOF
```

| Variable | Pflicht | Default | Bedeutung |
| --- | --- | --- | --- |
| `DATABASE_PATH` | ja | — | SQLite-Datei, im Compose auf `/data/orbitly.db` gesetzt |
| `SECRET_KEY_BASE` | ja | — | Cookie-/Session-Signatur, ≥ 64 Zeichen |
| `TOKEN_SIGNING_SECRET` | ja | — | Signatur der Auth-Tokens |
| `PHX_HOST` | ja | `example.com` | Hauptdomain (Dashboard-Host) für URL-Erzeugung |
| `PORT` | nein | `4000` | HTTP-Port im Container (Traefik zeigt hierhin) |
| `POOL_SIZE` | nein | `10` | DB-Connection-Pool |
| `TRUSTED_PROXY_HOPS` | nein | `1` | Anzahl Reverse-Proxies (Traefik = 1; CDN/LB davor → erhöhen) |

### 3. Migrationen (vor erstem Start und nach jedem Upgrade)

```sh
docker compose -f compose.prod.yml run --rm app /app/bin/migrate
```

Legt die SQLite-Datei an bzw. bringt das Schema auf Stand. Kein Mix im Image —
das Release-Skript `bin/migrate` ruft `Orbitly.Release.migrate`.

### 4. Ersten Admin + Hauptdomain anlegen

Es gibt **keine** offene Registrierung. Den Instanz-Admin legt der Release-Task
`bin/create_admin` an (idempotent, liest `ADMIN_EMAIL`/`ADMIN_PASSWORD`):

```sh
docker compose -f compose.prod.yml run --rm \
  -e ADMIN_EMAIL=admin@example.com \
  -e ADMIN_PASSWORD='BITTE-AENDERN' \
  app /app/bin/create_admin
```

Die Hauptdomain gibt es noch nicht als Task — einmalig per RPC:

```sh
docker compose -f compose.prod.yml up -d
docker compose -f compose.prod.yml exec app /app/bin/orbitly rpc '
  Ash.Seed.seed!(Orbitly.Shortener.Domain, %{
    hostname: "go.example.com", is_primary: true, active: true
  })
'
```

Danach Login unter `https://$PHX_HOST`; weitere Domains und Benutzer im Admin-UI.

### 5. Traefik-Routing

Die App bedient **mehrere** Hostnamen: das Dashboard auf `PHX_HOST` und jede
Redirect-Domain. Unbekannte Hosts → 404 (ADR-0003). Zwei Modelle (Labels in
`compose.prod.yml`):

- **Konkrete Hosts** (empfohlen): `Host(...)`-Liste, per-Host-ACME-Zertifikate
  automatisch. Bei neuer Domain: Label ergänzen + `docker compose up -d`.
- **Catch-all** (`HostRegexp(`^.+$`)`): fängt alle Hosts, braucht aber ein
  passendes Zertifikat (Wildcard via DNS-01 oder Default-Cert), weil ACME für
  unbekannte Hosts nichts on-demand ausstellt.

Traefik terminiert TLS und leitet auf Port `4000` (http) weiter; ein
HTTP→HTTPS-Redirect ist als Middleware vorkonfiguriert. `TRUSTED_PROXY_HOPS`
muss zur Proxy-Kette passen, sonst greifen Klick-IP und Auth-Rate-Limit am
falschen `x-forwarded-for`-Eintrag.

### 6. Upgrade

```sh
# .env: ORBITLY_VERSION anheben
docker compose -f compose.prod.yml pull
docker compose -f compose.prod.yml run --rm app /app/bin/migrate
docker compose -f compose.prod.yml up -d
```

### Release schneiden

`VERSION` ist die Versionsquelle für Mix und Images. `just release
[major|minor|patch]` (→ `release.sh`) erhöht die Version, ergänzt einen
datierten Abschnitt in `CHANGELOG.md`, committet, taggt und pusht. Der Tag
startet `.github/workflows/release.yml` (baut + pusht das Image, erstellt das
GitHub-Release).

## Dokumentation

- [Domänenmodell](docs/DOMAENENMODELL.md) — Entitäten, Invarianten, Abläufe
- [Glossar](docs/GLOSSAR.md) — Ubiquitous Language

Kernentscheidungen: Mandant = Einzelbenutzer, geteilte Domains (Wildcard nur am
Proxy), Redirect-Hotpath als eigener Plug mit ETS-Cache an Ash vorbei, keine
offene Registrierung, Klick-Rohdaten 12 Monate.

## Lizenz

Source-available unter der [Business Source License 1.1](LICENSE). Selbst
betreiben und modifizieren erlaubt; Hosting als Dienst für Dritte oder
Weiterverkauf braucht eine kommerzielle Lizenz. Jede Version wird vier Jahre
nach Veröffentlichung automatisch GPL v3.0. Klartext-Zusammenfassung:
[LICENSING.md](LICENSING.md). Kommerzielle Lizenz: office@stylite.de.
