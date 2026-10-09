import uuid

from fastapi.testclient import TestClient

from app.db.session import SessionLocal
from app.main import app
from app.models.push_subscription import PushSubscription
from app.services.notifications import _is_subscription_dead
from tests.helpers import auth_headers, unique_phone

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
    headers = auth_headers(client, unique_phone())
    payload = _subscribe_payload()
    response = client.post("/notifications/subscribe", headers=headers, json=payload)
    assert response.status_code == 200
    assert _count_subscriptions_for_endpoint(payload["endpoint"]) == 1


def test_subscribe_upserts_on_same_endpoint():
    headers = auth_headers(client, unique_phone())
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
    headers = auth_headers(client, unique_phone())
    response = client.post(
        "/notifications/subscribe", headers=headers, json=_subscribe_payload("https://evil.example/x")
    )
    assert response.status_code == 400


def test_subscribe_rejects_non_https_endpoint():
    headers = auth_headers(client, unique_phone())
    response = client.post(
        "/notifications/subscribe",
        headers=headers,
        json=_subscribe_payload("http://fcm.googleapis.com/fcm/send/x"),
    )
    assert response.status_code == 400


def test_unsubscribe_removes_subscription():
    headers = auth_headers(client, unique_phone())
    endpoint = f"{_VALID_ENDPOINT_PREFIX}{uuid.uuid4().hex}"
    client.post("/notifications/subscribe", headers=headers, json=_subscribe_payload(endpoint))
    response = client.delete("/notifications/subscribe", headers=headers, params={"endpoint": endpoint})
    assert response.status_code == 200
    assert _count_subscriptions_for_endpoint(endpoint) == 0


def test_unsubscribe_on_missing_endpoint_404s():
    headers = auth_headers(client, unique_phone())
    response = client.delete(
        "/notifications/subscribe", headers=headers, params={"endpoint": "https://fcm.googleapis.com/x"}
    )
    assert response.status_code == 404


def test_unsubscribe_requires_ownership():
    headers_a = auth_headers(client, unique_phone())
    headers_b = auth_headers(client, unique_phone())
    endpoint = f"{_VALID_ENDPOINT_PREFIX}{uuid.uuid4().hex}"
    client.post("/notifications/subscribe", headers=headers_a, json=_subscribe_payload(endpoint))
    response = client.delete("/notifications/subscribe", headers=headers_b, params={"endpoint": endpoint})
    assert response.status_code == 404
    assert _count_subscriptions_for_endpoint(endpoint) == 1


def test_account_deletion_removes_push_subscriptions():
    headers = auth_headers(client, unique_phone())
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
