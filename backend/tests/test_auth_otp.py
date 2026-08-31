from fastapi.testclient import TestClient

from app.main import app
from app.services.otp import MAX_OTP_ATTEMPTS
from tests.helpers import force_otp_requested_at, unique_phone

client = TestClient(app)


def test_otp_round_trip():
    phone = unique_phone()

    request_response = client.post("/auth/request-otp", json={"phone": phone})
    assert request_response.status_code == 200
    code = request_response.json()["debug_code"]
    assert code is not None

    verify_response = client.post("/auth/verify-otp", json={"phone": phone, "code": code})
    assert verify_response.status_code == 200
    assert "access_token" in verify_response.json()


def test_otp_wrong_code_rejected():
    phone = unique_phone()
    client.post("/auth/request-otp", json={"phone": phone})

    verify_response = client.post("/auth/verify-otp", json={"phone": phone, "code": "000000"})
    assert verify_response.status_code == 400


def test_me_requires_valid_token():
    phone = unique_phone()
    request_response = client.post("/auth/request-otp", json={"phone": phone})
    code = request_response.json()["debug_code"]
    verify_response = client.post("/auth/verify-otp", json={"phone": phone, "code": code})
    token = verify_response.json()["access_token"]

    me_response = client.get("/auth/me", headers={"Authorization": f"Bearer {token}"})
    assert me_response.status_code == 200
    assert me_response.json()["phone"] == phone
    assert me_response.json()["is_verified"] is True

    unauthenticated = client.get("/auth/me")
    assert unauthenticated.status_code == 401


def test_request_otp_throttled_when_repeated_too_soon():
    phone = unique_phone()
    first = client.post("/auth/request-otp", json={"phone": phone})
    assert first.status_code == 200

    second = client.post("/auth/request-otp", json={"phone": phone})
    assert second.status_code == 429


def test_request_otp_allowed_again_once_the_throttle_window_has_passed():
    phone = unique_phone()
    client.post("/auth/request-otp", json={"phone": phone})

    force_otp_requested_at(phone, seconds_ago=60)

    second = client.post("/auth/request-otp", json={"phone": phone})
    assert second.status_code == 200


def test_verify_otp_locks_out_after_max_failed_attempts():
    phone = unique_phone()
    request_response = client.post("/auth/request-otp", json={"phone": phone})
    code = request_response.json()["debug_code"]

    for _ in range(MAX_OTP_ATTEMPTS):
        wrong = client.post("/auth/verify-otp", json={"phone": phone, "code": "000000"})
        assert wrong.status_code == 400

    # Le code correct ne doit plus fonctionner une fois la limite d'essais atteinte — sinon
    # MAX_OTP_ATTEMPTS ne fait que ralentir un brute force au lieu de l'arrêter.
    locked_out = client.post("/auth/verify-otp", json={"phone": phone, "code": code})
    assert locked_out.status_code == 400


def test_verify_otp_failed_attempts_reset_by_a_fresh_code():
    phone = unique_phone()
    client.post("/auth/request-otp", json={"phone": phone})
    for _ in range(MAX_OTP_ATTEMPTS - 1):
        wrong = client.post("/auth/verify-otp", json={"phone": phone, "code": "000000"})
        assert wrong.status_code == 400

    force_otp_requested_at(phone, seconds_ago=60)
    fresh = client.post("/auth/request-otp", json={"phone": phone})
    fresh_code = fresh.json()["debug_code"]

    # Un nouveau code repart avec un compteur d'essais à zéro, pas la limite héritée du code
    # précédent.
    verify_response = client.post("/auth/verify-otp", json={"phone": phone, "code": fresh_code})
    assert verify_response.status_code == 200
