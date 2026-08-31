"""Test de charge sur la messagerie WebSocket (cahier des charges B.1 Phase 4 : "tests de charge
sur la messagerie temps réelle"), jamais fait avant ce palier malgré l'exigence explicite du
planning avant le jalon "Go/No-go bêta" (B.2).

Simule N matches concurrents, chacun avec ses 2 participants connectés en websocket en même
temps (le cas réel : ConnectionManager, services/messaging.py, diffuse par match, pas
globalement), et mesure pour chacun :
- le temps de connexion (handshake WS, y compris la vérification du token *avant* accept() —
  api/v1/messaging.py::chat_ws)
- la latence de diffusion d'un message (envoi côté A -> réception côté B, le chemin
  ConnectionManager.broadcast)
- le taux de succès de connexion et de livraison

La création des comptes/matches (REST, httpx) est délibérément mesurée à part de la session
websocket elle-même : c'est la latence de connexion+diffusion qui intéresse ce test, pas le débit
de l'API d'inscription.

Usage (le backend doit déjà tourner) :
    docker compose run --rm backend python scripts/load_test_messaging.py --matches 50
    docker compose run --rm backend python scripts/load_test_messaging.py --matches 200 --setup-concurrency 40
"""

import argparse
import asyncio
import json
import time
import uuid

import httpx
import websockets

BASE_URL = "http://backend:8000"
WS_BASE_URL = "ws://backend:8000"


async def _signup_and_publish(client: httpx.AsyncClient, display_name: str) -> tuple[str, str]:
    phone = "+336" + uuid.uuid4().hex[:8]
    otp = await client.post(f"{BASE_URL}/auth/request-otp", json={"phone": phone})
    otp.raise_for_status()
    code = otp.json()["debug_code"]
    if code is None:
        raise RuntimeError("DEBUG_OTP doit être à true côté backend pour ce script.")

    token_response = await client.post(
        f"{BASE_URL}/auth/verify-otp", json={"phone": phone, "code": code}
    )
    token_response.raise_for_status()
    token = token_response.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    me = await client.get(f"{BASE_URL}/auth/me", headers=headers)
    me.raise_for_status()
    user_id = me.json()["id"]

    publish = await client.put(
        f"{BASE_URL}/profiles/me/public",
        headers=headers,
        json={
            "display_name": display_name,
            "birth_date": "1996-01-01",
            "bio": "",
            "interests": [],
            "is_published": True,
        },
    )
    publish.raise_for_status()
    return token, user_id


async def create_match_pair(client: httpx.AsyncClient, index: int) -> dict:
    token_a, id_a = await _signup_and_publish(client, f"Charge A{index}")
    token_b, id_b = await _signup_and_publish(client, f"Charge B{index}")
    headers_a = {"Authorization": f"Bearer {token_a}"}
    headers_b = {"Authorization": f"Bearer {token_b}"}

    like_a = await client.post(
        f"{BASE_URL}/discovery/swipe",
        headers=headers_a,
        json={"to_user_id": id_b, "decision": "like"},
    )
    like_a.raise_for_status()
    like_b = await client.post(
        f"{BASE_URL}/discovery/swipe",
        headers=headers_b,
        json={"to_user_id": id_a, "decision": "like"},
    )
    like_b.raise_for_status()
    if not like_b.json()["matched"]:
        raise RuntimeError(f"Match #{index} : le swipe réciproque n'a pas matché.")

    matches = await client.get(f"{BASE_URL}/discovery/matches", headers=headers_a)
    matches.raise_for_status()
    match_id = next(m["match_id"] for m in matches.json() if m["other_user_id"] == id_b)

    return {"index": index, "match_id": match_id, "token_a": token_a, "token_b": token_b}


async def run_match_session(match: dict, timeout: float) -> dict:
    result = {
        "index": match["index"],
        "connect_ok": False,
        "delivery_ok": False,
        "connect_seconds": None,
        "broadcast_seconds": None,
        "error": None,
    }
    url_a = f"{WS_BASE_URL}/messaging/ws/{match['match_id']}?token={match['token_a']}"
    url_b = f"{WS_BASE_URL}/messaging/ws/{match['match_id']}?token={match['token_b']}"
    try:
        connect_start = time.monotonic()
        async with websockets.connect(url_a) as ws_a, websockets.connect(url_b) as ws_b:
            result["connect_ok"] = True
            result["connect_seconds"] = time.monotonic() - connect_start

            send_at = time.monotonic()
            await ws_a.send(json.dumps({"type": "message", "body": f"charge #{match['index']}"}))
            # A reçoit sa propre diffusion (ConnectionManager.broadcast envoie à tout le monde
            # dans le match, émetteur inclus — voir api/v1/messaging.py) : on l'absorbe avant le
            # message de B pour ne pas fausser la mesure de latence avec le mauvais frame.
            await asyncio.wait_for(ws_a.recv(), timeout=timeout)
            raw_b = await asyncio.wait_for(ws_b.recv(), timeout=timeout)
            result["broadcast_seconds"] = time.monotonic() - send_at

            payload = json.loads(raw_b)
            result["delivery_ok"] = (
                payload.get("type") == "message" and payload.get("body") == f"charge #{match['index']}"
            )
    except Exception as exc:  # noqa: BLE001 — rapporté dans le résultat, pas une erreur du script
        result["error"] = f"{type(exc).__name__}: {exc}"
    return result


def _percentile(values: list[float], pct: float) -> float:
    if not values:
        return float("nan")
    ordered = sorted(values)
    index = min(len(ordered) - 1, int(len(ordered) * pct))
    return ordered[index]


async def main() -> None:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "--matches",
        type=int,
        default=50,
        help="Nombre de matchs concurrents (défaut 50, soit 2x connexions WS).",
    )
    parser.add_argument(
        "--setup-concurrency",
        type=int,
        default=20,
        help="Comptes/matchs créés en parallèle pendant la mise en place (défaut 20).",
    )
    parser.add_argument(
        "--recv-timeout",
        type=float,
        default=5.0,
        help="Délai max d'attente d'un message avant échec (secondes, défaut 5).",
    )
    args = parser.parse_args()

    print(f"=== Test de charge messagerie — {args.matches} matchs concurrents ===\n")

    print(f"Mise en place ({args.matches} matchs, {args.setup_concurrency} en parallèle)...")
    setup_start = time.monotonic()
    semaphore = asyncio.Semaphore(args.setup_concurrency)

    async def _bounded_create(client: httpx.AsyncClient, index: int) -> dict:
        async with semaphore:
            return await create_match_pair(client, index)

    async with httpx.AsyncClient(timeout=30) as client:
        matches = await asyncio.gather(
            *(_bounded_create(client, i) for i in range(args.matches)), return_exceptions=True
        )
    setup_seconds = time.monotonic() - setup_start

    setup_failures = [m for m in matches if isinstance(m, Exception)]
    valid_matches = [m for m in matches if not isinstance(m, Exception)]
    print(
        f"Mise en place terminée en {setup_seconds:.1f}s : {len(valid_matches)} matchs prêts, "
        f"{len(setup_failures)} échecs de mise en place.\n"
    )
    if not valid_matches:
        print("Aucun match prêt, impossible de tester la messagerie.")
        return

    print(
        f"Ouverture de {len(valid_matches) * 2} connexions WebSocket "
        f"({len(valid_matches)} matchs) en simultané..."
    )
    session_start = time.monotonic()
    results = await asyncio.gather(
        *(run_match_session(m, args.recv_timeout) for m in valid_matches)
    )
    session_seconds = time.monotonic() - session_start

    connected = [r for r in results if r["connect_ok"]]
    delivered = [r for r in results if r["delivery_ok"]]
    connect_latencies = [r["connect_seconds"] for r in connected]
    broadcast_latencies = [r["broadcast_seconds"] for r in delivered]

    print(f"\n=== Résultats ({session_seconds:.1f}s pour la session complète) ===")
    print(f"Connexions réussies : {len(connected)}/{len(valid_matches)} paires")
    print(f"Messages livrés     : {len(delivered)}/{len(valid_matches)} paires")
    if connect_latencies:
        print(
            f"Latence de connexion  — p50 {_percentile(connect_latencies, .5)*1000:.0f} ms, "
            f"p95 {_percentile(connect_latencies, .95)*1000:.0f} ms, "
            f"p99 {_percentile(connect_latencies, .99)*1000:.0f} ms, "
            f"max {max(connect_latencies)*1000:.0f} ms"
        )
    if broadcast_latencies:
        print(
            f"Latence de diffusion  — p50 {_percentile(broadcast_latencies, .5)*1000:.0f} ms, "
            f"p95 {_percentile(broadcast_latencies, .95)*1000:.0f} ms, "
            f"p99 {_percentile(broadcast_latencies, .99)*1000:.0f} ms, "
            f"max {max(broadcast_latencies)*1000:.0f} ms"
        )

    failures = [r for r in results if r["error"] is not None]
    if failures:
        print(f"\n{len(failures)} échec(s) pendant la session — premiers exemples :")
        for r in failures[:5]:
            print(f"  match #{r['index']} : {r['error']}")


if __name__ == "__main__":
    asyncio.run(main())
