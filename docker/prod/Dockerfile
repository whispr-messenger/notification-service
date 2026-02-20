# =============================================================================
# Whispr Notification Service - Dockerfile
# Multi-stage build for production-ready Elixir application
# =============================================================================

# -----------------------------------------------------------------------------
# STAGE 1: Build
# -----------------------------------------------------------------------------
FROM elixir:1.19-alpine AS builder

ARG SECRET_KEY_BASE
ENV SECRET_KEY_BASE=${SECRET_KEY_BASE}

# Install build dependencies
RUN apk add --no-cache \
    build-base \
    git \
    curl

ENV MIX_ENV=prod \
    LANG=C.UTF-8

WORKDIR /app

# Install Hex + Rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Copy dependency files first (for caching)
COPY mix.exs mix.lock ./
COPY config config

# Install and compile dependencies
RUN mix deps.get --only prod && \
    mix deps.compile

# Copy application source
COPY lib lib
COPY priv priv

# Compile application
RUN mix compile

# Build release
RUN mix release

# -----------------------------------------------------------------------------
# STAGE 2: Runtime
# -----------------------------------------------------------------------------
# ⚠ IMPORTANT:
# On utilise la même base Alpine/Erlang que le builder
# pour éviter les erreurs OpenSSL / crypto NIF
FROM erlang:27-alpine AS runtime

# Install runtime dependencies only
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

LABEL org.opencontainers.image.title="Whispr Notification Service" \
    org.opencontainers.image.description="Notification service for Whispr Messenger" \
    org.opencontainers.image.vendor="Whispr" \
    org.opencontainers.image.version="0.1.0"

CMD ["bin/whispr_notification", "start"]
