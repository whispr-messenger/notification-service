# Étape 1 : Build Elixir/Phoenix + assets
FROM elixir:1.19

RUN apt-get update && apt-get install -y build-essential npm git

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
COPY config config

ENV MIX_ENV=prod

RUN mix deps.get
RUN mix deps.compile
RUN mix compile



RUN MIX_ENV=prod mix release

# Étape 2 : Runner minimal
FROM debian:bullseye-slim

RUN apt-get update && apt-get install -y libstdc++6 openssl libncurses6 locales && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=build /app/_build/prod/rel/whispr_notification ./

ENV LANG=en_US.UTF-8 \
    MIX_ENV=prod \
    REPLACE_OS_VARS=true \
    HOME=/app

EXPOSE 4000

CMD ["bin/whispr_notification", "start"]
