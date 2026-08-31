import enum
import uuid
from datetime import datetime, timezone

from sqlalchemy import Column, DateTime, ForeignKey, String
from sqlalchemy.dialects.postgresql import UUID

from app.db.base import Base


class BanAppealStatus(str, enum.Enum):
    PENDING = "pending"
    UPHELD = "upheld"
    OVERTURNED = "overturned"


class BanAppeal(Base):
    """Procédure de contestation humaine d'un bannissement automatique (cahier des charges A.9 :
    "possibilité de contestation humaine"), qui n'existait pas avant ce palier alors que le
    bannissement automatique, lui, était déjà en place depuis la Phase 4. Suit le même schéma que
    `Report` : démarre systématiquement 'pending', revue via Adminer (mise à jour manuelle de
    `status`/`decision_note`, et de `User.is_banned` si la contestation est retenue) — pas
    d'outillage de tri automatique, cohérent avec le reste de la modération MVP.
    """

    __tablename__ = "ban_appeals"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    message = Column(String(1000), nullable=False)
    status = Column(String(20), nullable=False, default=BanAppealStatus.PENDING.value)
    decision_note = Column(String(1000), nullable=True)
    created_at = Column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False
    )
    decided_at = Column(DateTime(timezone=True), nullable=True)
