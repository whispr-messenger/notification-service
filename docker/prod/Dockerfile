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

# Set environment variables
ENV MIX_ENV=prod \
    LANG=C.UTF-8

# Create app directory
WORKDIR /app

# Install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Copy dependency files first (for caching)
COPY mix.exs mix.lock ./
COPY config config

# Install dependencies
RUN --mount=type=cache,target=/root/.hex \
    --mount=type=cache,target=/root/.mix \
    mix deps.get --only prod && \
    mix deps.compile

# Copy application code
COPY lib lib

# Compile the application
RUN mix compile

# Build release (nom par défaut = app: :whispr_notification)
RUN mix release

# -----------------------------------------------------------------------------
# STAGE 2: Runtime
# -----------------------------------------------------------------------------
FROM alpine:3.18 AS runtime

# Install runtime dependencies
RUN apk add --no-cache \
    libstdc++ \
    openssl \
    openssl1.1-compat \
    ncurses-libs \
    libgcc \
    curl \
    bash


# Create non-root user for security
RUN addgroup -g 1000 whispr && \
    adduser -u 1000 -G whispr -s /bin/sh -D whispr

# Set environment variables
ENV MIX_ENV=prod \
    LANG=C.UTF-8 \
    PORT=4002 \
    GRPC_PORT=50052

WORKDIR /app

# Copy release from builder
COPY --from=builder --chown=whispr:whispr /app/_build/prod/rel/whispr_notification ./

USER whispr

# Expose ports (HTTP + gRPC) - adapte si besoin
EXPOSE 4002 50052

# Health check - adapte l’URL à ce que ton service expose*
# Image ghcr.io/whispr-messenger/notification-service:e0536bd@sha256:c6e9c986fa2f96393fc0cf755c6e52ec3109fb2c89bafdf7f5c0139dbd3c1659
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:4002/api/v1/health?type=live || exit 1

# OCI Labels
LABEL org.opencontainers.image.title="Whispr Notification Service" \
      org.opencontainers.image.description="Notification service for Whispr Messenger" \
      org.opencontainers.image.vendor="Whispr" \
      org.opencontainers.image.version="0.1.0"

# Start the application
CMD ["bin/whispr_notification", "start"]
