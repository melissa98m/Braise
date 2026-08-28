import enum
import uuid
from datetime import datetime, timezone

from sqlalchemy import Column, DateTime, ForeignKey, String
from sqlalchemy.dialects.postgresql import UUID

from app.db.base import Base


class ReportReason(str, enum.Enum):
    HARCELEMENT = "harcelement"
    FAUX_PROFIL = "faux_profil"
    CONTENU_INAPPROPRIE = "contenu_inapproprie"
    COMPORTEMENT_SUSPECT = "comportement_suspect"
    AUTRE = "autre"


class ReportStatus(str, enum.Enum):
    PENDING = "pending"
    FOUNDED = "founded"
    UNFOUNDED = "unfounded"


class Report(Base):
    __tablename__ = "reports"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    match_id = Column(UUID(as_uuid=True), ForeignKey("matches.id"), nullable=False, index=True)
    reporter_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    reported_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    reason = Column(String(30), nullable=False)
    comment = Column(String(1000), nullable=True)
    # MVP (cahier des charges C.1) : "revue humaine systématique, pas encore de tri automatique
    # fin" — tout signalement démarre 'pending' ; pas de transition automatique vers
    # founded/unfounded tant qu'il n'y a pas d'outillage de modération (Phase V2).
    status = Column(String(20), nullable=False, default=ReportStatus.PENDING.value)
    created_at = Column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False
    )
