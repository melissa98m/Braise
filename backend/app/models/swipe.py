import enum
import uuid
from datetime import datetime, timezone

from sqlalchemy import Column, DateTime, ForeignKey, String, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID

from app.db.base import Base


class SwipeDecision(str, enum.Enum):
    LIKE = "like"
    PASS = "pass"


class Swipe(Base):
    __tablename__ = "swipes"
    __table_args__ = (UniqueConstraint("from_user_id", "to_user_id", name="uq_swipe_pair"),)

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    from_user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    to_user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    decision = Column(String(4), nullable=False)
    created_at = Column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False
    )
