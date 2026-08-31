from fastapi.testclient import TestClient

from app.main import app
from tests.helpers import (
    auth_headers,
    ban_user,
    create_match,
    create_match_with,
    create_published_user,
    force_match_unlocked,
    read_trust_score,
    unique_phone,
)

client = TestClient(app)


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

    trust = client.get("/moderation/me/trust-score", headers=match["headers_b"]).json()
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
    force_match_unlocked(match["match_id"], hours_ago=1)

    response = client.post(
        f"/moderation/matches/{match['match_id']}/rating",
        headers=match["headers_a"],
        json={"score": 1, "comment": "Le courant n'est vraiment pas passé entre nous deux."},
    )
    assert response.status_code == 200
    assert response.json()["suspected_rancor"] is True


def test_low_score_far_from_unlock_not_flagged_by_rule():
    match = create_match(client)
    force_match_unlocked(match["match_id"], hours_ago=48)  # hors de la fenêtre de 24h

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

    # Le compte visé est désormais banni : son propre token est rejeté partout (y compris
    # /moderation/me/trust-score, voir plus bas), donc on relit son score directement en base.
    trust = read_trust_score(victim_id)
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

    trust = client.get("/moderation/me/trust-score", headers=victim_headers).json()
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
    headers, _ = create_published_user(client, "Jamais noté")
    trust = client.get("/moderation/me/trust-score", headers=headers).json()
    assert trust["score"] is None
    assert trust["rating_count"] == 0


def test_trust_score_requires_authentication():
    trust = client.get("/moderation/me/trust-score")
    assert trust.status_code == 401


def test_trust_score_cannot_target_another_user():
    # Régression pour l'IDOR corrigé : /moderation/me/trust-score ne prend plus de user_id en
    # paramètre, donc il n'y a plus de route qui accepterait un identifiant arbitraire.
    match = create_match(client)
    response = client.get(
        f"/moderation/users/{match['id_b']}/trust-score", headers=match["headers_a"]
    )
    assert response.status_code == 404


def test_ban_appeal_requires_banned_account():
    headers, _ = create_published_user(client, "Pas banni")
    response = client.post(
        "/moderation/ban-appeal", headers=headers, json={"message": "Pourquoi suis-je banni ?"}
    )
    assert response.status_code == 400


def test_ban_appeal_round_trip():
    victim_headers, victim_id = create_published_user(client, "Contestataire")
    ban_user(client, victim_headers, victim_id)

    # Un compte banni est rejeté partout ailleurs (cahier des charges A.4.4)...
    assert client.get("/auth/me", headers=victim_headers).status_code == 403

    # ...sauf sur la contestation elle-même (A.9 : la seule exception délibérée).
    filed = client.post(
        "/moderation/ban-appeal",
        headers=victim_headers,
        json={"message": "Cette note ne reflète pas du tout notre échange, je conteste."},
    )
    assert filed.status_code == 201
    body = filed.json()
    assert body["status"] == "pending"
    assert body["decided_at"] is None

    mine = client.get("/moderation/ban-appeal/mine", headers=victim_headers).json()
    assert len(mine) == 1
    assert mine[0]["id"] == body["id"]


def test_ban_appeal_rejects_too_short_message():
    victim_headers, victim_id = create_published_user(client, "Message trop court")
    ban_user(client, victim_headers, victim_id)

    response = client.post(
        "/moderation/ban-appeal", headers=victim_headers, json={"message": "non"}
    )
    assert response.status_code == 422


def test_ban_appeal_blocks_duplicate_pending():
    victim_headers, victim_id = create_published_user(client, "Deux contestations")
    ban_user(client, victim_headers, victim_id)

    payload = {"message": "Je conteste ce bannissement, ce n'est pas justifié."}
    first = client.post("/moderation/ban-appeal", headers=victim_headers, json=payload)
    assert first.status_code == 201

    second = client.post("/moderation/ban-appeal", headers=victim_headers, json=payload)
    assert second.status_code == 409


def test_ban_appeal_requires_authentication():
    response = client.post(
        "/moderation/ban-appeal", json={"message": "Je conteste ce bannissement."}
    )
    assert response.status_code == 401
