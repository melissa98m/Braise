import uuid
from datetime import datetime, timedelta, timezone

from fastapi.testclient import TestClient

from app.db.session import SessionLocal
from app.main import app
from app.models.match import Match
from tests.helpers import (
    auth_headers,
    create_match,
    create_match_with,
    create_published_user,
    unique_phone,
)

client = TestClient(app)


def _force_unlocked(match_id: str, hours_ago: float) -> None:
    # Atteindre unlock_threshold flammes par le vrai flux (une question/jour/utilisateur) prendrait
    # plusieurs jours réels : on pose directement l'état "match débloqué depuis X" en base pour
    # tester la règle de rancune post-déblocage, comme pour la lecture directe de la Phase 3.
    db = SessionLocal()
    try:
        match = db.get(Match, uuid.UUID(match_id))
        match.flame_count = match.unlock_threshold
        match.unlocked_at = datetime.now(timezone.utc) - timedelta(hours=hours_ago)
        db.commit()
    finally:
        db.close()


def test_rating_rejects_short_comment():
    match = create_match(client)
    response = client.post(
        f"/moderation/matches/{match['match_id']}/rating",
        headers=match["headers_a"],
        json={"score": 4, "comment": "trop court"},
    )
    assert response.status_code == 422


def test_rating_round_trip_updates_trust_score():
    match = create_match(client)
    response = client.post(
        f"/moderation/matches/{match['match_id']}/rating",
        headers=match["headers_a"],
        json={"score": 5, "comment": "Une conversation vraiment agréable et respectueuse."},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["suspected_rancor"] is False
    assert body["trust_score"] == 100

    trust = client.get(
        f"/moderation/users/{match['id_b']}/trust-score", headers=match["headers_a"]
    ).json()
    assert trust["score"] == 100
    assert trust["label"] == "EXEMPLAIRE"
    assert trust["rating_count"] == 1
    assert trust["flagged_count"] == 0


def test_rating_once_per_match():
    match = create_match(client)
    payload = {"score": 3, "comment": "Échange correct sans plus, rien à redire."}
    first = client.post(
        f"/moderation/matches/{match['match_id']}/rating", headers=match["headers_a"], json=payload
    )
    assert first.status_code == 200

    second = client.post(
        f"/moderation/matches/{match['match_id']}/rating", headers=match["headers_a"], json=payload
    )
    assert second.status_code == 409


def test_rating_requires_match_participant():
    match = create_match(client)
    outsider_headers = auth_headers(client, unique_phone())
    response = client.post(
        f"/moderation/matches/{match['match_id']}/rating",
        headers=outsider_headers,
        json={"score": 2, "comment": "Peu importe le contenu ici franchement."},
    )
    assert response.status_code == 404


def test_rancor_leaning_comment_flagged_by_classifier():
    match = create_match(client)
    response = client.post(
        f"/moderation/matches/{match['match_id']}/rating",
        headers=match["headers_a"],
        json={
            "score": 1,
            "comment": "Vraiment pas terrible physiquement, grosse déception à la découverte.",
        },
    )
    assert response.status_code == 200
    assert response.json()["suspected_rancor"] is True
    # Une note suspectée de rancune ne fait pas chuter le score de confiance de la même façon
    # qu'une note fiable : elle est exclue de la moyenne (voir services/moderation.py).
    assert response.json()["trust_score"] == 50


def test_post_unlock_low_score_flagged_by_rule():
    match = create_match(client)
    _force_unlocked(match["match_id"], hours_ago=1)

    response = client.post(
        f"/moderation/matches/{match['match_id']}/rating",
        headers=match["headers_a"],
        json={"score": 1, "comment": "Le courant n'est vraiment pas passé entre nous deux."},
    )
    assert response.status_code == 200
    assert response.json()["suspected_rancor"] is True


def test_low_score_far_from_unlock_not_flagged_by_rule():
    match = create_match(client)
    _force_unlocked(match["match_id"], hours_ago=48)  # hors de la fenêtre de 24h

    response = client.post(
        f"/moderation/matches/{match['match_id']}/rating",
        headers=match["headers_a"],
        json={"score": 1, "comment": "Le courant n'est vraiment pas passé entre nous deux."},
    )
    assert response.status_code == 200
    assert response.json()["suspected_rancor"] is False


def test_auto_ban_after_enough_low_ratings_and_ban_is_enforced():
    base = create_match(client)
    victim_headers, victim_id = base["headers_b"], base["id_b"]
    rater_2 = create_match_with(client, victim_headers, victim_id)
    rater_3 = create_match_with(client, victim_headers, victim_id)

    raters = (
        (base["headers_a"], base["match_id"]),
        (rater_2["headers"], rater_2["match_id"]),
        (rater_3["headers"], rater_3["match_id"]),
    )
    for headers, match_id in raters:
        response = client.post(
            f"/moderation/matches/{match_id}/rating",
            headers=headers,
            json={"score": 1, "comment": "Le courant n'est vraiment pas passé entre nous deux."},
        )
        assert response.status_code == 200

    # Le compte visé est désormais banni : on ne peut plus utiliser son propre token pour
    # consulter quoi que ce soit (voir plus bas), donc on relit son score via un autre compte.
    trust = client.get(
        f"/moderation/users/{victim_id}/trust-score", headers=base["headers_a"]
    ).json()
    assert trust["score"] == 0
    assert trust["rating_count"] == 3

    banned_check = client.get("/auth/me", headers=victim_headers)
    assert banned_check.status_code == 403


def test_two_low_ratings_do_not_trigger_ban():
    # Garde-fou explicite du cahier des charges (A.9) : sous le seuil minimum de notes, pas de
    # bannissement automatique même si la moyenne serait à 0.
    base = create_match(client)
    victim_headers, victim_id = base["headers_b"], base["id_b"]
    rater_2 = create_match_with(client, victim_headers, victim_id)

    for headers, match_id in ((base["headers_a"], base["match_id"]), (rater_2["headers"], rater_2["match_id"])):
        response = client.post(
            f"/moderation/matches/{match_id}/rating",
            headers=headers,
            json={"score": 1, "comment": "Le courant n'est vraiment pas passé entre nous deux."},
        )
        assert response.status_code == 200

    still_ok = client.get("/auth/me", headers=victim_headers)
    assert still_ok.status_code == 200

    trust = client.get(
        f"/moderation/users/{victim_id}/trust-score", headers=victim_headers
    ).json()
    assert trust["score"] == 0
    assert trust["rating_count"] == 2


def test_report_creation_and_listing():
    match = create_match(client)
    response = client.post(
        f"/moderation/matches/{match['match_id']}/report",
        headers=match["headers_a"],
        json={"reason": "comportement_suspect", "comment": "A insisté pour se voir immédiatement."},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "pending"

    mine = client.get("/moderation/reports/mine", headers=match["headers_a"]).json()
    assert any(r["id"] == body["id"] for r in mine)


def test_report_requires_match_participant():
    match = create_match(client)
    outsider_headers = auth_headers(client, unique_phone())
    response = client.post(
        f"/moderation/matches/{match['match_id']}/report",
        headers=outsider_headers,
        json={"reason": "autre"},
    )
    assert response.status_code == 404


def test_report_invalid_reason_rejected():
    match = create_match(client)
    response = client.post(
        f"/moderation/matches/{match['match_id']}/report",
        headers=match["headers_a"],
        json={"reason": "ce_motif_n_existe_pas"},
    )
    assert response.status_code == 422


def test_trust_score_null_when_no_ratings_yet():
    _, user_id = create_published_user(client, "Jamais noté")
    headers = auth_headers(client, unique_phone())
    trust = client.get(f"/moderation/users/{user_id}/trust-score", headers=headers).json()
    assert trust["score"] is None
    assert trust["rating_count"] == 0
