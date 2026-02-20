# =============================================================================
# Whispr Notification Service - Production Dockerfile
# Multi-stage build pour Elixir release sur Alpine
# =============================================================================

# -----------------------------------------------------------------------------
# STAGE 1: Build
# -----------------------------------------------------------------------------
FROM elixir:1.19-alpine AS builder

# Install build dependencies
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

# Install Hex + Rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Copy dependencies files first (cache)
COPY mix.exs mix.lock ./
COPY config config

# Fetch and compile dependencies
RUN mix deps.get --only prod
RUN mix deps.compile

# Copy application code
COPY lib lib

# Compile the application
RUN mix compile

# Build release
RUN mix release

# -----------------------------------------------------------------------------
# STAGE 2: Runtime
# -----------------------------------------------------------------------------
# Utiliser la même base erlang:27-alpine pour compatibilité crypto NIF
FROM erlang:27-alpine AS runtime

# Runtime dependencies
RUN apk add --no-cache \
    libstdc++ \
    openssl \
    ncurses-libs \
    libgcc \
    curl \
    bash \
    ca-certificates

# Create non-root user
RUN addgroup -g 1000 whispr && \
    adduser -u 1000 -G whispr -s /bin/sh -D whispr

ENV MIX_ENV=prod \
    LANG=C.UTF-8 \
    PORT=4002 \
    GRPC_PORT=4003

WORKDIR /app

# Copy release from builder
COPY --from=builder --chown=whispr:whispr /app/_build/prod/rel/whispr_notification ./

USER whispr

EXPOSE 4002 4003

# Healthcheck
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:4002/api/v1/health?type=live || exit 1

CMD ["bin/whispr_notification", "start"]
