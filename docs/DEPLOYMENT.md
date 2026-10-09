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

Une seule origine HTTPS pour tout — un seul nom de domaine, un seul certificat, aucun CORS :

```
Internet ──▶ Caddy (80/443, TLS auto, en-têtes de sécurité + CSP stricte)
               ├─ /                    → app web Flutter (build statique, aucune ressource tierce)
               ├─ /api/*               → backend:8000 (préfixe retiré ; WebSocket compris)
               ├─ /api/staff/          → tableau de bord de modération (servi par le backend)
               └─ /<bucket>/*          → minio:9000 (lectures signées GET/HEAD uniquement)

db, MinIO console (9001), Adminer (8081), Uptime Kuma (8082) : jamais publics — 127.0.0.1
uniquement, accès via tunnel SSH. Ollama (11434, optionnel — voir § 6) : même règle.
```

L'app ne contacte aucun domaine tiers depuis le navigateur des utilisateur·rice·s : CanvasKit,
polices de la charte et polices de secours (emoji, symboles) sont servis par ce serveur (voir
`infra/deploy/build_web.sh`, `mobile/fetch_fallback_fonts.sh`). Vérifié en local sur cette même
configuration Caddy (parcours complet dans Chrome : zéro requête externe, zéro violation de CSP).

## 1. Provisionner le VPS (LWS)

Hébergeur retenu : **LWS** (déjà nommé dans les mentions légales et la politique de
confidentialité — société et datacenters français). Une offre VPS sous Ubuntu 22.04 ou 24.04 LTS,
avec au moins 2 vCPU / 4 Go de RAM (Postgres, MinIO, Redis, backend, Caddy, sauvegardes, Uptime
Kuma ; prévoir plus si Ollama est activé).

```bash
scp infra/deploy/provision.sh root@<ip-du-vps>:/root/
ssh root@<ip-du-vps> "bash provision.sh"
```

Ce script (idempotent, relisible avant de le lancer) :
- met le système à jour et active les mises à jour de sécurité automatiques ;
- installe Docker Engine + le plugin Compose (script officiel Docker) ;
- configure `ufw` pour n'exposer que SSH/80/443 ;
- crée un utilisateur `bresonne` non-root, membre du groupe `docker`.

Si l'offre LWS ajoute son propre pare-feu réseau (panneau client), y ouvrir aussi 22/80/443 — les
deux se cumulent.

**Avant de fermer la session root** : copier une clé SSH publique dans
`/home/bresonne/.ssh/authorized_keys` et vérifier que la connexion par clé fonctionne. Ne jamais
désactiver l'accès root par mot de passe avant d'avoir confirmé cet accès de secours.

## 2. DNS

Un seul enregistrement pour l'app :

| Type | Nom | Valeur | Sert à |
|---|---|---|---|
| A | `<domaine>` (ou un sous-domaine, ex. `app.<domaine>`) | IP du VPS | App, API, photos |

Caddy n'obtient le certificat TLS qu'une fois ce nom effectivement résolu vers ce serveur
(challenge ACME HTTP-01) — le démarrer avant la propagation DNS le fait échouer sans dégât, il
suffit de relancer.

Pour l'envoi des codes de connexion par **Resend**, ajouter aussi les enregistrements que Resend
affiche à la création du domaine d'envoi (SPF et DKIM, en TXT/CNAME, plus un DMARC recommandé
`_dmarc.<domaine>` en TXT, ex. `v=DMARC1; p=none; rua=mailto:<adresse>`). Sans eux, Resend
n'envoie qu'à l'adresse du compte, et les codes finiraient en courriers indésirables. Choisir la
**région UE** à la création du domaine chez Resend, et accepter son accord de traitement des
données (DPA) — voir `docs/DPIA.md`.

## 3. Secrets

```bash
cp .env.prod.example .env
```

Puis remplacer **chaque** `CHANGE_ME` et `bresonne.example` par une vraie valeur, jamais les
valeurs de dev. **Le backend refuse de démarrer** tant qu'il en reste (`ENVIRONMENT=beta` ou
`production`, voir `backend/app/core/config.py`) : une erreur de configuration se voit
immédiatement dans `docker compose logs backend`, pas après coup.

```bash
openssl rand -base64 24    # POSTGRES_PASSWORD, MINIO_ROOT_USER/PASSWORD
openssl rand -base64 48    # JWT_SECRET
python3 -c "import secrets, base64; print(base64.b64encode(secrets.token_bytes(32)).decode())"  # MINIO_KMS_SECRET_KEY
```

Clés VAPID (notifications push) : commande dans `.env.example`. Clé Resend : créer une clé API
avec la seule permission « Sending access », à mettre dans `SMTP_PASSWORD`.

Points d'attention (voir aussi les commentaires dans `.env.prod.example`) :
- `ENVIRONMENT=beta` pour la bêta fermée : l'endpoint Premium de debug y reste autorisé (choix
  produit — les testeur·se·s essaient le Premium sans payer). `production` l'interdit.
- `DEBUG_OTP=false` — imposé hors développement de toute façon.
- `MINIO_PUBLIC_ENDPOINT` = le domaine de l'app (les photos sont sur la même origine) et
  `MINIO_PUBLIC_SECURE=true` — sinon les URLs pré-signées pointent en `http` (contenu mixte bloqué)
  ou sont signées pour le mauvais hôte.

## 4. Construire l'app web Flutter

Le conteneur `mobile` du `docker-compose.yml` de base est un outil de **dev**, jamais démarré en
prod. On construit un build statique, de préférence sur le poste de dev (l'image Flutter fait
plusieurs Go, inutile sur le VPS) puis on le copie :

```bash
bash infra/deploy/build_web.sh
rsync -az --delete mobile/bresonne_app/build/web/ bresonne@<ip>:bresonne/mobile/bresonne_app/build/web/
```

Le script fixe les deux options à ne jamais oublier : `API_BASE_URL=/api` (API sur la même
origine) et `--no-web-resources-cdn` (CanvasKit servi par nous), et télécharge les polices de
secours — sans elles la CSP du Caddyfile bloquerait le démarrage de l'app (page blanche). Le
résultat est monté en lecture seule dans le conteneur Caddy (voir `docker-compose.prod.yml`).

## 5. Démarrer

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d db minio minio-init redis
docker compose -f docker-compose.yml -f docker-compose.prod.yml run --rm backend alembic upgrade head
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

La base de bêta démarre **vide** (choix produit) : ne jamais lancer les scripts de seed
(`scripts/seed_*.py`) sur ce serveur — de vrais testeur·se·s swiperaient des profils fictifs.
Donner le rôle staff à son propre compte une fois inscrit·e via l'app :
`docker compose -f docker-compose.yml -f docker-compose.prod.yml run --rm backend python scripts/grant_staff.py <email>`.

Vérifications :
```bash
curl https://<domaine>/api/health          # {"status":"ok"}
curl -I https://<domaine>/                 # 200, en-têtes Content-Security-Policy et Strict-Transport-Security
curl -I https://<domaine>/api/docs         # 404 : Swagger n'est servi qu'en développement
```
Puis une vraie inscription depuis un téléphone : le code doit arriver par email (vérifier aussi
les courriers indésirables), et le tableau de bord staff répondre sur `https://<domaine>/api/staff/`.

## 6. Sauvegardes, supervision, KPIs (déjà construits, juste à pointer vers ce serveur)

- **Sauvegardes** (`infra/backup/`, déjà testées par restauration en local — voir
  `docs/ROADMAP.md` P0) : fonctionnent à l'identique sur le VPS. Reste à faire, spécifique à la
  prod : synchroniser `backup_data` vers un **second** emplacement physique (rclone/rsync vers un
  Storage Box séparé, D.7) — un volume Docker sur le même disque que la base ne protège pas
  contre une panne du serveur lui-même. Non fait ici : nécessite de choisir/payer ce second
  stockage, décision produit, pas une valeur par défaut à imposer.
- **Supervision** (Uptime Kuma, déjà en place) : accès via tunnel SSH uniquement en prod
  (`ssh -L 8082:localhost:8082 bresonne@<ip>`), jamais exposé publiquement (voir
  `docker-compose.prod.yml`). Ajouter un moniteur HTTPS externe sur `https://<domaine>/api/health`
  en plus de ceux posés par `infra/uptime-kuma/setup.py`.
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

- **Relecture juridique** des CGU / de la politique de confidentialité (`docs/legal/`, marquées
  « version bêta ») : à faire avant d'ouvrir au-delà d'un cercle restreint de testeur·se·s.
- **CI/CD** (déploiement automatisé sur push) : ce guide décrit une procédure manuelle
  volontairement — automatiser le déploiement d'un secret réel n'est pas un premier pas
  raisonnable avant d'avoir fait le premier déploiement manuel au moins une fois.
