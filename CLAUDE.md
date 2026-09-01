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
  `services/`, not in the router or in `core/`. `access_token_expire_minutes` (`core/config.py`,
  `.env`) is 21600 (15 days), not a short session-style expiry — staying signed in across app
  restarts matters more for this product than a tight expiry window, and re-auth past that point
  is just the phone OTP flow again (`WelcomeScreen` → `OtpScreen`), never a silent dead end. No
  separate refresh token: one long-lived JWT is the simplest thing that works, revisit only if a
  real need for shorter-lived tokens shows up (`docs/V2_FEATURES.md`).
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
  N+1, and likewise batches `unread_count` per match (P9.2, the mobile "Échanges" badge) — one
  query fetching every candidate message (sent by the other side, across all my matches) rather
  than one query per match; since the "read up to" threshold is per-match (`last_read_at_a`/`_b`,
  whichever side I am), the per-row date comparison happens in Python after that single fetch,
  same "batch the query, filter in Python" split as the compatibility scoring above. A swipe
  target that doesn't exist and one that exists but isn't `is_published` return the
  *same* 404 — don't let that distinction leak through, it's a user-enumeration vector. Base
  discovery filters (cahier des charges A.5: age range, looking-for gender, distance — the third
  added in P9.3, see below) live as nullable columns on `PublicProfile` (`gender`,
  `looking_for_gender`, `age_min`, `age_max`) set via the same `PUT /profiles/me/public` that
  edits the rest of the profile — no separate preferences endpoint. `get_feed` pushes the gender
  filter into the SQL query (plain equality, shrinks the pool before scoring) and applies the age
  range in the same Python loop that already computes `compatibility_score`, matching the
  existing "don't push age math into SQL" pattern above. A profile that hasn't set
  `looking_for_gender`/`age_min`/`age_max` filters nothing — those preferences are opt-in, not
  required at signup. **Distance (P9.3)**: no GPS capture and no paid geocoding API — the user
  picks a city from a closed list of ~50 major French cities (`services/geo.py`,
  `data/french_cities.csv`, hand-curated public-knowledge coordinates, not survey-grade but
  plenty for a city-level radius filter), resolved to `PublicProfile.city_lat`/`city_lon` once at
  `upsert_public_profile` time rather than re-geocoded on every feed request; a city outside that
  list is still saved as a display string (`city`) but resolves to no coordinates, so it's simply
  never usable as a distance filter — never a validation error, since `city` is just free text
  from the API's point of view. `max_distance_km` is my own opt-in search radius, symmetric to
  `age_min`/`age_max`: null means no filter. `get_feed` applies it in the same Python loop as the
  age range (`services/geo.haversine_km`, plain great-circle distance) — a candidate is excluded
  outright if either side lacks resolved coordinates, since there's no way to verify they're
  within range. `GET /profiles/cities` (no auth required — static reference data, nothing
  user-specific) lists the closed set for the mobile city picker. **"Who liked you" (P13, requested
  directly, not in the cahier des charges)**: `get_likes_received` finds profiles that liked the
  current user and that the user hasn't swiped yet in either direction — the same
  `already_swiped`-exclusion pattern as `get_feed`, so an existing match or an already-passed
  profile never shows up here. The count is always returned (free-tier hook); the candidate list
  itself (`DiscoveryCandidateOut`, same shape as the feed) is only populated for a premium account
  (`is_premium`) — an empty-vs-populated-list gate, not a per-card blur, simpler and enough to
  create the upgrade incentive. `_candidate_dict` was factored out of `get_feed`'s scoring loop so
  both functions build the exact same candidate shape rather than diverging. `GET
  /discovery/likes-received` (`LikesReceivedOut`) is the only new endpoint — "like back" and
  "pass" from that screen both reuse `POST /discovery/swipe` as-is; `record_swipe` already handles
  mutual-like-creates-match correctly regardless of which UI surface triggered it, so no new match
  logic was needed.

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
  consumed. `DailyQuestionOut.prompt` (P14 — found via an actual click-through, not a code read: the
  card rendered "QUESTION DU JOUR" straight into 4 unlabeled option buttons, with no sentence
  anywhere saying what to guess, because the model never had a question-text field at all, only
  `options`/`correct_answer`) is computed by `services.messaging._build_prompt` from the other
  side's *current* display name — never persisted alongside the question, so editing a display name
  doesn't freeze an already-answered day's prompt on a stale one. A correct answer increments `Match.flame_count` (shared, not per-user), matching "bonne
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
- `backend/scripts/seed_test_data.py` publishes 6 fixed personas (phone, profile, `city` — the
  last for exercising the P9.3 distance filter without hand-publishing 6 different profiles) via
  the real HTTP API, not direct DB writes — idempotent, since each persona has a fixed phone
  number and OTP verify just re-authenticates the same account rather than creating a duplicate.
  `seed_persona()` returns `(token, headers, user_id)` specifically so
  `backend/scripts/seed_beta_tester.py` can reuse an already-open session instead of requesting a
  second OTP for the same number moments later — the P6.1 throttle (`MIN_RESEND_INTERVAL_SECONDS`)
  correctly refuses that, caught by actually running this against the live stack, not assumed.
  `seed_beta_tester.py` layers a ready-to-explore tester account on top: publishes a profile open
  to everyone (no gender/age/distance filter, so every seeded persona shows up in its feed), then
  mutually likes two personas to create real matches via the actual swipe endpoint (not a
  shortcut) — one forced fully unlocked (`Match.flame_count = unlock_threshold`, direct DB write,
  same principle as `tests.helpers.force_match_unlocked`: simulating real daily-question days
  would take real days) with a real uploaded photo and two waiting messages, one left partially
  progressed (`flame_count = 2`) with today's daily question still answerable, and 4 personas
  left completely unswiped for testing discovery/matching from scratch. Messages are sent over a
  real `ChatSocket`-equivalent WebSocket connection (`websockets`, matching the pattern in
  `load_test_messaging.py`), not inserted directly into the `messages` table, so the same
  read/unread and broadcast logic a real conversation goes through actually ran.
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
- Push notifications: still not real push (no Firebase/APNs, no Service Worker registered — see
  `notifications/` below for what P9.1 added instead, which is a different, more limited thing).

**Infra** (`docker-compose.yml` + `infra/`): Postgres, MinIO (+ a one-shot `minio-init` container
that runs `infra/minio/init.sh` to create the `braise-photos` bucket via `mc`), the FastAPI
`backend`, `adminer` for DB inspection, and a `mobile` service behind the `mobile` Compose profile
(not started by default — its `entrypoint.sh` runs `flutter create` on first launch since the
Flutter SDK is never installed on the host, only inside that container). `entrypoint.sh` branches
on `MOBILE_MODE` (env, defaults to `dev`): `dev` is `flutter run -d web-server` (hot reload, the
normal dev loop) but its debug WebSocket back to the Flutter tool (DWDS) assumes the page is
loaded from the same origin the tool expects — silently fails (blank page, no error surfaced to
the user) when loaded from a different origin, which is exactly what happens for a local-network
beta tester hitting the host's LAN IP instead of `localhost`. `MOBILE_MODE=serve` runs a real
`flutter build web` and serves the static output with `python3 -m http.server` instead — no
debug connection at all, works identically from any origin. `entrypoint.sh` runs `flutter pub get`
explicitly before either branch's build/run command (P14): both `flutter build web` and
`flutter run` do their own implicit dependency resolution first, but that implicit step proved
intermittently racy in this container specifically — since the pub cache is never persisted
between container restarts (no named volume, just the `./mobile:/app` bind mount, see
`docker-compose.yml`), every start is a full fresh download, and dart2js would sometimes begin
compiling before every downloaded package had finished being written to disk ("file not found"
on `provider`, `vector_math`, or others, different package each time — not a real missing
dependency). An explicit, blocking `flutter pub get` beforehand removes the race; hasn't failed
once since. Since `entrypoint.sh` is `COPY`'d
into the image (not part of the `./mobile:/app` bind mount), changing `MOBILE_MODE` needs
`docker compose build mobile` before recreating the container, a plain restart won't pick it up
— see README, "Bêta-test entre proches" for the exact commands. The backend has
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
port 8082) — HTTP monitors on `http://backend:8000/health` and
`http://minio:9000/minio/health/live` plus a TCP monitor on `db:5432`, and the admin account
itself, are set up via `infra/uptime-kuma/setup.py` (P12.2) rather than by hand in the UI:
Uptime Kuma has no declarative config format, but its internal Socket.IO API is reachable from
outside the web UI through the `uptime-kuma-api` pip package (a client for the container's own
already-exposed API, not a third-party service), so the setup is scripted and idempotent instead
of a one-time manual ritual nobody can reproduce later. The notification channel (webhook —
Discord/Slack/generic JSON, `NotificationType` field names verified against the installed
package's `notification_providers.py`, not guessed) is scripted too, but needs a real webhook URL
passed in (`UPTIME_KUMA_WEBHOOK_URL`) that only the person running it can provide — the script
still creates the admin account and monitors without it, leaving just that one step manual.
`docs/DPIA.md` is the AIPD/DPIA required before any real beta (A.9/B.3): data inventory, legal
basis, existing technical measures already in the code (SSE-S3 encryption, `PhotoAccessLog`,
anonymizing deletion, `BanAppeal` — A.9's human contestation procedure for auto-bans, live since
P1.1, not the open item this sentence used to say it was), and the residual risks/actions that
are still open.

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
  `MultiProvider`, not a sibling — that ordering matters here). `MaterialApp` also pins
  `locale: const Locale('fr')` with `flutter_localizations`' delegates (P14) — this app has no
  second language, so there was never a reason to inherit whatever locale the browser/OS happens
  to report instead of guaranteeing French everywhere. Without it, `showDatePicker` (used for
  birth date in `ProfileSetupScreen`) rendered its own chrome in English ("Select date", "OK")
  inside an otherwise all-French app, and — the actually damaging part — its keyboard-entry mode
  expected `MM/DD/YYYY`: typing a date the French way (`JJ/MM`) silently produced the wrong date
  on a field that gates the 18+ check. Found by actually typing a birthdate during a UX pass, not
  by reading the widget tree.
- `lib/api/api_config.dart` (`ApiConfig.httpBaseUrl`/`.wsBaseUrl`) derives the API host from
  `Uri.base.host` (the page's own URL) at runtime rather than hardcoding `localhost` — needed for
  a friends-and-family beta on the local network (no VPS, see `docs/V2_FEATURES.md`): a tester's
  device visits the app via the host machine's LAN IP (`http://192.168.1.x:5000`), and
  `localhost` on *their* device would resolve to their own device, not the host running the
  backend. The same build works unmodified whether loaded via `localhost` or a LAN IP. Falls
  back to `'localhost'` when `Uri.base.host` is empty (the VM target `flutter test` runs on, not
  a real web context) — harmless, since screen tests never hit the real network
  (`AppServices(httpClient: ...)`). This only fixes the mobile side of the LAN-reachability
  problem: `MINIO_PUBLIC_ENDPOINT` and `CORS_ORIGINS` (backend `.env`, not committed) both still
  need the host's LAN IP added manually for private-photo URLs and cross-origin requests to work
  from another device — see the comments in `.env.example`.
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
- `lib/notifications/` (P9.1) gives the 3 notification toggles in `SettingsScreen` a real effect
  — before this they only remembered a preference, honestly documented as inert ("prochaine
  version"). This project is Flutter **web only** (see Mobile intro below — every platform folder
  `flutter create` scaffolds exists, but only `web` is ever actually served), which rules out
  `flutter_local_notifications` entirely: it has no web implementation. The real mechanism is the
  browser's native `Notification` API via `dart:js_interop`/`package:web`
  (`notification_platform_web.dart`) — free, local, no Firebase/APNs/Service Worker, but also
  fundamentally foreground-only: a plain web page cannot schedule a notification for a future
  time when its tab is closed, that needs a Service Worker (+ often Web Push), a separate,
  heavier piece of infra out of scope for this pass. `dart:js_interop` is a real Dart core
  library, but only on **web compile targets** — a file importing it cannot even compile for the
  VM, which is what `flutter test`/`flutter analyze` run on by default. `notification_platform.dart`
  resolves this with a conditional export (`if (dart.library.js_interop) ...`, the standard
  pattern replacing the old `dart.library.html` check), picking `notification_platform_web.dart`
  on web and the no-op `notification_platform_stub.dart` everywhere else — `flutter build web` is
  what actually proves the interop code compiles for the real target (run and confirmed working
  before this shipped; `flutter test`'s VM run can't exercise it at all). `NotificationsService`
  wraps those two platform functions behind injectable callbacks — same pattern as
  `ApiClient(httpClient: ...)` — so widget tests verify "fires with the right title/body at the
  right moment" without ever touching a real browser or depending on a granted permission.
  `NotificationPrefs` centralizes the 3 SharedPreferences keys (`SettingsScreen` used to declare
  them as private constants, now the single source both it and the firing sites read). Permission
  is requested from `SettingsScreen` only when a toggle is switched *on* by an explicit tap, never
  on app start or screen load — browsers routinely auto-deny or flag as spam a permission prompt
  not tied to a user gesture. Three fire points, each honest about what it can and can't do given
  the foreground-only constraint: `DiscoveryScreen._celebrateMatch` (a new mutual match — fires
  alongside the existing celebration dialog, not instead of it), `ConversationScreen`'s
  `socket.messages.listen` (a message from the other side while that conversation is open — there
  is no app-wide message listener across all matches, only the one conversation actively open),
  and `RootShell.initState` (a daily-question nudge, at most once per calendar day, tracked by a
  date stamp in `shared_preferences` rather than genuinely scheduled — the closest honest
  approximation of "daily reminder" achievable without a Service Worker).
- **Unread message badge (P9.2)**: `MatchSummary.unreadCount` (from `MatchOut.unread_count`,
  backend) surfaces as a `Badge.count` on each row in `MatchesListScreen` and, aggregated, on the
  "Échanges" tab icon in `RootShell`. `RootShell` fetches `getMatches()` a third time on its own
  purely for this total — `MatchesListScreen` and `ProfileTrustScreen` already each call it
  independently for their own needs, so a third independent caller follows the same established
  pattern rather than inventing shared state across 3 screens for one MVP-scale feature. That
  call is wrapped in `try/catch` (unlike the rest of `RootShell`, this one is easy to get wrong
  since nothing else in `RootShell` gates on `_loading`): a badge is decorative, so a failure
  here must never surface as an error or an unhandled exception — `MatchesListScreen` already
  shows its own error if the underlying problem persists. No live refresh while a conversation is
  open (no cross-screen event bus exists) — the badge updates on mount and when the user
  navigates away from the Échanges tab, which covers the real case (it clears after visiting the
  inbox) without new shared-state machinery.
- **Distance filter (P9.3)**: `ProfileSetupScreen` adds a city picker and a distance slider to
  the existing "PRÉFÉRENCES DE DÉCOUVERTE" section, alongside gender/age. `_loadCities()` fetches
  `GET /profiles/cities` independently of `_load()` (profile + photos) and fails silently on
  error — same "decorative feature, must never break the screen" rule as the P9.2 badge: an empty
  city list just means an empty dropdown, not a broken form. The distance `Slider` only appears
  once a city is picked (`if (_city != null)`); its label defaults to showing `100 km`
  (`_defaultMaxDistanceKm`) before the user ever drags it, which surfaced a real bug while
  writing this screen's test: `_save()` sent whatever `_maxDistanceKm` actually held — `null` if
  the slider was never touched — silently publishing *no* distance filter at all despite the
  screen visibly showing "100 km" the whole time. Fixed by falling back to
  `_maxDistanceKm ?? _defaultMaxDistanceKm` at save time, so what's sent always matches what was
  shown. `PublicProfile.city`/`.maxDistanceKm` are optional constructor params (not `required`)
  specifically so `ProfileSetupScreen._regenerateAvatar()` — which reconstructs a `PublicProfile`
  by hand from the previous one plus a new avatar — doesn't need touching for every future field
  added to this model; it does still explicitly carry both through, otherwise regenerating your
  avatar would have silently wiped your city/distance preference.
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
  `screens/onboarding/welcome_screen.dart` is the very first screen a signed-out user sees
  (`main.dart`'s `_AuthGate`, `AuthStatus.signedOut`) — a presentation screen with two CTAs
  ("Créer un compte" / "J'ai déjà un compte") before `OtpScreen`, requested explicitly rather
  than inferred from the mockups. Both CTAs push the exact same `const OtpScreen()`, no mode
  flag: the backend's OTP flow doesn't distinguish signup from login at all (`POST
  /auth/verify-otp` creates the account on first success, signs in on every one after — see
  `services/otp.py`), so faking a distinction client-side would be dishonest UI for a flow that's
  actually unified. `WelcomeScreen` is reached via a real `Navigator.push(braiseRoute(...))`, not
  folded into `_AuthGate`'s own status switch — the intent was always "no back-gesture path from
  inside the signed-in app back to the welcome/OTP screens", but the original implementation only
  half-delivered it: `OtpScreen`'s `pushReplacement` on successful verify swaps *only* the pushed
  OtpScreen route for the next screen, never touching the base `/` route underneath (which
  `_AuthGate` already re-renders as `RootShell` reactively once signed in, without any navigation
  call of its own) — so a *second*, redundant `RootShell` ended up stacked on top of the first,
  and its AppBar grew a real, poppable back arrow (`Navigator.canPop()` was genuinely true) that
  led nowhere useful: popping it just revealed the identical `RootShell` underneath. Found by
  actually clicking it during a P14 UX pass, not by reading this comment. Fixed by switching the
  two call sites that land on `RootShell` as a *terminal* destination — the already-published
  branch in `otp_screen.dart` and the end of onboarding in `concept_intro_screen.dart` — from
  `pushReplacement` to `Navigator.pushAndRemoveUntil(route, (_) => false)`, which clears the
  entire stack instead of swapping one route. The non-terminal hop in between
  (`ProfileSetupScreen` → `ConceptIntroScreen`, `profile_setup_screen.dart`) is left as a plain
  `pushReplacement` — it was never the problem, only whichever route actually lands on
  `RootShell` needs the stack wiped under it.
- `screens/legal/legal_screen.dart` (CGU + politique de confidentialité, requested explicitly)
  renders `docs/legal/CGU.md`/`POLITIQUE_CONFIDENTIALITE.md` as hardcoded Dart section lists
  (`_cguSections`/`_privacySections`, a two-tab `DefaultTabController`) rather than loading the
  Markdown files as assets at runtime — this project has no asset pipeline and the content is
  short enough that a loader would be more machinery than the problem needs. The two must be
  kept in sync by hand when either changes — a comment at the top of the Dart file says so. Both
  documents are explicitly marked "version bêta, pas encore relue par un·e professionnel·le du
  droit" in both the Markdown and the in-app text: drafted directly from `docs/DPIA.md`'s data
  inventory for accuracy, not generic boilerplate, but still not a substitute for real legal
  review before any launch beyond a small circle of beta testers. Reachable from two places:
  `WelcomeScreen` (a small underlined notice above the CTAs, the standard placement for
  consent-at-signup) and `SettingsScreen`'s RGPD card (for anyone wanting to re-read it later).
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
  `test/screens/matches_list_screen_test.dart` (P7.1) is the fifth — `MatchesListScreen` (the
  "Échanges" root tab) is a plain `GET /discovery/matches`, unlike `ConversationScreen` which
  can't use this project's `httpClient`-mock infra at all since it talks over a real WebSocket
  (`ChatSocket`, no injectable channel factory yet). 4 tests: unlocked vs locked match subtitles
  (`MatchSummary.isUnlocked` derived from `blurStage == 'net'`), the empty "go discover" state,
  a load error, and pull-to-refresh (`tester.fling` on the `ListView`, asserting the fetch count
  goes from 1 to 2). `test/screens/profile_trust_screen_test.dart` (P7.2) is the sixth, and found
  a real bug rather than just documenting existing behavior: `ProfileTrustScreen._load()` awaited
  3 parallel calls (profile, trust score, matches) via `Future.wait` with no `try/catch` at
  all — a transient failure on any one of them left `_loading` stuck at `true` forever, with
  nothing scrollable to pull-to-refresh from (`RootShell` keeps this screen mounted permanently
  via `IndexedStack`, so `initState` never reruns) — an infinite spinner with no recovery short of
  restarting the app. Fixed by catching `ApiException` and switching to an error state rendered
  inside a `ListView` (so pull-to-refresh keeps working from it), instead of letting the
  exception propagate unhandled. 2 tests: a successful load, and a failure on one of the three
  calls followed by a pull-to-refresh that succeeds — proving recovery actually works, not just
  that the error renders. P8 covers the six remaining directly-testable screens in one pass —
  `ConceptIntroScreen`, `RatingScreen`, `UnlockScreen` (empty/error states only; the
  photos-present case uses `Image.network`, which would hit the real network inside the test
  sandbox), `PaywallScreen`, `SettingsScreen`, and `ProfileSetupScreen` (the biggest: prefill,
  interests, bio prompts, gender chips, avatar regeneration, publish — all without ever touching
  `ImagePicker` or `showDatePicker`, two real platform flows this project's mock infra can't
  reach; `_save()` only requires `_birthDate` when `_profile` is still `null`, so publishing
  right after a successful load never needs the date picker at all). Two more real bugs found,
  same family as `ProfileTrustScreen` above: `PaywallScreen._load()` had no `try/catch` at all
  (the identical infinite-spinner trap), and `_activate()`/`_cancel()` silently swallowed errors
  instead of showing them; `SettingsScreen._exportData()`/`_deleteAccount()` had the same silent-
  swallow gap. All four fixed with the same `catch (ApiException e)` pattern used everywhere else
  in the app — an error state (with working pull-to-refresh) for `_load()`, a `SnackBar` for the
  rest. Two new test-infra traps surfaced along the way: `PaywallScreen`'s `_PulsingDiamond` runs
  `AnimationController.repeat()` forever unless the test harness forces
  `MediaQuery.disableAnimations: true` — otherwise `pumpAndSettle()` never finds a frame with no
  pending animation and times out; and `SettingsScreen`'s long `ListView` doesn't even build
  elements far below the fold (past the underlying `Sliver`'s `cacheExtent`), so
  `tester.ensureVisible()` has nothing to target — a tall enough test viewport sidesteps this
  rather than working around it. Only `ConversationScreen` remained untested at this point: it
  talks over a real WebSocket (`ChatSocket`, no injectable channel factory at the time), a
  refactor of its own and out of scope for this coverage pass — picked up in P10 below.

**Testing a real WebSocket screen** (`test/screens/conversation_screen_test.dart`, P10): closing
the one gap P8 left open. `ChatSocket` (`api/messaging_api.dart`) now takes an optional `channel`
(typed `StreamChannel<dynamic>`, not `WebSocketChannel` — the latter is what
`WebSocketChannel.connect` returns and is-a `StreamChannel`, but the field needs to also accept a
non-network fake in tests) defaulting to the real `WebSocketChannel.connect`; `ConversationScreen`
similarly takes an optional `chatSocketFactory`. Same injection shape as
`AppServices(httpClient: ...)` throughout this project. Tests build a
`package:stream_channel` `StreamChannelController<dynamic>()`, hand `ChatSocket` its `.local` end,
and use `.foreign.sink.add(...)` to simulate server frames / `.foreign.stream` to capture what the
screen actually sends. Two traps found writing this:
- A raw `.foreign.stream.listen((data) => ...)` call reliably hung `pumpAndSettle()` forever —
  not a timeout, an actual deadlock specific to mixing `stream_channel`'s controller with
  `flutter_test`'s `FakeAsync` test zone; `expectLater(stream, emits(...))` (or `emitsThrough`),
  the officially-blessed way to assert on a stream in the `test`/`flutter_test` packages, doesn't
  have this problem. Lesson: prefer `expectLater`/stream matchers over manual `.listen()` when
  asserting on any stream inside a widget test.
- `emits(matcher)` checks only the *very next* event, and this screen sends "housekeeping" frames
  incidentally — `_loadHistory()` always sends a `read` frame on load, and the composer sends a
  `typing` frame before the actual `message` frame it's testing. `emitsThrough(matcher)` (skip
  until a match, rather than require the first event to match) is what these tests actually need.

6 tests: history load, a message received over the socket (appears + triggers a `read` frame
back), sending a message (composer clears + a `message` frame goes out), the daily question
(render + answer + result), the typing indicator (appears on a `typing` event, clears after 3s of
silence), and a `read` event flipping "Envoyé" to "Lu" on the sender's own last message.

**Accessibility (P15)** — checked against the app's actual accessibility tree
(`page.locator('body').ariaSnapshot()` via `playwright-core`, with raw `flt-semantics`/`aria-*`
DOM inspection whenever the compact snapshot left doubt) rather than by reading widget code, since
Flutter's default semantics behavior can't be predicted from the widget tree alone:
- `main()` calls `SemanticsBinding.instance.ensureSemantics()` before `runApp` — never storing or
  disposing the returned `SemanticsHandle` — because Flutter web otherwise never builds its
  semantics tree until a manual gesture on a hidden `flt-semantics-placeholder` element activates
  it; without this, a screen reader hears nothing but "Enable accessibility, button" on first load.
- `Chip` carries checkbox-like semantics by default even with no `onTap`/`onDeleted` — every
  purely-informational chip (common-interest counts, per-interest chips, the "VÉRIFIÉ"/"BRAISE+"
  badges) wraps in `Semantics(excludeSemantics: true, label: ...)` to replace that with a neutral
  label, leaving the visual rendering untouched.
- Any custom composite row that needs its own scoped label *and* still exposes a real interactive
  child's state (`_NotifRow`'s `Switch` in `settings_screen.dart`, the stat cards in
  `profile_trust_screen.dart`) follows one pattern: `Semantics(container: true, label: ...,
  excludeSemantics: true, ...)`, replicating whatever state the excluded child would have carried
  (`toggled: value` for a switch) and, if the excluded child was tappable, an explicit `onTap` —
  `excludeSemantics` hides the child's own semantics entirely, so without that the row becomes
  unreachable/inert for assistive tech even though it still works fine for a mouse/touch user.
  `_StatCard` gained a `semanticValue` parameter for exactly this: its `child:` slot (the FLAMMES
  diamonds) has no plain-text `value` to fall back on. Confirmed via raw DOM that "0 FLAMMES" and
  "0 ÉCHANGES ACTIFS" render as two distinct, bounded `flt-semantics` nodes even though
  Playwright's condensed `ariaSnapshot()` view merges adjacent plain-text nodes back into the
  surrounding text for brevity — that merge is a quirk of the summary renderer, not evidence the
  fix didn't take.
- Bare icon-only tap targets need an explicit name or a screen reader announces just "button":
  `IconButton` via `tooltip`, a non-`IconButton` tappable (`InkWell`/`GestureDetector`) via
  `Semantics(button: true, label: ...)`. The delete-photo `GestureDetector` in
  `profile_setup_screen.dart` combined this with `HitTestBehavior.opaque` and a larger hit radius
  (12 → 16) — its 24px original was well under the ~44px minimum recommended touch target for a
  destructive action, though the fix stays modest to avoid overlapping the 96×120 photo tile it
  sits on.
- Not every apparent gap survives DOM-level verification: `SegmentedButton` (the theme selector)
  looked stateless in the compact `ariaSnapshot()` — three plain `button`s, no selected marker —
  but the raw DOM showed it already exposes the active choice via `aria-current`. Left alone.

**Accessibility, round 2 (P16)** — dimensions the first pass hadn't touched (keyboard, motion,
language, metadata), found the same way: measuring the real running app, not reading the theme
code and assuming it worked.
- `docs/DESIGN_TOKENS.md`'s `focusRing` token was already wired into `braise_theme.dart`, but only
  via `ThemeData.focusColor` — a subtle tint overlay, not a border. Pixel-diffing a focused vs.
  unfocused screenshot showed a ~24/255 max color shift on "Créer un compte": present in code,
  invisible in practice, on every button in the app. `_focusRingSide()` (`braise_theme.dart`)
  layers a real 3px `focusRing` border onto the *existing* `ButtonStyle` via `.copyWith(side: ...)`
  for all 4 button theme types (Elevated/Outlined/Text/Icon) — deliberately not a from-scratch
  style rebuild, so nothing else about each button's look changes except the focus state.
- `discovery_screen.dart`'s swipe animation (`_exitController`, the feed's `AnimatedSwitcher`) had
  fixed-duration animations with no `disableAnimations` check, unlike `braise_page_route.dart` and
  `PaywallScreen`'s pulsing diamond, which already respect it — on the single most-used screen in
  the app. Both now resolve to `Duration.zero` under reduced motion; `AnimationController.duration`
  is mutable, so `_exitController`'s gets reassigned once at the top of `build()` rather than
  needing the controller rebuilt.
- `web/index.html` had no `lang` attribute at all (screen readers can default to an English voice
  for entirely-French content) and, along with `web/manifest.json`, still carried the unedited
  Flutter scaffold defaults through every phase of this project: `<title>braise_app</title>`, a
  meta description reading "A new Flutter project.", and the stock Flutter blue
  (`#0175C2`) for `theme_color`/`background_color`. Fixed to `lang="fr"`, "Braise", the app's own
  tagline, and the actual dark/braise tokens (`surface/root` dark, `braise/fill`) — visible in the
  browser tab, bookmarks, and the icon name if someone adds the PWA to a home screen, not purely
  an accessibility nicety.
- Checked and already fine, no change made: reflow under a much narrower effective viewport (WCAG
  1.4.10, simulating high browser zoom), the light theme across every screen checked, `SnackBar`
  announcement and post-dialog focus restoration (both framework-level Flutter guarantees, not
  something this app's code controls), and keyboard tab order on the welcome screen.

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
