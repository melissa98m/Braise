import uuid
from datetime import datetime, timezone

from sqlalchemy import Column, DateTime, ForeignKey, String
from sqlalchemy.dialects.postgresql import UUID

from app.db.base import Base


class ModerationTargetType(str):
    REPORT = "report"
    BAN_APPEAL = "ban_appeal"
    RATING = "rating"


class ModerationAction(Base):
    """Journal d'audit des décisions de la revue de modération humaine (cahier des charges
    C.1/C.2, V2) — append-only, jamais mis à jour ni supprimé. Une ligne par décision (signalement
    résolu, contestation tranchée, note flaggée triée), quel que soit le type de file d'attente :
    une seule table plutôt qu'une par type, sur le modèle de ce que `docs/V2_FEATURES.md` §2
    demandait déjà pour les notes seules ("journaliser (rating_id, décision_staff)"), généralisé
    ici aux trois files pour la même raison de traçabilité/accountability, et parce que ce jeu de
    données devient le futur jeu d'entraînement réel du classifieur (services/moderation_ml.py).
    """

    __tablename__ = "moderation_actions"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    staff_user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    # "report" | "ban_appeal" | "rating" (voir ModerationTargetType) — pas de FK unique possible
    # puisque target_id pointe vers l'une de trois tables différentes selon target_type.
    target_type = Column(String(20), nullable=False, index=True)
    target_id = Column(UUID(as_uuid=True), nullable=False, index=True)
    decision = Column(String(20), nullable=False)
    note = Column(String(1000), nullable=True)
    created_at = Column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False
    )
