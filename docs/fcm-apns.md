# FCM et APNS

## Architecture

```
Notification Service
     │
     ├──▶ FCM (Firebase Cloud Messaging)
     │    └── Android devices
     │
     └──▶ APNS (Apple Push Notification)
          └── iOS devices
```

## Configuration

| Variable | Description |
|----------|-------------|
| FCM_KEY | Clé serveur Firebase |
| APNS_CERT | Certificat Apple |
| APNS_KEY | Clé privée Apple |
