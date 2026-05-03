# Préférences utilisateur

## Options

| Préférence | Description |
|-----------|-------------|
| Mute conversation | Pas de notif pour cette conv |
| Horaires silencieux | Pas de notif entre 22h et 8h |
| Fréquence | Immédiat / Groupé / Résumé |

## Flux

```
Notification entrante ──▶ Vérif préférences
                               │
                         Autorisé?
                          oui │ non
                         ┌────┼────┐
                         │        │
                      Envoyer   Filtré
```
