# =============================================================================
# Whispr Notification Service - Production Dockerfile
# Multi-stage build pour Elixir release sur Alpine
# =============================================================================

# -----------------------------------------------------------------------------
# STAGE 1: Build
# -----------------------------------------------------------------------------
FROM elixir:1.19-alpine AS builder

# Installer build dependencies pour compiler toutes les deps (NIF, crypto, grpc, ssl)
RUN apk add --no-cache \
    build-base \
    git \
    curl \
    openssl-dev \
    ncurses-dev \
    ca-certificates \
    bash

ENV MIX_ENV=prod \
    LANG=C.UTF-8

WORKDIR /app

# Installer Hex + Rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Copier les fichiers de dépendances pour cache
COPY mix.exs mix.lock ./
COPY config config

# Récupérer et compiler les dépendances
RUN mix deps.get --only prod
RUN mix deps.compile

# Copier le code source
COPY lib lib

# Compiler l'application et build la release
RUN mix compile
RUN mix release

# -----------------------------------------------------------------------------
# STAGE 2: Runtime
# -----------------------------------------------------------------------------
FROM erlang:27-alpine AS runtime

# Installer runtime dependencies
RUN apk add --no-cache \
    libstdc++ \
    openssl \
    ncurses-libs \
    libgcc \
    curl \
    bash \
    ca-certificates

# Créer un utilisateur non-root
RUN addgroup -g 1000 whispr && \
    adduser -u 1000 -G whispr -s /bin/sh -D whispr

ENV MIX_ENV=prod \
    LANG=C.UTF-8 \
    PORT=4002 \
    GRPC_PORT=4003

WORKDIR /app

# Copier la release depuis le builder
COPY --from=builder --chown=whispr:whispr /app/_build/prod/rel/whispr_notification ./

USER whispr

EXPOSE 4002 4003

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:4002/api/v1/health?type=live || exit 1

CMD ["bin/whispr_notification", "start"]
