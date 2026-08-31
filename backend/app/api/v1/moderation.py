import uuid

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.api.deps import get_current_user, get_current_user_even_if_banned
from app.db.session import get_db
from app.models.user import User
from app.schemas.moderation import (
    BanAppealIn,
    BanAppealOut,
    RatingIn,
    RatingOut,
    ReportIn,
    ReportOut,
    TrustScoreOut,
)
from app.services import moderation as moderation_service

router = APIRouter(prefix="/moderation", tags=["moderation"])


@router.post("/matches/{match_id}/rating", response_model=RatingOut)
def rate_match(
    match_id: uuid.UUID,
    payload: RatingIn,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    return moderation_service.create_rating(db, user, match_id, payload.score, payload.comment)


@router.post("/matches/{match_id}/report", response_model=ReportOut)
def report_match(
    match_id: uuid.UUID,
    payload: ReportIn,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    return moderation_service.create_report(db, user, match_id, payload.reason, payload.comment)


@router.get("/reports/mine", response_model=list[ReportOut])
def my_reports(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    return moderation_service.list_my_reports(db, user)


@router.get("/me/trust-score", response_model=TrustScoreOut)
def my_trust_score(
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    return moderation_service.get_trust_score(db, user.id)


@router.post("/ban-appeal", response_model=BanAppealOut, status_code=201)
def file_ban_appeal(
    payload: BanAppealIn,
    user: User = Depends(get_current_user_even_if_banned),
    db: Session = Depends(get_db),
):
    return moderation_service.file_ban_appeal(db, user, payload.message)


@router.get("/ban-appeal/mine", response_model=list[BanAppealOut])
def my_ban_appeals(
    user: User = Depends(get_current_user_even_if_banned),
    db: Session = Depends(get_db),
):
    return moderation_service.list_my_ban_appeals(db, user)
