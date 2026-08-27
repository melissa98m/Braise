from fastapi.testclient import TestClient

from app.main import app
from tests.helpers import unique_phone

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
