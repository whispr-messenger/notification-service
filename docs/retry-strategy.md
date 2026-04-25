# Stratégie de retry

## Flux

```
Envoi notification ──▶ FCM/APNS
                          │
                    Succès? 
                     oui │ non
                    ┌────┼────┐
                    │        │
                  Done    Retry
                          (backoff exponentiel)
                          │
                    Max retries?
                     non │ oui
                    ┌────┼────┐
                    │        │
                  Retry   Abandon
                          + log erreur
```
