from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.db.session import get_db
from app.models.swipe import SwipeDecision
from app.models.user import User
from app.schemas.discovery import DiscoveryCandidateOut, MatchOut, SwipeIn, SwipeOut
from app.services import discovery as discovery_service

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
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    decision = SwipeDecision(payload.decision)
    matched = discovery_service.record_swipe(db, user, payload.to_user_id, decision)
    return SwipeOut(decision=payload.decision, matched=matched)


@router.get("/matches", response_model=list[MatchOut])
def get_matches(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    return discovery_service.list_my_matches(db, user)
