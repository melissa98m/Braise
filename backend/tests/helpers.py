import uuid
from datetime import datetime, timedelta, timezone


def unique_phone() -> str:
    # Les tests tournent contre le vrai Postgres de dev (pas de base jetable) : un numéro
    # unique par appel évite les collisions avec les données laissées par un run précédent.
    return "+336" + uuid.uuid4().hex[:8]


def auth_token(client, phone: str) -> str:
    request = client.post("/auth/request-otp", json={"phone": phone})
    code = request.json()["debug_code"]
    verify = client.post("/auth/verify-otp", json={"phone": phone, "code": code})
    return verify.json()["access_token"]


def auth_headers(client, phone: str) -> dict:
    return {"Authorization": f"Bearer {auth_token(client, phone)}"}


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


def create_match(
    client,
    interests_a: list[str] | None = None,
    interests_b: list[str] | None = None,
) -> dict:
    token_a = auth_token(client, unique_phone())
    token_b = auth_token(client, unique_phone())
    headers_a = {"Authorization": f"Bearer {token_a}"}
    headers_b = {"Authorization": f"Bearer {token_b}"}

    id_a = client.get("/auth/me", headers=headers_a).json()["id"]
    id_b = client.get("/auth/me", headers=headers_b).json()["id"]

    for headers, interests in ((headers_a, interests_a), (headers_b, interests_b)):
        client.put(
            "/profiles/me/public",
            headers=headers,
            json={
                "display_name": "Match test",
                "birth_date": "1996-01-01",
                "bio": "",
                "interests": interests or [],
                "is_published": True,
            },
        )

    client.post("/discovery/swipe", headers=headers_a, json={"to_user_id": id_b, "decision": "like"})
    second = client.post(
        "/discovery/swipe", headers=headers_b, json={"to_user_id": id_a, "decision": "like"}
    )
    assert second.json()["matched"] is True

    matches = client.get("/discovery/matches", headers=headers_a).json()
    match_id = next(m["match_id"] for m in matches if m["other_user_id"] == id_b)

    return {
        "token_a": token_a,
        "headers_a": headers_a,
        "id_a": id_a,
        "token_b": token_b,
        "headers_b": headers_b,
        "id_b": id_b,
        "match_id": match_id,
    }


def create_match_with(client, other_headers: dict, other_id: str) -> dict:
    """Crée un nouvel utilisateur publié et le fait matcher avec un utilisateur *existant*.

    Sert à obtenir plusieurs match distincts vers la même personne (ex: N utilisateurs qui
    notent tous le même compte), ce que `create_match` seul ne permet pas puisqu'il crée
    systématiquement deux comptes neufs.
    """
    token = auth_token(client, unique_phone())
    headers = {"Authorization": f"Bearer {token}"}
    my_id = client.get("/auth/me", headers=headers).json()["id"]

    client.put(
        "/profiles/me/public",
        headers=headers,
        json={
            "display_name": "Match test",
            "birth_date": "1996-01-01",
            "bio": "",
            "interests": [],
            "is_published": True,
        },
    )

    client.post(
        "/discovery/swipe", headers=headers, json={"to_user_id": other_id, "decision": "like"}
    )
    second = client.post(
        "/discovery/swipe", headers=other_headers, json={"to_user_id": my_id, "decision": "like"}
    )
    assert second.json()["matched"] is True

    matches = client.get("/discovery/matches", headers=headers).json()
    match_id = next(m["match_id"] for m in matches if m["other_user_id"] == other_id)

    return {"token": token, "headers": headers, "id": my_id, "match_id": match_id}


def read_trust_score(user_id: str) -> dict:
    # /moderation/me/trust-score only exposes the caller's own score (fixed IDOR: it used to take
    # an arbitrary user_id) — tests that need to inspect *another* account's score after the fact
    # (e.g. a banned victim whose own token now 403s) read it straight from the service instead.
    from app.db.session import SessionLocal
    from app.services.moderation import compute_trust_score

    db = SessionLocal()
    try:
        return compute_trust_score(db, uuid.UUID(user_id))
    finally:
        db.close()


def ban_user(client, victim_headers: dict, victim_id: str) -> None:
    # Fait passer un compte sous le seuil MIN_RATINGS_FOR_AUTO_BAN via 3 notes basses de 3
    # comptes distincts, exactement le chemin réel de bannissement automatique
    # (services/moderation.create_rating) — pas un raccourci en base, pour que les tests de
    # contestation partent d'un compte réellement banni par le code, pas d'un état simulé.
    base = create_match_with(client, victim_headers, victim_id)
    rater_2 = create_match_with(client, victim_headers, victim_id)
    rater_3 = create_match_with(client, victim_headers, victim_id)
    for rater in (base, rater_2, rater_3):
        response = client.post(
            f"/moderation/matches/{rater['match_id']}/rating",
            headers=rater["headers"],
            json={"score": 1, "comment": "Le courant n'est vraiment pas passé entre nous deux."},
        )
        assert response.status_code == 200


def force_match_unlocked(match_id: str, hours_ago: float = 1) -> None:
    # Atteindre unlock_threshold flammes par le vrai flux (une question/jour/utilisateur) prendrait
    # plusieurs jours réels : on pose directement l'état "match débloqué depuis X" en base plutôt
    # que de simuler des jours de questions quotidiennes.
    from app.db.session import SessionLocal
    from app.models.match import Match

    db = SessionLocal()
    try:
        match = db.get(Match, uuid.UUID(match_id))
        match.flame_count = match.unlock_threshold
        match.unlocked_at = datetime.now(timezone.utc) - timedelta(hours=hours_ago)
        db.commit()
    finally:
        db.close()
