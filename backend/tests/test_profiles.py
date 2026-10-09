import io
import uuid
from datetime import date

from fastapi.testclient import TestClient

from app.db.session import SessionLocal
from app.main import app
from app.models.photo_access_log import PhotoAccessLog
from tests.helpers import auth_headers, create_match, force_match_unlocked, unique_email

client = TestClient(app)


def _auth_headers(email: str) -> dict:
    return auth_headers(client, email)


def test_public_profile_round_trip():
    headers = _auth_headers(unique_email())

    get_before = client.get("/profiles/me/public", headers=headers)
    assert get_before.status_code == 200
    assert get_before.json()["display_name"] == ""

    payload = {
        "display_name": "Sonia",
        "birth_date": "1996-04-12",
        "bio": "Je fais des cartes sonores des villes où je n'habiterai jamais.",
        "interests": ["Field recording", "Rando de nuit"],
        "is_published": True,
    }
    put_response = client.put("/profiles/me/public", json=payload, headers=headers)
    assert put_response.status_code == 200
    body = put_response.json()
    assert body["display_name"] == "Sonia"
    assert body["is_published"] is True
    assert body["interests"] == ["Field recording", "Rando de nuit"]
    assert isinstance(body["age"], int) and body["age"] > 18
    assert body["avatar"]["from_color"].startswith("#")
    # Badge "profil vérifié" (cahier des charges A.5) : posé dès que l'OTP a réussi une fois
    # (services/otp.py), avant même toute publication de profil.
    assert body["is_verified"] is True


def test_public_profile_rejects_minor():
    headers = _auth_headers(unique_email())

    too_young = date.today().replace(year=date.today().year - 10)
    payload = {
        "display_name": "Trop jeune",
        "birth_date": too_young.isoformat(),
        "bio": "",
        "interests": [],
    }
    response = client.put("/profiles/me/public", json=payload, headers=headers)
    assert response.status_code == 422


def test_avatar_regenerate_changes_seed():
    headers = _auth_headers(unique_email())
    first = client.post("/profiles/me/avatar/regenerate", headers=headers).json()
    second = client.post("/profiles/me/avatar/regenerate", headers=headers).json()
    assert first["seed"] != second["seed"]


def test_public_profile_requires_auth():
    response = client.get("/profiles/me/public")
    assert response.status_code == 401


def test_private_photo_upload_list_delete():
    headers = _auth_headers(unique_email())

    fake_image = io.BytesIO(b"\xff\xd8\xff" + b"0" * 100)  # en-tête JPEG minimal
    upload = client.post(
        "/profiles/me/private/photos",
        headers=headers,
        files={"file": ("photo.jpg", fake_image, "image/jpeg")},
    )
    assert upload.status_code == 200
    photos = upload.json()["photos"]
    assert len(photos) == 1
    assert photos[0]["url"].startswith("http")

    listing = client.get("/profiles/me/private", headers=headers)
    assert listing.status_code == 200
    assert len(listing.json()["photos"]) == 1

    key = photos[0]["key"]
    delete = client.delete(f"/profiles/me/private/photos/{key}", headers=headers)
    assert delete.status_code == 200
    assert delete.json()["photos"] == []


def test_private_photo_max_three():
    headers = _auth_headers(unique_email())
    for _ in range(3):
        fake_image = io.BytesIO(b"\xff\xd8\xff" + b"0" * 50)
        response = client.post(
            "/profiles/me/private/photos",
            headers=headers,
            files={"file": ("photo.jpg", fake_image, "image/jpeg")},
        )
        assert response.status_code == 200

    fourth = io.BytesIO(b"\xff\xd8\xff" + b"0" * 50)
    response = client.post(
        "/profiles/me/private/photos",
        headers=headers,
        files={"file": ("photo.jpg", fourth, "image/jpeg")},
    )
    assert response.status_code == 400


def test_partner_photos_blocked_before_unlock():
    match = create_match(client)
    response = client.get(
        f"/profiles/matches/{match['match_id']}/partner-photos", headers=match["headers_a"]
    )
    assert response.status_code == 403


def test_partner_photos_available_after_unlock_and_logged():
    match = create_match(client)
    fake_image = io.BytesIO(b"\xff\xd8\xff" + b"0" * 100)
    client.post(
        "/profiles/me/private/photos",
        headers=match["headers_b"],
        files={"file": ("photo.jpg", fake_image, "image/jpeg")},
    )
    force_match_unlocked(match["match_id"])

    response = client.get(
        f"/profiles/matches/{match['match_id']}/partner-photos", headers=match["headers_a"]
    )
    assert response.status_code == 200
    photos = response.json()["photos"]
    assert len(photos) == 1
    assert photos[0]["url"].startswith("http")

    db = SessionLocal()
    try:
        logged = (
            db.query(PhotoAccessLog)
            .filter(
                PhotoAccessLog.match_id == uuid.UUID(match["match_id"]),
                PhotoAccessLog.viewer_id == uuid.UUID(match["id_a"]),
                PhotoAccessLog.owner_id == uuid.UUID(match["id_b"]),
            )
            .count()
        )
        assert logged == 1
    finally:
        db.close()


def test_partner_photos_requires_match_participant():
    match = create_match(client)
    outsider_headers = auth_headers(client, unique_email())
    response = client.get(
        f"/profiles/matches/{match['match_id']}/partner-photos", headers=outsider_headers
    )
    assert response.status_code == 404
