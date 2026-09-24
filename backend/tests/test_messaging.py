import uuid
from datetime import date

from fastapi.testclient import TestClient

from app.db.session import SessionLocal
from app.main import app
from app.models.daily_question import DailyQuestion
from tests.helpers import auth_headers, auth_token, create_match, create_published_user, unique_phone

client = TestClient(app)


def _peek_correct_answer(match_id: str, for_user_id: str) -> str:
    # La bonne réponse n'est jamais exposée par l'API avant d'avoir répondu (voir
    # services/messaging.py) : on va la lire directement en base pour pouvoir tester le chemin
    # "bonne réponse" de façon déterministe, sans affaiblir l'API elle-même.
    db = SessionLocal()
    try:
        question = (
            db.query(DailyQuestion)
            .filter(
                DailyQuestion.match_id == uuid.UUID(match_id),
                DailyQuestion.for_user_id == uuid.UUID(for_user_id),
                DailyQuestion.question_date == date.today(),
            )
            .one()
        )
        return question.correct_answer
    finally:
        db.close()


def test_daily_question_correct_answer_increments_shared_flame_count():
    match = create_match(client, interests_a=["cinéma"], interests_b=["escalade", "poterie-x"])

    question = client.get(
        f"/messaging/matches/{match['match_id']}/daily-question", headers=match["headers_a"]
    )
    assert question.status_code == 200
    body = question.json()
    # Le texte exact dépend de OLLAMA_ENABLED (gabarit statique si désactivé/indisponible,
    # formulation générée à température non nulle sinon — voir services/question_llm.py) : seule
    # la forme (une vraie question) est garantie, jamais le texte mot pour mot — une assertion sur
    # le contenu exact rendrait ce test dépendant du conteneur ollama et de sa sortie non
    # déterministe.
    assert body["prompt"].strip().endswith("?")
    assert len(body["options"]) >= 2
    assert body["answered"] is False

    correct = _peek_correct_answer(match["match_id"], match["id_a"])
    assert correct in body["options"]

    answer = client.post(
        f"/messaging/matches/{match['match_id']}/daily-question/answer",
        headers=match["headers_a"],
        json={"selected": correct},
    )
    assert answer.status_code == 200
    result = answer.json()
    assert result["correct"] is True
    assert result["correct_answer"] == correct
    assert result["flame_count"] == 1

    matches = client.get("/discovery/matches", headers=match["headers_a"]).json()
    updated = next(m for m in matches if m["match_id"] == match["match_id"])
    assert updated["flame_count"] == 1
    assert updated["unlock_pct"] == round(1 / updated["unlock_threshold"] * 100)


def test_daily_question_wrong_answer_does_not_increment_flames():
    match = create_match(client, interests_a=[], interests_b=["escalade", "poterie-x"])

    question = client.get(
        f"/messaging/matches/{match['match_id']}/daily-question", headers=match["headers_a"]
    ).json()
    correct = _peek_correct_answer(match["match_id"], match["id_a"])
    wrong = next(opt for opt in question["options"] if opt != correct)

    answer = client.post(
        f"/messaging/matches/{match['match_id']}/daily-question/answer",
        headers=match["headers_a"],
        json={"selected": wrong},
    )
    assert answer.status_code == 200
    assert answer.json()["correct"] is False
    assert answer.json()["flame_count"] == 0


def test_daily_question_double_answer_rejected():
    match = create_match(client, interests_a=[], interests_b=["escalade", "poterie-x"])
    client.get(f"/messaging/matches/{match['match_id']}/daily-question", headers=match["headers_a"])
    correct = _peek_correct_answer(match["match_id"], match["id_a"])

    first = client.post(
        f"/messaging/matches/{match['match_id']}/daily-question/answer",
        headers=match["headers_a"],
        json={"selected": correct},
    )
    assert first.status_code == 200

    second = client.post(
        f"/messaging/matches/{match['match_id']}/daily-question/answer",
        headers=match["headers_a"],
        json={"selected": correct},
    )
    assert second.status_code == 409


def test_daily_question_invalid_option_rejected():
    match = create_match(client, interests_a=[], interests_b=["escalade", "poterie-x"])
    client.get(f"/messaging/matches/{match['match_id']}/daily-question", headers=match["headers_a"])

    response = client.post(
        f"/messaging/matches/{match['match_id']}/daily-question/answer",
        headers=match["headers_a"],
        json={"selected": "une réponse qui n'a jamais été proposée"},
    )
    assert response.status_code == 400


def test_daily_question_missing_when_target_has_no_interests():
    match = create_match(client, interests_a=[], interests_b=[])
    response = client.get(
        f"/messaging/matches/{match['match_id']}/daily-question", headers=match["headers_a"]
    )
    assert response.status_code == 404


def test_daily_question_uses_city_when_no_interests_or_bio():
    # Pas d'intérêts, pas de bio : seule la ville rend la question disponible (voir
    # services/messaging._eligible_categories) — la bonne réponse est bien la vraie ville du
    # profil, jamais une affirmation inventée.
    match = create_match(client, interests_a=[], interests_b=[], city_b="Lyon")
    response = client.get(
        f"/messaging/matches/{match['match_id']}/daily-question", headers=match["headers_a"]
    )
    assert response.status_code == 200
    body = response.json()
    correct = _peek_correct_answer(match["match_id"], match["id_a"])
    assert correct == "Lyon"
    assert correct in body["options"]
    assert len(set(body["options"])) == len(body["options"])


def test_daily_question_uses_bio_when_no_interests_or_city():
    # MIN_BIO_DECOYS (services/messaging.py) exige au moins 3 autres bios réelles publiées et
    # distinctes pour que la catégorie "bio" soit éligible — créées ici explicitement plutôt que
    # de compter sur des données laissées par d'autres tests.
    for i in range(4):
        create_published_user(
            client, f"Leurre{i}", bio=f"Une bio bien distincte et jamais réutilisée #{i}."
        )

    match = create_match(
        client,
        interests_a=[],
        interests_b=[],
        bio_b="La vraie bio, unique à ce test, de Match test B.",
    )
    response = client.get(
        f"/messaging/matches/{match['match_id']}/daily-question", headers=match["headers_a"]
    )
    assert response.status_code == 200
    body = response.json()
    correct = _peek_correct_answer(match["match_id"], match["id_a"])
    assert correct == "La vraie bio, unique à ce test, de Match test B."
    assert correct in body["options"]
    # Jamais l'option d'un décor dupliquée (bug réel trouvé et corrigé : _decoy_bios sans
    # .distinct() pouvait renvoyer la même bio plusieurs fois si plusieurs profils la partageaient).
    assert len(set(body["options"])) == len(body["options"])


def test_daily_question_requires_match_participant():
    match = create_match(client, interests_a=[], interests_b=["escalade", "poterie-x"])
    outsider_headers = auth_headers(client, unique_phone())

    response = client.get(
        f"/messaging/matches/{match['match_id']}/daily-question", headers=outsider_headers
    )
    assert response.status_code == 404


def test_message_history_requires_participant():
    match = create_match(client)
    outsider_headers = auth_headers(client, unique_phone())

    response = client.get(
        f"/messaging/matches/{match['match_id']}/messages", headers=outsider_headers
    )
    assert response.status_code == 404


def test_websocket_chat_round_trip_and_history():
    match = create_match(client)
    url_a = f"/messaging/ws/{match['match_id']}?token={match['token_a']}"
    url_b = f"/messaging/ws/{match['match_id']}?token={match['token_b']}"

    with client.websocket_connect(url_a) as ws_a, client.websocket_connect(url_b) as ws_b:
        ws_a.send_json({"body": "Le grésillement d'une cassette."})

        received_a = ws_a.receive_json()
        received_b = ws_b.receive_json()
        assert received_a["body"] == "Le grésillement d'une cassette."
        assert received_b["body"] == "Le grésillement d'une cassette."
        assert received_a["sender_id"] == match["id_a"]

    history = client.get(
        f"/messaging/matches/{match['match_id']}/messages", headers=match["headers_a"]
    ).json()
    assert any(m["body"] == "Le grésillement d'une cassette." for m in history)


def test_websocket_rejects_invalid_token():
    match = create_match(client)
    url = f"/messaging/ws/{match['match_id']}?token=not-a-real-token"
    try:
        with client.websocket_connect(url):
            raise AssertionError("la connexion aurait dû être refusée")
    except Exception:
        pass


def test_message_history_reports_unread_by_default():
    match = create_match(client)
    url = f"/messaging/ws/{match['match_id']}?token={match['token_a']}"
    with client.websocket_connect(url) as ws:
        ws.send_json({"type": "message", "body": "Pas encore lu."})
        ws.receive_json()

    history = client.get(
        f"/messaging/matches/{match['match_id']}/messages", headers=match["headers_a"]
    ).json()
    sent = next(m for m in history if m["body"] == "Pas encore lu.")
    assert sent["read"] is False
    assert sent["read_at"] is None
    assert sent["delivered"] is False
    assert sent["delivered_at"] is None


def test_websocket_read_marks_message_read_and_notifies_sender():
    match = create_match(client)
    url_a = f"/messaging/ws/{match['match_id']}?token={match['token_a']}"
    url_b = f"/messaging/ws/{match['match_id']}?token={match['token_b']}"

    with client.websocket_connect(url_a) as ws_a, client.websocket_connect(url_b) as ws_b:
        ws_a.send_json({"type": "message", "body": "Tu as vu mon message ?"})
        ws_a.receive_json()
        ws_b.receive_json()

        ws_b.send_json({"type": "read"})
        notified = ws_a.receive_json()
        assert notified["type"] == "read"
        assert notified["reader_id"] == match["id_b"]

    history = client.get(
        f"/messaging/matches/{match['match_id']}/messages", headers=match["headers_a"]
    ).json()
    sent = next(m for m in history if m["body"] == "Tu as vu mon message ?")
    assert sent["read"] is True
    assert sent["read_at"] is not None
    # Lire implique avoir reçu : mark_read fait aussi progresser last_delivered_at_* côté lecteur
    # (services/matches.mark_read), même si aucun accusé "delivered" explicite n'a été envoyé.
    assert sent["delivered"] is True
    assert sent["delivered_at"] is not None


def test_websocket_delivered_marks_message_delivered_without_marking_read():
    match = create_match(client)
    url_a = f"/messaging/ws/{match['match_id']}?token={match['token_a']}"
    url_b = f"/messaging/ws/{match['match_id']}?token={match['token_b']}"

    with client.websocket_connect(url_a) as ws_a, client.websocket_connect(url_b) as ws_b:
        ws_a.send_json({"type": "message", "body": "Juste reçu, pas encore lu."})
        ws_a.receive_json()
        ws_b.receive_json()

        ws_b.send_json({"type": "delivered"})
        notified = ws_a.receive_json()
        assert notified["type"] == "delivered"
        assert notified["deliverer_id"] == match["id_b"]

    history = client.get(
        f"/messaging/matches/{match['match_id']}/messages", headers=match["headers_a"]
    ).json()
    sent = next(m for m in history if m["body"] == "Juste reçu, pas encore lu.")
    assert sent["delivered"] is True
    assert sent["delivered_at"] is not None
    assert sent["read"] is False
    assert sent["read_at"] is None


def test_websocket_typing_broadcasts_to_other_participant():
    match = create_match(client)
    url_a = f"/messaging/ws/{match['match_id']}?token={match['token_a']}"
    url_b = f"/messaging/ws/{match['match_id']}?token={match['token_b']}"

    with client.websocket_connect(url_a) as ws_a, client.websocket_connect(url_b) as ws_b:
        ws_a.send_json({"type": "typing"})
        received = ws_b.receive_json()
        assert received == {
            "type": "typing",
            "match_id": match["match_id"],
            "sender_id": match["id_a"],
        }


def test_websocket_rejects_non_participant():
    match = create_match(client)
    outsider_token = auth_token(client, unique_phone())

    url = f"/messaging/ws/{match['match_id']}?token={outsider_token}"
    try:
        with client.websocket_connect(url):
            raise AssertionError("la connexion aurait dû être refusée")
    except Exception:
        pass
