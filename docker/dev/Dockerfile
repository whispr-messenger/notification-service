FROM elixir:1.19

WORKDIR /app

# Paquets système nécessaires en dev
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      curl \
      tini \
      inotify-tools \
      build-essential \
      postgresql-client \
      git \
    && rm -rf /var/lib/apt/lists/*

# Install hex and rebar with cache
RUN --mount=type=cache,target=/root/.hex \
    --mount=type=cache,target=/root/.mix \
    mix local.hex --force && \
    mix local.rebar --force

# Copy mix files first pour le cache deps
COPY mix.exs mix.lock ./

RUN --mount=type=cache,target=/root/.hex \
    --mount=type=cache,target=/root/.mix \
    mix deps.get

# Entrypoint dev
COPY ./docker/dev/entrypoint.sh /tmp/entrypoint.sh
RUN chmod +x /tmp/entrypoint.sh

ENTRYPOINT ["/usr/bin/tini", "--", "/bin/bash", "/tmp/entrypoint.sh"]
