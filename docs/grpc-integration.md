# Intégration gRPC

## Services appelés

```
Notification Service
     │
     ├──▶ Auth Service
     │    └── Vérif tokens, fetch device info
     │
     ├──▶ User Service
     │    └── Préférences utilisateur
     │
     └──▶ Messaging Service
          └── Contexte du message
```
