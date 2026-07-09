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

## Custom-Domain-Redirects (Root & Catch-all)

Neben normalen Kurzlinks (`domain/slug`) kann ein Admin pro Domain zwei
Spezial-Links anlegen — einfach den passenden Wert ins **Custom-address**-Feld
des Link-Formulars tippen:

| Eingabe | Ergebnis | Wirkt auf |
| --- | --- | --- |
| `/` oder `@` | **Root-Redirect** — `domain/` leitet weiter | nur Redirect-Domains (Hauptdomain-Wurzel bleibt das Dashboard) |
| `/*` oder `*` | **Catch-all** — fängt jeden sonst nicht passenden Pfad, auch mehrsegmentige | nur Redirect-Domains |

Auflösung pro Anfrage: konkreter Slug schlägt Catch-all; die Wurzel probiert
erst den Root-Link, dann den Catch-all; trifft nichts → 404. Beide erben
Ablaufdatum, Passwortschutz und Klick-Statistik wie normale Links. In der
Link-Liste erscheinen sie als `domain/` bzw. `domain/*`. Höchstens je einer pro
Domain.

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

`compose.prod.yml` liest die Werte aus einem `.env` daneben. Vorlage kopieren
und ausfüllen (die `.env` selbst ist gitignored):

```sh
cp .env.example .env
# MAIN_DOMAIN setzen, Secrets erzeugen:
echo "SECRET_KEY_BASE=$(openssl rand -base64 64 | tr -d '\n')" >> .env
echo "TOKEN_SIGNING_SECRET=$(openssl rand -base64 48 | tr -d '\n')" >> .env
```

| Variable | Pflicht | Default | Bedeutung |
| --- | --- | --- | --- |
| `DATABASE_PATH` | ja | — | SQLite-Datei, im Compose auf `/data/orbitly.db` gesetzt |
| `SECRET_KEY_BASE` | ja | — | Cookie-/Session-Signatur, ≥ 64 Zeichen |
| `TOKEN_SIGNING_SECRET` | ja | — | Signatur der Auth-Tokens |
| `MAIN_DOMAIN` | ja | — | Hauptdomain = Dashboard-Host = Primärdomain. Beim Boot als Hostname der Primärdomain gesetzt |
| `PORT` | nein | `4000` | HTTP-Port im Container (Traefik zeigt hierhin) |
| `POOL_SIZE` | nein | `10` | DB-Connection-Pool |
| `TRUSTED_PROXY_HOPS` | nein | `1` | Anzahl Reverse-Proxies (Traefik = 1; CDN/LB davor → erhöhen) |

### 3. Migrationen

Laufen **automatisch beim Container-Start** — `Orbitly.Application` hat einen
`Ecto.Migrator` im Supervisor, der im Release (Umgebungsvariable `RELEASE_NAME`
gesetzt) ausstehende Migrationen vor dem Endpoint ausführt. Legt die DB-Datei
beim ersten Start an. Kein separater Schritt nötig.

Manuell (z. B. Vorabprüfung ohne Server-Start) geht weiterhin:

```sh
docker compose -f compose.prod.yml run --rm app /app/bin/migrate
```

### 4. Ersten Admin anlegen

Es gibt **keine** offene Registrierung. Den Instanz-Admin legt der Release-Task
`bin/create_admin` an (idempotent, liest `ADMIN_EMAIL`/`ADMIN_PASSWORD`):

```sh
docker compose -f compose.prod.yml run --rm \
  -e ADMIN_EMAIL=admin@example.com \
  -e ADMIN_PASSWORD='BITTE-AENDERN' \
  app /app/bin/create_admin
```

Die **Hauptdomain** braucht keinen Task: sie kommt aus `MAIN_DOMAIN` und wird
beim Container-Start als Primärdomain in die DB synchronisiert (angelegt oder
umbenannt). `MAIN_DOMAIN` später ändern zieht Dashboard **und** alle dort
liegenden Links auf die neue Domain um — nur neu ausrollen, kein weiterer
Schritt. Weitere Redirect-Domains legst du im Admin-UI an.

Danach `docker compose -f compose.prod.yml up -d`, Login unter `https://$MAIN_DOMAIN`;
weitere Domains und Benutzer im Admin-UI.

### 5. Traefik-Routing

Die App bedient **mehrere** Hostnamen: das Dashboard auf `MAIN_DOMAIN` und jede
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
docker compose -f compose.prod.yml up -d   # Migrationen laufen automatisch beim Start
```

### 7. Links aus Kutt importieren (optional)

`bin/import_kutt` holt die Links einer Kutt-Instanz über deren API und legt sie
beim aktuellen Admin auf der Primärdomain an (oder `KUTT_DOMAIN`). Idempotent —
mehrfach ausführbar.

```sh
docker compose -f compose.prod.yml run --rm \
  -e KUTT_API_URL=http://kutt.intern:3000 \
  -e KUTT_API_KEY=<kutt-api-key> \
  app /app/bin/import_kutt
```

Im Dev: `just import-kutt http://localhost:3000 <KEY> [domain]`.

Grenzen (durch Kutts API bedingt): nur die Links des API-Key-Users; **keine
Passwort-Hashes** — geschützte Links kommen ohne Passwort rein und werden am
Ende aufgelistet (neu setzen); Klick-History wird **synthetisiert** (ein Event
pro gezähltem Visit, gleichmäßig über die Link-Lebensdauer verteilt,
Platzhalter-User-Agent, keine IP). Reserved-Slugs (`admin`, `stats`, …) bekommen
ein Suffix, bereits vorhandene Slugs werden übersprungen.

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
