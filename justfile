# https://github.com/casey/just
set shell := ["bash", "-cu"]

default:
    @just --list

# --- Dev-Stack (alles im Container, ADR-0007) -------------------------------

# Dev-Server mit Live-Reload → http://localhost:4000
dev:
    docker compose up --build

dev-up:
    docker compose up -d --build

down:
    docker compose down

logs:
    docker compose logs -f --tail=200

build:
    docker compose build

# Shell im App-Container
sh:
    docker compose run --rm app bash

# IEx mit laufender App
iex:
    docker compose run --rm app iex -S mix

# --- Mix im Container --------------------------------------------------------

# Tests; Argumente werden durchgereicht: just test test/orbitly/shortener
test *ARGS:
    docker compose run --rm app mix test {{ARGS}}

fmt:
    docker compose run --rm app mix format

# Deps holen + DB aufsetzen + Seeds (idempotent)
setup:
    docker compose run --rm app sh -c "mix local.hex --force && mix local.rebar --force && mix setup"

# Migration aus Resource-Änderungen generieren: just codegen add_feature_x
codegen NAME:
    docker compose run --rm app mix ash.codegen {{NAME}}

migrate:
    docker compose run --rm app mix ash.migrate

# Bump version, update CHANGELOG.md, tag, and push.
release type="patch":
    ./release.sh {{type}}

# --- Aufräumen ----------------------------------------------------------------

# Entfernt Container UND die Dev-Caches unter ./data (deps, _build, toolchain).
# Nächster Start kompiliert alles neu. Die SQLite-Dev-DB bleibt unberührt.
clean: down
    rm -rf data/deps data/build data/toolchain
