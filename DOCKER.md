# Docker — notification-service

Trois stacks : `dev`, `test`, `prod`. Chacune démarre Postgres + Redis + le
service Elixir. Les migrations Ecto sont jouées automatiquement au démarrage
(via `mix ecto.migrate` en dev/test, via `WhisprNotifications.Release.migrate/0`
en prod).

---

## Dev

```bash
# 1. Préparer l'env
cp docker/dev/env/.env.example docker/dev/.env
# éditer docker/dev/.env si besoin

# 2. Lancer
cd docker/dev
docker compose up -d

# 3. Suivre les logs
docker compose logs -f notification-service
```

Ce qui se passe :
1. `postgres` démarre, applique `init-db.sql` (extensions uuid, pgcrypto, pg_stat_statements).
2. `redis` démarre.
3. `notification-service` attend `pg_isready` puis exécute
   `mix ecto.create` + `mix ecto.migrate` + `mix phx.server`.

Accès :
- HTTP : `http://localhost:8080/api/v1/health`
- Postgres : `localhost:5432` (user/pass dans `.env`)

---

## Test

```bash
cd docker/test
docker compose up --abort-on-container-exit --build
```

Postgres est en **tmpfs** (pas de persistance) et `mix ecto.create + ecto.migrate`
tournent avant `mix test`. La sandbox Ecto (`test_helper.exs`) isole les tests.

---

## Prod

```bash
# 1. Préparer l'env
cp docker/prod/env/notification.prod.env.example \
   docker/prod/env/notification.prod.env
# éditer notification.prod.env (SECRET_KEY_BASE, mots de passe, FCM/APNS, etc.)

# 2. Lancer (note: --env-file obligatoire pour la substitution ${VAR})
cd docker/prod
docker compose --env-file env/notification.prod.env \
               -f docker-compose.prod.yml up -d
```

Ce qui se passe :
1. `postgres` démarre, applique `config/init.sql`.
2. `redis` démarre avec password.
3. `notification-service` attend `pg_isready` (via `depends_on: service_healthy`)
   puis `docker/prod/entrypoint.sh` exécute
   `bin/whispr_notification eval "WhisprNotifications.Release.migrate()"`
   avant `bin/whispr_notification start`.

Le release Elixir (mode OTP compilé) n'a pas `mix` disponible — d'où le module
`WhisprNotifications.Release` (`lib/whispr_notifications/release.ex`) qui sert
de point d'entrée pour les migrations.

---

## Variables d'env clé

| Var | Rôle | Dev (défaut) | Prod |
|---|---|---|---|
| `DATABASE_HOST` | host Postgres vu par l'app | `postgres` | — (via `DATABASE_URL`) |
| `DATABASE_URL` | URL complète Ecto (prod uniquement) | — | `ecto://user:pass@postgres/db` |
| `POSTGRES_USER` / `_PASSWORD` / `_DB` | conteneur Postgres | cf `.env.example` | cf `notification.prod.env.example` |
| `REDIS_HOST` | host Redis | `redis` | `redis` |
| `REDIS_PASSWORD` | mot de passe Redis | vide | recommandé en prod |
| `SECRET_KEY_BASE` | signature Phoenix | placeholder OK | **≥ 64 octets requis** |

---

## Rejouer les migrations manuellement

Dev :
```bash
docker compose -f docker/dev/compose.yml exec notification-service \
  mix ecto.migrate
```

Prod :
```bash
docker compose -f docker/prod/docker-compose.prod.yml \
               --env-file docker/prod/env/notification.prod.env \
               exec notification-service \
  /app/bin/whispr_notification eval "WhisprNotifications.Release.migrate()"
```

---

## Rollback d'une migration (prod)

```bash
docker compose exec notification-service \
  /app/bin/whispr_notification eval \
  "WhisprNotifications.Release.rollback(WhisprNotifications.Repo, 20260417000004)"
```
