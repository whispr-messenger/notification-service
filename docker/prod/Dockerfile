# =============================================================================
# Whispr Notification Service - Production Dockerfile
# Multi-stage build for Elixir release (Alpine stable)
# =============================================================================

# -----------------------------------------------------------------------------
# STAGE 1: Build
# -----------------------------------------------------------------------------
FROM elixir:1.19-alpine AS builder

# Install build dependencies (IMPORTANT pour NIF / crypto / grpc / ssl)
RUN apk add --no-cache \
    build-base \
    git \
    curl \
    openssl-dev \
    ncurses-dev

ENV MIX_ENV=prod \
    LANG=C.UTF-8

WORKDIR /app

# Install Hex + Rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Copy dependency files first (cache optimization)
COPY mix.exs mix.lock ./
COPY config config

# Fetch and compile dependencies
RUN mix deps.get --only prod
RUN mix deps.compile

# Copy application source
COPY lib lib

# Compile application
RUN mix compile

# Build release
RUN mix release

# -----------------------------------------------------------------------------
# STAGE 2: Runtime
# -----------------------------------------------------------------------------
# On garde erlang:27-alpine pour compatibilité OTP/OpenSSL
FROM erlang:27-alpine AS runtime

# Runtime dependencies only
RUN apk add --no-cache \
    libstdc++ \
    openssl \
    ncurses-libs \
    libgcc \
    curl \
    bash

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

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:4002/api/v1/health?type=live || exit 1

CMD ["bin/whispr_notification", "start"]
