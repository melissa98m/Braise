# Braise

Application de rencontre où l'affinité précède le physique. Cahier des charges complet et
maquettes fournis séparément ; voir `docs/ROADMAP.md` pour le plan d'exécution phase par phase et
`docs/DESIGN_TOKENS.md` pour la charte graphique.

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
```

Mobile (Phase 6, pas encore développé) :

```bash
docker compose --profile mobile up mobile
```

## Stack (figée, cahier des charges section D.11)

Flutter · FastAPI · PostgreSQL · WebSockets custom · MinIO · scikit-learn maison. Aucun service
payant tant que le MVP n'est pas validé en local (OTP, paiement et push sont stubés — voir
`docs/ROADMAP.md`).
