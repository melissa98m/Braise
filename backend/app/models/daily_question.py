import uuid
from datetime import datetime, timezone

from sqlalchemy import Boolean, Column, Date, DateTime, ForeignKey, String, UniqueConstraint
from sqlalchemy.dialects.postgresql import JSONB, UUID

from app.db.base import Base


class DailyQuestion(Base):
    __tablename__ = "daily_questions"
    # Une question par utilisateur, par match, par jour — l'unicité est appliquée par la
    # base (pas seulement par l'application) car deux requêtes concurrentes peuvent tenter de
    # générer la question du jour au même instant (voir services/messaging.py).
    __table_args__ = (
        UniqueConstraint("match_id", "for_user_id", "question_date", name="uq_daily_question"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    match_id = Column(UUID(as_uuid=True), ForeignKey("matches.id"), nullable=False, index=True)
    for_user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    question_date = Column(Date, nullable=False)
    correct_answer = Column(String, nullable=False)
    options = Column(JSONB, nullable=False)
    answered = Column(Boolean, nullable=False, default=False)
    is_correct = Column(Boolean, nullable=True)
    created_at = Column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False
    )
    answered_at = Column(DateTime(timezone=True), nullable=True)
