# Cache des appareils

## Fonctionnement

```
Login device ──▶ Auth Service ──▶ Event ──▶ Notification Service
                                                   │
                                             ┌─────▼─────┐
                                             │ DeviceCache│
                                             │  (Redis)   │
                                             └───────────┘
```

Le cache garde la correspondance user_id -> liste de device tokens (FCM/APNS).
