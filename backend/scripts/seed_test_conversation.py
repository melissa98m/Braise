"""Crée une conversation de test : fait matcher deux personas de seed_test_data.py puis échange
quelques messages via le vrai WebSocket de messagerie, pour vérifier que le flux marche de bout
en bout (match -> connexion WS -> envoi -> broadcast -> persistance).

Prérequis : avoir lancé `docker compose run --rm backend python scripts/seed_test_data.py` au
moins une fois (Alice et Bruno doivent déjà exister).

Usage :
    docker compose run --rm backend python scripts/seed_test_conversation.py
"""

import asyncio
import json

import httpx
import websockets

BASE_URL = "http://backend:8000"
WS_BASE_URL = "ws://backend:8000"

ALICE_EMAIL = "alice@example.com"
BRUNO_EMAIL = "bruno@example.com"


def login(client: httpx.Client, email: str) -> tuple[str, str]:
    otp = client.post("/auth/request-otp", json={"email": email})
    otp.raise_for_status()
    code = otp.json()["debug_code"]
    if code is None:
        raise RuntimeError("debug_code est vide : DEBUG_OTP doit être à true dans backend/.env.")

    token_response = client.post("/auth/verify-otp", json={"email": email, "code": code})
    token_response.raise_for_status()
    token = token_response.json()["access_token"]

    me = client.get("/auth/me", headers={"Authorization": f"Bearer {token}"})
    me.raise_for_status()
    return token, me.json()["id"]


def ensure_match(client: httpx.Client, token_a: str, id_a: str, token_b: str, id_b: str) -> str:
    headers_a = {"Authorization": f"Bearer {token_a}"}
    headers_b = {"Authorization": f"Bearer {token_b}"}

    for headers, target_id in ((headers_a, id_b), (headers_b, id_a)):
        response = client.post(
            "/discovery/swipe",
            headers=headers,
            json={"to_user_id": target_id, "decision": "like"},
        )
        # 409 = déjà swipé lors d'un run précédent du script (idempotence) : pas une erreur ici.
        if response.status_code not in (200, 409):
            response.raise_for_status()

    matches = client.get("/discovery/matches", headers=headers_a).json()
    match_id = next(m["match_id"] for m in matches if m["other_user_id"] == id_b)
    return match_id


async def send_message(token: str, match_id: str, body: str) -> None:
    uri = f"{WS_BASE_URL}/messaging/ws/{match_id}?token={token}"
    async with websockets.connect(uri) as ws:
        await ws.send(json.dumps({"body": body}))
        reply = await asyncio.wait_for(ws.recv(), timeout=5)
        print("  ->", json.loads(reply)["body"])


async def exchange(token_a: str, token_b: str, match_id: str) -> None:
    await send_message(token_a, match_id, "Salut Bruno, bien joué le voyage dont tu parlais !")
    await send_message(token_b, match_id, "Salut Alice, oui c'était en Islande, et toi ?")
    await send_message(token_a, match_id, "Jamais été, ça me tente beaucoup !")


def main() -> None:
    with httpx.Client(base_url=BASE_URL, timeout=10) as client:
        token_a, id_a = login(client, ALICE_EMAIL)
        token_b, id_b = login(client, BRUNO_EMAIL)

        match_id = ensure_match(client, token_a, id_a, token_b, id_b)
        print(f"Match Alice<->Bruno : {match_id}")

        asyncio.run(exchange(token_a, token_b, match_id))

        history = client.get(
            f"/messaging/matches/{match_id}/messages",
            headers={"Authorization": f"Bearer {token_a}"},
        ).json()
        print(f"\n{len(history)} message(s) persisté(s) :")
        for message in history:
            print(f"  [{message['created_at']}] {message['sender_id']}: {message['body']}")


if __name__ == "__main__":
    main()
