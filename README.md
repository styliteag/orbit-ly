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

## Deployment

Multi-Stage-`Dockerfile` baut ein Mix Release. Betrieb als ein Container hinter
einem externen Reverse Proxy (Traefik/Caddy, Wildcard-Catch-all, TLS-Terminierung).
Konfiguration über Umgebungsvariablen (`config/runtime.exs`), SQLite-Datei auf
einem Volume.

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
