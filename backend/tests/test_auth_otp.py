import uuid

import pytest
import redis
from fastapi.testclient import TestClient
from pydantic import ValidationError

from app.core.config import Settings, get_settings
from app.db.session import SessionLocal
from app.main import app
from app.models.otp_challenge import OtpChallenge
from app.models.user import User
from app.services import email as email_service
from app.services.otp import MAX_OTP_ATTEMPTS, MAX_REQUESTS_PER_EMAIL_PER_HOUR
from tests.helpers import auth_token, force_otp_requested_at, unique_email

client = TestClient(app)


def test_otp_round_trip():
    email = unique_email()

    request_response = client.post("/auth/request-otp", json={"email": email})
    assert request_response.status_code == 200
    code = request_response.json()["debug_code"]
    assert code is not None

    verify_response = client.post("/auth/verify-otp", json={"email": email, "code": code})
    assert verify_response.status_code == 200
    assert "access_token" in verify_response.json()


def test_otp_wrong_code_rejected():
    email = unique_email()
    client.post("/auth/request-otp", json={"email": email})

    verify_response = client.post("/auth/verify-otp", json={"email": email, "code": "000000"})
    assert verify_response.status_code == 400


def test_me_requires_valid_token():
    email = unique_email()
    request_response = client.post("/auth/request-otp", json={"email": email})
    code = request_response.json()["debug_code"]
    verify_response = client.post("/auth/verify-otp", json={"email": email, "code": code})
    token = verify_response.json()["access_token"]

    me_response = client.get("/auth/me", headers={"Authorization": f"Bearer {token}"})
    assert me_response.status_code == 200
    assert me_response.json()["email"] == email
    assert me_response.json()["is_verified"] is True

    unauthenticated = client.get("/auth/me")
    assert unauthenticated.status_code == 401


def test_request_otp_throttled_when_repeated_too_soon():
    email = unique_email()
    first = client.post("/auth/request-otp", json={"email": email})
    assert first.status_code == 200

    second = client.post("/auth/request-otp", json={"email": email})
    assert second.status_code == 429


def test_request_otp_allowed_again_once_the_throttle_window_has_passed():
    email = unique_email()
    client.post("/auth/request-otp", json={"email": email})

    force_otp_requested_at(email, seconds_ago=60)

    second = client.post("/auth/request-otp", json={"email": email})
    assert second.status_code == 200


def test_verify_otp_locks_out_after_max_failed_attempts():
    email = unique_email()
    request_response = client.post("/auth/request-otp", json={"email": email})
    code = request_response.json()["debug_code"]

    for _ in range(MAX_OTP_ATTEMPTS):
        wrong = client.post("/auth/verify-otp", json={"email": email, "code": "000000"})
        assert wrong.status_code == 400

    # Le code correct ne doit plus fonctionner une fois la limite d'essais atteinte — sinon
    # MAX_OTP_ATTEMPTS ne fait que ralentir un brute force au lieu de l'arrêter.
    locked_out = client.post("/auth/verify-otp", json={"email": email, "code": code})
    assert locked_out.status_code == 400


def test_verify_otp_failed_attempts_reset_by_a_fresh_code():
    email = unique_email()
    client.post("/auth/request-otp", json={"email": email})
    for _ in range(MAX_OTP_ATTEMPTS - 1):
        wrong = client.post("/auth/verify-otp", json={"email": email, "code": "000000"})
        assert wrong.status_code == 400

    force_otp_requested_at(email, seconds_ago=60)
    fresh = client.post("/auth/request-otp", json={"email": email})
    fresh_code = fresh.json()["debug_code"]

    # Un nouveau code repart avec un compteur d'essais à zéro, pas la limite héritée du code
    # précédent.
    verify_response = client.post("/auth/verify-otp", json={"email": email, "code": fresh_code})
    assert verify_response.status_code == 200


def test_request_otp_never_creates_an_account_before_verification():
    email = unique_email()
    response = client.post("/auth/request-otp", json={"email": email})
    assert response.status_code == 200

    with SessionLocal() as db:
        assert db.query(User).filter(User.email == email).count() == 0
        challenge = db.query(OtpChallenge).filter(OtpChallenge.email == email).one()
        # Jamais le code en clair en base : un HMAC-SHA256 hexadécimal.
        assert challenge.code_hash != response.json()["debug_code"]
        assert len(challenge.code_hash) == 64


def test_request_otp_response_is_identical_for_new_and_existing_accounts():
    existing = unique_email()
    auth_token(client, existing)
    # Vérification réussie = la ligne de challenge a disparu : aucun délai de renvoi à attendre.
    assert not _has_challenge(existing)

    new_response = client.post("/auth/request-otp", json={"email": unique_email()})
    existing_response = client.post("/auth/request-otp", json={"email": existing})
    assert new_response.status_code == existing_response.status_code == 200
    assert new_response.json()["message"] == existing_response.json()["message"]


def test_successful_verification_consumes_the_code():
    email = unique_email()
    code = client.post("/auth/request-otp", json={"email": email}).json()["debug_code"]
    assert client.post("/auth/verify-otp", json={"email": email, "code": code}).status_code == 200
    # Usage unique : le même code ne rouvre pas une deuxième session.
    assert client.post("/auth/verify-otp", json={"email": email, "code": code}).status_code == 400


def test_email_is_normalized_to_lowercase():
    local = f"Lea-{uuid.uuid4().hex[:8]}"
    code = client.post(
        "/auth/request-otp", json={"email": f"  {local}@Example.COM "}
    ).json()["debug_code"]
    verify = client.post(
        "/auth/verify-otp", json={"email": f"{local.lower()}@example.com", "code": code}
    )
    assert verify.status_code == 200
    token = verify.json()["access_token"]
    me = client.get("/auth/me", headers={"Authorization": f"Bearer {token}"}).json()
    assert me["email"] == f"{local.lower()}@example.com"


@pytest.mark.parametrize("email", ["pas-un-email", "a@localhost", "a@x.invalid", ""])
def test_request_otp_rejects_invalid_emails(email):
    assert client.post("/auth/request-otp", json={"email": email}).status_code == 422


def test_request_otp_capped_per_email_per_hour():
    email = unique_email()
    for _ in range(MAX_REQUESTS_PER_EMAIL_PER_HOUR):
        assert client.post("/auth/request-otp", json={"email": email}).status_code == 200
        force_otp_requested_at(email, seconds_ago=60)

    capped = client.post("/auth/request-otp", json={"email": email})
    assert capped.status_code == 429


def test_request_otp_capped_per_ip(monkeypatch):
    settings = get_settings()
    monkeypatch.setattr(settings, "otp_requests_per_ip_per_hour", 2)
    # Compteur Redis partagé entre runs (fenêtre d'une heure) : repartir de zéro pour l'IP du
    # TestClient, sinon un relancement dans l'heure hériterait du compte précédent.
    redis.Redis.from_url(settings.redis_url).delete("bresonne:otp:ip:testclient")
    try:
        assert client.post("/auth/request-otp", json={"email": unique_email()}).status_code == 200
        assert client.post("/auth/request-otp", json={"email": unique_email()}).status_code == 200
        assert client.post("/auth/request-otp", json={"email": unique_email()}).status_code == 429
    finally:
        redis.Redis.from_url(settings.redis_url).delete("bresonne:otp:ip:testclient")


def test_smtp_failure_never_raises(monkeypatch):
    settings = get_settings()
    monkeypatch.setattr(settings, "email_backend", "smtp")
    monkeypatch.setattr(settings, "smtp_host", "127.0.0.1")
    monkeypatch.setattr(settings, "smtp_port", 1)
    monkeypatch.setattr(settings, "smtp_security", "none")
    # Appelé en tâche de fond après la réponse : un fournisseur injoignable est journalisé, jamais
    # propagé (la réponse HTTP doit rester identique que l'envoi réussisse ou non).
    email_service.send_otp_email(unique_email(), "123456", 10)


def _base_settings(**overrides) -> dict:
    values = {
        "database_url": "postgresql+psycopg://u:p@db/x",
        "jwt_secret": "x" * 48,
        "minio_endpoint": "minio:9000",
        "minio_public_endpoint": "localhost:9000",
        "minio_root_user": "u",
        "minio_root_password": "a-real-password",
        "minio_bucket": "b",
        "minio_kms_secret_key": "key:abcdef",
        "vapid_private_key": "k",
        "vapid_public_key": "k",
        "environment": "beta",
        "debug_otp": False,
        "email_backend": "smtp",
        "smtp_host": "smtp.resend.com",
        "smtp_password": "re_real_key",
        "email_from": "Bresonne <no-reply@bresonne.fr>",
    }
    values.update(overrides)
    return values


def test_safe_beta_config_is_accepted():
    Settings(_env_file=None, **_base_settings(enable_debug_subscription_endpoint=True))


@pytest.mark.parametrize(
    "overrides",
    [
        {"debug_otp": True},
        {"email_backend": "console"},
        {"jwt_secret": "changeme-dev-only"},
        {"smtp_password": "CHANGE_ME"},
        {"email_from": "Bresonne <no-reply@example.com>"},
        {"smtp_security": "none"},
        {"environment": "production", "enable_debug_subscription_endpoint": True},
        {"push_enabled": True, "vapid_private_key": "CHANGE_ME"},
    ],
)
def test_unsafe_config_refused_outside_development(overrides):
    with pytest.raises(ValidationError):
        Settings(_env_file=None, **_base_settings(**overrides))


def _has_challenge(email: str) -> bool:
    with SessionLocal() as db:
        return db.query(OtpChallenge).filter(OtpChallenge.email == email).count() > 0
