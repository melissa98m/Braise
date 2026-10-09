"""Outils de bêta (P26) : retours des testeur·se·s, erreurs remontées par l'app, jours d'activité."""

import uuid
from datetime import date

import redis
from fastapi.testclient import TestClient

from app.core.config import get_settings
from app.db.session import SessionLocal
from app.main import app
from app.models.client_error import ClientError
from app.models.feedback import Feedback
from app.models.user_activity import UserActivity
from app.services import client_errors as client_errors_service
from tests.helpers import auth_headers, create_published_user, make_staff, unique_email

client = TestClient(app)


def _me_id(headers: dict) -> str:
    return client.get("/auth/me", headers=headers).json()["id"]


def _staff_headers() -> dict:
    headers, staff_id = create_published_user(client, "Staff")
    make_staff(staff_id)
    return headers


# --- Retours -----------------------------------------------------------------------------


def test_feedback_requires_auth():
    response = client.post("/feedback", json={"category": "bug", "message": "Ça plante ici."})
    assert response.status_code == 401


def test_feedback_is_stored_and_listed_for_staff():
    headers = auth_headers(client, unique_email())
    marker = f"Le bouton ne répond pas {uuid.uuid4().hex}"
    response = client.post(
        "/feedback",
        headers=headers,
        json={"category": "bug", "message": marker, "context": "settings"},
    )
    assert response.status_code == 201

    staff = _staff_headers()
    items = client.get("/admin/feedback?status=new&limit=50", headers=staff).json()
    item = next(i for i in items if i["message"] == marker)
    assert item["category"] == "bug"
    assert item["author"]["id"] == _me_id(headers)

    done = client.post(f"/admin/feedback/{item['id']}/status", headers=staff, json={"status": "done"})
    assert done.status_code == 200
    assert done.json()["handled_at"] is not None
    assert all(i["id"] != item["id"] for i in client.get("/admin/feedback", headers=staff).json())


def test_feedback_validation_and_daily_cap(monkeypatch):
    headers = auth_headers(client, unique_email())
    too_short = client.post("/feedback", headers=headers, json={"category": "bug", "message": "ko"})
    assert too_short.status_code == 422
    bad_category = client.post(
        "/feedback", headers=headers, json={"category": "spam", "message": "Bonjour !"}
    )
    assert bad_category.status_code == 422

    from app.services import feedback as feedback_service

    monkeypatch.setattr(feedback_service, "MAX_FEEDBACK_PER_DAY", 2)
    for _ in range(2):
        ok = client.post("/feedback", headers=headers, json={"category": "idea", "message": "Une idée."})
        assert ok.status_code == 201
    capped = client.post("/feedback", headers=headers, json={"category": "idea", "message": "Une idée."})
    assert capped.status_code == 429


def test_admin_beta_queues_are_staff_only():
    headers = auth_headers(client, unique_email())
    assert client.get("/admin/feedback", headers=headers).status_code == 403
    assert client.get("/admin/client-errors", headers=headers).status_code == 403
    counts = client.get("/admin/queue-counts", headers=_staff_headers()).json()
    assert "feedback_new" in counts and "client_errors_new" in counts


# --- Erreurs remontées par l'app -----------------------------------------------------------


def _error(marker: str, **overrides) -> dict:
    payload = {
        "message": f"Null check operator used on a null value ({marker})",
        "stack": f"#0 ConversationScreen._send ({marker}.dart:42)\n#1 ...",
        "source": "flutter",
        "path": "/",
    }
    payload.update(overrides)
    return payload


def _error_row(marker: str) -> ClientError:
    with SessionLocal() as db:
        return db.query(ClientError).filter(ClientError.message.contains(marker)).one()


def test_client_error_accepted_without_auth_and_grouped_by_fingerprint():
    marker = f"m{uuid.uuid4().hex}"
    assert client.post("/client-errors", json=_error(marker)).status_code == 204
    assert client.post("/client-errors", json=_error(marker)).status_code == 204

    row = _error_row(marker)
    assert row.occurrences == 2
    assert row.last_user_id is None


def test_client_error_numbers_do_not_split_the_fingerprint_and_query_is_dropped():
    marker = f"m{uuid.uuid4().hex}"
    client.post("/client-errors", json=_error(marker, message=f"RangeError {marker}: index 3 out of 5"))
    client.post(
        "/client-errors",
        json=_error(marker, message=f"RangeError {marker}: index 7 out of 9", path="/?match=abc"),
    )
    row = _error_row(marker)
    # Même erreur, valeurs différentes : une seule ligne, deux occurrences.
    assert row.occurrences == 2
    assert row.path == "/"


def test_client_error_links_the_signed_in_user_and_reopens_when_it_recurs():
    headers = auth_headers(client, unique_email())
    marker = f"m{uuid.uuid4().hex}"
    client.post("/client-errors", headers=headers, json=_error(marker))
    row = _error_row(marker)
    assert str(row.last_user_id) == _me_id(headers)

    staff = _staff_headers()
    client.post(f"/admin/client-errors/{row.id}/status", headers=staff, json={"status": "done"})
    assert _error_row(marker).status == "done"
    client.post("/client-errors", json=_error(marker))
    # Une erreur « traitée » qui revient est une régression : elle repasse à traiter.
    assert _error_row(marker).status == "new"


def test_client_error_long_payload_is_truncated_not_refused():
    marker = f"m{uuid.uuid4().hex}"
    response = client.post(
        "/client-errors", json=_error(marker, message=marker + "x" * 3000, stack="y" * 20000)
    )
    assert response.status_code == 204
    row = _error_row(marker)
    assert len(row.message) == client_errors_service.MESSAGE_MAX
    assert len(row.stack) == client_errors_service.STACK_MAX


def test_client_error_capped_per_ip(monkeypatch):
    monkeypatch.setattr(client_errors_service, "MAX_REPORTS_PER_IP_PER_HOUR", 2)
    key = "bresonne:client-errors:ip:testclient"
    redis.Redis.from_url(get_settings().redis_url).delete(key)
    try:
        for _ in range(2):
            assert client.post("/client-errors", json=_error(uuid.uuid4().hex)).status_code == 204
        assert client.post("/client-errors", json=_error(uuid.uuid4().hex)).status_code == 429
    finally:
        redis.Redis.from_url(get_settings().redis_url).delete(key)


# --- Jours d'activité ------------------------------------------------------------------------


def _activity_days(user_id: str) -> list[date]:
    with SessionLocal() as db:
        return [
            row.day for row in db.query(UserActivity).filter(UserActivity.user_id == uuid.UUID(user_id))
        ]


def test_authenticated_requests_record_one_activity_row_per_day():
    headers = auth_headers(client, unique_email())
    user_id = _me_id(headers)
    client.get("/auth/me", headers=headers)
    client.get("/profiles/cities", headers=headers)
    assert _activity_days(user_id) == [date.today()]


def test_account_deletion_removes_feedback_and_activity_and_export_lists_them():
    headers = auth_headers(client, unique_email())
    user_id = _me_id(headers)
    client.post("/feedback", headers=headers, json={"category": "other", "message": "Merci pour l'app !"})
    marker = f"m{uuid.uuid4().hex}"
    client.post("/client-errors", headers=headers, json=_error(marker))

    export = client.get("/auth/me/export", headers=headers).json()
    assert export["feedback_sent"][0]["message"] == "Merci pour l'app !"
    assert export["active_days"] == [date.today().isoformat()]

    assert client.delete("/auth/me", headers=headers).status_code == 200
    with SessionLocal() as db:
        assert db.query(Feedback).filter(Feedback.user_id == uuid.UUID(user_id)).count() == 0
    assert _activity_days(user_id) == []
    # L'erreur reste (utile au produit) mais n'est plus rattachée au compte supprimé.
    assert _error_row(marker).last_user_id is None
