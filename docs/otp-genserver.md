# OTP GenServers

## Processus supervisés

| GenServer | Rôle |
|-----------|------|
| JwksCache | Cache des clés publiques auth-service |
| DeviceCacheService | Cache des device tokens |

## Supervision

```
Application
     │
     ▼
Supervisor
     │
     ├──▶ JwksCache (restart: permanent)
     └──▶ DeviceCacheService (restart: permanent)
```
