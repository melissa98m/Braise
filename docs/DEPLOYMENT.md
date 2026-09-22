# Guide de déploiement — VPS de production

P4.4 du plan d'action post-MVP (`docs/ROADMAP.md`) : les scripts et la checklist pour sortir du
Docker Compose local vers un vrai VPS, conformément au choix technique du cahier des charges
(D.7 : VPS auto-géré Hetzner/OVH/Scaleway + Docker, D.11 : stack recommandée MVP).

**Ce document ne déclenche rien tout seul.** Rien ici n'a été exécuté contre une vraie
infrastructure depuis cet environnement de développement (pas de VPS disponible pour le tester) —
chaque fichier a été relu avec soin et la fusion Docker Compose elle-même a été validée
(`docker compose -f docker-compose.yml -f docker-compose.prod.yml config`), mais un vrai
déploiement engage un coût réel et un compte réel : à faire déclencher volontairement, étape par
étape, pas en pilote automatique.

## Vue d'ensemble

```
Internet ──▶ Caddy (80/443, TLS auto) ──▶ backend:8000   (api.<domaine>)
                                     └──▶ minio:9000      (objects.<domaine>, URLs pré-signées)
                                     └──▶ fichiers statiques Flutter web (app.<domaine>)

db, MinIO console (9001), Adminer (8081), Uptime Kuma (8082) : jamais publics — 127.0.0.1
uniquement, accès via tunnel SSH. Ollama (11434, optionnel — voir § 6) : même règle.
```

## 1. Provisionner le VPS

Choisir un fournisseur (D.7 : Hetzner CPX21/CPX31, OVH, Scaleway — privilégier une localisation
proche des utilisateurs visés, pertinent pour la latence et la conformité RGPD), Ubuntu 22.04 ou
24.04 LTS.

```bash
scp infra/deploy/provision.sh root@<ip-du-vps>:/root/
ssh root@<ip-du-vps> "bash provision.sh"
```

Ce script (idempotent, relisible avant de le lancer) :
- met le système à jour et active les mises à jour de sécurité automatiques ;
- installe Docker Engine + le plugin Compose (script officiel Docker) ;
- configure `ufw` pour n'exposer que SSH/80/443 ;
- crée un utilisateur `bresonne` non-root, membre du groupe `docker`.

**Avant de fermer la session root** : copier une clé SSH publique dans
`/home/bresonne/.ssh/authorized_keys` et vérifier que la connexion par clé fonctionne. Ne jamais
désactiver l'accès root par mot de passe avant d'avoir confirmé cet accès de secours.

## 2. DNS

Pointer trois sous-domaines vers l'IP du VPS (enregistrements A, TTL bas le temps de valider) :

| Sous-domaine | Sert à |
|---|---|
| `api.<domaine>` | Le backend FastAPI |
| `objects.<domaine>` | Les photos privées (URLs pré-signées MinIO) |
| `app.<domaine>` | L'app web Flutter |

Caddy ne délivrera de certificat TLS qu'une fois ces domaines effectivement résolus vers ce
serveur (challenge ACID HTTP-01) — les démarrer avant que le DNS ait propagé fait échouer Caddy
au démarrage, sans dégât, il suffit de relancer une fois le DNS propagé.

## 3. Secrets

```bash
cp .env.prod.example .env
```

Puis remplacer **chaque** `CHANGE_ME` par une vraie valeur générée, jamais les valeurs de dev :

```bash
openssl rand -base64 24    # POSTGRES_PASSWORD, MINIO_ROOT_USER/PASSWORD
openssl rand -base64 48    # JWT_SECRET
python3 -c "import secrets, base64; print(base64.b64encode(secrets.token_bytes(32)).decode())"  # MINIO_KMS_SECRET_KEY
```

Points d'attention spécifiques à la prod (voir les commentaires dans `.env.prod.example`) :
- `DEBUG_OTP=false` sans exception — sinon le code OTP est renvoyé dans la réponse API, ce qui
  annule toute vérification. Nécessite un vrai fournisseur SMS pour être utilisable avec de
  vrais utilisateurs (hors périmètre gratuit/local du MVP, voir le backlog KYC de
  `docs/ROADMAP.md`).
- `ENABLE_DEBUG_SUBSCRIPTION_ENDPOINT=false` sans exception — sinon `POST
  /subscriptions/debug-activate` reste joignable et accorde le Premium à n'importe quel compte
  authentifié sans paiement. Nécessite une vraie intégration StoreKit/Play Billing (cahier des
  charges D.8) pour être remplacé par un vrai flux d'achat.
- `MINIO_PUBLIC_SECURE=true` — sépare désormais le schéma du client interne MinIO (reste `http`,
  trafic conteneur-à-conteneur en clair sur le réseau Docker privé) de celui du client public
  (doit suivre le vrai schéma externe, `https` derrière Caddy) : voir `backend/app/core/config.py`.
  Sans ce réglage distinct, les URLs pré-signées pointaient en `http` même derrière un reverse
  proxy TLS — bloquées par le navigateur (contenu mixte) ou rejetées par MinIO (signature pour le
  mauvais schéma).

## 4. Construire l'app web Flutter

Le conteneur `mobile` du `docker-compose.yml` de base est un outil de **dev** (`flutter create`/
`flutter run`, hot-reload) — jamais démarré en prod. Construire un artefact statique à la place :

```bash
docker compose run --rm --entrypoint bash mobile -c "cd /app/bresonne_app && flutter build web --release"
```

Le résultat (`mobile/bresonne_app/build/web/`) est monté en lecture seule dans le conteneur Caddy
(voir `docker-compose.prod.yml`) — rien de plus à faire, `docker compose up` le sert directement.

## 5. Démarrer

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d db minio minio-init
docker compose -f docker-compose.yml -f docker-compose.prod.yml run --rm backend alembic upgrade head
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

Vérifications :
```bash
curl https://api.<domaine>/health          # {"status":"ok"}
curl -I https://app.<domaine>/              # 200, certificat valide
```

## 6. Sauvegardes, supervision, KPIs (déjà construits, juste à pointer vers ce serveur)

- **Sauvegardes** (`infra/backup/`, déjà testées par restauration en local — voir
  `docs/ROADMAP.md` P0) : fonctionnent à l'identique sur le VPS. Reste à faire, spécifique à la
  prod : synchroniser `backup_data` vers un **second** emplacement physique (rclone/rsync vers un
  Storage Box séparé, D.7) — un volume Docker sur le même disque que la base ne protège pas
  contre une panne du serveur lui-même. Non fait ici : nécessite de choisir/payer ce second
  stockage, décision produit, pas une valeur par défaut à imposer.
- **Supervision** (Uptime Kuma, déjà en place) : accès via tunnel SSH uniquement en prod
  (`ssh -L 8082:localhost:8082 bresonne@<ip>`), jamais exposé publiquement (voir
  `docker-compose.prod.yml`). Ajouter un 4ᵉ moniteur HTTPS sur `https://api.<domaine>/health` en
  plus des 3 déjà documentés dans `README.md`.
- **Adminer** : même règle, tunnel SSH uniquement (`ssh -L 8081:localhost:8081 bresonne@<ip>`).
- **Ollama** (question du jour personnalisée, optionnel — voir `README.md`) : off par défaut
  (`OLLAMA_ENABLED=false`), donc rien à faire pour un VPS qui ne l'active pas. Si activé
  (`docker compose -f docker-compose.yml -f docker-compose.prod.yml --profile ai up -d ollama
  ollama-init`), `docker-compose.prod.yml` verrouille déjà son port sur `127.0.0.1` — vérifié par
  `docker compose ... config`, pas supposé (voir `CLAUDE.md`). Prévoir la RAM/le CPU du modèle en
  plus du reste de la stack avant de l'activer sur un VPS modeste.
- **KPIs** (`backend/scripts/compute_kpis.py`, P4.1) : `docker compose -f docker-compose.yml -f
  docker-compose.prod.yml run --rm backend python scripts/compute_kpis.py` — fonctionne à
  l'identique, aucune adaptation nécessaire.

## 7. Continuité technologique (cahier des charges C.3)

Ce déploiement ne change aucune brique retenue en D.11 — même Postgres, même FastAPI, même MinIO,
même WebSockets custom, même modèle de modération scikit-learn : uniquement l'endroit où ça
tourne (VPS au lieu du poste de dev) et l'ajout de Caddy comme reverse proxy/TLS, cohérent avec
D.7 qui recommandait déjà "éventuellement épaulé par un PaaS self-hosted".

## Ce qui reste volontairement hors de ce guide

- **CGU / politique de confidentialité** : document juridique, pas un artefact technique — à
  rédiger avec l'porteur du projet (ou un juriste), pas improvisé ici.
- **Un vrai fournisseur SMS** (remplacer `DEBUG_OTP`) : entraîne un coût récurrent, cahier des
  charges D.6/D.12 — décision à prendre au moment de vraiment ouvrir une bêta à des inconnus, pas
  avant.
- **CI/CD** (déploiement automatisé sur push) : ce guide décrit une procédure manuelle
  volontairement — automatiser le déploiement d'un secret réel n'est pas un premier pas
  raisonnable avant d'avoir fait le premier déploiement manuel au moins une fois.
