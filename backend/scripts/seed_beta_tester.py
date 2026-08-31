"""Prépare un compte de bêta-testeur·se déjà rempli — pas juste des profils à swiper (voir
`seed_test_data.py`, réutilisé ici), mais un compte qui a déjà des matchs, une conversation avec
des messages non lus, un match déjà débloqué (photo privée visible tout de suite), et un autre en
cours de progression (question du jour encore disponible) — pour tester en quelques clics plutôt
que de devoir reconstruire cet état à la main à chaque fois.

Idempotent comme `seed_test_data.py` : relancer ce script réutilise le même numéro de téléphone
(donc le même compte) plutôt que d'en créer un nouveau à chaque fois. Le déblocage forcé du match
et le flame_count partiel sur le second, en revanche, sont réappliqués à chaque lancement (pas de
mal à le refaire, juste redondant si déjà fait).

Usage (le backend applicatif doit déjà tourner) :
    docker compose run --rm backend python scripts/seed_beta_tester.py
"""

import asyncio
import base64
import json
import os
import sys
from datetime import datetime, timedelta, timezone

import httpx
import websockets

# Même contrainte que compute_kpis.py : lancé comme `python scripts/x.py`, sys.path[0] est
# scripts/, pas la racine du backend — nécessaire pour importer app.* ci-dessous.
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from seed_test_data import PERSONAS, seed_persona  # noqa: E402

from app.db.session import SessionLocal  # noqa: E402
from app.models.match import Match  # noqa: E402

BASE_URL = "http://backend:8000"
WS_BASE_URL = "ws://backend:8000"

TESTER_PHONE = "+33600000099"
TESTER_PROFILE = {
    "display_name": "Testeur",
    "birth_date": "1995-06-15",
    "bio": "Compte de bêta-test — déjà des matchs prêts, explorez toutes les fonctionnalités.",
    "interests": ["cinéma", "musique", "voyage", "sport"],
    "gender": "homme",
    # Volontairement ouvert à tout le monde (pas de filtre genre/âge/distance) : le but est de
    # voir tous les profils de seed_test_data.py dans le feed, pas d'en filtrer par erreur.
    "looking_for_gender": None,
    "age_min": None,
    "age_max": None,
    "city": "Paris",
}

# Nom des personas de seed_test_data.py à faire matcher immédiatement avec le compte testeur.
UNLOCKED_MATCH_PERSONA = "Alice"  # débloqué d'entrée : photo privée visible, prêt à noter.
IN_PROGRESS_MATCH_PERSONA = "Bruno"  # flammes partielles : question du jour encore à répondre.

# PNG 1x1 minimal, valide — suffit pour tester l'affichage d'une photo privée sans avoir besoin
# d'un vrai fichier image sur cette machine.
_PLACEHOLDER_PNG = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
)


def _auth(client: httpx.Client, phone: str) -> tuple[str, dict, str]:
    otp = client.post("/auth/request-otp", json={"phone": phone})
    otp.raise_for_status()
    code = otp.json()["debug_code"]
    if code is None:
        raise RuntimeError("DEBUG_OTP doit être à true dans backend/.env pour ce script.")
    verify = client.post("/auth/verify-otp", json={"phone": phone, "code": code})
    verify.raise_for_status()
    token = verify.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}
    me = client.get("/auth/me", headers=headers)
    me.raise_for_status()
    return token, headers, me.json()["id"]


def _upload_placeholder_photo(client: httpx.Client, headers: dict) -> None:
    files = {"file": ("photo.png", _PLACEHOLDER_PNG, "image/png")}
    response = client.post("/profiles/me/private/photos", headers=headers, files=files)
    response.raise_for_status()


def _mutual_like(client: httpx.Client, headers_a: dict, id_a: str, headers_b: dict, id_b: str) -> None:
    client.post(
        "/discovery/swipe", headers=headers_a, json={"to_user_id": id_b, "decision": "like"}
    ).raise_for_status()
    client.post(
        "/discovery/swipe", headers=headers_b, json={"to_user_id": id_a, "decision": "like"}
    ).raise_for_status()


def _match_id_with(client: httpx.Client, headers: dict, other_user_id: str) -> str:
    matches = client.get("/discovery/matches", headers=headers).json()
    return next(m["match_id"] for m in matches if m["other_user_id"] == other_user_id)


def _force_unlock(match_id: str) -> None:
    """Écrit directement flame_count/unlocked_at plutôt que de simuler des jours de questions
    quotidiennes — même principe que tests.helpers.force_match_unlocked, mais pour un vrai compte
    de bêta-test, pas un test automatisé."""
    db = SessionLocal()
    try:
        match = db.get(Match, match_id)
        match.flame_count = match.unlock_threshold
        match.unlocked_at = datetime.now(timezone.utc) - timedelta(hours=1)
        db.commit()
    finally:
        db.close()


def _set_partial_flames(match_id: str, flames: int) -> None:
    db = SessionLocal()
    try:
        match = db.get(Match, match_id)
        match.flame_count = flames
        db.commit()
    finally:
        db.close()


async def _send_messages(match_id: str, token: str, bodies: list[str]) -> None:
    url = f"{WS_BASE_URL}/messaging/ws/{match_id}?token={token}"
    async with websockets.connect(url) as ws:
        for body in bodies:
            await ws.send(json.dumps({"type": "message", "body": body}))
            await ws.recv()  # attend l'écho avant le message suivant, garde l'ordre


def main() -> None:
    with httpx.Client(base_url=BASE_URL, timeout=10) as client:
        print("=== Profils candidats (seed_test_data.py) ===")
        # Garde les sessions déjà ouvertes : les réutiliser pour Alice/Bruno ci-dessous évite de
        # redemander un OTP pour le même numéro dans la foulée, que le throttle anti-brute-force
        # (P6.1, MIN_RESEND_INTERVAL_SECONDS) refuserait à raison.
        sessions: dict[str, tuple[str, dict, str]] = {}
        for persona in PERSONAS:
            sessions[persona["display_name"]] = seed_persona(client, persona)

        print("\n=== Compte testeur ===")
        token_t, headers_t, id_t = _auth(client, TESTER_PHONE)
        client.put(
            "/profiles/me/public", headers=headers_t, json={**TESTER_PROFILE, "is_published": True}
        ).raise_for_status()
        print(f"Testeur   user_id={id_t}  phone={TESTER_PHONE}")

        print(f"\n=== Match débloqué avec {UNLOCKED_MATCH_PERSONA} ===")
        token_u, headers_u, id_u = sessions[UNLOCKED_MATCH_PERSONA]
        _upload_placeholder_photo(client, headers_u)
        _mutual_like(client, headers_t, id_t, headers_u, id_u)
        match_id_unlocked = _match_id_with(client, headers_t, id_u)
        _force_unlock(match_id_unlocked)
        asyncio.run(
            _send_messages(
                match_id_unlocked,
                token_u,
                [
                    "Salut ! Alors, prêt·e à tester l'appli ? 😄",
                    "Le profil se débloque déjà des deux côtés, tu peux voir mes photos.",
                ],
            )
        )
        print(f"match_id={match_id_unlocked} — débloqué, 2 messages non lus, photo privée visible.")

        print(f"\n=== Match en cours avec {IN_PROGRESS_MATCH_PERSONA} ===")
        token_p, headers_p, id_p = sessions[IN_PROGRESS_MATCH_PERSONA]
        _mutual_like(client, headers_t, id_t, headers_p, id_p)
        match_id_progress = _match_id_with(client, headers_t, id_p)
        _set_partial_flames(match_id_progress, 2)
        asyncio.run(
            _send_messages(match_id_progress, token_p, ["Hello ! On a déjà 2 flammes en commun."])
        )
        print(f"match_id={match_id_progress} — 2/5 flammes, 1 message non lu, question du jour dispo.")

        remaining = [
            p["display_name"]
            for p in PERSONAS
            if p["display_name"] not in (UNLOCKED_MATCH_PERSONA, IN_PROGRESS_MATCH_PERSONA)
        ]
        print(f"\n=== Reste dans le feed, jamais swipé : {', '.join(remaining)} ===")

        print(
            "\nConnexion : ouvrir l'app, \"J'ai déjà un compte\", entrer "
            f"{TESTER_PHONE} — le code s'affiche directement (DEBUG_OTP)."
        )


if __name__ == "__main__":
    main()
