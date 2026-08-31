import uuid
from datetime import date

from fastapi.testclient import TestClient

from app.main import app
from app.services.subscriptions import FREE_MATCH_LIMIT
from tests.helpers import auth_headers, create_match, create_published_user, unique_phone

client = TestClient(app)


def _tag(word: str, suffix: str) -> str:
    # Suffixe unique par test : évite que des intérêts identiques accumulés par des runs
    # précédents (base de dev persistante, pas de rollback) ne faussent le score de ce run.
    return f"{word}-{suffix}"


def _birth_date_for_age(age: int) -> str:
    today = date.today()
    return date(today.year - age, today.month, min(today.day, 28)).isoformat()


def test_feed_ranks_by_shared_interests_and_excludes_self():
    suffix = uuid.uuid4().hex[:6]
    shared = [_tag("escalade", suffix), _tag("littérature", suffix)]

    me_headers, me_id = create_published_user(client, "Léa", interests=shared)
    _, close_match_id = create_published_user(
        client, "Karim", interests=[*shared, _tag("jeux vidéo", suffix)]
    )
    _, far_match_id = create_published_user(client, "Sofia", interests=[_tag("cuisine", suffix)])

    feed = client.get("/discovery/feed", headers=me_headers)
    assert feed.status_code == 200
    body = feed.json()

    feed_ids = [candidate["user_id"] for candidate in body]
    assert me_id not in feed_ids
    assert close_match_id in feed_ids
    assert far_match_id in feed_ids
    assert feed_ids.index(close_match_id) < feed_ids.index(far_match_id)

    close = next(c for c in body if c["user_id"] == close_match_id)
    assert close["common_interests"] == sorted(shared)
    assert close["compatibility_score"] > 0


def test_feed_excludes_unpublished_and_already_swiped_profiles():
    suffix = uuid.uuid4().hex[:6]
    me_headers, _ = create_published_user(
        client, "Observateur", interests=[_tag("cinéma", suffix)]
    )
    unpublished_headers = auth_headers(client, unique_phone())
    client.put(
        "/profiles/me/public",
        headers=unpublished_headers,
        json={
            "display_name": "Jamais publié",
            "birth_date": "1996-01-01",
            "bio": "",
            "interests": [],
            "is_published": False,
        },
    )
    unpublished_id = client.get("/auth/me", headers=unpublished_headers).json()["id"]

    _, swiped_id = create_published_user(client, "Déjà vu", interests=["cinéma"])
    client.post(
        "/discovery/swipe",
        headers=me_headers,
        json={"to_user_id": swiped_id, "decision": "pass"},
    )

    feed_ids = [c["user_id"] for c in client.get("/discovery/feed", headers=me_headers).json()]
    assert unpublished_id not in feed_ids
    assert swiped_id not in feed_ids


def test_mutual_like_creates_match_with_zero_progress():
    headers_a, id_a = create_published_user(client, "Marc")
    headers_b, id_b = create_published_user(client, "Camille")

    first = client.post(
        "/discovery/swipe", headers=headers_a, json={"to_user_id": id_b, "decision": "like"}
    )
    assert first.status_code == 200
    assert first.json()["matched"] is False

    second = client.post(
        "/discovery/swipe", headers=headers_b, json={"to_user_id": id_a, "decision": "like"}
    )
    assert second.status_code == 200
    assert second.json()["matched"] is True

    matches_a = client.get("/discovery/matches", headers=headers_a).json()
    match = next(m for m in matches_a if m["other_user_id"] == id_b)
    assert match["flame_count"] == 0
    assert match["unlock_pct"] == 0
    assert match["blur_stage"] == "silhouette"

    matches_b = client.get("/discovery/matches", headers=headers_b).json()
    assert any(m["other_user_id"] == id_a for m in matches_b)


def test_one_sided_like_does_not_match():
    headers_a, _ = create_published_user(client, "Unilatéral A")
    headers_b, id_b = create_published_user(client, "Unilatéral B")

    response = client.post(
        "/discovery/swipe", headers=headers_a, json={"to_user_id": id_b, "decision": "like"}
    )
    assert response.json()["matched"] is False
    assert client.get("/discovery/matches", headers=headers_a).json() == []


def test_cannot_swipe_self():
    headers, my_id = create_published_user(client, "Solo")
    response = client.post(
        "/discovery/swipe", headers=headers, json={"to_user_id": my_id, "decision": "like"}
    )
    assert response.status_code == 400


def test_swipe_on_missing_or_unpublished_profile_returns_404():
    headers, _ = create_published_user(client, "Chercheur")

    missing = client.post(
        "/discovery/swipe",
        headers=headers,
        json={"to_user_id": str(uuid.uuid4()), "decision": "like"},
    )
    assert missing.status_code == 404

    unpublished_headers = auth_headers(client, unique_phone())
    unpublished_id = client.get("/auth/me", headers=unpublished_headers).json()["id"]
    response = client.post(
        "/discovery/swipe",
        headers=headers,
        json={"to_user_id": unpublished_id, "decision": "like"},
    )
    assert response.status_code == 404


def test_duplicate_swipe_rejected():
    headers, _ = create_published_user(client, "Répétitif")
    _, target_id = create_published_user(client, "Cible")

    first = client.post(
        "/discovery/swipe", headers=headers, json={"to_user_id": target_id, "decision": "pass"}
    )
    assert first.status_code == 200

    second = client.post(
        "/discovery/swipe", headers=headers, json={"to_user_id": target_id, "decision": "like"}
    )
    assert second.status_code == 409


def test_discovery_endpoints_require_auth():
    assert client.get("/discovery/feed").status_code == 401
    assert client.get("/discovery/matches").status_code == 401
    assert (
        client.post(
            "/discovery/swipe", json={"to_user_id": str(uuid.uuid4()), "decision": "like"}
        ).status_code
        == 401
    )


def test_free_tier_match_limit_blocks_further_likes():
    hub_headers, hub_id = create_published_user(client, "Hub")

    for _ in range(FREE_MATCH_LIMIT):
        other_headers, other_id = create_published_user(client, "Autre")
        client.post(
            "/discovery/swipe", headers=hub_headers, json={"to_user_id": other_id, "decision": "like"}
        )
        reciprocal = client.post(
            "/discovery/swipe", headers=other_headers, json={"to_user_id": hub_id, "decision": "like"}
        )
        assert reciprocal.json()["matched"] is True

    _, one_more_id = create_published_user(client, "En trop")
    blocked = client.post(
        "/discovery/swipe", headers=hub_headers, json={"to_user_id": one_more_id, "decision": "like"}
    )
    assert blocked.status_code == 402

    # Un "pass" n'est jamais limité : seul le fait de *liker* est concerné.
    passed = client.post(
        "/discovery/swipe", headers=hub_headers, json={"to_user_id": one_more_id, "decision": "pass"}
    )
    assert passed.status_code == 200


def test_premium_bypasses_free_tier_match_limit():
    hub_headers, hub_id = create_published_user(client, "Hub premium")
    client.post("/subscriptions/debug-activate", headers=hub_headers)

    for _ in range(FREE_MATCH_LIMIT + 1):
        other_headers, other_id = create_published_user(client, "Autre premium")
        like_response = client.post(
            "/discovery/swipe", headers=hub_headers, json={"to_user_id": other_id, "decision": "like"}
        )
        assert like_response.status_code == 200
        reciprocal = client.post(
            "/discovery/swipe", headers=other_headers, json={"to_user_id": hub_id, "decision": "like"}
        )
        assert reciprocal.json()["matched"] is True


def test_feed_candidates_report_verified_badge():
    suffix = uuid.uuid4().hex[:6]
    me_headers, _ = create_published_user(client, "Observatrice vérif", interests=[_tag("art", suffix)])
    _, candidate_id = create_published_user(client, "Candidat", interests=[_tag("art", suffix)])

    candidate = next(
        c
        for c in client.get("/discovery/feed", headers=me_headers).json()
        if c["user_id"] == candidate_id
    )
    # create_published_user passe par le vrai flux OTP (tests/helpers.auth_headers), donc
    # is_verified est déjà à true — pas besoin de forcer un état artificiel pour ce test.
    assert candidate["is_verified"] is True


def test_feed_candidates_report_trust_score():
    suffix = uuid.uuid4().hex[:6]
    me_headers, _ = create_published_user(client, "Observatrice confiance", interests=[_tag("art", suffix)])
    _, unrated_id = create_published_user(client, "Jamais noté", interests=[_tag("art", suffix)])

    feed_before = {
        c["user_id"]: c for c in client.get("/discovery/feed", headers=me_headers).json()
    }
    assert feed_before[unrated_id]["trust_score"] is None
    assert feed_before[unrated_id]["trust_label"] is None

    # Un candidat noté positivement doit voir son score remonter dans le feed d'un tiers, pas
    # seulement dans son propre /moderation/me/trust-score (cahier des charges A.3/A.4.4 : le
    # score de confiance doit informer la découverte, pas rester privé).
    match = create_match(client, interests_a=[_tag("art", suffix)])
    rate_response = client.post(
        f"/moderation/matches/{match['match_id']}/rating",
        headers=match["headers_a"],
        json={"score": 5, "comment": "Une conversation vraiment agréable et respectueuse."},
    )
    assert rate_response.status_code == 200

    feed_after = {
        c["user_id"]: c for c in client.get("/discovery/feed", headers=me_headers).json()
    }
    assert feed_after[match["id_b"]]["trust_score"] == 100
    assert feed_after[match["id_b"]]["trust_label"] == "EXEMPLAIRE"


def test_feed_filters_by_looking_for_gender():
    suffix = uuid.uuid4().hex[:6]
    me_headers, _ = create_published_user(
        client, "Filtre genre", interests=[_tag("cinéma", suffix)], looking_for_gender="femme"
    )
    _, homme_id = create_published_user(
        client, "Un homme", interests=[_tag("cinéma", suffix)], gender="homme"
    )
    _, femme_id = create_published_user(
        client, "Une femme", interests=[_tag("cinéma", suffix)], gender="femme"
    )
    _, sans_genre_id = create_published_user(
        client, "Genre non renseigné", interests=[_tag("cinéma", suffix)]
    )

    feed_ids = {c["user_id"] for c in client.get("/discovery/feed", headers=me_headers).json()}
    assert femme_id in feed_ids
    assert homme_id not in feed_ids
    # Un profil qui n'a pas renseigné son genre ne peut pas être vérifié comme correspondant au
    # filtre actif : il est exclu, pas inclus par défaut.
    assert sans_genre_id not in feed_ids


def test_feed_without_gender_preference_shows_everyone():
    suffix = uuid.uuid4().hex[:6]
    me_headers, _ = create_published_user(client, "Sans préférence", interests=[_tag("art", suffix)])
    _, homme_id = create_published_user(
        client, "Un homme bis", interests=[_tag("art", suffix)], gender="homme"
    )

    feed_ids = {c["user_id"] for c in client.get("/discovery/feed", headers=me_headers).json()}
    assert homme_id in feed_ids


def test_feed_filters_by_age_range():
    suffix = uuid.uuid4().hex[:6]
    me_headers, _ = create_published_user(
        client,
        "Filtre âge",
        interests=[_tag("rando", suffix)],
        age_min=30,
        age_max=40,
    )
    _, young_id = create_published_user(
        client,
        "Trop jeune",
        interests=[_tag("rando", suffix)],
        birth_date=_birth_date_for_age(22),
    )
    _, in_range_id = create_published_user(
        client,
        "Dans la tranche",
        interests=[_tag("rando", suffix)],
        birth_date=_birth_date_for_age(35),
    )
    _, old_id = create_published_user(
        client,
        "Trop âgé",
        interests=[_tag("rando", suffix)],
        birth_date=_birth_date_for_age(55),
    )

    feed_ids = {c["user_id"] for c in client.get("/discovery/feed", headers=me_headers).json()}
    assert in_range_id in feed_ids
    assert young_id not in feed_ids
    assert old_id not in feed_ids


def test_profile_rejects_age_min_above_age_max():
    headers = auth_headers(client, unique_phone())
    response = client.put(
        "/profiles/me/public",
        headers=headers,
        json={
            "display_name": "Incohérent",
            "birth_date": "1996-01-01",
            "bio": "",
            "interests": [],
            "is_published": True,
            "age_min": 40,
            "age_max": 25,
        },
    )
    assert response.status_code == 422


def test_profile_rejects_invalid_gender_value():
    headers = auth_headers(client, unique_phone())
    response = client.put(
        "/profiles/me/public",
        headers=headers,
        json={
            "display_name": "Genre invalide",
            "birth_date": "1996-01-01",
            "bio": "",
            "interests": [],
            "is_published": True,
            "gender": "extraterrestre",
        },
    )
    assert response.status_code == 422


def test_match_list_reports_unread_count_from_the_other_side_only():
    # P9.2 : le badge de messages non lus côté mobile s'appuie sur ce champ — un message que
    # j'ai moi-même envoyé ne doit jamais compter comme "non lu" pour moi.
    match = create_match(client)
    url_a = f"/messaging/ws/{match['match_id']}?token={match['token_a']}"
    url_b = f"/messaging/ws/{match['match_id']}?token={match['token_b']}"

    with client.websocket_connect(url_b) as ws_b:
        ws_b.send_json({"type": "message", "body": "Premier message."})
        ws_b.receive_json()
        ws_b.send_json({"type": "message", "body": "Deuxième message."})
        ws_b.receive_json()

    with client.websocket_connect(url_a) as ws_a:
        ws_a.send_json({"type": "message", "body": "Ma propre réponse."})
        ws_a.receive_json()

    matches_a = client.get("/discovery/matches", headers=match["headers_a"]).json()
    assert matches_a[0]["unread_count"] == 2

    with client.websocket_connect(url_a) as ws_a:
        ws_a.send_json({"type": "read"})

    matches_a_after_read = client.get("/discovery/matches", headers=match["headers_a"]).json()
    assert matches_a_after_read[0]["unread_count"] == 0
