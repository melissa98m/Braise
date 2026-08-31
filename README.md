# Braise

Application de rencontre où l'affinité précède le physique. Cahier des charges complet et
maquettes fournis séparément ; voir `docs/ROADMAP.md` pour le plan d'exécution phase par phase,
`docs/DESIGN_TOKENS.md` pour la charte graphique, et `docs/V2_FEATURES.md` pour ce qu'il reste à
construire au-delà du MVP actuel (KYC, modération humaine, paiement/push/SMS réels, etc.).

## Démarrer en local (gratuit, 100 % Docker)

```bash
cp .env.example .env   # déjà fait si tu reprends ce repo tel quel
docker compose up -d db minio minio-init
docker compose up backend
```

- API : http://localhost:8010 — doc interactive sur http://localhost:8010/docs
- Health check : `curl localhost:8010/health`
- Console MinIO : http://localhost:9001 (identifiants dans `.env`)
- Adminer (inspection Postgres) : http://localhost:8081 (système `PostgreSQL`, serveur `db`)

> Ports choisis pour éviter les conflits avec d'autres projets locaux sur cette machine (8000 et
> 8080 sont déjà pris). En cas de nouveau conflit : `ss -ltn` puis ajuster `docker-compose.yml`.

Première migration + tests :

```bash
docker compose run --rm backend alembic revision --autogenerate -m "create users table"
docker compose run --rm backend alembic upgrade head
docker compose run --rm backend pytest
docker compose run --rm backend ruff check .   # lint (P5.3, backend/ruff.toml)
```

Mobile (Flutter web) :

```bash
docker compose --profile mobile up mobile
```

- App : http://localhost:5000

## Bêta-test entre proches sur le réseau local

Pas de VPS ni de domaine (voir `docs/V2_FEATURES.md`) : pour qu'un·e proche sur le même Wi-Fi/LAN
puisse utiliser l'app depuis son propre téléphone/PC, il faut lui donner l'IP locale de cette
machine, pas `localhost` (qui sur son appareil ne désignerait que lui-même).

1. Trouver l'IP locale de cette machine : `hostname -I` (Linux) — premier résultat, souvent en
   `192.168.x.x`.
2. Dans `.env` (pas `.env.example`, qui reste générique) :
   - `MINIO_PUBLIC_ENDPOINT=<ip-locale>:9000` (sinon les photos privées ne s'affichent que sur ce
     poste).
   - `CORS_ORIGINS=http://localhost:5000,http://<ip-locale>:5000` (sinon le navigateur du
     testeur bloque les appels vers l'API).
   - `MOBILE_MODE=serve` — **indispensable**, pas juste une optimisation :
     `flutter run -d web-server` (le mode par défaut, `MOBILE_MODE=dev`) ouvre une connexion
     WebSocket de debug vers l'outil Flutter pour le hot reload ; cette connexion échoue
     silencieusement quand la page est chargée depuis une autre origine que celle attendue par le
     harnais de debug (DWDS), et la page reste blanche pour qui accède via l'IP LAN — vécu
     directement en testant ce guide. `serve` fait un vrai build de production
     (`flutter build web`), servi en fichiers statiques sans aucune connexion de debug.
3. Reconstruire et redémarrer pour appliquer (`MOBILE_MODE` est lu par `mobile/entrypoint.sh`,
   copié dans l'image au build — un simple redémarrage ne suffit pas) :
   ```bash
   docker compose build mobile
   docker compose up -d --force-recreate backend
   docker compose --profile mobile up -d --force-recreate mobile
   ```
   Le build de production prend ~30s (visible dans `docker compose logs mobile`, cherche
   "Bêta (build de production) servie") avant que le port 5000 ne réponde correctement.
4. Donner aux testeur·se·s l'adresse `http://<ip-locale>:5000` — même réseau Wi-Fi requis.

L'app Flutter (`lib/api/api_config.dart`) résout déjà l'hôte de l'API dynamiquement depuis l'URL
de la page (`Uri.base.host`) : aucune modification de code nécessaire pour ça, seulement les
variables d'environnement ci-dessus. `DEBUG_OTP=true` reste actif (défaut de `.env.example`) : le
code de vérification s'affiche directement dans l'app, pas besoin d'un vrai SMS pour ce type de
bêta.

### Données de test

Pour tester chaque fonctionnalité sans tout construire à la main (swiper des dizaines de profils
avant d'obtenir un match, attendre des jours de questions quotidiennes pour débloquer un profil
privé...) :

```bash
docker compose run --rm backend python scripts/seed_beta_tester.py
```

Crée 6 profils candidats variés (genre, âge, ville — de quoi tester les filtres de découverte,
voir `services/geo.py`) et un compte testeur (`+33600000099`) déjà dans un état riche : un match
déjà débloqué avec 2 messages non lus et une vraie photo privée visible (`Alice`), un match en
cours à 2/5 flammes avec la question du jour encore disponible (`Bruno`), et 4 profils jamais
swipés pour tester la découverte/le matching à froid. Se connecter avec `+33600000099` — le code
s'affiche directement dans l'app (`DEBUG_OTP=true`). Idempotent pour les profils (même numéro à
chaque lancement) ; le déblocage forcé et le flame_count partiel sont réappliqués à chaque
exécution, sans conséquence si déjà en place.

Pour revenir au mode développement normal (hot reload) ensuite : repasser `MOBILE_MODE=dev` (ou
retirer la ligne) dans `.env`, puis `docker compose build mobile && docker compose --profile
mobile up -d --force-recreate mobile`.

## Sauvegardes & supervision (durcissement opérationnel, cahier des charges B.3/D.7/D.12)

Sauvegardes automatisées (dump Postgres + miroir des photos MinIO) et **testées par restauration
réelle**, pas juste supposées fonctionner — voir `infra/backup/` :

```bash
docker compose up -d backup          # service en continu, 1 sauvegarde/jour (BACKUP_INTERVAL_SECONDS)
docker compose run --rm backup /scripts/backup.sh         # sauvegarde à la demande
docker compose run --rm backup /scripts/test_restore.sh   # sauvegarde -> restauration dans une base/bucket jetables -> vérification -> nettoyage
```

Supervision basique (Uptime Kuma, gratuit, auto-hébergé) :

```bash
docker compose up -d uptime-kuma
```

- Dashboard : http://localhost:8082 — au premier démarrage, créer le compte admin puis ajouter 3
  moniteurs : HTTP `http://backend:8000/health`, HTTP `http://minio:9000/minio/health/live`, TCP
  `db:5432`, avec une notification (email/webhook) en cas d'échec.

Détail des risques couverts et de ceux qui restent : `docs/DPIA.md`.

## KPIs de succès (cahier des charges A.10)

```bash
docker compose run --rm backend python scripts/compute_kpis.py
docker compose run --rm backend python scripts/compute_kpis.py --recent-days 30 --retention-days 30
```

Calcule les 9 indicateurs (acquisition, activation, engagement, rétention, confiance,
monétisation, produit) directement depuis les tables existantes — pas de tableau de bord séparé
à maintenir. La rétention est un proxy documenté dans le script (pas de journal de
connexion/session dans ce projet), pas une vraie mesure DAU/MAU.

## Test de charge messagerie (cahier des charges B.1 Phase 4)

```bash
docker compose run --rm backend python scripts/load_test_messaging.py --matches 100
```

Simule N matchs concurrents (2 participants connectés en websocket chacun) et rapporte latence
de connexion/diffusion et taux de succès. C'est ce script qui a mis au jour l'épuisement du pool
de connexions DB corrigé dans `api/v1/messaging.py` — voir `docs/ROADMAP.md` (P4.3).

## Évaluation du modèle de modération (cahier des charges D.5, jalon B.2)

```bash
docker compose run --rm backend python scripts/evaluate_moderation_model.py
```

Validation croisée à 5 plis du classifieur de rancune au seuil de décision réellement utilisé en
production — précision/rappel/matrice de confusion, pas juste "ça s'entraîne sans erreur".
Résultats actuels et méthode : `docs/MODEL_EVALUATION.md`.

## Intégration continue

`.github/workflows/ci.yml` lance à chaque push/PR exactement les mêmes commandes Docker que
ci-dessus (backend : migrations + `ruff check .` + `pytest -q` ; mobile : `flutter analyze` +
`flutter test`) — pas de mock, les mêmes conteneurs Postgres/MinIO réels qu'en local. Gratuit
(minutes GitHub Actions), aucun service tiers payant.

## Stack (figée, cahier des charges section D.11)

Flutter · FastAPI · PostgreSQL · WebSockets custom · MinIO · scikit-learn maison. Aucun service
payant tant que le MVP n'est pas validé en local (OTP, paiement et push sont stubés — voir
`docs/ROADMAP.md`).
