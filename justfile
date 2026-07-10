# https://github.com/casey/just
set shell := ["bash", "-cu"]

default:
    @just --list

# --- Dev stack (everything in the container, ADR-0007) ----------------------

# Dev server with live reload → http://localhost:4000
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

# Shell in the app container
sh:
    docker compose run --rm app bash

# IEx with the app running
iex:
    docker compose run --rm app iex -S mix

# --- Mix in the container ----------------------------------------------------

# Tests; arguments are passed through: just test test/orbitly/shortener
test *ARGS:
    docker compose run --rm app mix test {{ARGS}}

fmt:
    docker compose run --rm app mix format

# Fetch deps + set up DB + seeds (idempotent)
setup:
    docker compose run --rm app sh -c "mix local.hex --force && mix local.rebar --force && mix setup"

# Generate a blank Ecto migration: just gen-migration add_feature_x
gen-migration NAME:
    docker compose run --rm app mix ecto.gen.migration {{NAME}}

migrate:
    docker compose run --rm app mix ecto.migrate

# Bump version, update CHANGELOG.md, tag, and push (triggers the GHA release build).
release type="patch":
    ./release.sh {{type}}

# Build the prod image LOCALLY and push straight to the registries (no CI).
# just publish        → amd64 + arm64   |   just publish amd64   → single arch
publish platforms="all":
    ./build-and-push.sh {{platforms}}

# Import links from a Kutt instance (API). just import-kutt URL KEY [DOMAIN]
import-kutt url key domain="":
    docker compose run --rm app mix orbitly.import_kutt --api-url {{url}} --api-key {{key}} {{ if domain == "" { "" } else { "--domain " + domain } }}

# --- Cleanup ------------------------------------------------------------------

# Removes containers AND the dev caches under ./data (deps, _build, toolchain).
# Next start recompiles everything. The SQLite dev DB stays untouched.
clean: down
    rm -rf data/deps data/build data/toolchain
