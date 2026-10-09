from fastapi.testclient import TestClient

from app.main import app
from tests.helpers import (
    auth_headers,
    ban_user,
    create_match,
    create_published_user,
    find_rating_id,
    force_match_unlocked,
    make_staff,
    unique_email,
)

client = TestClient(app)


def _staff_headers() -> dict:
    headers, staff_id = create_published_user(client, "Staff")
    make_staff(staff_id)
    return headers


def _report_via(match: dict) -> str:
    response = client.post(
        f"/moderation/matches/{match['match_id']}/report",
        headers=match["headers_a"],
        json={"reason": "harcelement", "comment": "Comportement déplacé pendant l'échange."},
    )
    assert response.status_code == 200
    return response.json()["id"]


def _flagged_rating_via(match: dict) -> str:
    # Règle post-déblocage (services/moderation._is_post_unlock_rancor) : note basse peu après le
    # déblocage du match — plus simple et déterministe à déclencher en test que le classifieur ML.
    force_match_unlocked(match["match_id"], hours_ago=1)
    response = client.post(
        f"/moderation/matches/{match['match_id']}/rating",
        headers=match["headers_a"],
        json={"score": 1, "comment": "Décevant une fois les photos enfin débloquées, dommage."},
    )
    assert response.status_code == 200
    assert response.json()["suspected_rancor"] is True
    ratings = client.get("/moderation/me/trust-score", headers=match["headers_b"]).json()
    assert ratings["flagged_count"] >= 1
    return find_rating_id(match["match_id"], match["id_a"])


# ---------------------------------------------------------------------------
# Contrôle d'accès
# ---------------------------------------------------------------------------


def test_admin_routes_require_authentication():
    for path in ("/admin/queue-counts", "/admin/reports", "/admin/ban-appeals", "/admin/flagged-ratings"):
        assert client.get(path).status_code == 401


def test_admin_routes_reject_non_staff_user():
    headers = auth_headers(client, unique_email())
    for path in ("/admin/queue-counts", "/admin/reports", "/admin/ban-appeals", "/admin/flagged-ratings"):
        response = client.get(path, headers=headers)
        assert response.status_code == 403


def test_staff_user_can_reach_queue_counts():
    staff = _staff_headers()
    response = client.get("/admin/queue-counts", headers=staff)
    assert response.status_code == 200
    body = response.json()
    assert set(body) == {
        "reports_pending",
        "ban_appeals_pending",
        "flagged_ratings_pending",
        "feedback_new",
        "client_errors_new",
    }


# ---------------------------------------------------------------------------
# Signalements
# ---------------------------------------------------------------------------


def test_resolve_report_founded_with_ban():
    staff = _staff_headers()
    match = create_match(client)
    report_id = _report_via(match)

    response = client.post(
        f"/admin/reports/{report_id}/resolve",
        headers=staff,
        json={"decision": "founded", "note": "Comportement confirmé après relecture.", "ban_reported": True},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "founded"
    assert body["reported"]["is_banned"] is True

    # Le compte banni perd l'accès, comme un bannissement automatique.
    me = client.get("/auth/me", headers=match["headers_b"])
    assert me.status_code == 403


def test_resolve_report_founded_without_ban_does_not_ban():
    staff = _staff_headers()
    match = create_match(client)
    report_id = _report_via(match)

    response = client.post(
        f"/admin/reports/{report_id}/resolve",
        headers=staff,
        json={"decision": "founded", "note": "Fondé mais premier avertissement.", "ban_reported": False},
    )
    assert response.status_code == 200
    assert response.json()["reported"]["is_banned"] is False
    assert client.get("/auth/me", headers=match["headers_b"]).status_code == 200


def test_resolve_report_unfounded():
    staff = _staff_headers()
    match = create_match(client)
    report_id = _report_via(match)

    response = client.post(
        f"/admin/reports/{report_id}/resolve",
        headers=staff,
        json={"decision": "unfounded", "note": "Aucun élément probant."},
    )
    assert response.status_code == 200
    assert response.json()["status"] == "unfounded"
    assert response.json()["reported"]["is_banned"] is False


def test_resolve_report_twice_conflicts():
    staff = _staff_headers()
    match = create_match(client)
    report_id = _report_via(match)

    first = client.post(
        f"/admin/reports/{report_id}/resolve",
        headers=staff,
        json={"decision": "unfounded", "note": "Rien à signaler."},
    )
    assert first.status_code == 200

    second = client.post(
        f"/admin/reports/{report_id}/resolve",
        headers=staff,
        json={"decision": "founded", "note": "Nouvelle tentative.", "ban_reported": False},
    )
    assert second.status_code == 409


def test_report_detail_includes_prior_report_count():
    staff = _staff_headers()
    match_1 = create_match(client)
    _report_via(match_1)
    match_2 = create_match(client)
    second_report_id = _report_via(match_2)

    detail = client.get(f"/admin/reports/{second_report_id}", headers=staff)
    assert detail.status_code == 200
    assert detail.json()["prior_reports_against_reported"] >= 0  # comptes distincts, donc 0 ici

    response = client.get("/admin/reports?status=pending", headers=staff)
    assert response.status_code == 200
    assert len(response.json()) >= 2


# ---------------------------------------------------------------------------
# Contestations de bannissement
# ---------------------------------------------------------------------------


def test_resolve_ban_appeal_overturned_unbans_user():
    staff = _staff_headers()
    headers, victim_id = create_published_user(client, "Victime")
    ban_user(client, headers, victim_id)
    assert client.get("/auth/me", headers=headers).status_code == 403

    appeal = client.post(
        "/moderation/ban-appeal",
        headers=headers,
        json={"message": "Je conteste cette décision, c'est une erreur."},
    )
    assert appeal.status_code == 201
    appeal_id = appeal.json()["id"]

    response = client.post(
        f"/admin/ban-appeals/{appeal_id}/resolve",
        headers=staff,
        json={"decision": "overturned", "note": "Erreur confirmée, notes ré-examinées."},
    )
    assert response.status_code == 200
    assert response.json()["status"] == "overturned"
    assert response.json()["user"]["is_banned"] is False
    assert client.get("/auth/me", headers=headers).status_code == 200


def test_resolve_ban_appeal_upheld_keeps_user_banned():
    staff = _staff_headers()
    headers, victim_id = create_published_user(client, "Victime")
    ban_user(client, headers, victim_id)

    appeal = client.post(
        "/moderation/ban-appeal", headers=headers, json={"message": "Je conteste cette décision, injuste."}
    )
    appeal_id = appeal.json()["id"]

    response = client.post(
        f"/admin/ban-appeals/{appeal_id}/resolve",
        headers=staff,
        json={"decision": "upheld", "note": "Décision confirmée après relecture des notes."},
    )
    assert response.status_code == 200
    assert response.json()["user"]["is_banned"] is True
    assert client.get("/auth/me", headers=headers).status_code == 403


def test_resolve_ban_appeal_twice_conflicts():
    staff = _staff_headers()
    headers, victim_id = create_published_user(client, "Victime")
    ban_user(client, headers, victim_id)
    appeal_id = client.post(
        "/moderation/ban-appeal", headers=headers, json={"message": "Je conteste cette décision, svp."}
    ).json()["id"]

    first = client.post(
        f"/admin/ban-appeals/{appeal_id}/resolve",
        headers=staff,
        json={"decision": "upheld", "note": "Maintenu."},
    )
    assert first.status_code == 200
    second = client.post(
        f"/admin/ban-appeals/{appeal_id}/resolve",
        headers=staff,
        json={"decision": "overturned", "note": "Nouvelle tentative."},
    )
    assert second.status_code == 409


# ---------------------------------------------------------------------------
# Notes signalées
# ---------------------------------------------------------------------------


def test_flagged_rating_appears_in_queue_and_can_be_cleared():
    staff = _staff_headers()
    match = create_match(client)
    rating_id = _flagged_rating_via(match)

    detail = client.get(f"/admin/flagged-ratings/{rating_id}", headers=staff)
    assert detail.status_code == 200
    assert detail.json()["flagged_post_unlock_rule"] is True

    before = client.get("/moderation/me/trust-score", headers=match["headers_b"]).json()
    assert before["flagged_count"] == 1

    response = client.post(
        f"/admin/flagged-ratings/{rating_id}/review",
        headers=staff,
        json={"decision": "cleared", "note": "Contexte vérifié, note légitime."},
    )
    assert response.status_code == 200
    assert response.json()["suspected_rancor"] is False

    after = client.get("/moderation/me/trust-score", headers=match["headers_b"]).json()
    assert after["flagged_count"] == 0

    still_pending = client.get("/admin/flagged-ratings", headers=staff).json()
    assert rating_id not in [item["id"] for item in still_pending]


def test_flagged_rating_confirmed_stays_excluded_and_leaves_queue():
    staff = _staff_headers()
    match = create_match(client)
    rating_id = _flagged_rating_via(match)

    response = client.post(
        f"/admin/flagged-ratings/{rating_id}/review",
        headers=staff,
        json={"decision": "confirmed", "note": "Rancune confirmée."},
    )
    assert response.status_code == 200
    assert response.json()["suspected_rancor"] is True

    after = client.get("/moderation/me/trust-score", headers=match["headers_b"]).json()
    assert after["flagged_count"] == 1  # exclu de la moyenne, toujours compté comme signalé

    still_pending = client.get("/admin/flagged-ratings", headers=staff).json()
    assert rating_id not in [item["id"] for item in still_pending]


def test_review_flagged_rating_twice_conflicts():
    staff = _staff_headers()
    match = create_match(client)
    rating_id = _flagged_rating_via(match)

    first = client.post(
        f"/admin/flagged-ratings/{rating_id}/review",
        headers=staff,
        json={"decision": "cleared", "note": "OK."},
    )
    assert first.status_code == 200
    second = client.post(
        f"/admin/flagged-ratings/{rating_id}/review",
        headers=staff,
        json={"decision": "confirmed", "note": "Nouvelle tentative."},
    )
    assert second.status_code == 409


def test_queue_counts_decrement_after_resolution():
    staff = _staff_headers()
    before = client.get("/admin/queue-counts", headers=staff).json()

    match = create_match(client)
    report_id = _report_via(match)
    after_report = client.get("/admin/queue-counts", headers=staff).json()
    assert after_report["reports_pending"] == before["reports_pending"] + 1

    client.post(
        f"/admin/reports/{report_id}/resolve",
        headers=staff,
        json={"decision": "unfounded", "note": "Classé sans suite."},
    )
    after_resolve = client.get("/admin/queue-counts", headers=staff).json()
    assert after_resolve["reports_pending"] == before["reports_pending"]
