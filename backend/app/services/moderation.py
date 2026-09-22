import uuid
from datetime import datetime, timedelta, timezone

from fastapi import HTTPException, status
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.models.ban_appeal import BanAppeal, BanAppealStatus
from app.models.match import Match
from app.models.rating import Rating
from app.models.report import Report, ReportStatus
from app.models.user import User
from app.services.matches import get_match_or_404, other_user_id
from app.services.moderation_ml import predict_is_rancor

# Une note très négative postée dans les heures qui suivent le déblocage du profil privé est le
# schéma de rancune explicitement cité par le cahier des charges (A.4.5) : "rejet lié au physique
# découvert tardivement". Ce n'est qu'un des deux signaux (voir _is_post_unlock_rancor) — l'autre
# vient du classifieur de texte (services/moderation_ml.py).
POST_UNLOCK_RANCOR_WINDOW = timedelta(hours=24)
LOW_SCORE_THRESHOLD = 2

# Empêche qu'une ou deux notes malveillantes suffisent à bannir un utilisateur qui vient tout
# juste de commencer à recevoir des avis — protection explicitement demandée par le cahier des
# charges (A.9 : "limiter les faux positifs du modèle de classification").
MIN_RATINGS_FOR_AUTO_BAN = 3

_TRUST_LABEL_THRESHOLDS = (
    (85, "EXEMPLAIRE"),
    (70, "SOLIDE"),
    (50, "EN CONSTRUCTION"),
)


def _is_post_unlock_rancor(match: Match, score: int, now: datetime) -> bool:
    if match.unlocked_at is None or score > LOW_SCORE_THRESHOLD:
        return False
    return (now - match.unlocked_at) <= POST_UNLOCK_RANCOR_WINDOW


def _trust_label(score: int) -> str:
    for threshold, label in _TRUST_LABEL_THRESHOLDS:
        if score >= threshold:
            return label
    return "FRAGILE"


def compute_trust_score(db: Session, user_id: uuid.UUID) -> dict:
    return compute_trust_scores_batch(db, [user_id]).get(
        user_id, {"score": None, "label": None, "rating_count": 0, "flagged_count": 0}
    )


def compute_trust_scores_batch(db: Session, user_ids: list[uuid.UUID]) -> dict[uuid.UUID, dict]:
    """Même calcul que compute_trust_score, mais en une seule requête pour N utilisateurs — sert
    le feed de découverte (services/discovery.get_feed), où interroger une fois par candidat
    romprait le principe déjà en place ailleurs dans ce module (pool borné, coût prévisible)."""
    if not user_ids:
        return {}

    ratings_by_user: dict[uuid.UUID, list[Rating]] = {}
    for rating in db.query(Rating).filter(Rating.ratee_id.in_(user_ids)).all():
        ratings_by_user.setdefault(rating.ratee_id, []).append(rating)

    return {
        user_id: _trust_score_from_ratings(ratings_by_user.get(user_id, []))
        for user_id in user_ids
    }


def _trust_score_from_ratings(ratings: list[Rating]) -> dict:
    total = len(ratings)
    if total == 0:
        return {"score": None, "label": None, "rating_count": 0, "flagged_count": 0}

    trusted = [r for r in ratings if not r.suspected_rancor]
    flagged_count = total - len(trusted)
    if trusted:
        avg = sum((r.score - 1) / 4 * 100 for r in trusted) / len(trusted)
    else:
        # Tout ce qui a été reçu est suspect : score neutre en attendant une revue humaine,
        # plutôt qu'un 0 injustifié ou une moyenne sur des données jugées non fiables.
        avg = 50
    score = round(avg)
    return {
        "score": score,
        "label": _trust_label(score),
        "rating_count": total,
        "flagged_count": flagged_count,
    }


def create_rating(db: Session, user: User, match_id: uuid.UUID, score: int, comment: str) -> dict:
    match = get_match_or_404(db, user, match_id)
    ratee_id = other_user_id(match, user)

    existing = (
        db.query(Rating)
        .filter(Rating.match_id == match_id, Rating.rater_id == user.id)
        .one_or_none()
    )
    if existing is not None:
        raise HTTPException(status.HTTP_409_CONFLICT, "Vous avez déjà noté cet échange.")

    now = datetime.now(timezone.utc)
    suspected_rancor = _is_post_unlock_rancor(match, score, now) or predict_is_rancor(comment)

    db.add(
        Rating(
            match_id=match_id,
            rater_id=user.id,
            ratee_id=ratee_id,
            score=score,
            comment=comment,
            suspected_rancor=suspected_rancor,
        )
    )
    try:
        db.flush()
    except IntegrityError:
        db.rollback()
        raise HTTPException(status.HTTP_409_CONFLICT, "Vous avez déjà noté cet échange.")

    trust = compute_trust_score(db, ratee_id)
    ratee = db.get(User, ratee_id)
    if (
        ratee is not None
        and not ratee.is_banned
        and trust["rating_count"] >= MIN_RATINGS_FOR_AUTO_BAN
        and trust["score"] is not None
        and trust["score"] <= 0
    ):
        ratee.is_banned = True
        ratee.banned_at = now

    db.commit()
    return {"suspected_rancor": suspected_rancor, "trust_score": trust["score"]}


def create_report(
    db: Session, user: User, match_id: uuid.UUID, reason: str, comment: str
) -> Report:
    match = get_match_or_404(db, user, match_id)
    reported_id = other_user_id(match, user)

    report = Report(
        match_id=match_id,
        reporter_id=user.id,
        reported_id=reported_id,
        reason=reason,
        comment=comment,
        status=ReportStatus.PENDING.value,
    )
    db.add(report)
    db.commit()
    db.refresh(report)
    return report


def list_my_reports(db: Session, user: User) -> list[Report]:
    return (
        db.query(Report)
        .filter(Report.reporter_id == user.id)
        .order_by(Report.created_at.desc())
        .all()
    )


def get_trust_score(db: Session, user_id: uuid.UUID) -> dict:
    return compute_trust_score(db, user_id)


def file_ban_appeal(db: Session, user: User, message: str) -> BanAppeal:
    if not user.is_banned:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Ce compte n'est pas banni.")

    existing_pending = (
        db.query(BanAppeal)
        .filter(BanAppeal.user_id == user.id, BanAppeal.status == BanAppealStatus.PENDING.value)
        .one_or_none()
    )
    if existing_pending is not None:
        raise HTTPException(
            status.HTTP_409_CONFLICT, "Une contestation est déjà en cours d'examen."
        )

    appeal = BanAppeal(user_id=user.id, message=message, status=BanAppealStatus.PENDING.value)
    db.add(appeal)
    db.commit()
    db.refresh(appeal)
    return appeal


def list_my_ban_appeals(db: Session, user: User) -> list[BanAppeal]:
    return (
        db.query(BanAppeal)
        .filter(BanAppeal.user_id == user.id)
        .order_by(BanAppeal.created_at.desc())
        .all()
    )
