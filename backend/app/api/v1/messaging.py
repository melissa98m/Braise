import asyncio
import uuid

from fastapi import (
    APIRouter,
    Depends,
    HTTPException,
    Query,
    WebSocket,
    WebSocketDisconnect,
    status,
)
from sqlalchemy.orm import Session

from app.api.deps import get_current_user, user_from_token
from app.db.session import SessionLocal, get_db
from app.models.user import User
from app.schemas.messaging import (
    DailyQuestionAnswerIn,
    DailyQuestionOut,
    DailyQuestionResultOut,
    MessageOut,
)
from app.services import matches as matches_service
from app.services import messaging as messaging_service
from app.services import notifications as notifications_service
from app.ws.connection_manager import manager

router = APIRouter(prefix="/messaging", tags=["messaging"])


@router.get("/matches/{match_id}/messages", response_model=list[MessageOut])
def list_messages(
    match_id: uuid.UUID,
    limit: int = Query(default=50, ge=1, le=100),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    return messaging_service.list_messages(db, user, match_id, limit)


@router.get("/matches/{match_id}/daily-question", response_model=DailyQuestionOut)
def get_daily_question(
    match_id: uuid.UUID,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    return messaging_service.get_or_create_daily_question(db, user, match_id)


@router.post("/matches/{match_id}/daily-question/answer", response_model=DailyQuestionResultOut)
def answer_daily_question(
    match_id: uuid.UUID,
    payload: DailyQuestionAnswerIn,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    return messaging_service.answer_daily_question(db, user, match_id, payload.selected)


@router.websocket("/ws/{match_id}")
async def chat_ws(websocket: WebSocket, match_id: uuid.UUID, token: str = Query(...)):
    # L'auth WebSocket ne peut pas passer par un header Authorization classique côté navigateur :
    # le token voyage en query string, d'où la vérification manuelle (pas de Depends ici) avant
    # même d'accepter la connexion.
    #
    # Une session par opération (ci-dessous), jamais une session gardée ouverte pour toute la
    # durée de la connexion : un test de charge (docs/ROADMAP.md, P4.3) a montré qu'une session
    # tenue du connect au disconnect épuise le pool SQLAlchemy (5 + 10 overflow par défaut) dès
    # une quinzaine de conversations ouvertes en même temps — une connexion WS peut rester
    # ouverte des heures, contrairement à une requête REST. Passé ce seuil, tout le reste de
    # l'API (y compris les routes REST qui n'ont rien à voir avec la messagerie) se met à
    # échouer en TimeoutError faute de connexion disponible dans le pool. Ici, une session ne
    # vit que le temps d'une vérification ou d'un événement reçu, exactement comme une requête
    # REST via `Depends(get_db)`.
    with SessionLocal() as db:
        try:
            user = user_from_token(token, db)
            messaging_service.assert_match_participant(db, user, match_id)
            user_id = user.id
        except HTTPException:
            await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
            return

    await manager.connect(match_id, websocket)
    try:
        while True:
            data = await websocket.receive_json()
            event_type = data.get("type", "message")

            if event_type == "typing":
                # Éphémère, jamais persisté : juste un relais aux autres connexions du match,
                # y compris sur une autre instance backend (voir ws/connection_manager.py).
                await manager.broadcast(
                    match_id, {"type": "typing", "match_id": str(match_id), "sender_id": str(user_id)}
                )
                continue

            if event_type == "delivered":
                with SessionLocal() as db:
                    user = db.get(User, user_id)
                    match = messaging_service.assert_match_participant(db, user, match_id)
                    delivered_at = matches_service.mark_delivered(db, match, user)
                await manager.broadcast(
                    match_id,
                    {
                        "type": "delivered",
                        "match_id": str(match_id),
                        "deliverer_id": str(user_id),
                        "delivered_at": delivered_at.isoformat(),
                    },
                )
                continue

            if event_type == "read":
                with SessionLocal() as db:
                    user = db.get(User, user_id)
                    match = messaging_service.assert_match_participant(db, user, match_id)
                    read_at = matches_service.mark_read(db, match, user)
                await manager.broadcast(
                    match_id,
                    {
                        "type": "read",
                        "match_id": str(match_id),
                        "reader_id": str(user_id),
                        "read_at": read_at.isoformat(),
                    },
                )
                continue

            body = str(data.get("body", "")).strip()
            if not body:
                continue
            with SessionLocal() as db:
                user = db.get(User, user_id)
                message = messaging_service.create_message(db, user, match_id, body)
                message_id, created_at, saved_body = message.id, message.created_at, message.body
            # asyncio.to_thread : pywebpush est bloquant, chat_ws est async — jamais bloquer la
            # boucle de réception WS dessus. Fire-and-forget (résultat jamais attendu) : un échec
            # d'envoi push ne doit jamais retarder la livraison du message sur le socket déjà
            # ouvert, qui est le mécanisme de livraison principal, le push n'étant qu'un rattrapage
            # pour l'onglet fermé.
            asyncio.create_task(
                asyncio.to_thread(notifications_service.notify_new_message, match_id, user_id, saved_body)
            )
            await manager.broadcast(
                match_id,
                {
                    "type": "message",
                    "id": str(message_id),
                    "match_id": str(match_id),
                    "sender_id": str(user_id),
                    "body": saved_body,
                    "created_at": created_at.isoformat(),
                    # Toujours faux à l'envoi : personne d'autre n'a encore pu recevoir ni lire ce
                    # message (voir services/matches.message_is_delivered/message_is_read).
                    "delivered": False,
                    "delivered_at": None,
                    "read": False,
                    "read_at": None,
                },
            )
    except WebSocketDisconnect:
        pass
    finally:
        await manager.disconnect(match_id, websocket)
