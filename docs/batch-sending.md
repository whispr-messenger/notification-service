# Envoi en batch

## Schéma

```
N notifications ──▶ Regroupement par device type
                          │
                    ┌─────┼─────┐
                    │           │
              FCM batch    APNS batch
              (max 500)    (max 100)
```

Le batching réduit le nombre d'appels réseau vers FCM/APNS.
