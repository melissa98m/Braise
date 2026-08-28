from datetime import datetime, timezone

from sqlalchemy import Boolean, Column, DateTime, ForeignKey
from sqlalchemy.dialects.postgresql import UUID

from app.db.base import Base


class Subscription(Base):
    __tablename__ = "subscriptions"

    # Un seul palier Premium au MVP (cahier des charges C.1) : une ligne courante par
    # utilisateur suffit, pas d'historique de paliers à modéliser pour l'instant.
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), primary_key=True)
    is_active = Column(Boolean, nullable=False, default=False)
    started_at = Column(DateTime(timezone=True), nullable=True)
    expires_at = Column(DateTime(timezone=True), nullable=True)
    cancel_at_period_end = Column(Boolean, nullable=False, default=False)
    canceled_at = Column(DateTime(timezone=True), nullable=True)
    updated_at = Column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
        nullable=False,
    )
