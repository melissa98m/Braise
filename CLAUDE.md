# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Braise is a dating app whose product spec lives outside this repo (a 59-page cahier des charges +
4 design-mockup documents provided in chat, not committed as files). The core product idea:
affinity/personality is revealed before physical photos, gated by a "flames" gamification loop.
`docs/ROADMAP.md` is the phase-by-phase build plan derived from that spec; `docs/DESIGN_TOKENS.md`
is the dark/light color and typography system extracted from the mockups, to be used verbatim once
the Flutter UI (Phase 6) starts.

**Hard constraint for this project**: everything must run in Docker, and only free/local services
are used until the MVP is validated — no real SMS provider, no Apple/Google store accounts, no
Firebase, no paid cloud. See "Stubs" below for how each of those is faked for now.

## Commands

All commands run through Docker Compose from the repo root; there is no local Python/Node install
expected on the host beyond Docker itself.

```bash
# Start the datastore + object storage (Postgres, MinIO) and the API
docker compose up -d db minio minio-init
docker compose up backend            # foreground, logs visible; add -d to detach

# Migrations (Alembic, autogenerate from SQLAlchemy models in backend/app/models/)
docker compose run --rm backend alembic revision --autogenerate -m "message"
docker compose run --rm backend alembic upgrade head

# Tests (pytest, runs against the real Postgres/MinIO containers — not mocked)
docker compose run --rm backend pytest
docker compose run --rm backend pytest tests/test_auth_otp.py -v   # single file
docker compose run --rm backend pytest -k test_otp_round_trip      # single test

# Mobile (Flutter, Phase 6 only — not built out yet)
docker compose --profile mobile up mobile
```

Ports are deliberately non-default because this machine runs many other local projects:
- API: `localhost:8010` (Swagger UI at `/docs`)
- MinIO console: `localhost:9001`
- Adminer (Postgres inspector): `localhost:8081`
- Flutter web (Phase 6): `localhost:5000`

If a port conflicts with something else already running, check `ss -ltn` / `docker ps` before
picking a new one — don't assume the defaults below (8000, 8080, 5432) are free on this host.

## Architecture

**Backend** (`backend/`, FastAPI + SQLAlchemy + Alembic + Postgres, all in `backend/app/`):
- `main.py` wires every router in `api/v1/` into the app. Each product module from the spec has
  its own router file (`auth`, `profiles`, `discovery`, `messaging`, `moderation`,
  `subscriptions`), even before it has real logic — unbuilt modules currently expose a single
  `/ping` returning `{"module": ..., "status": "stub — Phase N"}` so the Swagger UI always lists
  the full intended API surface and it's obvious what phase built what.
- `core/config.py` — a single `Settings` (pydantic-settings) object read from `.env`, cached via
  `get_settings()`. Add new env-driven config here, not scattered `os.environ` reads.
- `core/security.py` — JWT creation/decoding and OTP code generation live together here (both are
  "auth primitives"); business logic that *uses* them (looking up/mutating a `User`) lives in
  `services/`, not in the router or in `core/`.
- `db/base.py` (declarative `Base`) and `db/session.py` (`get_db()` FastAPI dependency) are the only
  two files that touch SQLAlchemy engine/session setup. New models import `Base` from `db/base.py`
  and must be imported in `app/models/__init__.py` — Alembic's `env.py` only sees models that have
  been imported into `Base.metadata` by the time it runs.
- `services/` holds the actual business logic per module (e.g. `otp.py` for request/verify OTP,
  `storage.py` for the MinIO client). Routers stay thin: parse request → call a service → shape
  response.
- Migrations are in `app/migrations/versions/`, generated with `alembic revision --autogenerate`
  against the live dev Postgres — don't hand-write migration files; let Alembic diff the models.

**Stubs for what would normally cost money** (intentional, not TODOs to "fix" casually — see
`docs/ROADMAP.md` for when each graduates to the real thing):
- OTP: no SMS provider. `services/otp.py` logs the code to stdout and the API returns it directly
  in the response body when `DEBUG_OTP=true` in `.env`.
- Payments/subscriptions: `subscriptions` router is a stub; no StoreKit/Play Billing integration
  yet (arrives with a real store build, Phase 5+).
- Push notifications: not implemented at all yet — not needed to validate product logic.
- ML moderation (`moderation` router): stub for now; the real version (Phase 4) is a small
  scikit-learn classifier trained on a local seed dataset, no external API calls.

**Infra** (`docker-compose.yml` + `infra/`): Postgres, MinIO (+ a one-shot `minio-init` container
that runs `infra/minio/init.sh` to create the `braise-photos` bucket via `mc`), the FastAPI
`backend`, `adminer` for DB inspection, and a `mobile` service behind the `mobile` Compose profile
(not started by default — its `entrypoint.sh` runs `flutter create` on first launch since the
Flutter SDK is never installed on the host, only inside that container).

**Build order**: the repo is being built phase-by-phase per `docs/ROADMAP.md` (Identité & Profils →
Matching & Découverte → Messagerie & Flammes → Confiance & Modération → Monétisation/Sécurité →
Mobile). Check that file's checkboxes before assuming a module is unbuilt — the `/ping` stub
pattern above is how you can tell from the code itself which phase a router belongs to.
