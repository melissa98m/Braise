import uuid
from datetime import datetime, timezone

from sqlalchemy import Column, DateTime, ForeignKey
from sqlalchemy.dialects.postgresql import UUID

from app.db.base import Base


class PhotoAccessLog(Base):
    """Journal d'audit des accès aux photos du profil privé d'*un autre* utilisateur (cahier des
    charges A.9/A.6 : "journal d'audit des accès aux données sensibles"). Ne journalise pas la
    consultation de ses propres photos — seulement la divulgation à un tiers, l'événement qui
    compte pour la conformité RGPD.
    """

    __tablename__ = "photo_access_logs"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    match_id = Column(UUID(as_uuid=True), ForeignKey("matches.id"), nullable=False, index=True)
    viewer_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    owner_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    accessed_at = Column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False
    )
