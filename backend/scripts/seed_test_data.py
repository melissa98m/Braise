"""Crée un jeu de comptes/profils de test publiés, pour tester manuellement l'app (Swagger,
Flutter web) sans repasser par le flux OTP à la main pour chaque persona.

Idempotent : chaque persona a un numéro de téléphone fixe, donc relancer ce script réutilise le
même compte (créé au premier passage) et se contente de rejouer OTP + republier le profil, plutôt
que de créer des doublons.

Usage (le backend applicatif doit déjà tourner) :
    docker compose run --rm backend python scripts/seed_test_data.py

`city` (P9.3) est une valeur de la liste fermée de `services/geo.py` — sert à tester le filtre de
distance sans avoir à publier manuellement 6 profils différents. Voir aussi
`scripts/seed_beta_tester.py`, qui réutilise ces personas et y ajoute un compte testeur déjà
matché/en conversation, pour un bêta-test qui n'a pas à tout construire à la main non plus.
"""

import httpx

BASE_URL = "http://backend:8000"

PERSONAS = [
    {
        "phone": "+33600000001",
        "display_name": "Alice",
        "birth_date": "2004-03-15",
        "bio": "Toujours partante pour un concert ou une expo.",
        "interests": ["musique", "cinéma", "voyage"],
        "gender": "femme",
        "looking_for_gender": "homme",
        "age_min": 22,
        "age_max": 32,
        "city": "Paris",
    },
    {
        "phone": "+33600000002",
        "display_name": "Bruno",
        "birth_date": "2001-05-20",
        "bio": "Grimpe, cuisine, recommence.",
        "interests": ["sport", "cuisine", "voyage"],
        "gender": "homme",
        "looking_for_gender": "femme",
        "age_min": 20,
        "age_max": 30,
        "city": "Lyon",
    },
    {
        "phone": "+33600000003",
        "display_name": "Chloé",
        "birth_date": "2002-07-10",
        "bio": "Libraire le jour, série le soir.",
        "interests": ["lecture", "cinéma", "musique"],
        "gender": "femme",
        "looking_for_gender": "homme",
        "age_min": 23,
        "age_max": 33,
        "city": "Marseille",
    },
    {
        "phone": "+33600000004",
        "display_name": "David",
        "birth_date": "1998-01-25",
        "bio": "Randonnée le week-end, code la semaine.",
        "interests": ["sport", "voyage", "lecture"],
        "gender": "homme",
        "looking_for_gender": "femme",
        "age_min": 21,
        "age_max": 29,
        "city": "Reims",
    },
    {
        "phone": "+33600000005",
        "display_name": "Emma",
        "birth_date": "2000-11-02",
        "bio": "Cuisine du monde et vieux vinyles.",
        "interests": ["cuisine", "musique", "lecture"],
        "gender": "non_binaire",
        "looking_for_gender": "non_binaire",
        "age_min": 22,
        "age_max": 34,
        "city": "Lille",
    },
    {
        "phone": "+33600000006",
        "display_name": "Farid",
        "birth_date": "1996-04-18",
        "bio": "Cinéphile, footeux, jamais les deux en même temps.",
        "interests": ["cinéma", "sport", "voyage"],
        "gender": "homme",
        "looking_for_gender": "homme",
        "age_min": 25,
        "age_max": 38,
        "city": "Nice",
    },
]


def seed_persona(client: httpx.Client, persona: dict) -> tuple[str, dict, str]:
    """Renvoie (token, headers, user_id) — pour que `seed_beta_tester.py` puisse réutiliser cette
    même session au lieu de redemander un OTP pour le même numéro juste après (le throttle
    anti-brute-force posé en P6.1, `MIN_RESEND_INTERVAL_SECONDS`, le refuserait à raison)."""
    phone = persona["phone"]

    otp_response = client.post("/auth/request-otp", json={"phone": phone})
    otp_response.raise_for_status()
    code = otp_response.json()["debug_code"]
    if code is None:
        raise RuntimeError(
            "debug_code est vide : DEBUG_OTP doit être à true dans backend/.env pour ce script."
        )

    token_response = client.post("/auth/verify-otp", json={"phone": phone, "code": code})
    token_response.raise_for_status()
    token = token_response.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    me = client.get("/auth/me", headers=headers)
    me.raise_for_status()
    user_id = me.json()["id"]

    profile_response = client.put(
        "/profiles/me/public",
        headers=headers,
        json={
            "display_name": persona["display_name"],
            "birth_date": persona["birth_date"],
            "bio": persona["bio"],
            "interests": persona["interests"],
            "is_published": True,
            "gender": persona["gender"],
            "looking_for_gender": persona["looking_for_gender"],
            "age_min": persona["age_min"],
            "age_max": persona["age_max"],
            "city": persona["city"],
        },
    )
    profile_response.raise_for_status()

    print(f"{persona['display_name']:<8} user_id={user_id}  phone={phone}  token={token}")
    return token, headers, user_id


def main() -> None:
    with httpx.Client(base_url=BASE_URL, timeout=10) as client:
        for persona in PERSONAS:
            seed_persona(client, persona)


if __name__ == "__main__":
    main()
