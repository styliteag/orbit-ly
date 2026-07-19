# This file is based on these images:
#
#   - https://hub.docker.com/r/hexpm/elixir/tags - for the builder image
#     E.g.: docker.io/hexpm/elixir:1.20.2-erlang-28.5.0.3-debian-trixie-20260623-slim
#   - https://hub.docker.com/_/debian/tags?name=trixie-20260623-slim - for the runner image
#     E.g.: docker.io/debian:trixie-20260623-slim
#
# Find builder and runner images on Docker Hub or on Hex's Build Server (Bob).
# We recommend using Bob's Web UI to find recent tags:
#
#   - https://bob.hex.pm/docker
#
# We suggest using the same Debian version for both the builder and runner images.
#
# We suggest Debian/Ubuntu instead of Alpine to avoid production compatibility issues
# (such as DNS resolution failures, and dynamically linked NIFs/precompiled binaries).
#
# For finding packages in Debian, search on https://packages.debian.org/.

ARG ELIXIR_VERSION=1.20.2
ARG OTP_VERSION=28.5.0.3
ARG DEBIAN_VERSION=trixie-20260623-slim

ARG BUILDER_IMAGE="docker.io/hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="docker.io/debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

# install build dependencies
RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential git \
  && rm -rf /var/lib/apt/lists/*

# prepare build dir
WORKDIR /app

# install hex + rebar
RUN mix local.hex --force \
  && mix local.rebar --force

# set build ENV
ENV MIX_ENV="prod"

# install mix dependencies
#
# VERSION is deliberately NOT the real file yet, and ARG VERSION is declared
# below rather than here: release.sh bumps VERSION on every release, the layer
# cache keys on file content, and a build-arg is part of the cache key of every
# RUN that follows its declaration. Either one above this point invalidates
# mix deps.compile on every single release — the most expensive step in the
# build. mix.exs reads VERSION via File.read! at project/0 time, so the file has
# to exist for `mix deps.get` to run at all; a placeholder satisfies that, and
# nothing about a dependency depends on the parent app's version. The real
# version lands after deps.compile, before the app itself is compiled.
COPY mix.exs mix.lock ./
RUN echo -n "0.0.0-dev" > VERSION
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

# Real version, past the dependency layer: the file for local builds, the
# build-arg for CI, which passes the tag explicitly.
ARG VERSION=unknown
COPY VERSION ./
RUN if [ "$VERSION" != "unknown" ]; then echo -n "$VERSION" > VERSION; fi

RUN mix assets.setup

COPY priv priv

COPY lib lib

# Compile the release
RUN mix compile

COPY assets assets

# compile assets
RUN mix assets.deploy

# Changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/

COPY rel rel
RUN mix release

# start a new build stage so that the final image will only contain
# the compiled release and other runtime necessities
FROM ${RUNNER_IMAGE} AS final

# The release does not execute Perl. Debian marks perl-base as essential for
# package-management scripts, so remove it only after all runtime packages and
# CA certificates are configured; the immutable final image never runs apt/dpkg.
RUN apt-get update \
  && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 ca-certificates \
  && apt-get purge -y --allow-remove-essential perl-base \
  && rm -rf /var/lib/apt/lists/*

# Debian provides C.UTF-8 without the `locales` package. Keeping the runtime on
# this built-in UTF-8 locale avoids pulling Perl and other unused tooling into
# the public image.
ENV LANG=C.UTF-8
ENV LANGUAGE=C.UTF-8
ENV LC_ALL=C.UTF-8

WORKDIR "/app"
RUN chown nobody /app

# set runner ENV
ENV MIX_ENV="prod"

# Only copy the final release from the build stage
COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/orbitly ./

USER nobody

# If using an environment that doesn't automatically reap zombie processes, it is
# advised to add an init process such as tini via `apt-get install`
# above and adding an entrypoint. See https://github.com/krallin/tini for details
# ENTRYPOINT ["/tini", "--"]

CMD ["/app/bin/server"]
