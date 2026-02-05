# Whispr Messenger - Notification Microservice

[![Quality Gate Status]]

## Overview

Microservice de notifications développé par DALM1 équipe Whispr. Ce service assure la gestion, le filtrage et la livraison des notifications push en lien avec plusieurs microservices via Istio Service Mesh, garantissant sécurité, scalabilité et résilience.

## Table of Contents

- [Tech Stack](#tech-stack)
- [Architecture](#architecture)
- [Features](#features)
- [Installation](#installation)
- [Configuration](#configuration)
- [Usage](#usage)
- [API Endpoints](#api-endpoints)
- [Testing](#testing)
- [Deployment](#deployment)
- [Support](#support)
- [License](#license)

## Tech Stack

- **Langage** : Elixir
- **Framework** : Phoenix (+ OTP)
- **Base de données** : PostgreSQL via Ecto
- **Cache** : Redis
- **Service Mesh** : Istio avec mTLS et Envoy
- **Notifications Push** : FCM (Firebase), APNS (Apple)
- **API** : REST + gRPC (mTLS via Istio)
- **Tests** : ExUnit (unitaires, intégration, workers)

## Architecture

### Main Services

- **DeviceCacheService** : gestion du cache des appareils
- **NotificationService** : formatage, filtrage, gestion de règles et préférences
- **DeliveryService** : batching, retry, envoi vers FCM/APNS
- **EventService** : gestion des événements métiers (message, média, modération)
- **GrpcService** : communication avec auth-service, user-service, messaging-service

## Features

- Distribution multi-canal des notifications (FCM/APNS)
- Préférences utilisateur et device (mute, horaires, fréquences)
- Filtrage intelligent par conversation, contenu, calendrier
- Historique des notifications envoyées
- Retry automatique et tolérance aux pannes
- Synchronisation du cache avec auth-service
- Observabilité avancée (logs, métriques, traces Istio)
- API REST : gestion des paramètres, historique
- API gRPC : envoi/batch, intégration inter-microservices

## Installation

### Prérequis

- Elixir 1.15+
- Erlang 26+
- PostgreSQL 14+
- Redis 6+
- Docker / Kubernetes / Istio (cluster ou local)

### Étapes

```bash
cp .env.example .env
mix deps.get
mix ecto.create
mix ecto.migrate
```

## Configuration

Variables à définir dans `.env` :
- `DB_HOST`, `DB_PORT`, `DB_USERNAME`, `DB_PASSWORD`, `DB_NAME`
- `REDIS_HOST`, `REDIS_PORT`, `REDIS_PASSWORD`
- `FCM_KEY`, `APNS_CERT`, `APNS_KEY`
- `ISTIO_ENABLED`, `GRPC_PORT`, `REST_PORT`

## Usage

### Développement

```bash
mix phx.server # Démarrage Phoenix
mix test # Exécuter les tests unitaires et d'intégration
mix docs # Générer la documentation
```

### Production

```bash
MIX_ENV=prod mix release
_build/prod/rel/notification_service/bin/notification_service start
docker build -t notification-service .
docker-compose up -d
```

## API Endpoints

### REST

- `GET /notifications/:user_id` — Historique des notifications
- `PUT /settings/:user_id` — Mise à jour des préférences
- `GET /health` — Health check du service

### gRPC

- `SendNotification`
- `SendBulkNotifications`
- `NotifyDeviceEvent`
- Voir détails & schémas dans `/documentation`

## Testing

- Suite ExUnit (unitaires, intégration, workers)
- Couverture > 90%

## Deployment

- Docker, Docker Compose & Kubernetes (GKE supporté)
- Déploiement continu via GitHub Actions & ArgoCD
- Rolling updates & blue/green deploy via Istio

## Support

- Documentation dans `/documentation`
- Vérifier les logs
- Support via Teams/Discord (voir `.env`)

## License

Projet Whispr : usage privé, tous droits réservés.

---

**Développé par l'équipe Whispr**

Version : 1.0.0  
Dernière mise à jour – 14/11/2025

