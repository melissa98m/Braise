from fastapi import APIRouter, BackgroundTasks, Depends, Query
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.db.session import get_db
from app.models.swipe import SwipeDecision
from app.models.user import User
from app.schemas.discovery import (
    DiscoveryCandidateOut,
    LikesReceivedOut,
    MatchOut,
    SwipeIn,
    SwipeOut,
)
from app.services import discovery as discovery_service
from app.services import notifications as notifications_service

router = APIRouter(prefix="/discovery", tags=["discovery"])


@router.get("/feed", response_model=list[DiscoveryCandidateOut])
def get_feed(
    limit: int = Query(default=20, ge=1, le=50),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    return discovery_service.get_feed(db, user, limit)


@router.post("/swipe", response_model=SwipeOut)
def swipe(
    payload: SwipeIn,
    background_tasks: BackgroundTasks,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    decision = SwipeDecision(payload.decision)
    matched = discovery_service.record_swipe(db, user, payload.to_user_id, decision)
    if matched:
        # Après le commit de record_swipe, jamais dans sa transaction : un envoi push est un appel
        # HTTP externe bloquant (pywebpush), il ne doit jamais pouvoir retarder ou faire échouer
        # l'écriture d'un vrai match. notify_new_match ouvre de toute façon sa propre session.
        background_tasks.add_task(notifications_service.notify_new_match, user.id, payload.to_user_id)
    return SwipeOut(decision=payload.decision, matched=matched)


@router.get("/matches", response_model=list[MatchOut])
def get_matches(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    return discovery_service.list_my_matches(db, user)


@router.get("/likes-received", response_model=LikesReceivedOut)
def get_likes_received(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    return discovery_service.get_likes_received(db, user)
