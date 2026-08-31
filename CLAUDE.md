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
  `subscriptions`) — as of Phase 5 all six have real logic; none are left as the `/ping`
  `{"module": ..., "status": "stub — Phase N"}` placeholder that unbuilt modules used to expose
  (only Phase 6 / mobile remains, and it isn't a backend router).
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
- `api/deps.py` — `user_from_token` is the single place that turns a JWT into a `User`, used both
  by the `get_current_user` HTTP dependency and manually by the messaging WebSocket handler (which
  can't use `Depends`). It also enforces `is_banned` — a banned user gets 403 from *every* protected
  endpoint. Any new protected endpoint takes `user: User = Depends(get_current_user)`, nothing
  bespoke per-router — with exactly one deliberate exception:
  `get_current_user_even_if_banned` (shares the same JWT-decoding/deleted-account checks via the
  private `_resolve_user` helper, just skips the `is_banned` check) is used only by
  `POST /moderation/ban-appeal` and `GET /moderation/ban-appeal/mine`, because a banned user
  needs exactly one reachable endpoint to contest the ban (cahier des charges A.9) — see Trust &
  moderation below. Don't reuse it anywhere else.
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
  `is_verified` (`User`, set true on first successful OTP by `services/otp.py`) is the "profil
  vérifié" badge A.5 Module 1 lists as MVP scope — it existed on the model and in `/auth/me` since
  Phase 1 but was never threaded through `PublicProfileOut`/`DiscoveryCandidateOut` until later, so
  it had no visible badge anywhere despite being set for every account. `to_public_profile_out`
  takes `is_verified` as an explicit argument rather than re-querying `User` — both of its callers
  already have the `User` object from `Depends(get_current_user)`. `get_feed` batches it in one
  `IN (...)` lookup over the candidate pool, same N+1-avoidance pattern as `list_my_matches`.
  `DiscoveryCandidateOut` also carries `trust_score`/`trust_label` (score only, never
  `rating_count`/`flagged_count` — those stay more granular than a third party needs, same
  minimization logic as the age-not-birthdate rule above). This is deliberately *not* the same
  thing the `/moderation/*/trust-score` IDOR fix removed: that fix stopped anyone from reading an
  *arbitrary* user's rating internals by guessing a UUID; A.3/A.4.4 still require the score itself
  to inform discovery decisions before a match exists, which the old vulnerable endpoint was never
  actually wired into anyway (discovery never referenced trust data at all, before or after the
  fix — grep confirms it). `services.moderation.compute_trust_score` now delegates to
  `compute_trust_scores_batch` (one `ratee_id IN (...)` query grouped in Python) so `get_feed` can
  resolve up to `MAX_CANDIDATE_POOL` scores in one query instead of one per candidate — same
  batching principle as `is_verified` and `list_my_matches` above.
- **MinIO has two clients in `services/storage.py`**, both pointed at the same server: `_client`
  uses `MINIO_ENDPOINT` (`minio:9000`, the Docker service name — for uploads/deletes from the
  backend container) and `_public_client` uses `MINIO_PUBLIC_ENDPOINT` (`localhost:9000` — the only
  host a browser or the Flutter app can actually resolve) for `presigned_get_url` only. Both pin
  `region="us-east-1"` explicitly — without it, minio-py does a network round-trip to look up the
  bucket region before signing, which fails when this code runs *inside* the backend container and
  tries to reach `localhost:9000` (that's the container itself, not MinIO). Don't merge these two
  clients back into one; presigned URLs must stay signed against the externally-reachable host.
  `minio_secure`/`minio_public_secure` (`core/config.py`) are two separate settings, not one —
  `_client`'s traffic never leaves the private Docker network so it stays plain `http` even in
  prod, but `_public_client` signs URLs a real browser fetches, which must follow whatever scheme
  is actually externally reachable (`https` once a TLS-terminating reverse proxy sits in front —
  see `docs/DEPLOYMENT.md`/`infra/deploy/`). A signature computed for the wrong scheme is either
  rejected by MinIO or blocked by the browser as mixed content; both default to `false`, matching
  local dev unchanged, and only prod's `.env` sets `MINIO_PUBLIC_SECURE=true`.

- `services/matches.py` — `get_match_or_404`/`other_user_id` are the shared "is this user actually
  a participant in this match" check, used by discovery, messaging, moderation and profiles
  (partner-photos). It used to be copy-pasted per service; if you're about to write a fourth copy,
  don't — import from here instead.
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
  *same* 404 — don't let that distinction leak through, it's a user-enumeration vector. Base
  discovery filters (cahier des charges A.5: age range + looking-for gender; distance stays out of
  scope, no geolocation capture exists anywhere in the app) live as nullable columns on
  `PublicProfile` (`gender`, `looking_for_gender`, `age_min`, `age_max`) set via the same
  `PUT /profiles/me/public` that edits the rest of the profile — no separate preferences endpoint.
  `get_feed` pushes the gender filter into the SQL query (plain equality, shrinks the pool before
  scoring) and applies the age range in the same Python loop that already computes
  `compatibility_score`, matching the existing "don't push age math into SQL" pattern above. A
  profile that hasn't set `looking_for_gender`/`age_min`/`age_max` filters nothing — those
  preferences are opt-in, not required at signup.

- **Messaging & daily question** (`models/message.py`, `models/daily_question.py`,
  `ws/connection_manager.py`, `services/messaging.py`): `ConnectionManager` is an in-memory
  `dict[match_id, set[WebSocket]]` — correct for a single backend process (this MVP), but it must
  be swapped for a shared pub/sub (Centrifugo/Redis, per cahier des charges D.4) before running more
  than one backend replica, or messages silently stop reaching participants connected to a different
  instance. WebSocket auth can't use the `Authorization` header (browsers can't set it on the
  handshake), so the JWT travels as a `?token=` query param and is checked manually
  (`api/deps.user_from_token`) *before* `websocket.accept()` — a rejected connection is closed with
  `WS_1008_POLICY_VIOLATION`, never accepted-then-closed. `services.matches.get_match_or_404` gates
  every messaging endpoint (REST and WS) the same way discovery gates swipes: a match that doesn't
  exist and one
  that exists but isn't yours both 404. The daily question is deterministic
  (`random.Random(f"{match_id}:{for_user_id}:{date}")`) so repeated `GET`s the same day return the
  identical question without needing to read it back from the DB first, but it's still persisted on
  first read (`DailyQuestion`, unique on match+user+day, `IntegrityError` on the race between two
  concurrent first `GET`s is caught and re-read, not treated as a bug). The correct answer is never
  in the `GET` response — only revealed in the `POST .../answer` result, after that day's attempt is
  consumed. A correct answer increments `Match.flame_count` (shared, not per-user), matching "bonne
  réponse = +1 flamme pour vous deux" in the mockups; `Match.flame_count` already existed from
  Phase 2, this phase just started writing to it. Read status and typing (A.5 Module 3 listed both
  as MVP scope; deferred at the time) are now in: `Match.last_read_at_a`/`last_read_at_b` are a
  "read up to" timestamp per side, not a flag per message — enough for a 1:1 chat, no separate
  table. `services.matches.message_is_read` is symmetric (a fact about the message, not about who's
  asking): a message is read once the *recipient* (never the sender) has a `last_read_at` at or
  after `created_at`. `chat_ws` dispatches on a `type` field now (`"message"` is still the default
  when absent, so the old client behavior — sending a bare `{"body": ...}` — still works):
  `"typing"` is a pure relay, never persisted; `"read"` calls `mark_read` and rebroadcasts so the
  *other* open connection updates live. `GET .../messages` computes `read` per message via
  `message_is_read`, so a client that reloads history sees accurate ticks without replaying WS
  events. `chat_ws` opens a fresh `SessionLocal()` per operation (`with SessionLocal() as db:`,
  once for the initial auth/participant check, once more per received `read`/`message` event —
  `typing` needs no DB access at all) instead of holding one session for the whole connection's
  lifetime. This isn't a style preference: `backend/scripts/load_test_messaging.py` (P4.3)
  measured the old code locking up the *entire* app — including unrelated REST endpoints — at
  ~15 concurrently open conversations, because a WS connection can stay open for hours and the
  old code held its `SessionLocal()` checked out from the pool (`pool_size=5` + `max_overflow=10`
  = 15) for that whole duration; the 16th+ concurrent chat blocked on `pool_timeout` (30s) and
  every other request queued behind it. After the fix, a session is only checked out for the
  brief moment of handling one event, so an idle connection between messages holds zero pool
  capacity — verified at 400 concurrent matches (800 simultaneous WS connections, 100% connect
  and delivery success) with the backend staying fully responsive throughout. `user_id` (a plain
  UUID) is threaded through the receive loop instead of the `User`/`Match` ORM objects from the
  auth check — those become invalid once their session closes, so each per-event session
  re-fetches what it needs by id rather than reusing detached instances across sessions. (`models/rating.py`, `models/report.py`, `services/moderation.py`,
  `services/moderation_ml.py`): a `Rating` is one score+comment per `(match_id, rater_id)` — the
  trust score is *never stored*, it's recomputed on every read from all `Rating` rows for a user
  (`compute_trust_score`), so there's no cached counter that can drift out of sync. A rating is
  flagged `suspected_rancor` by either of two independent signals: a rule (score ≤ 2 posted within
  `POST_UNLOCK_RANCOR_WINDOW` of `Match.unlocked_at`) or `moderation_ml.predict_is_rancor` (a
  TF-IDF + logistic regression pipeline trained at import time on a hand-written seed dataset in
  that file — real scikit-learn, real training, but a toy dataset; retrain on bêta data before
  trusting it, per the docstring there). `build_pipeline()`/`load_dataset()` are factored out
  (not private) so `backend/scripts/evaluate_moderation_model.py` (P5.1) can cross-validate the
  *exact* production architecture rather than a hand-copied approximation that could silently
  drift from what's actually served — the module-level `_pipeline` still fits once on the full
  490-example dataset at import for runtime use (more training data is strictly better for the
  model that actually runs), evaluation is a separate concern measured by 5-fold stratified CV,
  never by looking at training accuracy on data the model already saw. At the production decision
  threshold (`RANCOR_PROBABILITY_THRESHOLD = 0.6`), measured false-positive rate on that seed set
  is 0 % (0/295 authentic comments wrongly flagged) at the cost of a 9.7% false-negative rate —
  numbers and method in `docs/MODEL_EVALUATION.md`, guarded against regression by
  `tests/test_moderation_ml.py::test_model_false_positive_rate_at_production_threshold` (same CV,
  fixed seed, fails if the false-positive rate on this dataset climbs past 2%). Flagged ratings are excluded from the trust-score average
  rather than counted against it — human review decides, the model doesn't punish directly.
  Auto-ban (`User.is_banned`) only fires past `MIN_RATINGS_FOR_AUTO_BAN = 3` — a deliberate
  floor so one or two bad-faith ratings can't zero out a brand-new user (cahier des charges A.9).
  Reports (`Report`) always start `status="pending"`: there's no automatic founded/unfounded
  triage or reviewer UI yet (cahier des charges C.1 explicitly scopes that to V2) — inspect them
  via Adminer for now, not a moderation endpoint that doesn't exist. `GET /moderation/me/trust-score`
  only ever returns the caller's own score (derived from the JWT) — it used to be
  `GET /moderation/users/{user_id}/trust-score`, a straight IDOR (any authenticated user could
  read anyone else's `rating_count`/`flagged_count` by guessing a UUID; the app itself never
  called it with anything but the caller's own id). `BanAppeal` (`models/ban_appeal.py`) is the
  human-contestation path A.9 requires for an auto-ban: same shape as `Report` (starts `pending`,
  reviewed via Adminer, no auto-triage), reachable through `get_current_user_even_if_banned` (see
  `api/deps.py` above) since a banned user is 403'd everywhere else. One pending appeal per user
  at a time; filing requires `user.is_banned` (400 otherwise — nothing to contest).
- **Monetization & security** (`models/subscription.py`, `models/photo_access_log.py`,
  `services/subscriptions.py`, `services/account.py`): `Subscription` is one current-state row per
  user (no history table — single tier per cahier des charges C.1), `is_premium` computed from
  `is_active and expires_at > now`, never trusted as a cached flag on its own. `record_swipe`
  (discovery) calls `can_create_new_match` before accepting a "like" — a free user at
  `FREE_MATCH_LIMIT` gets 402, checked *before* the swipe is even recorded, so it can never leave a
  half-completed match attempt. `GET /profiles/matches/{id}/partner-photos` is the actual payoff of
  the whole flames mechanic — it was missing through Phase 3/4: unlocking a match only ever set
  `Match.unlocked_at`, nothing let the *other* participant see the photos that state was supposed
  to unlock. Gated on `unlocked_at is not None` (403 otherwise), and every access is written to
  `PhotoAccessLog` — but only cross-user access; viewing your own photos via `/profiles/me/private`
  is not logged, that's not the disclosure event RGPD audit trails care about. Private photo
  uploads are encrypted at rest via MinIO's SSE-S3 (`sse=SseS3()` in `storage.upload_private_photo`,
  keyed by `MINIO_KMS_SECRET_KEY` — a single local secret, no external KMS); verify it's actually
  applied with `mc stat`, which reports `Encryption: SSE-S3` on a correctly-encrypted object — SSE-S3
  is the only mode compatible with plain presigned-GET browser access, SSE-C would require the
  client to hold and send the encryption key itself. Account deletion
  (`services.account.delete_my_account`) anonymizes rather than cascades: profile fields are
  cleared, private photos removed from MinIO, `phone` replaced with a `deleted-{uuid}` tombstone,
  `User.deleted_at` set — but `Match`/`Rating`/`Report` rows involving this user stay, and a
  deleted user's own message *bodies* get replaced with a placeholder rather than deleted, because
  the other participant's conversation history is their data too. `deleted_at` is checked in
  `api/deps.user_from_token` alongside `is_banned` — a JWT issued before deletion is still
  cryptographically valid until it expires, so this is the actual enforcement point, not the delete
  endpoint itself.
- `backend/scripts/scrape_dating_reviews.py` (+ `google-play-scraper` in requirements.txt) is a
  separate, standalone data-collection script — not part of the running API, not imported by
  anything under `app/`. Its output lands in `backend/scripts/data/` (gitignored). Read it before
  assuming what it does; it wasn't written as part of the phase work above.
- `backend/scripts/compute_kpis.py` computes the 9 A.10 KPIs directly against the DB (`SessionLocal`,
  not the API) — there's no staff/admin role in this project, so a script fits the existing pattern
  (Reports/BanAppeal are already "consult via Adminer", not via a protected endpoint that doesn't
  exist) better than inventing an auth boundary for one read-only report. It inserts the backend
  root onto `sys.path` explicitly before importing `app.*` — running a script as `python
  scripts/x.py` (rather than `python -m scripts.x`) puts `scripts/`, not `/app`, on `sys.path[0]`,
  which `pytest` never hits because it resolves `app.*` for `tests/` a different way (it's its own
  console-script entry point, not a plain script invocation). "Rétention à J7/J30" has no real
  signal to compute from — this project has no login/session event log — so `retention_proxy` is
  explicitly documented as an approximation (swiped again ≥N days after signup), not a real DAU/MAU
  retention figure; don't quote it outside internal debugging without that caveat attached.
- **OTP brute-force protection (P6.1)**: `services/otp.py` had no limits at all — a 6-digit code
  (10^6 possibilities) valid for `OTP_TTL_MINUTES = 10` with unlimited verify attempts is a real
  account-takeover path, not a robustness nitpick, given anyone who learns a victim's phone number
  could script the whole keyspace within the validity window. Two independent limits, both on
  `User` (`otp_requested_at`, `otp_attempts` — no Redis/external store, matches this project's
  "everything in Postgres" pattern): `MIN_RESEND_INTERVAL_SECONDS = 30` rejects a repeated
  `request_otp` for the same phone with 429 before that window elapses (raised as `HTTPException`
  straight from the service, same pattern as `discovery.py`/`moderation.py`); `MAX_OTP_ATTEMPTS =
  5` neutralizes the *current* code (`otp_code` cleared) once that many `verify_otp` calls for it
  have failed — deliberately not just a rejection: without clearing the code, a correct code
  submitted after the limit would still work, so `MAX_OTP_ATTEMPTS` would only slow an attacker
  down instead of stopping them. Both counters reset on every fresh `request_otp` call, so a
  legitimate user who mistypes a code isn't punished by their *next* code. No mobile changes
  needed — `OtpScreen` has no resend button while a code is pending (`_requestOtp`'s button is
  disabled via `_loading` during the call), so the throttle path isn't reachable from the current
  UI at all; it exists purely as a server-side backstop.

**Stubs for what would normally cost money** (intentional, not TODOs to "fix" casually — see
`docs/ROADMAP.md` for when each graduates to the real thing):
- OTP: no SMS provider. `services/otp.py` logs the code to stdout and the API returns it directly
  in the response body when `DEBUG_OTP=true` in `.env`.
- Payments/subscriptions: real free/premium logic exists (Phase 5), but activation is
  `POST /subscriptions/debug-activate` rather than a real purchase — no StoreKit/Play Billing
  integration until there's an actual store build to attach it to (cahier des charges D.8).
- Push notifications: not implemented at all yet — not needed to validate product logic.

**Infra** (`docker-compose.yml` + `infra/`): Postgres, MinIO (+ a one-shot `minio-init` container
that runs `infra/minio/init.sh` to create the `braise-photos` bucket via `mc`), the FastAPI
`backend`, `adminer` for DB inspection, and a `mobile` service behind the `mobile` Compose profile
(not started by default — its `entrypoint.sh` runs `flutter create` on first launch since the
Flutter SDK is never installed on the host, only inside that container). The backend has
`CORSMiddleware` enabled (`main.py`, origins from `Settings.cors_origin_list` / `CORS_ORIGINS` env
var, default `http://localhost:5000`) so the Flutter web app can call it cross-origin. `backend`
depends on `minio-init: condition: service_completed_successfully`, not just `minio:
service_healthy` (P6.2) — without it, `docker compose run backend ...`/`up backend` could start
before the `braise-photos` bucket actually exists (`minio` reports healthy once it can answer
requests, independently of whether `minio-init` has finished creating the bucket yet), a race
that's usually invisible locally (`minio-init` is fast) but real in CI where nothing has "warmed
up" yet.

**Continuous integration** (`.github/workflows/ci.yml`, P6.2): two parallel jobs, `backend`
(migrations, `ruff check .`, `pytest -q`) and `mobile` (`flutter analyze`, `flutter test`), each
running the exact Docker commands documented in `README.md` against real Postgres/MinIO
containers — no mocks, no third-party service. Free (GitHub Actions minutes), matches the
project's no-paid-service constraint. `flutter analyze` exits non-zero even for an `info`-level
finding, so the pipeline needed one pre-existing lint hint fixed to start green
(`moderation_api.dart`'s conditional map entry rewritten with Dart 3.8+'s null-aware map-value
syntax, `'comment': ?comment`, instead of `if (comment != null) 'comment': comment` — same
behavior, no lint finding).

**Operational hardening** (`infra/backup/`, post-MVP P0 — cahier des charges B.3/D.7/D.12
"sauvegardes automatisées et testées" was a listed critical dependency that phases 0-6 never
actually addressed): a `backup` Compose service (own `Dockerfile`, based on `postgres:16-alpine`
so `pg_dump`/`pg_restore` are always version-matched with the `db` service, plus the `mc` binary)
runs `backup.sh` on a loop (`BACKUP_INTERVAL_SECONDS`, default daily) — `pg_dump -F c` to
`backup_data:/backups/db` with retention (`BACKUP_RETENTION_DAYS`), and `mc mirror --remove` of the
`braise-photos` bucket to `/backups/photos` (mirror, not accumulate — deleted photos don't pile up
forever). `restore.sh <target_db> [target_bucket]` restores the latest dump into any target
database/bucket, deliberately never defaulting to overwriting the live one silently.
`test_restore.sh` is the actual proof this works, not an assumption: backup → restore into
throwaway `braise_restore_test` / `braise-photos-restore-test` → compare row/object counts against
the source → drop both. Run it with `docker compose run --rm backup /scripts/test_restore.sh`.
`entrypoint.sh` is the container's `ENTRYPOINT`; it `exec "$@"` when `docker compose run backup
<cmd>` passes an explicit command (needed for `test_restore.sh`/`backup.sh` to run once instead of
being silently swallowed by the default infinite loop — this was a real bug caught by actually
running the test, not just writing it) and only falls into the backup loop when invoked with no
args (`docker compose up backup`). Basic uptime supervision is `uptime-kuma` (official image,
port 8082, one-time manual setup: create the admin account, add HTTP monitors on
`http://backend:8000/health` and `http://minio:9000/minio/health/live` plus a TCP monitor on
`db:5432`, and a notification channel — nothing is pre-seeded, Uptime Kuma has no declarative
config format for that). `docs/DPIA.md` is the AIPD/DPIA required before any real beta (A.9/B.3):
data inventory, legal basis, existing technical measures already in the code (SSE-S3 encryption,
`PhotoAccessLog`, anonymizing deletion), and the residual risks/actions that are still open —
notably that A.9 requires a human contestation procedure for auto-bans and none exists yet.

**Production deployment** (`docker-compose.prod.yml`, `infra/deploy/`, `docs/DEPLOYMENT.md`,
post-MVP P4.4 — D.7/D.11's VPS-auto-géré recommendation, never scripted until this palier): the
prod file is an *overlay*, always used with the base (`-f docker-compose.yml -f
docker-compose.prod.yml`), never standalone. It locks every admin-facing service (`db`, MinIO
console, Adminer, Uptime Kuma) to `127.0.0.1`-only (SSH-tunnel access, never public) and adds
`caddy` as the one thing that touches ports 80/443 — automatic Let's Encrypt TLS, config in
`infra/deploy/Caddyfile` using Caddy's native `{$VAR}` substitution (`API_DOMAIN`/
`OBJECTS_DOMAIN`/`APP_DOMAIN`/`ACME_EMAIL`, from `.env`) rather than hardcoded domains. Two
non-obvious Compose merge behaviors this file depends on, confirmed by testing (`docker compose
... config`), not assumed: list fields like `ports`/`volumes` don't merge across `-f` files by
default (an override of `ports: []` leaves the base list untouched), so clearing one needs the
explicit `!reset []` tag, and *replacing* a non-empty base list needs `!override [...]` instead
— `!reset` with non-empty content silently drops it. `infra/deploy/provision.sh` bootstraps a
bare Ubuntu VPS (Docker install, `ufw`, a non-root `braise` deploy user) — reviewed but not run
against a real VPS from this environment (none available), so treat it as reviewed-not-verified
until it's actually exercised once.

**Mobile** (`mobile/braise_app/`, Flutter web, all commands run in the `mobile` container — the
Flutter SDK is never installed on the host):
- Every container-side Flutter command (`flutter create`, `flutter pub get`, `flutter run`, ...)
  writes files as root, since the `ghcr.io/cirruslabs/flutter:stable` image runs as root. Run
  `docker compose run --rm --entrypoint bash mobile -c "chown -R 1000:1000 /app/braise_app"`
  afterwards or the host user can't edit those files.
- `lib/theme/braise_tokens.dart` (`BraiseTokens.dark`/`.light`, `BraiseSpacing`, `BraiseRadii`) and
  `lib/theme/braise_theme.dart` (`buildBraiseTheme(Brightness)`) port `docs/DESIGN_TOKENS.md` 1:1 —
  don't hand-pick colors/spacing in a screen, add a token first if one's missing. Dark is the
  default at install (`ThemeController` starts at `ThemeMode.dark`, matching the spec's "Sombre
  reste le défaut"), but the user can switch to Clair/Système from Settings — persisted in
  `shared_preferences` (`braise_theme_mode`), read by `MaterialApp.themeMode` via a `Builder` so it
  can `context.watch` the controller (`main.dart`'s `MaterialApp` is a descendant of the
  `MultiProvider`, not a sibling — that ordering matters here).
- `lib/api/` is a thin typed wrapper per backend module (`auth_api.dart`, `profiles_api.dart`,
  etc.) over `api_client.dart`, which injects `Authorization: Bearer <token>` via a `tokenProvider`
  closure and throws `ApiException` (with `isUnauthorized`/`isForbidden`/`isPaymentRequired`
  getters) on non-2xx, using FastAPI's `detail` string as the message. `messaging_api.dart` also
  has `ChatSocket`, which connects to `/messaging/ws/{match_id}?token=...` — the same
  token-in-query-string pattern as the backend (Phase 3), because a browser can't set an
  `Authorization` header on a WebSocket handshake. One raw JSON stream, demultiplexed into
  `messages`/`typingEvents`/`readEvents` by the server-tagged `type` field — no sealed-union type,
  just three `.where()`+`.map()` views over the same broadcast stream. `ConversationScreen` sends
  `sendTyping()` on composer changes (throttled to once per 2s, not per keystroke) and
  `markRead()` both after loading history and whenever an incoming message arrives while the
  screen is open — there's no explicit "mark as read" UI action, opening/having the conversation
  open *is* the action. The read tick ("Envoyé"/"Lu") renders only under the single most recent
  message the current user sent, never per-bubble — a tick on every message would be noise the
  mockups never called for.
- `lib/state/app_services.dart` (`AppServices`) wires every API client plus `AuthController`
  (`ChangeNotifier`, JWT persisted via `shared_preferences` under `braise_token`) into one
  `Provider`-injected bundle; the circular dependency (the API client needs a token from the auth
  controller, which needs an API client) is resolved with a `late final` + closure, not a second
  bespoke wiring pattern. `AuthController` has 4 states, not 3 (`AuthStatus.unknown/signedOut/
  signedIn/banned`): the backend lets a banned user's OTP verify succeed and only 403s on the
  follow-up `/auth/me` call (`services/otp.py` doesn't check `is_banned`), so both `verifyOtp` and
  `restoreSession` must catch that specific `ApiException` (matched on the exact backend detail
  string `'Compte suspendu.'`, kept in sync with `api/deps.py` by a comment on both ends) and route
  to `banned` — keeping the token, unlike every other `ApiException` case, which signs out. Without
  this, a banned user was just silently bounced to the OTP screen with no explanation and no way to
  reach the ban-appeal endpoint at all.
- Screens live under `lib/screens/<module>/`, one subfolder per backend module, and are adapted
  from the mockups rather than copied verbatim where the backend doesn't match: OTP entry replaces
  the mockup's KYC/ID-scan step (no KYC exists), discovery is a single-card feed rather than a
  swipe grid (the spec's "no catalog" principle), the private-photo grid and GDPR export/delete
  actions live in `screens/settings/` (moved out of the profile/trust screen so that screen stays
  about profile info, not account settings) with no mockup equivalent because otherwise those Phase
  1/5 endpoints had no UI at all, and root navigation is 3 tabs (Découvrir/Échanges/Moi) rather
  than the mockup's 4 — no screen justifies a dedicated "Braises" tab beyond what Échanges/Moi
  already show. `screens/moderation/report_screen.dart` is one shared report flow (motif + texte
  obligatoires) reused from conversation, unlock, and rating screens, instead of three separate
  ad-hoc dialogs. `screens/moderation/ban_appeal_screen.dart` is what `AuthStatus.banned` routes
  to from `main.dart` — shows the latest `BanAppeal` status or the form to file one.
  `screens/onboarding/concept_intro_screen.dart` is A.4.1.5's dedicated pedagogical screen (why
  the physique is deferred, how flames work, how the veil lifts) — a 3-page `PageView`, shown
  exactly once, wired in from `ProfileSetupScreen._save` only when `isOnboarding == true` (a
  profile edit later in the app's life never re-shows it). Its icons mix the sign-language
  primitives from `widgets/sign_shapes.dart` (`SignDiamond` for flames, `SignHatchedCircle` for
  the veil) with one plain Material icon for "personality/interests," a concept none of the 4
  spec-defined primitives (braise/voile/confiance/vérifié) actually represents — same pragmatic
  mixing `screens/settings/settings_screen.dart` already does for its own icons.
- `test/widget_test.dart` exercises the theme system (background tokens per brightness, WCAG
  contrast ratio on `inkFloor`) rather than pumping the full `BraiseApp`, which would make a real
  network call via `restoreSession()` — that gap is now closed for `ApiClient` specifically (see
  below), not for the full app tree. It uses `testWidgets`/`pumpAndSettle`, not a bare `test()` —
  `buildBraiseTheme` calls into `google_fonts`, which resolves fonts asynchronously outside the
  widget-test zone and fails the test late ("failed after it had already completed") under plain
  `test()`. `GoogleFonts.config.allowRuntimeFetching = false` keeps tests offline (silent fallback
  font, never a real fetch).
- `ApiClient` takes an optional `httpClient` (`http.Client`, defaults to a real one) instead of
  calling the top-level `http.get`/`.post`/etc. functions directly — the one-line change that makes
  HTTP mocking possible at all. Tests inject `package:http/testing.dart`'s `MockClient` (shipped by
  the `http` package already in `pubspec.yaml`, no `mockito` needed) to fake backend responses.
  `test/state/auth_controller_test.dart` is the first thing built on this: it exercises
  `AuthController.restoreSession`/`verifyOtp` against a mocked `/auth/me`/`/auth/verify-otp` —
  signedIn, signedOut (expired/deleted token), and specifically `banned` (403 exact detail
  `'Compte suspendu.'`, token must survive) — the branch added for `AuthStatus.banned` that had
  zero test coverage before this. Plain `test()`, not `testWidgets()`: `AuthController` is a
  `ChangeNotifier` with no widget tree to pump. `AppServices` takes an optional `httpClient` (P5.2)
  so a full screen can be pumped under a real `Provider<AppServices>` in a test without ever
  touching the network — `test/screens/ban_appeal_screen_test.dart` is the first thing built on
  it (form validation, successful filing, an existing pending appeal, an overturned one letting a
  new filing happen). Building it surfaced a real trap in `package:http`'s `Response(String,
  ...)` constructor: it picks the body's encoding from the `Content-Type` *response header*, not
  from the string's actual content — with no header set it silently falls back to Latin-1, and
  any accented character (French, so: everywhere) then fails `utf8.decode` inside
  `ApiClient._decode` with a confusing `FormatException`, not a clean HTTP error. Every mock JSON
  response needs `headers: {'content-type': 'application/json; charset=utf-8'}` (see the `_json`
  helper in both test files) — `auth_controller_test.dart` predates this fix and had been passing
  by accident: `'Compte suspendu.'` has no accent so it happened to round-trip fine, while
  `'Compte supprimé.'` silently decoded to a generic fallback message that the test never
  compared against, only the resulting `AuthStatus` (which still landed right by coincidence).
  `test/screens/report_screen_test.dart` is the second screen built on this same infra —
  `ReportScreen`'s 5 motif tiles + text field + button exceed the default 800×600 test viewport,
  so a plain `tester.tap()` on anything below the fold misses silently (a hit-test warning, not a
  thrown exception) instead of driving `onPressed`; fixed with a `_tapAfterScrollingTo` helper
  that calls `tester.ensureVisible()` before every tap on a motif or the submit button, rather
  than enlarging the test viewport (which would just hide the same bug on any other screen this
  tall). `test/screens/otp_screen_test.dart` is the third — `OtpScreen`, the very first screen
  every user hits, pinning its button to the bottom with a `Spacer` rather than a scroll view
  (unlike `ReportScreen`), so its step-2 content (debug banner included) overflows the 800×600
  test viewport by 1px on a constraint no real device ever hits; here enlarging the test viewport
  (`tester.binding.setSurfaceSize`) is the right fix, the opposite call from `ReportScreen`.
  Writing the "already-published profile -> `RootShell`" case surfaced a real production bug in
  `discovery_screen.dart`: `_exitController` was a lazily-initialized `late final =
  AnimationController(vsync: this, ...)` field read only from `_swipe()` and `dispose()`, never
  `build()` — a user who opens Discover, never swipes, then leaves the screen makes `dispose()`
  the field's first-ever access, constructing a ticker-backed `AnimationController` at a point
  where the element is already deactivated and can't resolve its `TickerMode` ancestor, throwing
  "Looking up a deactivated widget's ancestor is unsafe." Fixed by constructing it in
  `initState()` instead, where the widget is guaranteed mounted — this had been broken since the
  swipe-exit animation was introduced and nothing exercised the no-swipe teardown path before this
  test did. `test/screens/discovery_screen_test.dart` (P6.3) is the fourth screen and the first
  tested directly rather than as a side effect of another screen's navigation — the busiest
  screen in the app (feed, swipe, match celebration) had no direct coverage before this, only the
  indirect pass that found the `_exitController` bug above. 6 tests: feed load (candidate +
  next-up preview), empty feed, load error, a "pass" that empties the feed, a "like" that gets
  matched (celebration dialog opens, then closes without navigating into `ConversationScreen` —
  out of scope for this file), and a 402-rejected swipe (snackbar shown, card stays put). Unlike
  `OtpScreen`/`ReportScreen`, no viewport or scroll trap here — the body is
  `Expanded`/`AnimatedSwitcher`-driven, not a fixed-height content stack.

**Lint** (`backend/ruff.toml`, P5.3 — mobile has had `flutter_lints` since the start, the backend
had nothing before this): `docker compose run --rm backend ruff check .`. `line-length = 110`, not
ruff's default 88 — covers nearly all existing code without forcing a mass reformat of carefully
written "why" comments; the handful of lines that still exceeded it (mostly long f-string print
statements in `scripts/`) were wrapped by hand instead of raising the limit further.
`app/models/__init__.py` is the one file exempted from the `I001` (import sort) rule
(`per-file-ignores`) — its import order is chronological by build phase (each new model appended
at the bottom when introduced), which the ruff config treats as deliberate rather than something
to alphabetize away. `app/migrations/` is excluded entirely — autogenerated, never hand-edited.

**Tests run against the real dev Postgres/MinIO, not a throwaway database** — there's no
per-test transaction rollback or fixture teardown. Any test that creates a `User` (i.e. touches
auth) must call `tests.helpers.unique_phone()` rather than a hardcoded number, or it will pass once
and then fail on every rerun once that phone number already has data attached to it.
`tests/helpers.py` also has `create_published_user`, `create_match`/`create_match_with` (a second
user matched to an *existing* one, for "N raters, one target" scenarios), and
`force_match_unlocked` (writes `Match.flame_count`/`unlocked_at` directly — reaching
`unlock_threshold` through the real one-question-per-day flow would take real days). Add to these
shared helpers rather than re-inlining the same setup in a new test file.

**Build order**: the repo was built phase-by-phase per `docs/ROADMAP.md` (Identité & Profils →
Matching & Découverte → Messagerie & Flammes → Confiance & Modération → Monétisation/Sécurité →
Mobile) — all 7 phases (0-6) are done. Check that file's checkboxes for what each phase deliberately
left out of scope.
