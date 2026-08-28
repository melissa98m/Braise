import uuid


def unique_phone() -> str:
    # Les tests tournent contre le vrai Postgres de dev (pas de base jetable) : un numéro
    # unique par appel évite les collisions avec les données laissées par un run précédent.
    return "+336" + uuid.uuid4().hex[:8]


def auth_headers(client, phone: str) -> dict:
    request = client.post("/auth/request-otp", json={"phone": phone})
    code = request.json()["debug_code"]
    verify = client.post("/auth/verify-otp", json={"phone": phone, "code": code})
    token = verify.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


def create_published_user(
    client,
    display_name: str,
    interests: list[str] | None = None,
    birth_date: str = "1996-01-01",
) -> tuple[dict, str]:
    headers = auth_headers(client, unique_phone())
    me = client.get("/auth/me", headers=headers).json()
    client.put(
        "/profiles/me/public",
        headers=headers,
        json={
            "display_name": display_name,
            "birth_date": birth_date,
            "bio": "",
            "interests": interests or [],
            "is_published": True,
        },
    )
    return headers, me["id"]
