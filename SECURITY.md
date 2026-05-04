# Sécurité

## Authentification

Vérification JWT via JWKS (auth-service).

## Push notifications

- Clés FCM et certificats APNS stockés dans Vault
- Communication gRPC sécurisée via mTLS (Istio)
- Filtrage des notifications par préférences utilisateur
- Pas de stockage de contenu des messages

## Journalisation — données sensibles

Le service applique deux règles strictes (testées dans `test/security/logging_test.exs`) :

1. **Tokens APNS** : jamais interpolés en clair dans les messages Logger. Le
   client APNS (`lib/whispr_notifications/delivery/apns_client.ex`) n'écrit que
   la forme masquée `***xxxxxx` (6 derniers caractères).
2. **Identifiants personnels** (`user_id`, `report_id`, `appeal_id`,
   `reported_user_id`) : transmis via **Logger metadata** uniquement, jamais
   interpolés dans le corps du message. Les clés autorisées sont déclarées dans
   `config/config.exs` et `config/prod.exs` sous `config :logger, :console`.

### Filtrage côté agent de logs

En production, les logs sont ingérés par **Loki** (cf.
`documentation/1_architecture/1_system_design.md`). Les identifiants transitant
par metadata doivent être scrubbés sur le pipeline, pas côté application, afin
de conserver la traçabilité locale tout en évitant la propagation vers les
systèmes tiers.

**Promtail (Loki)** — pipeline `scrape_configs` :

```yaml
pipeline_stages:
  - regex:
      expression: '(?P<user_id_kv>user_id=[0-9a-fA-F-]+)'
  - replace:
      expression: 'user_id=[0-9a-fA-F-]+'
      replace: 'user_id=REDACTED'
  - replace:
      expression: 'report_id=[0-9a-fA-F-]+'
      replace: 'report_id=REDACTED'
  - replace:
      expression: 'appeal_id=[0-9a-fA-F-]+'
      replace: 'appeal_id=REDACTED'
  - replace:
      expression: 'reported_user_id=[0-9a-fA-F-]+'
      replace: 'reported_user_id=REDACTED'
```

**Datadog Agent** — `logs_config.processing_rules` :

```yaml
logs:
  - type: file
    path: /var/log/notification-service/*.log
    service: notification-service
    log_processing_rules:
      - type: mask_sequences
        name: mask_user_id
        pattern: 'user_id=[0-9a-fA-F-]+'
        replace_placeholder: 'user_id=REDACTED'
      - type: mask_sequences
        name: mask_report_id
        pattern: 'report_id=[0-9a-fA-F-]+'
        replace_placeholder: 'report_id=REDACTED'
      - type: mask_sequences
        name: mask_appeal_id
        pattern: 'appeal_id=[0-9a-fA-F-]+'
        replace_placeholder: 'appeal_id=REDACTED'
      - type: mask_sequences
        name: mask_reported_user_id
        pattern: 'reported_user_id=[0-9a-fA-F-]+'
        replace_placeholder: 'reported_user_id=REDACTED'
```

### Procédure d'ajout d'un nouvel identifiant

1. Ajouter la clé au whitelist `metadata:` dans `config/config.exs` **et**
   `config/prod.exs`.
2. Utiliser `Logger.<level>("message", <key>: value)` — ne jamais interpoler.
3. Ajouter un cas dans `test/security/logging_test.exs` asserant l'absence de
   la valeur dans `message_body(log)`.
4. Ajouter la règle de masking correspondante dans Promtail / Datadog.

### Référence

Cette politique dérive de la section Journalisation du socle RGPD
(minimisation des données, pseudonymisation des identifiants) — cf.
`documentation/1_architecture/3_security_policy.md` §Minimisation données et
§Pseudonymisation logs.
