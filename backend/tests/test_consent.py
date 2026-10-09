from fastapi.testclient import TestClient

from app.main import app
from tests.helpers import auth_token, unique_email

client = TestClient(app)


def _verify_only(email: str) -> str:
    """Comme `tests.helpers.auth_token`, mais sans l'appel automatique à `POST /auth/consent` —
    pour tester le comportement d'un compte qui n'a encore rien consenti."""
    request_response = client.post("/auth/request-otp", json={"email": email})
    code = request_response.json()["debug_code"]
    verify_response = client.post("/auth/verify-otp", json={"email": email, "code": code})
    return verify_response.json()["access_token"]


def test_new_account_has_no_consent_and_cannot_publish_profile():
    headers = {"Authorization": f"Bearer {_verify_only(unique_email())}"}

    me = client.get("/auth/me", headers=headers)
    assert me.json()["consents_given"] is False

    publish = client.put(
        "/profiles/me/public",
        headers=headers,
        json={"display_name": "X", "birth_date": "1996-01-01", "is_published": True},
    )
    assert publish.status_code == 403


def test_partial_consent_is_not_complete():
    headers = {"Authorization": f"Bearer {_verify_only(unique_email())}"}

    partial = client.post(
        "/auth/consent",
        headers=headers,
        json={"age_confirmed": True, "cgu_accepted": True},
    )
    assert partial.status_code == 200
    assert partial.json()["consents_given"] is False

    publish = client.put(
        "/profiles/me/public",
        headers=headers,
        json={"display_name": "X", "birth_date": "1996-01-01", "is_published": True},
    )
    assert publish.status_code == 403


def test_full_consent_unlocks_profile_publish():
    headers = {"Authorization": f"Bearer {_verify_only(unique_email())}"}

    full = client.post(
        "/auth/consent",
        headers=headers,
        json={
            "age_confirmed": True,
            "cgu_accepted": True,
            "privacy_acknowledged": True,
            "sensitive_data_consented": True,
        },
    )
    assert full.json()["consents_given"] is True
    assert client.get("/auth/me", headers=headers).json()["consents_given"] is True

    publish = client.put(
        "/profiles/me/public",
        headers=headers,
        json={"display_name": "X", "birth_date": "1996-01-01", "is_published": True},
    )
    assert publish.status_code == 200


def test_consent_timestamps_do_not_move_once_set():
    headers = {"Authorization": f"Bearer {_verify_only(unique_email())}"}
    first = client.post(
        "/auth/consent",
        headers=headers,
        json={"age_confirmed": True},
    ).json()
    second = client.post(
        "/auth/consent",
        headers=headers,
        json={"age_confirmed": True},
    ).json()
    assert first["consent_age_at"] == second["consent_age_at"]


def test_helper_auth_token_already_grants_full_consent():
    headers = {"Authorization": f"Bearer {auth_token(client, unique_email())}"}
    assert client.get("/auth/me", headers=headers).json()["consents_given"] is True
