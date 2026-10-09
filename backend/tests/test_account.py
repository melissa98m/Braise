from fastapi.testclient import TestClient

from app.main import app
from tests.helpers import auth_headers, create_match, unique_email

client = TestClient(app)


def test_export_contains_profile_and_matches():
    match = create_match(client, interests_a=["cinéma"], interests_b=["escalade"])

    export = client.get("/auth/me/export", headers=match["headers_a"])
    assert export.status_code == 200
    body = export.json()
    assert body["account"]["email"] is not None
    assert body["public_profile"]["interests"] == ["cinéma"]
    assert len(body["matches"]) == 1
    assert body["matches"][0]["other_user_id"] == match["id_b"]


def test_delete_account_scrubs_profile_and_blocks_future_auth():
    headers = auth_headers(client, unique_email())
    client.put(
        "/profiles/me/public",
        headers=headers,
        json={
            "display_name": "À supprimer",
            "birth_date": "1996-01-01",
            "bio": "Une bio à effacer",
            "interests": ["cinéma"],
            "is_published": True,
        },
    )

    delete_response = client.delete("/auth/me", headers=headers)
    assert delete_response.status_code == 200

    still_using_old_token = client.get("/auth/me", headers=headers)
    assert still_using_old_token.status_code == 403


def test_deleted_users_messages_are_scrubbed_for_the_other_participant():
    match = create_match(client)

    with client.websocket_connect(
        f"/messaging/ws/{match['match_id']}?token={match['token_a']}"
    ) as ws_a:
        ws_a.send_json({"body": "Un message qui doit disparaître."})
        ws_a.receive_json()

    client.delete("/auth/me", headers=match["headers_a"])

    history = client.get(
        f"/messaging/matches/{match['match_id']}/messages", headers=match["headers_b"]
    ).json()
    assert any(m["body"] == "[message supprimé]" for m in history)
    assert not any(m["body"] == "Un message qui doit disparaître." for m in history)


def test_export_and_delete_require_auth():
    assert client.get("/auth/me/export").status_code == 401
    assert client.delete("/auth/me").status_code == 401


def test_deleted_account_email_is_tombstoned_and_reusable_for_a_fresh_account():
    email = unique_email()
    headers = auth_headers(client, email)
    old_id = client.get("/auth/me", headers=headers).json()["id"]
    assert client.delete("/auth/me", headers=headers).status_code == 200

    # L'adresse d'origine ne pointe plus vers le compte anonymisé : une nouvelle inscription avec
    # la même adresse repart d'un compte vierge, jamais de l'historique supprimé.
    new_me = client.get("/auth/me", headers=auth_headers(client, email)).json()
    assert new_me["id"] != old_id
    assert new_me["email"] == email
