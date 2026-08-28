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
  `storage.py` for the MinIO client, `profiles.py` for public/private profile CRUD, `avatar.py` for
  the deterministic avatar-sigil). Routers stay thin: parse request → call a service → shape
  response.
- `api/deps.py` — `get_current_user` is the one auth dependency every protected route uses (decodes
  the bearer JWT, loads the `User`). Any new protected endpoint takes
  `user: User = Depends(get_current_user)`, nothing bespoke per-router.
- Migrations are in `app/migrations/versions/`, generated with `alembic revision --autogenerate`
  against the live dev Postgres — don't hand-write migration files; let Alembic diff the models.
- **Profiles** (`models/profile.py`): `PublicProfile` (display_name, bio, interests, `avatar_seed`)
  and `PrivateProfile` (`photo_keys`, up to 3, in MinIO under `private/{user_id}/...`) are separate
  tables, one-to-one with `User`, matching the product's public/private split. `PublicProfileOut`
  only ever exposes computed `age`, never `birth_date` — don't add a raw-birthdate field to any
  public-facing schema, that's the exact de-anonymization risk the spec (A.6) calls out. The avatar
  is never a stored image: `services/avatar.py` derives a gradient spec (two hex colors + angle)
  deterministically from `avatar_seed` via `hashlib.sha256`, so "regenerate" is just a new random
  seed — actual gradient rendering happens client-side (Phase 6) using `docs/DESIGN_TOKENS.md`.
- **MinIO has two clients in `services/storage.py`**, both pointed at the same server: `_client`
  uses `MINIO_ENDPOINT` (`minio:9000`, the Docker service name — for uploads/deletes from the
  backend container) and `_public_client` uses `MINIO_PUBLIC_ENDPOINT` (`localhost:9000` — the only
  host a browser or the Flutter app can actually resolve) for `presigned_get_url` only. Both pin
  `region="us-east-1"` explicitly — without it, minio-py does a network round-trip to look up the
  bucket region before signing, which fails when this code runs *inside* the backend container and
  tries to reach `localhost:9000` (that's the container itself, not MinIO). Don't merge these two
  clients back into one; presigned URLs must stay signed against the externally-reachable host.

- **Discovery & matching** (`models/swipe.py`, `models/match.py`, `services/discovery.py`):
  `Swipe` (from_user_id, to_user_id, decision, unique pair constraint) records like/pass; a mutual
  `like` creates a `Match` with a *canonical* pair ordering (`_ordered_pair`, smaller UUID string
  first) so `(A,B)` and `(B,A)` can never both insert. Match creation happens inside
  `db.begin_nested()` (a SAVEPOINT): if two mutual "like" requests race, the loser's `IntegrityError`
  is caught without rolling back the swipe that was already flushed — don't replace this with a bare
  `try/db.rollback()`, that would also discard the swipe. The feed (`get_feed`) scores candidates by
  Jaccard similarity of `interests` computed in Python after a *bounded* DB fetch
  (`MAX_CANDIDATE_POOL = 200` rows, further capped to `limit` ≤ 50 in the response) — this keeps
  per-request cost predictable without needing a JSONB-array-overlap SQL query at MVP scale.
  `list_my_matches` batches the other-side profile lookup into one `IN (...)` query instead of
  N+1. A swipe target that doesn't exist and one that exists but isn't `is_published` return the
  *same* 404 — don't let that distinction leak through, it's a user-enumeration vector. No
  age/gender/distance filtering yet (cahier des charges A.5 lists it as MVP scope; deliberately
  deferred, see `docs/ROADMAP.md` Phase 2).

- **Messaging & daily question** (`models/message.py`, `models/daily_question.py`,
  `ws/connection_manager.py`, `services/messaging.py`): `ConnectionManager` is an in-memory
  `dict[match_id, set[WebSocket]]` — correct for a single backend process (this MVP), but it must
  be swapped for a shared pub/sub (Centrifugo/Redis, per cahier des charges D.4) before running more
  than one backend replica, or messages silently stop reaching participants connected to a different
  instance. WebSocket auth can't use the `Authorization` header (browsers can't set it on the
  handshake), so the JWT travels as a `?token=` query param and is checked manually
  (`api/deps.user_from_token`) *before* `websocket.accept()` — a rejected connection is closed with
  `WS_1008_POLICY_VIOLATION`, never accepted-then-closed. `_get_match_or_404` gates every messaging
  endpoint (REST and WS) the same way discovery gates swipes: a match that doesn't exist and one
  that exists but isn't yours both 404. The daily question is deterministic
  (`random.Random(f"{match_id}:{for_user_id}:{date}")`) so repeated `GET`s the same day return the
  identical question without needing to read it back from the DB first, but it's still persisted on
  first read (`DailyQuestion`, unique on match+user+day, `IntegrityError` on the race between two
  concurrent first `GET`s is caught and re-read, not treated as a bug). The correct answer is never
  in the `GET` response — only revealed in the `POST .../answer` result, after that day's attempt is
  consumed. A correct answer increments `Match.flame_count` (shared, not per-user), matching "bonne
  réponse = +1 flamme pour vous deux" in the mockups; `Match.flame_count` already existed from
  Phase 2, this phase just started writing to it.

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

**Tests run against the real dev Postgres/MinIO, not a throwaway database** — there's no
per-test transaction rollback or fixture teardown. Any test that creates a `User` (i.e. touches
auth) must call `tests.helpers.unique_phone()` rather than a hardcoded number, or it will pass once
and then fail on every rerun once that phone number already has data attached to it.

**Build order**: the repo is being built phase-by-phase per `docs/ROADMAP.md` (Identité & Profils →
Matching & Découverte → Messagerie & Flammes → Confiance & Modération → Monétisation/Sécurité →
Mobile). Check that file's checkboxes before assuming a module is unbuilt — the `/ping` stub
pattern above is how you can tell from the code itself which phase a router belongs to.
