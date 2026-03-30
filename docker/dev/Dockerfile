FROM elixir:1.19

WORKDIR /app

ENV HEX_HTTP_TIMEOUT=120
ENV HEX_HTTP_CONCURRENCY=1
ENV HEX_HTTP_RETRIES=20

RUN mix local.hex --force && \
    mix local.rebar --force

# Copy mix files first pour le cache deps
COPY mix.exs mix.lock ./

RUN MIX_ENV=dev mix deps.get

RUN MIX_ENV=dev mix deps.compile

COPY config ./config
COPY lib ./lib

RUN MIX_ENV=dev mix compile

# Entrypoint dev
COPY ./docker/dev/entrypoint.sh /tmp/entrypoint.sh
RUN chmod +x /tmp/entrypoint.sh

ENTRYPOINT ["/bin/bash", "/tmp/entrypoint.sh"]
