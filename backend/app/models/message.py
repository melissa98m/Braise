import uuid
from datetime import datetime, timezone

from sqlalchemy import Column, DateTime, ForeignKey, Index, String
from sqlalchemy.dialects.postgresql import UUID

from app.db.base import Base


class Message(Base):
    __tablename__ = "messages"
    # Index composite plutôt que deux index séparés : couvre à la fois "tous les messages d'un
    # match" (préfixe gauche) et "... triés par date", le seul accès dont ce module a besoin.
    __table_args__ = (Index("ix_messages_match_created", "match_id", "created_at"),)

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    match_id = Column(UUID(as_uuid=True), ForeignKey("matches.id"), nullable=False)
    sender_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    body = Column(String(2000), nullable=False)
    created_at = Column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False
    )
