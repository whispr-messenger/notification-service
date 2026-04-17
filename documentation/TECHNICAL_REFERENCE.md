# Notification Service - Documentation Technique (Etat Reel du Code)

> **Date**: 2026-04-17
> **Version du code analysee**: HEAD actuel
> **Objectif**: Documenter l'etat reel de l'implementation, identifier les ecarts avec l'architecture cible, et auditer les ameliorations necessaires.

---

## Table des Matieres

- [1. Stack Technique](#1-stack-technique)
- [2. Architecture Applicative](#2-architecture-applicative)
- [3. Arbre OTP et Processus](#3-arbre-otp-et-processus)
- [4. Endpoints API](#4-endpoints-api)
- [5. Authentification et Securite](#5-authentification-et-securite)
- [6. Integrations Externes](#6-integrations-externes)
- [7. Infrastructure et Deploiement](#7-infrastructure-et-deploiement)
- [8. Ecarts Implementation vs Architecture Cible](#8-ecarts-implementation-vs-architecture-cible)
- [9. Audit de Securite](#9-audit-de-securite)
- [10. Plan d'Ameliorations](#10-plan-dameliorations)

---

## 1. Stack Technique

### 1.1 Langage et Framework

| Composant | Version | Role |
|-----------|---------|------|
| **Elixir** | ~1.19 | Langage principal |
| **Phoenix** | ~1.8.0 | Framework web HTTP |
| **Plug/Cowboy** | ~2.6 | Serveur HTTP |
| **grpcbox** | ~0.17 | Serveur gRPC |
| **protobuf** | ~0.12 | Serialisation gRPC |

### 1.2 Base de Donnees et Cache

| Composant | Version | Role | Etat |
|-----------|---------|------|------|
| **PostgreSQL** (via Ecto) | ecto_sql ~3.13 | Stockage persistant | **Non initialise** (`ecto_repos: []`) |
| **Redis** (via Redix) | ~1.2 | Cache, PubSub | **Actif** (ModerationSubscriber) |
| **Phoenix PubSub** | ~2.1 | Distribution interne | Actif |

### 1.3 Push Notifications

| Composant | Version | Role | Etat |
|-----------|---------|------|------|
| **fcmex** | ~0.6 | Firebase Cloud Messaging | **Stub** (retourne `:ok`) |
| **pigeon** | ~2.0 | Apple Push Notifications | **Stub** (retourne `:ok`) |

### 1.4 Authentification

| Composant | Version | Role |
|-----------|---------|------|
| **joken** | ~2.6 | Decodage JWT |
| **jose** | - | Verification signatures JWKS |

### 1.5 HTTP et Utilitaires

| Composant | Version | Role |
|-----------|---------|------|
| **req** | ~0.5 | Client HTTP (JWKS fetch) |
| **elixir_uuid** | ~1.2 | Generation UUID |
| **phoenix_swagger** | ~0.8 | Documentation API |

### 1.6 Observabilite

| Composant | Version | Role |
|-----------|---------|------|
| **telemetry** | ~1.2 | Evenements internes |
| **telemetry_metrics** | ~1.0 | Metriques |
| **telemetry_poller** | ~1.0 | Collecte periodique |

### 1.7 Qualite de Code

| Composant | Version | Role |
|-----------|---------|------|
| **excoveralls** | ~0.18 | Couverture de tests |
| **credo** | ~1.7 | Linter statique |
| **dialyxir** | ~1.4 | Typage statique |

---

## 2. Architecture Applicative

### 2.1 Structure des Modules

```
lib/
├── whispr_notifications/                  # Domaine metier
│   ├── application.ex                     # Point d'entree OTP, arbre de supervision
│   ├── auth/                              # Authentification JWT/JWKS
│   │   ├── jwks.ex                        # Parsing JWKS, extraction cles EC P-256
│   │   ├── jwks_cache.ex                  # GenServer: cache des cles publiques
│   │   └── jwt_verifier.ex                # Verification JWT avec JOSE
│   ├── delivery/                          # Livraison des notifications
│   │   ├── fcm_client.ex                  # Client FCM (STUB)
│   │   ├── apns_client.ex                 # Client APNS (STUB)
│   │   ├── batch_processor.ex             # Traitement par lot
│   │   └── retry_manager.ex               # Logique de retry (max 3)
│   ├── devices/                           # Gestion des appareils
│   │   ├── device_cache.ex                # Struct DeviceCache en memoire
│   │   ├── cache_manager.ex               # GenServer: cache par utilisateur
│   │   └── auth_client.ex                 # Interface vers auth-service
│   ├── events/                            # Traitement evenementiel
│   │   ├── message_events.ex              # Evenements nouveaux messages
│   │   ├── moderation_events.ex           # Evenements moderation (Redis)
│   │   ├── group_events.ex                # Evenements groupes
│   │   └── system_events.ex               # Notifications systeme
│   ├── notifications/                     # Coeur metier
│   │   ├── notification.ex                # Struct Notification
│   │   ├── notifications.ex               # API principale (create, validate)
│   │   ├── history.ex                     # Persistance historique (STUB)
│   │   ├── formatter.ex                   # Formatage par plateforme (FCM/APNS/Web)
│   │   └── filter.ex                      # Filtrage pre-envoi
│   ├── preferences/                       # Preferences utilisateur
│   │   ├── user_settings.ex               # Quiet hours, toggles push
│   │   ├── conversation_settings.ex       # Mute, priorite par conversation
│   │   └── manager.ex                     # Stockage preferences (STUB)
│   └── workers/                           # Workers de fond
│       ├── token_refresher.ex             # GenServer 1h - refresh tokens (STUB)
│       ├── cache_sync_worker.ex           # GenServer 10min - sync cache (STUB)
│       ├── cleanup_worker.ex              # GenServer 12h - purge anciens (STUB)
│       └── metrics_worker.ex              # GenServer 1min - emission metriques (STUB)
│
├── whispr_notifications_grpc/             # Couche gRPC
│   ├── server.ex                          # Serveur gRPC (VIDE)
│   └── service/
│       ├── event_service.ex               # Service evenements (VIDE)
│       └── notification_service.ex        # Service notifications (VIDE)
│
├── whispr_notifications_web/              # Couche HTTP
│   ├── endpoint.ex                        # Phoenix Endpoint (CORS, telemetrie)
│   ├── router.ex                          # Definit toutes les routes REST
│   ├── controllers/
│   │   ├── health_controller.ex           # GET /api/v1/health
│   │   ├── auth_check_controller.ex       # GET /api/v1/auth-check
│   │   ├── notifications_controller.ex    # POST /api/v1/notifications
│   │   ├── settings_controller.ex         # GET/PUT settings (STUB)
│   │   ├── mute_controller.ex             # POST/DELETE mute (STUB)
│   │   ├── error_html.ex                  # Rendu erreurs HTML
│   │   ├── error_json.ex                  # Rendu erreurs JSON
│   │   └── fallback_controller.ex         # Gestionnaire d'erreurs
│   └── plugs/
│       ├── authenticate.ex                # Plug JWT Bearer
│       └── cors.ex                        # Plug CORS
│
└── whispr_notifications_workers/          # Workers applicatifs
    ├── token_refresher.ex
    ├── cache_sync_worker.ex
    ├── cleanup_worker.ex
    ├── metrics_worker.ex
    └── moderation_subscriber.ex           # Redis PubSub (6 canaux moderation)
```

### 2.2 Flux de Donnees Principal

```
[Client HTTP] ──Bearer JWT──> [Authenticate Plug] ──> [Router] ──> [Controller]
                                      │
                                      ▼
                               [JwtVerifier] ──> [JwksCache] ──> [JWKS Endpoint]
                                                                   (auth-service)

[Redis PubSub] ──moderation events──> [ModerationSubscriber] ──> [ModerationEvents]
                                                                        │
                                                                        ▼
                                                              [Notifications.create]
                                                                        │
                                                                        ▼
                                                              [Filter] ──> [Formatter]
                                                                              │
                                                                              ▼
                                                              [BatchProcessor] ──> [FCM/APNS]
                                                                                    (STUB)
```

---

## 3. Arbre OTP et Processus

### 3.1 Superviseur Principal (`application.ex`)

Les enfants demarres dans l'ordre:

| # | Module | Type | Intervalle | Etat |
|---|--------|------|-----------|------|
| 1 | `WhisprNotifications.Devices.CacheManager` | GenServer | - | **Actif** |
| 2 | `WhisprNotifications.Workers.TokenRefresher` | GenServer | 1h | **Stub** (no-op) |
| 3 | `WhisprNotifications.Workers.CacheSyncWorker` | GenServer | 10min | **Stub** (no-op) |
| 4 | `WhisprNotifications.Workers.CleanupWorker` | GenServer | 12h | **Stub** (no-op) |
| 5 | `WhisprNotifications.Workers.MetricsWorker` | GenServer | 1min | **Stub** (no-op) |
| 6 | `WhisprNotifications.Workers.ModerationSubscriber` | GenServer | - | **Actif** |
| 7 | `WhisprNotificationsWeb.Endpoint` | Supervisor | - | **Actif** |

### 3.2 ModerationSubscriber - Canaux Redis

Le worker souscrit a 6 canaux Redis et dispatch vers `ModerationEvents`:

| Canal Redis | Handler |
|-------------|---------|
| `whispr:moderation:report_created` | `ModerationEvents.handle_report_created/1` |
| `whispr:moderation:sanction_applied` | `ModerationEvents.handle_sanction_applied/1` |
| `whispr:moderation:sanction_lifted` | `ModerationEvents.handle_sanction_lifted/1` |
| `whispr:moderation:appeal_created` | `ModerationEvents.handle_appeal_created/1` |
| `whispr:moderation:appeal_resolved` | `ModerationEvents.handle_appeal_resolved/1` |
| `whispr:moderation:threshold_reached` | `ModerationEvents.handle_threshold_warning/1` |

**Comportement de reconnexion**: retry automatique avec backoff de 5s (non exponentiel).

### 3.3 JwksCache

- Accepte uniquement les cles **EC P-256** (`kty: "EC"`, `crv: "P-256"`)
- Stockage en memoire: `kid => JOSE.JWK`
- Initialisation possible par: JSON inline, URL HTTP (avec retry), ou vide (tests)
- HTTP fetch: timeout 15s, retry 2x sur erreurs transitoires

---

## 4. Endpoints API

### 4.1 Scopes de Routes

Le router definit **deux scopes identiques** pour supporter l'API gateway avec ou sans prefix `/notification`:
- Scope 1: `/api/...`
- Scope 2: `/notification/api/...`

### 4.2 Endpoints Sans Authentification

| Methode | Path | Controller | Action | Description |
|---------|------|------------|--------|-------------|
| `GET` | `/api/v1/health` | `HealthController` | `live` | Health check. Retourne `{"status": "ok"}` |
| `POST` | `/api/conversations/:conversation_id/mute` | `MuteController` | `mute` | Mute une conversation **(STUB/TODO)** |
| `DELETE` | `/api/conversations/:conversation_id/mute` | `MuteController` | `unmute` | Unmute une conversation **(STUB/TODO)** |
| `GET` | `/api/settings/:id` | `SettingsController` | `show` | Obtenir les parametres de notification **(STUB)** |
| `PUT` | `/api/settings/:id` | `SettingsController` | `update` | Mettre a jour les parametres **(STUB, retourne 204)** |

> **ALERTE SECURITE**: Les endpoints `mute`, `settings` ne sont PAS proteges par authentification JWT.

### 4.3 Endpoints Avec Authentification JWT

| Methode | Path | Controller | Action | Description |
|---------|------|------------|--------|-------------|
| `GET` | `/api/v1/auth-check` | `AuthCheckController` | `show` | Verifie le JWT et retourne le `sub` claim |
| `POST` | `/api/v1/notifications` | `NotificationsController` | `create` | Cree et envoie une notification |

### 4.4 Detail des Requetes/Reponses

#### `POST /api/v1/notifications`

**Headers requis:**
```
Authorization: Bearer <jwt_token>
Content-Type: application/json
```

**Body:**
```json
{
  "user_id": "uuid (requis)",
  "type": "message | group | system (requis)",
  "title": "string (requis)",
  "body": "string (requis)",
  "context": {},
  "conversation_id": "uuid (optionnel)",
  "metadata": {}
}
```

**Reponse succes (201):**
```json
{
  "data": {
    "notification_id": "uuid",
    "status": "sent",
    "type": "message",
    "title": "...",
    "body": "..."
  }
}
```

**Reponse erreur (422):**
```json
{
  "errors": {
    "detail": "Missing required fields: ..."
  }
}
```

#### `GET /api/v1/auth-check`

**Headers requis:**
```
Authorization: Bearer <jwt_token>
```

**Reponse succes (200):**
```json
{
  "authenticated": true,
  "user_id": "<sub claim du JWT>"
}
```

#### `GET /api/v1/health`

**Reponse (200):**
```json
{
  "status": "ok"
}
```

### 4.5 gRPC (Port 50053/40011)

| Service | Methode | Etat |
|---------|---------|------|
| `EventService` | - | **VIDE** (aucune methode implementee) |
| `NotificationService` | - | **VIDE** (aucune methode implementee) |

> Aucun fichier `.proto` n'a ete trouve dans le repo.

---

## 5. Authentification et Securite

### 5.1 Flux JWT

```
1. Client envoie: Authorization: Bearer <token>
2. Plug Authenticate extrait le token
3. JwtVerifier.verify(token):
   a. Decode le header protege (segment 1 du JWT)
   b. Extrait kid + alg
   c. Verifie que alg ∈ ["ES256"] (configurable)
   d. Recupere la cle publique depuis JwksCache par kid
   e. JOSE.JWT.verify_strict(jwk, allowed_algs, token)
   f. Valide exp >= now
   g. Valide iss (optionnel)
   h. Valide aud (optionnel)
4. Succes → assigne :jwt_claims et :jwt_sub au conn
5. Echec → 401 Unauthorized
```

### 5.2 Algorithmes Supportes

- **ES256** uniquement (EC P-256) par defaut
- Configurable via `config :whispr_notification, :jwt, allowed_algs: [...]`

### 5.3 CORS

**Origines autorisees (hardcodees):**
```
https://whispr-api.roadmvn.com
https://whispr-preprod.roadmvn.com
https://preprod-whispr-api.roadmvn.com
https://whispr.epitech.beer
```

Surcharge possible via variable d'environnement `CORS_ALLOWED_ORIGINS`.

**Methodes:** GET, POST, PUT, PATCH, DELETE, OPTIONS
**Headers:** Authorization, Content-Type, Accept, Origin, User-Agent

---

## 6. Integrations Externes

### 6.1 Redis

| Usage | Implementation |
|-------|---------------|
| PubSub moderation | **Actif** - 6 canaux souscrits |
| Cache appareils | **Partiel** - CacheManager GenServer utilise la memoire |
| Rate limiting | **Non implemente** |

**Connexion:** Configurable via env vars `REDIS_HOST`, `REDIS_PORT`, `REDIS_DB`, `REDIS_PASSWORD`.
Support TLS optionnel en production.

### 6.2 Firebase Cloud Messaging (FCM)

**Etat:** STUB uniquement

- `FcmClient.send/2` retourne `:ok` sans effectuer d'appel reseau
- Configuration prevue: `FCM_PROJECT_ID`, `FCM_JSON_KEYFILE`
- Format payload prepare:
  ```elixir
  %{
    notification: %{title: ..., body: ...},
    data: %{"notification_id" => ..., "type" => ..., ...}
  }
  ```

### 6.3 Apple Push Notification Service (APNS)

**Etat:** STUB uniquement

- `ApnsClient.send/2` retourne `:ok` sans effectuer d'appel reseau
- Configuration prevue: `APNS_KEY_PATH`, `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_MODE`
- Format payload prepare:
  ```elixir
  %{
    "aps" => %{
      "alert" => %{"title" => ..., "body" => ...},
      "sound" => "default"
    },
    "meta" => %{"notification_id" => ..., "type" => ...}
  }
  ```

### 6.4 Services gRPC Inter-Services

| Service | Port | Role | Etat |
|---------|------|------|------|
| auth-service | 50056 | Recuperation appareils, JWKS | Config uniquement |
| messaging-service | 50052 | Evenements messages | Config uniquement |
| user-service | 50055 | Donnees utilisateur | Config uniquement |

> Aucun client gRPC n'est reellement implemente. Les modules `service/` sont vides.

---

## 7. Infrastructure et Deploiement

### 7.1 Docker

**Production (`docker/prod/Dockerfile`):**
- Multi-stage build: `elixir:1.19-alpine` (builder) → `elixir:1.19-alpine` (runtime)
- Utilisateur non-root: `whispr` (uid 1000)
- Ports exposes: `4002` (HTTP), `50052` (gRPC)
- Health check: `curl -fsS http://localhost:4002/api/v1/health` (30s interval)
- Entry: `bin/whispr_notification start`

### 7.2 Ports par Environnement

| Environnement | Port HTTP | Port gRPC |
|---------------|-----------|-----------|
| Dev | 4000 (defaut) | 4001 |
| Prod (Dockerfile) | 4002 | 50052 |
| Prod (config) | 4011 | 40011 |

> **Incoherence**: Le Dockerfile expose 4002/50052, mais `config/prod.exs` reference 4011/40011.

### 7.3 CI/CD

| Workflow | Declencheur | Role |
|----------|-------------|------|
| `ci.yml` | Push main/develop/preprod | Tests, securite, Docker build |
| `cd.yml` | CI Pipeline complete | MAJ manifestes K8s dans infra repo |
| `tests.yml` | Push | Tests Elixir (`mix test`) |
| `docker.yml` | Appel depuis CI | Build + push image GHCR |
| `codecov.yml` | Push | Rapport de couverture |

### 7.4 Kubernetes

- **Namespace**: `whispr`
- **Manifestes**: deployment, configmap, service, service-account, PDB, HPA, Istio VirtualService/DestinationRule
- **Environnements**: development, preprod, production, prod

### 7.5 ArgoCD

3 applications ArgoCD distinctes:
- `notification-service` (production, branche main)
- `preprod-notification-service` (preprod, branche deploy/preprod)
- `citadel-notification-service` (prod-citadel, branche main)

---
