import uuid
from datetime import date

from fastapi.testclient import TestClient

from app.core.config import get_settings
from app.db.session import SessionLocal
from app.main import app
from app.models.daily_question import DailyQuestion
from app.models.push_subscription import PushSubscription
from app.services.notifications import (
    _is_subscription_dead,
    message_push,
    send_daily_question_reminders,
    users_to_remind_for_daily_question,
)
from tests.helpers import auth_headers, create_match, force_match_unlocked, unique_email

client = TestClient(app)

_VALID_ENDPOINT_PREFIX = "https://fcm.googleapis.com/fcm/send/"


def _subscribe_payload(endpoint: str | None = None) -> dict:
    return {
        "endpoint": endpoint or f"{_VALID_ENDPOINT_PREFIX}{uuid.uuid4().hex}",
        "keys": {"p256dh": "fake-p256dh-key", "auth": "fake-auth-key"},
        "user_agent": "pytest",
    }


def _count_subscriptions_for_endpoint(endpoint: str) -> int:
    db = SessionLocal()
    try:
        return db.query(PushSubscription).filter(PushSubscription.endpoint == endpoint).count()
    finally:
        db.close()


def test_get_vapid_public_key_is_unauthenticated_and_returns_configured_key():
    response = client.get("/notifications/vapid-public-key")
    assert response.status_code == 200
    assert response.json()["public_key"]


def test_subscribe_requires_auth():
    response = client.post("/notifications/subscribe", json=_subscribe_payload())
    assert response.status_code == 401


def test_unsubscribe_requires_auth():
    response = client.delete("/notifications/subscribe", params={"endpoint": "https://x"})
    assert response.status_code == 401


def test_subscribe_creates_a_subscription():
    headers = auth_headers(client, unique_email())
    payload = _subscribe_payload()
    response = client.post("/notifications/subscribe", headers=headers, json=payload)
    assert response.status_code == 200
    assert _count_subscriptions_for_endpoint(payload["endpoint"]) == 1


def test_subscribe_upserts_on_same_endpoint():
    headers = auth_headers(client, unique_email())
    endpoint = f"{_VALID_ENDPOINT_PREFIX}{uuid.uuid4().hex}"
    client.post("/notifications/subscribe", headers=headers, json=_subscribe_payload(endpoint))
    second_payload = _subscribe_payload(endpoint)
    second_payload["keys"]["p256dh"] = "updated-p256dh-key"
    response = client.post("/notifications/subscribe", headers=headers, json=second_payload)
    assert response.status_code == 200
    assert _count_subscriptions_for_endpoint(endpoint) == 1

    db = SessionLocal()
    try:
        sub = db.query(PushSubscription).filter(PushSubscription.endpoint == endpoint).one()
        assert sub.p256dh == "updated-p256dh-key"
    finally:
        db.close()


def test_subscribe_rejects_disallowed_endpoint_host():
    headers = auth_headers(client, unique_email())
    response = client.post(
        "/notifications/subscribe", headers=headers, json=_subscribe_payload("https://evil.example/x")
    )
    assert response.status_code == 400


def test_subscribe_rejects_non_https_endpoint():
    headers = auth_headers(client, unique_email())
    response = client.post(
        "/notifications/subscribe",
        headers=headers,
        json=_subscribe_payload("http://fcm.googleapis.com/fcm/send/x"),
    )
    assert response.status_code == 400


def test_unsubscribe_removes_subscription():
    headers = auth_headers(client, unique_email())
    endpoint = f"{_VALID_ENDPOINT_PREFIX}{uuid.uuid4().hex}"
    client.post("/notifications/subscribe", headers=headers, json=_subscribe_payload(endpoint))
    response = client.delete("/notifications/subscribe", headers=headers, params={"endpoint": endpoint})
    assert response.status_code == 200
    assert _count_subscriptions_for_endpoint(endpoint) == 0


def test_unsubscribe_on_missing_endpoint_404s():
    headers = auth_headers(client, unique_email())
    response = client.delete(
        "/notifications/subscribe", headers=headers, params={"endpoint": "https://fcm.googleapis.com/x"}
    )
    assert response.status_code == 404


def test_unsubscribe_requires_ownership():
    headers_a = auth_headers(client, unique_email())
    headers_b = auth_headers(client, unique_email())
    endpoint = f"{_VALID_ENDPOINT_PREFIX}{uuid.uuid4().hex}"
    client.post("/notifications/subscribe", headers=headers_a, json=_subscribe_payload(endpoint))
    response = client.delete("/notifications/subscribe", headers=headers_b, params={"endpoint": endpoint})
    assert response.status_code == 404
    assert _count_subscriptions_for_endpoint(endpoint) == 1


def test_account_deletion_removes_push_subscriptions():
    headers = auth_headers(client, unique_email())
    endpoint = f"{_VALID_ENDPOINT_PREFIX}{uuid.uuid4().hex}"
    client.post("/notifications/subscribe", headers=headers, json=_subscribe_payload(endpoint))
    assert _count_subscriptions_for_endpoint(endpoint) == 1

    response = client.delete("/auth/me", headers=headers)
    assert response.status_code == 200
    assert _count_subscriptions_for_endpoint(endpoint) == 0


def test_is_subscription_dead_treats_404_and_410_as_dead_others_as_not():
    assert _is_subscription_dead(404) is True
    assert _is_subscription_dead(410) is True
    assert _is_subscription_dead(200) is False
    assert _is_subscription_dead(500) is False
    assert _is_subscription_dead(None) is False


def test_message_push_never_carries_message_content():
    match_id = uuid.uuid4()
    push = message_push("Léa", match_id)
    assert push["title"] == "Nouveau message de Léa"
    assert push["body"] == "Ouvrez Bresonne pour le lire."
    # Regroupée par conversation, et le clic ouvre directement cette conversation.
    assert push["tag"] == f"match-{match_id}"
    assert push["url"] == f"/?match={match_id}"


def _subscribe(headers: dict, notify_question: bool = True) -> None:
    payload = _subscribe_payload()
    payload["notify_question"] = notify_question
    assert client.post("/notifications/subscribe", headers=headers, json=payload).status_code == 200


def _to_remind() -> set[str]:
    with SessionLocal() as db:
        return {str(u) for u in users_to_remind_for_daily_question(db, date.today())}


def test_daily_reminder_targets_subscribed_users_with_an_unanswered_question():
    match = create_match(client, interests_a=["cinéma"], interests_b=["cinéma"])
    _subscribe(match["headers_a"], notify_question=True)
    _subscribe(match["headers_b"], notify_question=False)

    to_remind = _to_remind()
    assert match["id_a"] in to_remind
    # Catégorie « question » désactivée de son côté : jamais de rappel.
    assert match["id_b"] not in to_remind


def test_daily_reminder_skips_a_question_already_answered_today():
    match = create_match(client, interests_a=["cinéma"], interests_b=["cinéma"])
    _subscribe(match["headers_a"])
    client.get(f"/messaging/matches/{match['match_id']}/daily-question", headers=match["headers_a"])
    with SessionLocal() as db:
        question = (
            db.query(DailyQuestion)
            .filter(
                DailyQuestion.match_id == uuid.UUID(match["match_id"]),
                DailyQuestion.for_user_id == uuid.UUID(match["id_a"]),
            )
            .one()
        )
        correct = question.correct_answer
    client.post(
        f"/messaging/matches/{match['match_id']}/daily-question/answer",
        headers=match["headers_a"],
        json={"selected": correct},
    )
    assert match["id_a"] not in _to_remind()


def test_daily_reminder_skips_unlocked_matches():
    match = create_match(client, interests_a=["cinéma"], interests_b=["cinéma"])
    _subscribe(match["headers_a"])
    force_match_unlocked(match["match_id"])
    # Plus rien à gagner en flammes une fois le voile levé : pas de rappel pour ce match.
    assert match["id_a"] not in _to_remind()


def test_daily_reminder_is_sent_at_most_once_per_day(monkeypatch):
    monkeypatch.setattr(get_settings(), "push_enabled", True)
    match = create_match(client, interests_a=["cinéma"], interests_b=["cinéma"])
    _subscribe(match["headers_a"])
    # Les clés de test sont factices : le chiffrement échoue avant tout appel réseau, et cet échec
    # est isolé par abonnement (send_push_to_user) — la boucle de rappels continue quand même.
    first = {str(u) for u in send_daily_question_reminders()}
    second = {str(u) for u in send_daily_question_reminders()}
    assert match["id_a"] in first
    assert match["id_a"] not in second
