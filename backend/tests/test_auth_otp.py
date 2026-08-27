from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_otp_round_trip():
    phone = "+33600000000"

    request_response = client.post("/auth/request-otp", json={"phone": phone})
    assert request_response.status_code == 200
    code = request_response.json()["debug_code"]
    assert code is not None

    verify_response = client.post("/auth/verify-otp", json={"phone": phone, "code": code})
    assert verify_response.status_code == 200
    assert "access_token" in verify_response.json()


def test_otp_wrong_code_rejected():
    phone = "+33600000001"
    client.post("/auth/request-otp", json={"phone": phone})

    verify_response = client.post("/auth/verify-otp", json={"phone": phone, "code": "000000"})
    assert verify_response.status_code == 400
