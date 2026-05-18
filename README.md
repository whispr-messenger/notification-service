# Whispr Messenger — notification-service

[![App Status](https://argocd.whispr.epitech.beer/api/badge?name=notification-service&revision=true&showAppName=true)](https://argocd.whispr.epitech.beer/applications/notification-service)

Microservice Elixir/Phoenix responsable de la livraison des notifications push de Whispr Messenger : fan-out FCM (Android/Web) et APNS (iOS), inbox persistante, préférences utilisateur, badges, gestion des devices. Communication inter-services en HTTP via Istio.

## Table of contents

- [Tech stack](#tech-stack)
- [Architecture](#architecture)
- [Installation locale](#installation-locale)
- [Configuration](#configuration)
- [Démarrage](#démarrage)
- [API REST](#api-rest)
- [Tests & qualité](#tests--qualité)
- [Déploiement](#déploiement)
- [Documentation complémentaire](#documentation-complémentaire)
- [Support & contribution](#support--contribution)
- [License](#license)

## Tech stack

| Composant | Choix |
|-----------|-------|
| Runtime | Elixir 1.18 / Erlang OTP 27 |
| Framework HTTP | Phoenix 1.8 (REST JSON uniquement) |
| Base de données | PostgreSQL via Ecto 3.13 |
| Cache & pub/sub | Redis 7 (mode `direct` ou `sentinel`) via Redix |
| Push providers | FCM HTTP v1 (Pigeon + Goth) · APNS HTTP/2 + JWT ES256 (Pigeon) |
| Auth inter-services | JWT ES256 vérifié contre le JWKS d'`auth-service` |
| Observabilité | Logger JSON (`LOG_FORMAT=json`), Sentry optionnel, Telemetry |
| Tests | ExUnit + ExCoveralls (Docker Compose en CI) |
| CI / CD | GitHub Actions · GHCR · ArgoCD (GitOps) |

## Architecture

### Arbre de supervision OTP

L'application démarre dans l'ordre :

1. `WhisprNotifications.Repo` — pool Ecto Postgres
2. `Phoenix.PubSub` — bus interne
3. `Auth.JwksCache` — prefetch des clés publiques d'`auth-service` (fallback gracieux sur clé vide si injoignable)
4. `WhisprNotificationsWeb.Endpoint` — HTTP Phoenix
5. Workers domaine : `Devices.CacheManager`, `TokenRefresher`, `CacheSyncWorker`, `CleanupWorker`, `MetricsWorker`
6. Subscribers Redis pub/sub : `ModerationSubscriber`, `CallsSubscriber`, `MessagingSubscriber`, `ContactsSubscriber`, `InboxSubscriber`
7. Dispatchers push (démarrés conditionnellement) : `Goth + FcmDispatcher` si FCM configuré, `ApnsDispatcher` si APNS configuré

Source : `lib/whispr_notifications/application.ex`.

### Contextes métier (`lib/whispr_notifications/`)

- `auth/` — vérification JWT, cache JWKS
- `devices/` — registre des devices push + cache async
- `notifications/` — formatage cross-platform, historique
- `delivery/` — `BatchProcessor`, `FcmClient`, `ApnsClient`, `RetryManager`
- `preferences/` — quiet hours, mute conversation, filtre mentions-only
- `badges/` — compteur de notifs non lues par user
- `inbox/` — persistance Postgres + diffusion WebSocket via PubSub
- `events/` — handlers des messages Redis (message, call, contact, moderation)

## Installation locale

### Prérequis

- Elixir `~> 1.18`, Erlang OTP 27
- PostgreSQL 15+
- Redis 7+
- Docker + Docker Compose (recommandé pour la BDD/Redis de dev)

### Setup

```bash
mix deps.get
mix ecto.create
mix ecto.migrate
```

Pour la base et Redis en local, utiliser le compose dev :

```bash
docker compose -f docker/dev/compose.yml up -d
```

## Configuration

Toute la configuration runtime vit dans `config/runtime.exs` (lecture à chaque boot du release). Aucun secret n'est compilé dans l'image.

### Variables d'environnement

| Variable | Obligatoire | Défaut | Description |
|----------|-------------|--------|-------------|
| `DATABASE_URL` | prod | — | `ecto://user:pass@host/db` |
| `DATABASE_POOL_SIZE` | non | `10` | Taille du pool Ecto |
| `DATABASE_SSL` | non | `false` | TLS Postgres |
| `SECRET_KEY_BASE` | prod | — | ≥ 64 bytes, `mix phx.gen.secret` |
| `PORT` | non | `4011` | Port HTTP Phoenix |
| `PHX_HOST` | non | `localhost` | Host public (URL générée) |
| `CORS_ALLOWED_ORIGINS` | prod | — | Liste CSV, pas de wildcard accepté en prod |
| **Redis** | | | |
| `REDIS_MODE` | non | `direct` | `direct` ou `sentinel` |
| `REDIS_HOST` / `REDIS_PORT` | mode direct | `localhost` / `6379` | |
| `REDIS_SENTINELS` / `REDIS_MASTER_NAME` / `REDIS_SENTINEL_PASSWORD` | mode sentinel | — | HA Redis |
| `REDIS_USERNAME` / `REDIS_PASSWORD` | selon | — | Auth Redis |
| `REDIS_DB` | non | `0` (`1` en test) | Index DB |
| `REDIS_SSL` | non | `false` | |
| **JWT / JWKS** | | | |
| `AUTH_JWKS_URL` | oui | `http://auth-service/auth/.well-known/jwks.json` | Endpoint JWKS d'`auth-service` |
| `JWKS_REFRESH_INTERVAL_MS` | non | `3600000` | Refresh périodique du cache |
| `JWT_ISSUER` | oui | — | Claim `iss` attendu |
| `JWT_AUDIENCE` | oui | — | Claim `aud` attendu |
| **FCM (Android/Web)** | | | |
| `FCM_PROJECT_ID` | si FCM | — | ID projet Firebase |
| `FCM_JSON_KEYFILE` | si FCM | — | Chemin vers le service account JSON monté |
| `FCM_JSON` | alt. | — | Service account inline (contenu) |
| **APNS (iOS)** | | | |
| `APNS_KEY_PATH` | si APNS | — | Chemin vers le `.p8` |
| `APNS_KEY_ID` / `APNS_TEAM_ID` | si APNS | — | Identifiants Apple |
| `APNS_MODE` | non | `dev` | `dev` ou `prod` |
| `APNS_DEFAULT_TOPIC` | non | — | Bundle ID iOS fallback |
| **Observabilité** | | | |
| `LOG_LEVEL` | non | `info` | `debug` \| `info` \| `warning` \| `error` |
| `LOG_FORMAT` | non | text | `json` pour formatter structuré |
| `SENTRY_DSN` | non | — | Active la capture d'erreurs si présent |
| `RELEASE_LEVEL` | non | `production` | Tag d'environnement Sentry |

Les dispatchers push (FCM, APNS) ne sont démarrés que si leurs credentials sont fournis. En dev sans creds, les clients renvoient `{:error, :not_configured}` sans faire crasher la supervision.

## Démarrage

```bash
# Développement (rechargement de code)
mix phx.server

# REPL interactif
iex -S mix

# Production (release)
MIX_ENV=prod mix release
_build/prod/rel/whispr_notification/bin/whispr_notification start
```

Construction de l'image Docker prod :

```bash
docker build -f docker/prod/Dockerfile -t notification-service .
```

L'image utilise un user non-root (`whispr:whispr`, uid 1000) et expose un healthcheck HTTP sur `/api/v1/health`.

## API REST

Base URL locale : `http://localhost:4011`

Toutes les routes existent en double sous deux préfixes :

- `/api/...` — quand la gateway strippe le préfixe `notification`
- `/notification/api/...` — quand elle forwarde le chemin complet

### Endpoints publics (pas d'auth)

| Méthode | Route | Description |
|---------|-------|-------------|
| `GET` | `/api/v1/health` | Liveness probe |
| `GET` | `/api/v1/health/ready` | Readiness probe (vérifie Postgres + Redis) |

### Endpoints authentifiés (`Authorization: Bearer <jwt_es256>`)

| Méthode | Route | Description |
|---------|-------|-------------|
| `GET` | `/api/v1/auth-check` | Valide le JWT, retourne le `sub` |
| `POST` | `/api/v1/notifications` | Crée et dispatch une notification |
| `GET` | `/api/v1/badge` | Compteur badge du user courant |
| `GET` / `PUT` | `/api/v1/settings` | Préférences du user courant |
| `GET` / `PUT` | `/api/settings/:user_id` | Préférences explicites (legacy) |
| `POST` | `/api/v1/devices` | Enregistre un token push (FCM/APNS) |
| `DELETE` | `/api/v1/devices/:device_id` | Désenregistre un device |
| `POST` | `/api/conversations/:conversation_id/mute` | Mute une conversation |
| `DELETE` | `/api/conversations/:conversation_id/mute` | Unmute |
| `GET` | `/api/v1/inbox` | Liste les notifications en attente |
| `POST` | `/api/v1/inbox/mark-read` | Marque comme lues |

Voir [`API_JSON.md`](API_JSON.md) pour les schémas requête/réponse complets et [`ENDPOINTS_DB.md`](ENDPOINTS_DB.md) pour la correspondance routes ↔ tables.

### Évènements Redis consommés

Le service écoute plusieurs canaux Redis pub/sub pour déclencher des push :

- `whispr:messaging:events` — nouveaux messages
- `whispr:calls:events` — appels entrants/manqués
- `whispr:contacts:events` — invitations contact
- `whispr:moderation:events` — décisions modération
- `whispr:notifications:inbox` — broadcast inbox côté WebSocket

## Tests & qualité

```bash
# Suite complète + couverture XML/HTML
mix test
mix coveralls.html

# Tests isolés
mix test test/whispr_notifications/auth/jwt_verifier_test.exs

# Format et lint (manuel)
mix format --check-formatted
mix credo --strict

# Audit CVE des deps Hex
mix deps.audit
```

En CI, les tests tournent en Docker Compose (Postgres + Redis éphémères, credentials générés à la volée). Voir `.github/workflows/tests.yml`.

La couverture est suivie via Codecov (`codecov.yml`). Les CVE Hex sont scannées en bloquant par `mix_audit` (`.github/workflows/elixir-sast.yml`).

## Déploiement

- **Build** : workflow `docker.yml` construit et pousse l'image sur GHCR à chaque merge sur `deploy/preprod` ou `main`.
- **Release** : workflow `release.yml` tag automatiquement (SemVer dérivé des Conventional Commits) au merge sur `main`.
- **Déploiement** : ArgoCD synchronise depuis le repo `infrastructure` (GitOps). Le statut de l'app est visible via le badge en tête de README.
- **Probes k8s** : `/api/v1/health` en liveness, `/api/v1/health/ready` en readiness.

Pipeline détaillé : voir `../DEPLOYMENT_PIPELINE.md`.

## Documentation complémentaire

| Fichier | Contenu |
|---------|---------|
| [`API_JSON.md`](API_JSON.md) | Schémas JSON requête/réponse de chaque endpoint |
| [`ENDPOINTS_DB.md`](ENDPOINTS_DB.md) | Routes ↔ tables Postgres |
| [`SECURITY.md`](SECURITY.md) | Modèle de menace, JWT, secrets |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | Conventions de contribution |
| [`DOCKER.md`](DOCKER.md) | Détails images dev/test/prod |
| `documentation/` | Schémas d'architecture détaillés |

## Support & contribution

- Conventions de commit : [Conventional Commits](https://www.conventionalcommits.org/) — le type (`feat`, `fix`, `chore`, …) pilote le bump SemVer au merge sur `main`.
- Branches : `WHISPR-<id>-short-description` (worktrees dans `.worktrees/`).
- Avant PR : `mix format && mix credo --strict && mix test`.

Bug, idée ou question : ouvrir une issue GitHub ou contacter l'équipe sur le canal Whispr.

## License

Projet Whispr — usage privé, tous droits réservés.

---

Développé par l'équipe Whispr.
