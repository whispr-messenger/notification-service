FROM elixir:1.19

WORKDIR /app

ENV MIX_ENV=dev

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

<<<<<<< Updated upstream
RUN mix local.hex --force && \
    mix local.rebar --force
=======
# Install hex and rebar
RUN --mount=type=cache,target=/root/.hex \
    mix local.hex --force && mix local.rebar --force
>>>>>>> Stashed changes

# Copy mix files first pour le cache deps
COPY mix.exs mix.lock ./

<<<<<<< Updated upstream
RUN MIX_ENV=dev mix deps.get

RUN MIX_ENV=dev mix deps.compile
=======
RUN --mount=type=cache,target=/root/.hex \
    mix do deps.get, deps.compile
>>>>>>> Stashed changes

COPY config ./config
COPY lib ./lib

<<<<<<< Updated upstream
RUN MIX_ENV=dev mix compile
=======
RUN --mount=type=cache,target=/root/.hex \
    mix compile
>>>>>>> Stashed changes

# Entrypoint dev
COPY ./docker/dev/entrypoint.sh /tmp/entrypoint.sh
RUN chmod +x /tmp/entrypoint.sh

ENTRYPOINT ["/usr/bin/tini", "--", "/bin/bash", "/tmp/entrypoint.sh"]
