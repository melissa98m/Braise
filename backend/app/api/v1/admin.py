import uuid
from typing import Literal

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.api.deps import get_current_staff_user
from app.db.session import get_db
from app.models.user import User
from app.schemas.admin import (
    BanAppealDetailOut,
    BanAppealListItemOut,
    BanAppealResolveIn,
    ClientErrorItemOut,
    FeedbackItemOut,
    FlaggedRatingDetailOut,
    FlaggedRatingListItemOut,
    QueueCountsOut,
    RatingReviewIn,
    ReportDetailOut,
    ReportListItemOut,
    ReportResolveIn,
    TriageIn,
    UserSummaryOut,
)
from app.services import admin_beta as beta_service
from app.services import admin_moderation as service

router = APIRouter(prefix="/admin", tags=["admin"])


@router.get("/queue-counts", response_model=QueueCountsOut)
def queue_counts(
    staff: User = Depends(get_current_staff_user), db: Session = Depends(get_db)
):
    return service.queue_counts(db)


@router.get("/reports", response_model=list[ReportListItemOut])
def list_reports(
    status: Literal["pending", "founded", "unfounded"] = "pending",
    limit: int = 20,
    offset: int = 0,
    staff: User = Depends(get_current_staff_user),
    db: Session = Depends(get_db),
):
    return service.list_reports(db, status, limit, offset)


@router.get("/reports/{report_id}", response_model=ReportDetailOut)
def get_report(
    report_id: uuid.UUID,
    staff: User = Depends(get_current_staff_user),
    db: Session = Depends(get_db),
):
    return service.report_detail(db, report_id)


@router.post("/reports/{report_id}/resolve", response_model=ReportDetailOut)
def resolve_report(
    report_id: uuid.UUID,
    payload: ReportResolveIn,
    staff: User = Depends(get_current_staff_user),
    db: Session = Depends(get_db),
):
    service.resolve_report(
        db, staff, report_id, payload.decision, payload.note, payload.ban_reported
    )
    return service.report_detail(db, report_id)


@router.get("/ban-appeals", response_model=list[BanAppealListItemOut])
def list_ban_appeals(
    status: Literal["pending", "upheld", "overturned"] = "pending",
    limit: int = 20,
    offset: int = 0,
    staff: User = Depends(get_current_staff_user),
    db: Session = Depends(get_db),
):
    return service.list_ban_appeals(db, status, limit, offset)


@router.get("/ban-appeals/{appeal_id}", response_model=BanAppealDetailOut)
def get_ban_appeal(
    appeal_id: uuid.UUID,
    staff: User = Depends(get_current_staff_user),
    db: Session = Depends(get_db),
):
    return service.ban_appeal_detail(db, appeal_id)


@router.post("/ban-appeals/{appeal_id}/resolve", response_model=BanAppealDetailOut)
def resolve_ban_appeal(
    appeal_id: uuid.UUID,
    payload: BanAppealResolveIn,
    staff: User = Depends(get_current_staff_user),
    db: Session = Depends(get_db),
):
    service.resolve_ban_appeal(db, staff, appeal_id, payload.decision, payload.note)
    return service.ban_appeal_detail(db, appeal_id)


@router.get("/flagged-ratings", response_model=list[FlaggedRatingListItemOut])
def list_flagged_ratings(
    limit: int = 20,
    offset: int = 0,
    staff: User = Depends(get_current_staff_user),
    db: Session = Depends(get_db),
):
    return service.list_flagged_ratings(db, limit, offset)


@router.get("/flagged-ratings/{rating_id}", response_model=FlaggedRatingDetailOut)
def get_flagged_rating(
    rating_id: uuid.UUID,
    staff: User = Depends(get_current_staff_user),
    db: Session = Depends(get_db),
):
    return service.flagged_rating_detail(db, rating_id)


@router.post("/flagged-ratings/{rating_id}/review", response_model=FlaggedRatingDetailOut)
def review_flagged_rating(
    rating_id: uuid.UUID,
    payload: RatingReviewIn,
    staff: User = Depends(get_current_staff_user),
    db: Session = Depends(get_db),
):
    service.review_flagged_rating(db, staff, rating_id, payload.decision, payload.note)
    return service.flagged_rating_detail(db, rating_id)


@router.get("/me", response_model=UserSummaryOut)
def whoami(staff: User = Depends(get_current_staff_user), db: Session = Depends(get_db)):
    """Utilisé par le tableau de bord staff (static/admin/app.js) juste après la connexion pour
    confirmer l'accès admin avant d'afficher le tableau de bord — /auth/me existe déjà mais ne
    porte pas is_staff dans sa réponse, et l'exposer là serait une fuite d'information pour tout
    utilisateur non-staff qui l'appelle. Ce endpoint est lui-même déjà 403 pour un non-staff, donc
    son seul fait de répondre 200 EST la confirmation."""
    return service.user_summary(db, staff.id)


@router.get("/feedback", response_model=list[FeedbackItemOut])
def list_feedback(
    status: Literal["new", "done"] = "new",
    limit: int = 20,
    offset: int = 0,
    staff: User = Depends(get_current_staff_user),
    db: Session = Depends(get_db),
):
    return beta_service.list_feedback(db, status, limit, offset)


@router.post("/feedback/{feedback_id}/status", response_model=FeedbackItemOut)
def triage_feedback(
    feedback_id: uuid.UUID,
    payload: TriageIn,
    staff: User = Depends(get_current_staff_user),
    db: Session = Depends(get_db),
):
    return beta_service.triage_feedback(db, staff, feedback_id, payload.status)


@router.get("/client-errors", response_model=list[ClientErrorItemOut])
def list_client_errors(
    status: Literal["new", "done"] = "new",
    limit: int = 20,
    offset: int = 0,
    staff: User = Depends(get_current_staff_user),
    db: Session = Depends(get_db),
):
    return beta_service.list_client_errors(db, status, limit, offset)


@router.post("/client-errors/{error_id}/status", response_model=ClientErrorItemOut)
def triage_client_error(
    error_id: uuid.UUID,
    payload: TriageIn,
    staff: User = Depends(get_current_staff_user),
    db: Session = Depends(get_db),
):
    return beta_service.triage_client_error(db, error_id, payload.status)
