"""Files « Retours » et « Erreurs » du tableau de bord staff (bêta, P26) — voir schemas/admin.py.

Séparé de admin_moderation.py : rien ici n'agit sur un compte ni n'écrit dans le journal des
décisions de modération (moderation_actions) ; seulement un statut de suivi.
"""

import uuid
from datetime import datetime, timezone

from fastapi import HTTPException, status
from sqlalchemy.orm import Session

from app.models.client_error import ClientError
from app.models.feedback import Feedback
from app.models.user import User
from app.services.admin_moderation import _clamp_pagination, user_summary


def list_feedback(db: Session, status_filter: str, limit: int, offset: int) -> list[dict]:
    limit, offset = _clamp_pagination(limit, offset)
    rows = (
        db.query(Feedback)
        .filter(Feedback.status == status_filter)
        .order_by(Feedback.created_at.desc())
        .limit(limit)
        .offset(offset)
        .all()
    )
    return [_feedback_item(db, row) for row in rows]


def _feedback_item(db: Session, row: Feedback) -> dict:
    return {
        "id": row.id,
        "category": row.category,
        "message": row.message,
        "context": row.context,
        "user_agent": row.user_agent,
        "status": row.status,
        "created_at": row.created_at,
        "handled_at": row.handled_at,
        "author": user_summary(db, row.user_id),
    }


def triage_feedback(db: Session, staff: User, feedback_id: uuid.UUID, new_status: str) -> dict:
    row = db.get(Feedback, feedback_id)
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Retour introuvable.")
    row.status = new_status
    row.handled_at = datetime.now(timezone.utc) if new_status == "done" else None
    row.handled_by = staff.id if new_status == "done" else None
    db.commit()
    return _feedback_item(db, row)


def list_client_errors(db: Session, status_filter: str, limit: int, offset: int) -> list[dict]:
    limit, offset = _clamp_pagination(limit, offset)
    rows = (
        db.query(ClientError)
        .filter(ClientError.status == status_filter)
        .order_by(ClientError.last_seen_at.desc())
        .limit(limit)
        .offset(offset)
        .all()
    )
    return [_client_error_item(db, row) for row in rows]


def _client_error_item(db: Session, row: ClientError) -> dict:
    return {
        "id": row.id,
        "message": row.message,
        "stack": row.stack,
        "source": row.source,
        "path": row.path,
        "user_agent": row.user_agent,
        "occurrences": row.occurrences,
        "status": row.status,
        "first_seen_at": row.first_seen_at,
        "last_seen_at": row.last_seen_at,
        "last_user": user_summary(db, row.last_user_id) if row.last_user_id else None,
    }


def triage_client_error(db: Session, error_id: uuid.UUID, new_status: str) -> dict:
    row = db.get(ClientError, error_id)
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Erreur introuvable.")
    row.status = new_status
    db.commit()
    return _client_error_item(db, row)
