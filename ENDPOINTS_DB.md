# Notification Service — Endpoints & Base de données

## TL;DR

**Aujourd'hui, modifier un endpoint ne change rien en base de données.**

Le service déclare bien les dépendances `ecto_sql` + `postgrex` dans `mix.exs`,
mais :

- aucun module `Repo` n'existe dans `lib/`,
- `config/config.exs` contient `ecto_repos: []` (ligne 17),
- `WhisprNotifications.Application` (`lib/whispr_notifications/application.ex`)
  ne démarre aucun `Repo` dans son arbre de supervision,
- il n'y a **aucun dossier `priv/repo/migrations`**,
- les contrôleurs et les managers renvoient des stubs (`:ok`, structs par
  défaut, `send_resp(conn, 204, "")`) avec des `# TODO: persister…`.

Seul **Redis** est réellement configuré et utilisé (cache devices, pub/sub).
PostgreSQL est prévu par la doc (`documentation/1_architecture/2_database_design.md`)
mais pas implémenté.

---

## Inventaire des endpoints HTTP

Source : `lib/whispr_notifications_web/router.ex`.
Les routes sont exposées deux fois (`/api/...` et `/notification/api/...`) selon
que la gateway strippe ou non le préfixe — le comportement est identique.

| Méthode | Chemin | Controller / action | Auth JWT | Touche la BDD aujourd'hui ? | Devrait toucher la BDD ? |
|---|---|---|---|---|---|
| GET  | `/v1/health` | `HealthController.live` | ❌ | Non | Non |
| GET  | `/v1/auth-check` | `AuthCheckController.show` | ✅ | Non | Non |
| GET  | `/settings/:id` | `SettingsController.show` | ✅ | ❌ stub (`Manager.get_user_settings` renvoie un struct vide) | ✅ `SELECT` sur `user_settings` |
| PUT/PATCH | `/settings/:id` | `SettingsController.update` | ✅ | ❌ stub (`204` sans rien faire, TODO ligne 26) | ✅ `UPDATE`/`UPSERT` sur `user_settings` |
| POST | `/conversations/:conversation_id/mute` | `MuteController.mute` | ✅ | ❌ stub (TODO ligne 6) | ✅ `UPSERT` sur `conversation_settings` (muted=true) |
| DELETE | `/conversations/:conversation_id/mute` | `MuteController.unmute` | ✅ | ❌ stub (TODO ligne 12) | ✅ `UPDATE` sur `conversation_settings` (muted=false) |
| POST | `/v1/notifications` | `NotificationsController.create` | ✅ | ❌ `History.save/1` renvoie `:ok` sans persister | ✅ `INSERT` dans `notification_history` + insert des `delivery_attempts` |
| POST | `/v1/devices` | `DevicesController.register` | ✅ | ✅ `SELECT` pré-check puis `INSERT … ON CONFLICT` sur `devices` via l'index unique partiel `(user_id, device_id) WHERE deleted_at IS NULL` | — |
| DELETE | `/v1/devices/:device_id` | `DevicesController.unregister` | ✅ | ✅ `UPDATE devices SET deleted_at=…, updated_at=… WHERE user_id=… AND device_id=… AND deleted_at IS NULL` (idempotent via `Devices.soft_delete_by_user_device/2`) | — |

---

## Détail par endpoint

### `GET /settings/:id` — `SettingsController.show/2`
- Appelle `WhisprNotifications.Preferences.Manager.get_user_settings(user_id)`.
- **État actuel** : `manager.ex:22-24` renvoie `{:ok, %UserSettings{user_id: user_id}}` avec **les valeurs par défaut** du struct. Aucun `Repo.get`.
- **Cible BDD** : lire une ligne `user_settings` (PK `user_id`) contenant au minimum les champs exposés par le contrôleur : `message_push_enabled`, `message_email_enabled`, `system_push_enabled`, `marketing_push_enabled`, `quiet_hours_start`, `quiet_hours_end`.

### `PUT /settings/:id` — `SettingsController.update/2`
- **État actuel** : `settings_controller.ex:25-29` ignore les params et renvoie `204`. Commentaire explicite `# TODO: persister les settings et renvoyer le nouvel état`.
- **Cible BDD** : `INSERT … ON CONFLICT (user_id) DO UPDATE` sur `user_settings` avec les champs du body. Retourner le nouvel état (ou `204`).

### `POST /conversations/:conversation_id/mute` — `MuteController.mute/2`
- **État actuel** : `mute_controller.ex:5-9` — `TODO: persister les ConversationSettings.muted = true`.
- **Cible BDD** : `UPSERT` sur `conversation_settings` (clé composite `user_id` + `conversation_id`) avec `muted=true` et éventuellement `mute_until` si fourni dans le body.

### `DELETE /conversations/:conversation_id/mute` — `MuteController.unmute/2`
- **État actuel** : `mute_controller.ex:11-16` — `TODO: persister les ConversationSettings.muted = false`.
- **Cible BDD** : `UPDATE conversation_settings SET muted=false, mute_until=NULL WHERE user_id=… AND conversation_id=…`.

### `POST /v1/notifications` — `NotificationsController.create/2`
- Pipeline : `Notifications.create/1` → valide → `Notification.new/1` → `History.save/1` → `deliver_if_possible/1`.
- **État actuel** :
  - `notifications/history.ex:17` — `def save(_notif), do: :ok` (comportement stub, ne persiste rien).
  - `deliver_if_possible/1` (`notifications.ex:97`) pousse vers `BatchProcessor` uniquement si le cache Redis des devices est présent ; aucun fallback DB.
- **Cible BDD** :
  - `INSERT` dans `notification_history` (id, user_id, conversation_id, type, title, body, context, metadata, created_at).
  - Pour chaque device ciblé, `INSERT` dans `delivery_attempts` avec le statut/provider (APNS, FCM).
  - Option : marquer `read_at` via un futur endpoint `PATCH /notifications/:id/read` qui mettrait à jour `notification_history.read_at` (méthode `History.mark_read/2` déjà déclarée dans le `Behaviour` mais stubée).

### `GET /v1/health`, `GET /v1/auth-check`
- Pas de BDD attendue. `auth-check` lit seulement `conn.assigns[:jwt_sub]` posé par le plug d'auth.

### `POST /v1/devices` — `DevicesController.register/2`
- Pipeline :
  1. `user_id = conn.assigns[:jwt_sub]` — jamais dans le body (pas d'impersonation possible).
  2. Le controller fait un `Repo.exists?` sur `(user_id, device_id)` (incluant les lignes soft-deleted) pour décider le code de réponse.
  3. `Devices.upsert/1` → `Repo.insert(changeset, on_conflict: {:replace, [:fcm_token, :platform, :app_version, :updated_at]}, conflict_target: ("user_id", "device_id") WHERE deleted_at IS NULL, returning: true)`.
- **Cible BDD** :
  - Premier enregistrement → `INSERT` → **201**.
  - Rotation de token / app upgrade (ligne active présente) → `UPDATE` via ON CONFLICT sur l'index partiel → **200**.
  - Re-register après DELETE → l'index partiel ne matche pas (la tombstone a `deleted_at NOT NULL`), donc `INSERT` d'une nouvelle ligne. Mais le pré-check du controller voit l'ancienne tombstone, donc la réponse reste **200**.
- Unique key logique : `(user_id, device_id) WHERE deleted_at IS NULL` (partielle) — seules les lignes actives sont contraintes.

### `DELETE /v1/devices/:device_id` — `DevicesController.unregister/2`
- **État actuel** : idempotent, répond toujours **204** (même si la ligne n'existe pas, même si elle est déjà soft-deleted).
- Appelle `Devices.soft_delete_by_user_device(user_id, device_id)` qui fait un `Repo.update_all` ciblant uniquement les lignes actives.
- **Cible BDD** : `UPDATE devices SET deleted_at=NOW(), updated_at=NOW() WHERE user_id=? AND device_id=? AND deleted_at IS NULL`.
- La ligne n'est jamais physiquement supprimée côté chemin chaud → préserve la trace pour les audit / métriques. La purge dure (`Devices.hard_delete/1`) est réservée au `TokenRefresher` après la fenêtre de rétention.

---

## Ce qui touche (ou devrait toucher) la BDD hors endpoints HTTP

Ces flux ne sont pas déclenchés par le routeur mais consomment/produiraient des lignes en base :

| Composant | Fichier | État | Cible BDD |
|---|---|---|---|
| `Notifications.History.save/2` | `lib/whispr_notifications/notifications/history.ex` | stub | `INSERT notification_history` |
| `Notifications.History.mark_read/2` | idem | stub | `UPDATE notification_history SET read_at=…` |
| `Notifications.History.list_for_user/2` | idem | renvoie `[]` | `SELECT … FROM notification_history WHERE user_id=…` |
| `Preferences.Manager.get_user_settings/1` | `lib/whispr_notifications/preferences/manager.ex` | stub | `SELECT user_settings` |
| `Preferences.Manager.get_conversation_settings/2` | idem | stub | `SELECT conversation_settings` |
| `Devices.upsert/1`, `soft_delete_by_user_device/2`, `list_active_for_user/1` | `lib/whispr_notifications/devices.ex` | ✅ actif | `INSERT … ON CONFLICT` / `UPDATE devices SET deleted_at=…` / `SELECT … WHERE deleted_at IS NULL` |
| `Devices.mark_invalid/2`, `list_invalidated_before/1`, `hard_delete/1` | idem | ✅ actif | `UPDATE devices SET last_error=…, deleted_at=…` (chemin FCM soft-delete) et `DELETE devices WHERE id=?` (purge TokenRefresher) |
| `Devices.CacheManager` + `DeviceCache` + `AuthClient` | `lib/whispr_notifications/devices/` | Redis cache + fan-out | Redis lit la source de vérité depuis la table `devices` via `list_active_for_user/1` |
| `Delivery.BatchProcessor`, `Delivery.RetryManager` | `lib/whispr_notifications/delivery/` | Livraison only | Devrait écrire les `delivery_attempts` (status, provider, retried_at, error_code) |
| `Workers.CleanupWorker` | `lib/whispr_notifications_workers/` | — | Devrait supprimer/archiver `notification_history` anciens et purger `delivery_attempts` obsolètes |
| `Workers.CacheSyncWorker` | idem | — | Devrait hydrater Redis depuis `user_settings` + `conversation_settings` |
| `Workers.ModerationSubscriber` | idem | Consommateur PubSub | Pourrait persister des `system_events` ou `moderation_audit` selon la politique |
| `Events.*` (`message_events`, `group_events`, `system_events`, `moderation_events`) | `lib/whispr_notifications/events/` | Handlers gRPC/bus | En règle générale produisent une `notification_history` si la notif est émise |

---

## Schéma BDD cible (résumé de `documentation/1_architecture/2_database_design.md`)

Tables PostgreSQL prévues :

- `user_settings` — réglages globaux utilisateur (push/email/quiet hours).
- `conversation_settings` — overrides par conversation (mute, priorité).
- `notification_history` — historique des notifications envoyées.
- `delivery_attempts` — tentatives de livraison APNS/FCM avec leur statut.
- `devices` — source de vérité des push targets par utilisateur (`user_id`, `device_id`, `fcm_token`, `platform`, `app_version`, `last_error`, `last_error_at`, `deleted_at`, timestamps). Index unique partiel sur `(user_id, device_id) WHERE deleted_at IS NULL`, plus index simples sur `user_id`, `fcm_token`, `last_error`. `BatchProcessor` pousse les tokens invalides en soft-delete via `Devices.mark_invalid/2` (renseigne `last_error` / `last_error_at` + `deleted_at`). `TokenRefresher` purge définitivement les lignes invalides plus anciennes que la fenêtre de rétention via `hard_delete/1`.
- `notification_interactions` — ouvertures/clics/actions côté client.
- `notification_templates` — gabarits i18n pour formater les notifs.

Redis (déjà branché via `redix`) reste la couche chaude : cache devices,
throttling, dedup, coordination inter-nœuds.

---

## Checklist pour brancher réellement la BDD

1. Créer `lib/whispr_notifications/repo.ex` (`use Ecto.Repo, otp_app: :whispr_notification, adapter: Ecto.Adapters.Postgres`).
2. Ajouter `ecto_repos: [WhisprNotifications.Repo]` dans `config/config.exs` et la config Postgres dans `dev.exs` / `runtime.exs`.
3. Démarrer `WhisprNotifications.Repo` dans `application.ex` **avant** les workers qui en dépendent.
4. Créer `priv/repo/migrations/` avec les migrations pour `user_settings`, `conversation_settings`, `notification_history`, `delivery_attempts`, etc.
5. Remplacer les structs `%UserSettings{}` / `%ConversationSettings{}` (purs POJOs aujourd'hui) par des schémas Ecto (`use Ecto.Schema` + `changeset/2`).
6. Implémenter pour de vrai :
   - `Preferences.Manager.get_user_settings/1` et un nouveau `update_user_settings/2`,
   - `Preferences.Manager.get_conversation_settings/2` et `set_muted/3`,
   - `Notifications.History.save/1`, `mark_read/2`, `list_for_user/2`.
7. Câbler les contrôleurs stubs (`SettingsController.update`, `MuteController.{mute,unmute}`) sur ces fonctions.
8. Ajouter `Ecto.Adapters.SQL.Sandbox` dans `test/test_helper.exs` (déjà attendu par `CLAUDE.md`).
