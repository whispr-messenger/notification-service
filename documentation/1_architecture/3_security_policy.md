# Politique de Sécurité - Service de Notifications

## 1. Introduction

### 1.1 Objectif du Document
Cette politique de sécurité définit les mesures techniques et pratiques à implémenter pour protéger le service de notifications (Notification Service) de l'application Whispr dans le cadre de notre projet de fin d'études.

### 1.2 Contexte et Importance
Le service de notifications gère l'ensemble des notifications push, des préférences utilisateur et du suivi des livraisons. Il constitue un point critique pour la vie privée des utilisateurs et doit garantir la confidentialité des données de notification, l'intégrité des paramètres utilisateur et la disponibilité du service de distribution.

### 1.3 Principes Fondamentaux
- **Protection des tokens d'appareil**: Sécurisation des tokens FCM/APNS contre les fuites et abus
- **Confidentialité des préférences**: Protection des paramètres personnels de notification
- **Minimisation des données**: Limitation des informations stockées dans les notifications
- **Livraison fiable**: Garantie de distribution sécurisée sans perte ni duplication
- **Séparation des privilèges**: Isolation stricte entre les utilisateurs et leurs appareils
- **Défense en profondeur**: Multiples couches de protection complémentaires

## 2. Protection des Communications

### 2.1 Sécurité des Communications Externes

#### 2.1.1 Intégration FCM (Firebase Cloud Messaging)
- Utilisation des clés de serveur FCM stockées dans Google Secret Manager
- Authentification via OAuth 2.0 pour les appels API FCM
- Validation des certificats SSL/TLS pour toutes les connexions
- Pools de connexions sécurisées avec réutilisation des sessions HTTP/2
- Timeout et retry configurés pour éviter les blocages

#### 2.1.2 Intégration APNS (Apple Push Notification Service)
- Certificats APNS stockés de manière sécurisée avec rotation automatique
- Connexions TLS mutuelles avec validation stricte des certificats
- Utilisation du protocole HTTP/2 pour les connexions APNS
- Gestion des tokens provider avec renouvellement automatique
- Validation des réponses APNS pour détecter les tokens invalides

#### 2.1.3 Protection des Payloads
- Limitation de la taille des payloads selon les contraintes des plateformes
- Validation du format des données avant envoi
- Pas d'inclusion de données sensibles dans le payload
- Chiffrement des données personnalisées quand nécessaire
- Obfuscation des identifiants dans les notifications

### 2.2 Sécurité des Communications Internes

#### 2.2.1 Communication gRPC Inter-Services
- mTLS (TLS mutuel) pour toutes les communications gRPC
- Certificats générés automatiquement via service mesh
- Validation des identités de service à chaque requête
- Chiffrement des données sensibles dans les messages gRPC
- Timeout et circuit breakers pour éviter les blocages

#### 2.2.2 API REST Externes
- TLS 1.3 obligatoire pour toutes les connexions HTTP
- Authentification JWT validée pour chaque requête
- Rate limiting par utilisateur et par endpoint
- Validation stricte des entrées avec sanitisation
- CORS configuré de manière restrictive

## 3. Gestion des Tokens et Appareils

### 3.1 Protection des Tokens d'Appareil

#### 3.1.1 Stockage Sécurisé des Tokens
- Chiffrement symétrique des tokens FCM/APNS en base de données
- Clés de chiffrement gérées via Google Secret Manager
- Rotation automatique des clés de chiffrement tous les 90 jours
- Index partiels pour éviter l'indexation des tokens chiffrés
- Pas de stockage des tokens en logs ou caches non chiffrés

#### 3.1.2 Validation et Nettoyage des Tokens
- Vérification de la validité des tokens avant chaque envoi
- Suppression automatique des tokens signalés comme invalides
- Nettoyage périodique des tokens d'appareils inactifs (>30 jours)
- Limitation du nombre de tokens par utilisateur (max 10)
- Détection et blocage des tentatives de spam de tokens

#### 3.1.3 Gestion du Cycle de Vie
- Enregistrement sécurisé avec validation de l'origine
- Mise à jour atomique des tokens lors du renouvellement
- Désenregistrement immédiat lors de la déconnexion
- Audit trail des modifications de tokens
- Isolation entre les tokens de différentes plateformes

### 3.2 Sécurité des Métadonnées d'Appareil

#### 3.2.1 Minimisation des Données
- Stockage minimal des métadonnées d'appareil nécessaires
- Pseudonymisation des identifiants d'appareil
- Pas de stockage d'informations personnelles identifiables
- Agrégation des données pour les statistiques
- Suppression automatique des métadonnées anciennes

#### 3.2.2 Contrôle d'Accès aux Appareils
- Vérification de propriété avant toute modification
- Isolation stricte entre les appareils de différents utilisateurs
- Validation des autorisations pour les opérations sensibles
- Journalisation des accès aux informations d'appareil
- Protection contre l'énumération des appareils

## 4. Protection des Données

### 4.1 Classification des Données

#### 4.1.1 Données Hautement Sensibles
- Tokens de notification push : chiffrés avec rotation des clés
- Préférences de confidentialité : accès restreint au propriétaire
- Historique des interactions : anonymisé et limité dans le temps
- Informations de géolocalisation (si utilisées) : chiffrées et minimisées

#### 4.1.2 Données Modérément Sensibles
- Préférences de notification : protégées par authentification
- Métadonnées d'appareil : pseudonymisées
- Statistiques d'utilisation : agrégées et anonymisées
- Paramètres de conversation : accès contrôlé

#### 4.1.3 Données Faiblement Sensibles
- Templates de notification : protection contre la falsification
- Métriques système : expurgées des identifiants personnels
- Logs d'erreur : sanitisés des données sensibles
- Configuration système : protection contre les modifications non autorisées

### 4.2 Chiffrement au Repos

#### 4.2.1 Base de Données PostgreSQL
- Chiffrement transparent de la base de données complète (TDE)
- Chiffrement additionnel pour les colonnes hautement sensibles
- Clés de chiffrement gérées via Google Cloud KMS
- Isolation des données par utilisateur via RLS (Row Level Security)
- Partitionnement des données sensibles pour limiter l'exposition

#### 4.2.2 Données Temporaires
- TTL strict sur toutes les données Redis (max 24h pour les préférences)
- Pas de persistance sur disque pour les données temporaires
- Chiffrement des données sensibles même en cache
- Purge immédiate des données après usage
- Protection des dumps mémoire contre l'exposition de données

### 4.3 Chiffrement en Transit

#### 4.3.1 Communications Client-Serveur
- TLS 1.3 obligatoire avec suites cryptographiques restrictives
- Certificate pinning pour les applications mobiles
- Perfect Forward Secrecy (PFS) pour toutes les connexions
- HTTP Strict Transport Security (HSTS) avec includeSubDomains
- Validation stricte des certificats côté client

#### 4.3.2 Communications Vers Services Externes
- Validation des certificats FCM/APNS avec certificate pinning
- Chiffrement des payloads sensibles avant transmission
- Utilisation de canaux sécurisés pour les clés d'API
- Monitoring des connexions pour détecter les anomalies
- Timeout appropriés pour éviter les connexions pendantes

## 5. Résilience et Disponibilité

### 5.1 Architecture Tolérante aux Pannes

#### 5.1.1 Supervision OTP
- Stratégies de supervision adaptées aux workers de notification
- Isolation des défaillances par type de notification (FCM/APNS)
- Redémarrage automatique avec backoff exponentiel
- Circuit breakers pour les services externes indisponibles
- Monitoring de la santé des processus critiques

#### 5.1.2 Distribution et Clustering
- Clustering sécurisé entre nœuds Elixir avec authentification
- Distribution intelligente des charges de notification
- Réplication des données critiques entre nœuds
- Détection automatique des nœuds défaillants
- Récupération transparente après partition réseau

### 5.2 Protection Contre les Surcharges

#### 5.2.1 Rate Limiting Granulaire
- Par utilisateur : 100 notifications par heure
- Par appareil : 50 notifications par heure
- Par type de notification : limites adaptées à la criticité
- Limitation globale pour éviter la saturation des services externes
- Files d'attente prioritaires pour les notifications critiques

#### 5.2.2 Gestion de la Charge
- Batch processing intelligent pour optimiser les appels API
- Back pressure pour contrôler la charge sur les services externes
- Mécanismes de délestage en cas de surcharge critique
- Monitoring temps réel des quotas FCM/APNS
- Dégradation gracieuse avec notification des utilisateurs

### 5.3 Récupération après Incident

#### 5.3.1 Persistance et Retry
- Persistance des notifications en attente de livraison
- Mécanismes de retry avec backoff exponentiel (max 5 tentatives)
- Queue de rattrapage pour les notifications échouées
- Expiration automatique des notifications obsolètes
- Métriques de succès/échec pour monitoring

#### 5.3.2 Objectifs de Disponibilité
- RTO (Recovery Time Objective) : < 5 minutes
- RPO (Recovery Point Objective) : < 1 minute de perte potentielle
- Disponibilité cible : 99.5% (moins de 3.6h d'indisponibilité par mois)
- Tests de récupération mensuels
- Documentation des procédures d'urgence

## 6. Protection Contre les Menaces

### 6.1 Détection des Abus

#### 6.1.1 Monitoring Comportemental
- Détection des patterns d'envoi anormaux (spam de notifications)
- Identification des tentatives de DoS via notifications
- Surveillance des taux d'échec anormalement élevés
- Analyse des patterns de connexion suspects
- Alertes sur les volumes de notification inhabituels

#### 6.1.2 Protection Anti-Spam
- Limitation du taux de notifications par utilisateur/conversation
- Détection des notifications dupliquées ou répétitives
- Filtrage intelligent basé sur le contenu des notifications
- Quarantaine temporaire des comptes suspects
- Mécanismes de signalement d'abus par les utilisateurs

### 6.2 Sécurité des APIs

#### 6.2.1 Validation et Sanitisation
- Validation stricte de tous les paramètres d'entrée
- Sanitisation des données avant traitement
- Protection contre l'injection de commandes dans les templates
- Validation des formats JSON et gRPC
- Échappement des caractères spéciaux dans les notifications

#### 6.2.2 Protection Contre les Attaques
- Protection CSRF pour les endpoints sensibles
- Validation des origins pour les requêtes cross-origin
- Protection contre les attaques de timing via normalisation
- Détection des tentatives d'énumération d'utilisateurs
- Logging sécurisé des tentatives d'accès malveillant

### 6.3 Sécurité des Workers de Background

#### 6.3.1 Isolation des Processus
- Exécution des workers dans des processus isolés
- Limitation des ressources système par worker
- Timeout strict pour éviter les blocages
- Monitoring de l'utilisation mémoire/CPU
- Restart automatique en cas de comportement anormal

#### 6.3.2 Protection des Jobs Batch
- Validation de l'intégrité des données de job
- Prévention de l'exécution de jobs malveillants
- Isolation des jobs par type et priorité
- Audit trail complet des exécutions de jobs
- Mécanismes d'annulation d'urgence

## 7. Intégration avec les Autres Services

### 7.1 Communication avec le Service de Messagerie

#### 7.1.1 Réception Sécurisée des Événements
- Authentification mutuelle gRPC avec certificats
- Validation de l'origine et de l'intégrité des événements
- Déduplication des événements pour éviter les notifications multiples
- Rate limiting des événements entrants par service
- Circuit breaker en cas de volume d'événements anormal

#### 7.1.2 Traitement des Données de Message
- Pas de stockage du contenu des messages
- Validation des références aux conversations et messages
- Respect des permissions d'accès aux métadonnées
- Anonymisation des données sensibles dans les logs
- Expiration automatique des références obsolètes

### 7.2 Intégration avec User Service

#### 7.2.1 Validation des Utilisateurs
- Vérification des identités via tokens JWT
- Synchronisation sécurisée des paramètres utilisateur
- Respect des préférences de confidentialité
- Propagation des événements de blocage/déblocage
- Validation des permissions pour les opérations sensibles

#### 7.2.2 Gestion des Relations Utilisateur
- Application des règles de blocage pour les notifications
- Respect des paramètres de visibilité
- Filtrage des notifications selon les relations
- Synchronisation des changements de profil
- Protection contre l'inférence de relations

### 7.3 Intégration avec Auth Service

#### 7.3.1 Authentification et Autorisation
- Validation des tokens JWT à chaque requête sensible
- Vérification des permissions granulaires
- Gestion des sessions d'appareil multiples
- Révocation immédiate après déconnexion
- Audit des accès aux fonctions administratives

#### 7.3.2 Gestion des Appareils
- Synchronisation sécurisée des appareils enregistrés
- Validation de l'appartenance appareil-utilisateur
- Détection des appareils compromis ou suspects
- Révocation coordonnée des accès
- Protection contre l'usurpation d'appareil

## 8. Détection et Réponse aux Incidents

### 8.1 Monitoring et Alertes

#### 8.1.1 Métriques de Sécurité
- Taux d'échec des notifications par plateforme
- Nombre de tokens invalides détectés
- Tentatives d'accès non autorisé aux préférences
- Volume de notifications par utilisateur (détection spam)
- Délais de livraison anormaux (potentielle attaque)

#### 8.1.2 Détection d'Anomalies
- Profils de base pour l'utilisation normale
- Alertes sur les écarts statistiques significatifs
- Détection des patterns d'attaque connus
- Corrélation entre événements système et sécurité
- Alertes temps réel pour les incidents critiques

### 8.2 Classification et Réponse aux Incidents

#### 8.2.1 Niveaux de Gravité
- **Critique** : Fuite de tokens de notification ou accès non autorisé aux préférences
- **Élevé** : Spam massif de notifications ou contournement du rate limiting
- **Moyen** : Défaillance des services externes ou dégradation de performance
- **Faible** : Erreurs mineures n'affectant pas la sécurité ou la fonctionnalité

#### 8.2.2 Procédures de Réponse
- Escalade automatique selon la gravité
- Procédures d'isolation des comptes compromis
- Révocation d'urgence des tokens suspects
- Communication coordonnée avec les équipes
- Documentation et analyse post-incident

### 8.3 Forensique et Investigation

#### 8.3.1 Conservation des Preuves
- Logs sécurisés avec intégrité garantie
- Snapshots des états système lors d'incidents
- Corrélation temporelle des événements
- Chaîne de custody pour les preuves numériques
- Anonymisation des données personnelles dans les investigations

#### 8.3.2 Analyse des Incidents
- Outils d'analyse automatisée des logs
- Reconstruction de chronologie des événements
- Identification des vecteurs d'attaque
- Évaluation de l'impact sur les utilisateurs
- Recommandations de remédiation

## 9. Développement Sécurisé

### 9.1 Pratiques de Développement

#### 9.1.1 Code Sécurisé pour Elixir
- Utilisation des patterns OTP pour l'isolation
- Validation stricte avec Ecto changesets
- Gestion explicite des erreurs et timeouts
- Protection contre les injections dans les requêtes
- Tests de sécurité automatisés dans la CI/CD

#### 9.1.2 Gestion des Secrets
- Utilisation de Google Secret Manager
- Pas de secrets en dur dans le code
- Rotation automatique des secrets critiques
- Accès aux secrets limité par environnement
- Audit des accès aux secrets

### 9.2 Tests de Sécurité

#### 9.2.1 Tests Automatisés
- Tests unitaires pour les fonctions de sécurité
- Tests d'intégration pour les flux critiques
- Tests de charge pour valider le rate limiting
- Tests de chaos pour la résilience
- Scans de vulnérabilités automatisés

#### 9.2.2 Revues de Sécurité
- Revues de code obligatoires pour les composants sensibles
- Audit des dépendances externes
- Validation des configurations de sécurité
- Tests de pénétration réguliers
- Évaluation de la surface d'attaque

## 10. Protection des Données Personnelles

### 10.1 Conformité RGPD

#### 10.1.1 Principes Appliqués
- Minimisation des données collectées pour les notifications
- Finalités strictement définies pour chaque donnée
- Limitation de la durée de conservation (max 30 jours pour l'historique)
- Pseudonymisation des identifiants dans les logs
- Consentement explicite pour les notifications non essentielles

#### 10.1.2 Droits des Utilisateurs
- Accès aux préférences et historique de notifications
- Rectification des paramètres de notification
- Effacement des données d'appareil et préférences
- Portabilité des paramètres de notification
- Opposition au traitement pour marketing

### 10.2 Transparence et Contrôle

#### 10.2.1 Paramètres de Confidentialité
- Contrôle granulaire des types de notifications
- Gestion des horaires "Ne pas déranger"
- Préférences par conversation et global
- Visibilité sur les appareils enregistrés
- Options de suppression des données

#### 10.2.2 Information des Utilisateurs
- Documentation claire sur les données collectées
- Notifications des changements de politique
- Alertes sur les activités suspectes sur le compte
- Transparence sur les échecs de livraison
- Options pour les notifications de sécurité

## 11. Sauvegarde et Récupération

### 11.1 Protection des Données Critiques

#### 11.1.1 Stratégie de Sauvegarde
- Sauvegarde quotidienne des préférences utilisateur
- Sauvegarde des tokens d'appareil avec chiffrement renforcé
- Pas de sauvegarde de l'historique détaillé (conformité RGPD)
- Séparation géographique des sauvegardes
- Tests de restauration mensuels

#### 11.1.2 Rétention des Données
- Préférences utilisateur : conservation jusqu'à suppression du compte
- Tokens d'appareil : suppression après 90 jours d'inactivité
- Historique de notifications : maximum 30 jours
- Logs de sécurité : 90 jours pour investigation
- Métriques agrégées : 2 ans pour analyse de tendances

### 11.2 Continuité de Service

#### 11.2.1 Haute Disponibilité
- Architecture multi-région pour la résilience
- Réplication des données critiques en temps réel
- Basculement automatique entre régions
- Load balancing avec health checks
- Monitoring continu de la disponibilité

#### 11.2.2 Plan de Récupération d'Urgence
- Procédures documentées pour chaque type d'incident
- Scripts de restauration automatisés
- Équipes d'astreinte formées aux procédures
- Tests de récupération trimestriels
- Communication de crise avec les utilisateurs

---

## Annexes

### A. Matrice des Risques de Sécurité

| Risque | Probabilité | Impact | Mesures de Contrôle |
|--------|-------------|--------|---------------------|
| Fuite de tokens FCM/APNS | Faible | Critique | Chiffrement des tokens, rotation des clés, monitoring |
| Spam de notifications | Moyenne | Élevé | Rate limiting, détection d'anomalies, quarantaine |
| Déni de service sur FCM/APNS | Moyenne | Élevé | Circuit breakers, retry logic, queues de backup |
| Accès non autorisé aux préférences | Faible | Moyen | Authentification forte, contrôle d'accès granulaire |
| Compromission des clés API externes | Très faible | Critique | Secret Manager, rotation automatique, monitoring |
| Manipulation des statuts de livraison | Faible | Faible | Validation d'intégrité, audit des modifications |

### B. Métriques de Sécurité

| Métrique | Objectif | Fréquence de Mesure |
|----------|----------|---------------------|
| Taux de livraison des notifications | > 95% | Temps réel |
| Détection des tokens invalides | < 1% des tentatives | Quotidienne |
| Temps de détection des anomalies | < 5 minutes | Par incident |
| Disponibilité du service | > 99.5% | Mensuelle |
| Couverture des tests de sécurité | > 90% du code critique | Par release |
| Conformité aux limites de rate limiting | 100% | Continue |

### C. Contacts d'Urgence

| Rôle | Responsabilité | Contact |
|------|----------------|---------|
| Responsable Sécurité | Coordination incidents sécurité | [Email sécurisé] |
| Admin Système | Gestion infrastructure | [Contact d'astreinte] |
| Lead Développeur | Correctifs d'urgence | [Contact technique] |
| Responsable Données | Conformité RGPD | [Contact DPO] |

### D. Références

- Firebase Cloud Messaging Security Best Practices
- Apple Push Notification Service Security Guide
- OWASP Mobile Security Testing Guide
- NIST Cybersecurity Framework
- RGPD - Règlement Général sur la Protection des Données
- Elixir Security Guidelines