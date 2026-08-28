from fastapi.testclient import TestClient

from app.main import app
from tests.helpers import auth_headers, unique_phone

client = TestClient(app)


def test_subscription_defaults_to_free():
    headers = auth_headers(client, unique_phone())
    response = client.get("/subscriptions/me", headers=headers)
    assert response.status_code == 200
    body = response.json()
    assert body["is_premium"] is False
    assert body["expires_at"] is None


def test_debug_activate_grants_premium():
    headers = auth_headers(client, unique_phone())
    response = client.post("/subscriptions/debug-activate", headers=headers)
    assert response.status_code == 200
    body = response.json()
    assert body["is_premium"] is True
    assert body["expires_at"] is not None
    assert body["cancel_at_period_end"] is False

    me = client.get("/subscriptions/me", headers=headers).json()
    assert me["is_premium"] is True


def test_premium_badge_reflected_on_public_profile():
    headers = auth_headers(client, unique_phone())
    client.put(
        "/profiles/me/public",
        headers=headers,
        json={
            "display_name": "Premium",
            "birth_date": "1996-01-01",
            "bio": "",
            "interests": [],
            "is_published": True,
        },
    )
    before = client.get("/profiles/me/public", headers=headers).json()
    assert before["is_premium"] is False

    client.post("/subscriptions/debug-activate", headers=headers)
    after = client.get("/profiles/me/public", headers=headers).json()
    assert after["is_premium"] is True


def test_cancel_keeps_premium_until_expiry():
    headers = auth_headers(client, unique_phone())
    client.post("/subscriptions/debug-activate", headers=headers)

    response = client.post("/subscriptions/cancel", headers=headers)
    assert response.status_code == 200
    body = response.json()
    # Résiliation = pas de renouvellement, pas de coupure immédiate.
    assert body["cancel_at_period_end"] is True
    assert body["is_premium"] is True


def test_subscription_endpoints_require_auth():
    assert client.get("/subscriptions/me").status_code == 401
    assert client.post("/subscriptions/debug-activate").status_code == 401
    assert client.post("/subscriptions/cancel").status_code == 401
