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

Mobile (Phase 6, pas encore développé) :

```bash
docker compose --profile mobile up mobile
```

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
