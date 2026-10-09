"""Service de la revue de modération humaine (cahier des charges C.1/C.2, V2) — distinct de
services/moderation.py (qui reste la surface *utilisateur* : noter, signaler, contester un
bannissement). Même séparation de préoccupations que moderation_ml.py vis-à-vis de moderation.py :
les décisions du personnel ne se mélangent pas aux endpoints que les utilisateurs ordinaires
appellent.
"""

import uuid
from datetime import datetime, timezone

from fastapi import HTTPException, status
from sqlalchemy.orm import Session

from app.models.ban_appeal import BanAppeal, BanAppealStatus
from app.models.match import Match
from app.models.moderation_action import ModerationAction
from app.models.profile import PublicProfile
from app.models.rating import Rating
from app.models.report import Report, ReportStatus
from app.models.user import User
from app.services.moderation import _is_post_unlock_rancor, compute_trust_score
from app.services.moderation_ml import rancor_probability

DEFAULT_LIMIT = 20
MAX_LIMIT = 100


def _clamp_pagination(limit: int, offset: int) -> tuple[int, int]:
    return max(1, min(limit, MAX_LIMIT)), max(0, offset)


def user_summary(db: Session, user_id: uuid.UUID) -> dict:
    user = db.get(User, user_id)
    profile = db.get(PublicProfile, user_id)
    trust = compute_trust_score(db, user_id)
    return {
        "id": user_id,
        "email": user.email if user else None,
        "display_name": profile.display_name if profile else None,
        "is_verified": bool(user.is_verified) if user else False,
        "is_banned": bool(user.is_banned) if user else False,
        "trust_score": trust["score"],
        "trust_label": trust["label"],
    }


def _prior_report_count(db: Session, reported_id: uuid.UUID, exclude_report_id: uuid.UUID) -> int:
    return (
        db.query(Report)
        .filter(Report.reported_id == reported_id, Report.id != exclude_report_id)
        .count()
    )


def queue_counts(db: Session) -> dict:
    return {
        "reports_pending": db.query(Report)
        .filter(Report.status == ReportStatus.PENDING.value)
        .count(),
        "ban_appeals_pending": db.query(BanAppeal)
        .filter(BanAppeal.status == BanAppealStatus.PENDING.value)
        .count(),
        "flagged_ratings_pending": db.query(Rating)
        .filter(Rating.suspected_rancor.is_(True), Rating.moderation_reviewed_at.is_(None))
        .count(),
    }


def _log_action(
    db: Session, staff: User, target_type: str, target_id: uuid.UUID, decision: str, note: str | None
) -> None:
    db.add(
        ModerationAction(
            staff_user_id=staff.id,
            target_type=target_type,
            target_id=target_id,
            decision=decision,
            note=note,
        )
    )


# ---------------------------------------------------------------------------
# Signalements
# ---------------------------------------------------------------------------


def list_reports(db: Session, status_filter: str, limit: int, offset: int) -> list[Report]:
    limit, offset = _clamp_pagination(limit, offset)
    return (
        db.query(Report)
        .filter(Report.status == status_filter)
        .order_by(Report.created_at.asc())
        .offset(offset)
        .limit(limit)
        .all()
    )


def get_report_or_404(db: Session, report_id: uuid.UUID) -> Report:
    report = db.get(Report, report_id)
    if report is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Signalement introuvable.")
    return report


def report_detail(db: Session, report_id: uuid.UUID) -> dict:
    report = get_report_or_404(db, report_id)
    return {
        "id": report.id,
        "match_id": report.match_id,
        "reason": report.reason,
        "comment": report.comment,
        "status": report.status,
        "created_at": report.created_at,
        "reporter": user_summary(db, report.reporter_id),
        "reported": user_summary(db, report.reported_id),
        "prior_reports_against_reported": _prior_report_count(db, report.reported_id, report.id),
    }


def resolve_report(
    db: Session,
    staff: User,
    report_id: uuid.UUID,
    decision: str,
    note: str | None,
    ban_reported: bool,
) -> Report:
    report = get_report_or_404(db, report_id)
    if report.status != ReportStatus.PENDING.value:
        raise HTTPException(status.HTTP_409_CONFLICT, "Ce signalement a déjà été traité.")

    report.status = decision
    if ban_reported:
        reported = db.get(User, report.reported_id)
        if reported is not None and not reported.is_banned:
            reported.is_banned = True
            reported.banned_at = datetime.now(timezone.utc)

    _log_action(db, staff, "report", report.id, decision, note)
    db.commit()
    db.refresh(report)
    return report


# ---------------------------------------------------------------------------
# Contestations de bannissement
# ---------------------------------------------------------------------------


def list_ban_appeals(db: Session, status_filter: str, limit: int, offset: int) -> list[BanAppeal]:
    limit, offset = _clamp_pagination(limit, offset)
    return (
        db.query(BanAppeal)
        .filter(BanAppeal.status == status_filter)
        .order_by(BanAppeal.created_at.asc())
        .offset(offset)
        .limit(limit)
        .all()
    )


def get_ban_appeal_or_404(db: Session, appeal_id: uuid.UUID) -> BanAppeal:
    appeal = db.get(BanAppeal, appeal_id)
    if appeal is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Contestation introuvable.")
    return appeal


def ban_appeal_detail(db: Session, appeal_id: uuid.UUID) -> dict:
    appeal = get_ban_appeal_or_404(db, appeal_id)
    history = (
        db.query(BanAppeal)
        .filter(BanAppeal.user_id == appeal.user_id, BanAppeal.id != appeal.id)
        .order_by(BanAppeal.created_at.desc())
        .all()
    )
    return {
        "id": appeal.id,
        "message": appeal.message,
        "status": appeal.status,
        "created_at": appeal.created_at,
        "decided_at": appeal.decided_at,
        "decision_note": appeal.decision_note,
        "user": user_summary(db, appeal.user_id),
        "prior_appeals_count": len(history),
    }


def resolve_ban_appeal(
    db: Session, staff: User, appeal_id: uuid.UUID, decision: str, note: str | None
) -> BanAppeal:
    appeal = get_ban_appeal_or_404(db, appeal_id)
    if appeal.status != BanAppealStatus.PENDING.value:
        raise HTTPException(status.HTTP_409_CONFLICT, "Cette contestation a déjà été traitée.")

    appeal.status = decision
    appeal.decision_note = note
    appeal.decided_at = datetime.now(timezone.utc)
    if decision == BanAppealStatus.OVERTURNED.value:
        user = db.get(User, appeal.user_id)
        if user is not None:
            user.is_banned = False

    _log_action(db, staff, "ban_appeal", appeal.id, decision, note)
    db.commit()
    db.refresh(appeal)
    return appeal


# ---------------------------------------------------------------------------
# Notes signalées (suspected_rancor)
# ---------------------------------------------------------------------------


def list_flagged_ratings(db: Session, limit: int, offset: int) -> list[Rating]:
    limit, offset = _clamp_pagination(limit, offset)
    return (
        db.query(Rating)
        .filter(Rating.suspected_rancor.is_(True), Rating.moderation_reviewed_at.is_(None))
        .order_by(Rating.created_at.asc())
        .offset(offset)
        .limit(limit)
        .all()
    )


def get_rating_or_404(db: Session, rating_id: uuid.UUID) -> Rating:
    rating = db.get(Rating, rating_id)
    if rating is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Note introuvable.")
    return rating


def flagged_rating_detail(db: Session, rating_id: uuid.UUID) -> dict:
    rating = get_rating_or_404(db, rating_id)
    match = db.get(Match, rating.match_id)
    post_unlock_rancor = (
        _is_post_unlock_rancor(match, rating.score, datetime.now(timezone.utc))
        if match is not None
        else False
    )
    return {
        "id": rating.id,
        "match_id": rating.match_id,
        "score": rating.score,
        "comment": rating.comment,
        "suspected_rancor": rating.suspected_rancor,
        "created_at": rating.created_at,
        "rater": user_summary(db, rating.rater_id),
        "ratee": user_summary(db, rating.ratee_id),
        "rancor_probability": rancor_probability(rating.comment),
        "flagged_post_unlock_rule": post_unlock_rancor,
    }


def review_flagged_rating(
    db: Session, staff: User, rating_id: uuid.UUID, decision: str, note: str | None
) -> Rating:
    rating = get_rating_or_404(db, rating_id)
    if rating.moderation_reviewed_at is not None:
        raise HTTPException(status.HTTP_409_CONFLICT, "Cette note a déjà été traitée.")

    if decision == "cleared":
        rating.suspected_rancor = False
    elif decision != "confirmed":
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Décision inconnue.")

    rating.moderation_reviewed_at = datetime.now(timezone.utc)
    rating.moderation_reviewed_by = staff.id

    _log_action(db, staff, "rating", rating.id, decision, note)
    db.commit()
    db.refresh(rating)
    return rating
