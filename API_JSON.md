# Notification Service — Référence JSON des endpoints

Base URL locale : `http://localhost:4002`
Préfixes équivalents :
- `/api/...` (gateway qui strippe le préfixe `notification`)
- `/notification/api/...` (gateway qui transmet le chemin complet)

Toutes les routes sauf `/v1/health` requièrent l'en-tête :

```
Authorization: Bearer <jwt_es256>
Content-Type: application/json
```

Les identifiants (`user_id`, `conversation_id`) sont typés `string` côté BDD —
des UUIDs sont attendus en prod mais n'importe quelle chaîne est acceptée.

---

## 1. `GET /api/v1/health` — healthcheck

Aucune auth. Aucun corps.

**Requête**
```http
GET /api/v1/health
```

**Réponse 200**
```json
{ "status": "ok" }
```

---

## 2. `GET /api/v1/auth-check` — vérifie le JWT

**Requête**
```http
GET /api/v1/auth-check
Authorization: Bearer <jwt>
```

**Réponse 200**
```json
{
  "status": "ok",
  "sub": "550e8400-e29b-41d4-a716-446655440000"
}
```

**401** si le token est invalide/absent :
```json
{ "error": "unauthorized" }
```

---

## 3. `GET /api/settings/:id` — lire les préférences d'un user

`:id` = `user_id`.

**Requête**
```http
GET /api/settings/550e8400-e29b-41d4-a716-446655440000
Authorization: Bearer <jwt>
```

**Réponse 200** — préférences trouvées ou valeurs par défaut si aucun enregistrement en base :
```json
{
  "user_id": "550e8400-e29b-41d4-a716-446655440000",
  "language": "fr",
  "timezone": "Europe/Paris",
  "message_push_enabled": true,
  "message_email_enabled": false,
  "system_push_enabled": true,
  "marketing_push_enabled": false,
  "quiet_hours_start": "22:00:00",
  "quiet_hours_end": "07:00:00"
}
```

`quiet_hours_start`/`quiet_hours_end` peuvent être `null`.
`language`, `timezone` peuvent être `null`.

---

## 4. `PUT /api/settings/:id` — créer/mettre à jour les préférences

Upsert sur `user_settings` (clé unique `user_id`).

**Requête**
```http
PUT /api/settings/550e8400-e29b-41d4-a716-446655440000
Authorization: Bearer <jwt>
Content-Type: application/json
```
```json
{
  "language": "fr",
  "timezone": "Europe/Paris",
  "message_push_enabled": true,
  "message_email_enabled": false,
  "system_push_enabled": true,
  "marketing_push_enabled": false,
  "quiet_hours_start": "22:00:00",
  "quiet_hours_end": "07:00:00"
}
```

Tous les champs sont optionnels. Seuls les champs envoyés sont mis à jour
(les autres gardent leur valeur actuelle ou la valeur par défaut Ecto).

Formats acceptés :
- booléens : `true` / `false`
- heures : `"HH:MM:SS"` (parsé par Ecto en `Time`)
- strings : `language`, `timezone` (fuseau IANA valide, ex. `"Europe/Paris"`)

**Réponse 200** — renvoie l'état final :
```json
{
  "user_id": "550e8400-e29b-41d4-a716-446655440000",
  "language": "fr",
  "timezone": "Europe/Paris",
  "message_push_enabled": true,
  "message_email_enabled": false,
  "system_push_enabled": true,
  "marketing_push_enabled": false,
  "quiet_hours_start": "22:00:00",
  "quiet_hours_end": "07:00:00"
}
```

**Réponse 422** (validation Ecto, ex. `timezone` invalide) :
```json
{
  "errors": {
    "quiet_hours_start": ["is invalid"]
  }
}
```

---

## 5. `POST /api/conversations/:conversation_id/mute` — couper les notifs

Upsert sur `conversation_settings` avec `muted=true`.
`user_id` est lu dans `params["user_id"]` **ou** à défaut du `sub` du JWT.

**Requête (mute permanent)**
```http
POST /api/conversations/aaaa-bbbb-cccc-dddd/mute
Authorization: Bearer <jwt>
Content-Type: application/json
```
```json
{
  "user_id": "550e8400-e29b-41d4-a716-446655440000"
}
```

**Requête (mute jusqu'à une date ISO8601)**
```json
{
  "user_id": "550e8400-e29b-41d4-a716-446655440000",
  "mute_until": "2026-04-20T09:00:00Z"
}
```

**Réponse 204** — succès, pas de corps.

**Réponse 400**
```json
{ "errors": { "user_id": ["is required"] } }
```
```json
{ "errors": { "mute_until": ["must be ISO8601"] } }
```

**Réponse 422** (erreurs de changeset) :
```json
{ "errors": { "conversation_id": ["can't be blank"] } }
```

---

## 6. `DELETE /api/conversations/:conversation_id/mute` — réactiver les notifs

Même auth et même résolution du `user_id` que POST.

**Requête**
```http
DELETE /api/conversations/aaaa-bbbb-cccc-dddd/mute
Authorization: Bearer <jwt>
Content-Type: application/json
```
```json
{ "user_id": "550e8400-e29b-41d4-a716-446655440000" }
```

(`user_id` en query string fonctionne aussi :
`DELETE /api/conversations/.../mute?user_id=...`.)

**Réponse 204** — succès, pas de corps.

---

## 7. `POST /api/v1/notifications` — créer et envoyer une notification

Enregistre dans `notification_history` puis pousse via APNS/FCM si le cache
Redis des devices est dispo.

**Requête — message**
```http
POST /api/v1/notifications
Authorization: Bearer <jwt>
Content-Type: application/json
```
```json
{
  "user_id": "550e8400-e29b-41d4-a716-446655440000",
  "type": "message",
  "title": "Nouveau message",
  "body": "Alice : Salut !",
  "conversation_id": "aaaa-bbbb-cccc-dddd",
  "context": {
    "message_id": "msg-123",
    "sender_id": "alice-uuid"
  },
  "metadata": {
    "priority": "high"
  }
}
```

**Requête — notif système**
```json
{
  "user_id": "550e8400-e29b-41d4-a716-446655440000",
  "type": "system",
  "title": "Compte vérifié",
  "body": "Votre adresse email a été confirmée.",
  "context": { "event": "email_verified" }
}
```

**Champs**
| Champ | Type | Requis | Valeurs |
|---|---|---|---|
| `user_id` | string | oui | id destinataire |
| `type` | string | oui | `"message"`, `"group"`, `"system"` |
| `title` | string | oui | — |
| `body` | string | oui | — |
| `conversation_id` | string | non | lié à une conversation |
| `context` | object | non | défaut `{}` ; clés transformées en strings |
| `metadata` | object | non | défaut `{}` |

**Réponse 201**
```json
{
  "id": "0e4b1f1c-8b4f-4c1b-9d61-8c0a7f6a1c3b",
  "user_id": "550e8400-e29b-41d4-a716-446655440000",
  "type": "message",
  "title": "Nouveau message",
  "body": "Alice : Salut !",
  "conversation_id": "aaaa-bbbb-cccc-dddd",
  "created_at": "2026-04-17T10:32:04Z"
}
```

**Réponse 400** — validation métier :
```json
{
  "errors": [
    "user_id est requis",
    "type doit être message, group ou system"
  ]
}
```

---

## Récap — ce qui atterrit en base

| Endpoint | Table touchée | Opération |
|---|---|---|
| `GET /settings/:id` | `user_settings` | `SELECT` |
| `PUT /settings/:id` | `user_settings` | `INSERT … ON CONFLICT (user_id) DO UPDATE` |
| `POST /conversations/:id/mute` | `conversation_settings` | upsert sur `(user_id, conversation_id)` |
| `DELETE /conversations/:id/mute` | `conversation_settings` | upsert avec `muted=false`, `mute_until=null` |
| `POST /v1/notifications` | `notification_history` | `INSERT` (idempotent via `on_conflict: :nothing`) |
| `GET /v1/health`, `GET /v1/auth-check` | — | aucune |

`delivery_attempts` est créée mais pas encore écrite (ce sera le rôle du
`BatchProcessor` / `RetryManager` à brancher ensuite).

---

## Exemple cURL rapide

```bash
export TOKEN="eyJhbGci..."
export USER="550e8400-e29b-41d4-a716-446655440000"

# Lire les settings
curl -H "Authorization: Bearer $TOKEN" \
     http://localhost:4002/api/settings/$USER

# Mettre à jour les settings
curl -X PUT \
     -H "Authorization: Bearer $TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"quiet_hours_start":"22:00:00","quiet_hours_end":"07:00:00"}' \
     http://localhost:4002/api/settings/$USER

# Mute une conversation pour 1h
curl -X POST \
     -H "Authorization: Bearer $TOKEN" \
     -H "Content-Type: application/json" \
     -d "{\"user_id\":\"$USER\",\"mute_until\":\"2026-04-17T12:00:00Z\"}" \
     http://localhost:4002/api/conversations/conv-123/mute

# Unmute
curl -X DELETE \
     -H "Authorization: Bearer $TOKEN" \
     -H "Content-Type: application/json" \
     -d "{\"user_id\":\"$USER\"}" \
     http://localhost:4002/api/conversations/conv-123/mute

# Envoyer une notif
curl -X POST \
     -H "Authorization: Bearer $TOKEN" \
     -H "Content-Type: application/json" \
     -d "{\"user_id\":\"$USER\",\"type\":\"system\",\"title\":\"Test\",\"body\":\"Hello\"}" \
     http://localhost:4002/api/v1/notifications
```

---

## Bootstrap avant le premier appel

```bash
# 1. Récupérer les deps (inclut ecto_sql, postgrex)
mix deps.get

# 2. Créer la DB + jouer les migrations
mix ecto.setup      # ecto.create + ecto.migrate

# 3. Lancer le serveur
mix phx.server      # ou: iex -S mix phx.server
```

Variables d'env optionnelles :
- `DATABASE_HOST` (default `localhost`)
- `DATABASE_PORT` (default `5432`)
- `DATABASE_USER` (default `postgres`)
- `DATABASE_PASSWORD` (default `postgres`)
- `DATABASE_NAME` (default `whispr_notification_dev`)
- `DATABASE_POOL_SIZE` (default `10`)

En production : `DATABASE_URL=ecto://user:pass@host/db` obligatoire
(`config/runtime.exs`).
