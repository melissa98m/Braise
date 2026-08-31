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
    db = SessionLocal()
    try:
        user = user_from_token(token, db)
        match = messaging_service.assert_match_participant(db, user, match_id)
    except HTTPException:
        db.close()
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
        return

    await manager.connect(match_id, websocket)
    try:
        while True:
            data = await websocket.receive_json()
            event_type = data.get("type", "message")

            if event_type == "typing":
                # Éphémère, jamais persisté : juste un relais aux autres connexions du match
                # (voir ws/connection_manager.py — un seul process backend pour l'instant).
                await manager.broadcast(
                    match_id, {"type": "typing", "match_id": str(match_id), "sender_id": str(user.id)}
                )
                continue

            if event_type == "read":
                read_at = matches_service.mark_read(db, match, user)
                await manager.broadcast(
                    match_id,
                    {
                        "type": "read",
                        "match_id": str(match_id),
                        "reader_id": str(user.id),
                        "read_at": read_at.isoformat(),
                    },
                )
                continue

            body = str(data.get("body", "")).strip()
            if not body:
                continue
            message = messaging_service.create_message(db, user, match_id, body)
            await manager.broadcast(
                match_id,
                {
                    "type": "message",
                    "id": str(message.id),
                    "match_id": str(match_id),
                    "sender_id": str(user.id),
                    "body": message.body,
                    "created_at": message.created_at.isoformat(),
                    # Toujours faux à l'envoi : personne d'autre n'a encore pu marquer le match
                    # comme lu après ce message (voir services/matches.message_is_read).
                    "read": False,
                },
            )
    except WebSocketDisconnect:
        pass
    finally:
        manager.disconnect(match_id, websocket)
        db.close()
