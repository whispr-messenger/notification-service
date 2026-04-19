# Contribuer au Notification Service

## Stack

- Elixir / Phoenix
- PostgreSQL + Redis
- FCM / APNS

## Lancer le projet

```bash
cp .env.example .env
mix deps.get
mix ecto.create
mix phx.server
```

## Tests

```bash
mix test
```

## Conventions

- Conventional commits
- Branches : `WHISPR-XXX-description`
- Format : `mix format`
