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
    # Généré (Ollama) ou gabarit statique — décidé et figé une seule fois à la création de la
    # ligne (voir services/messaging.py._generate_prompt), jamais recalculé sur une lecture :
    # un appel LLM à chaque GET serait payé à chaque ouverture d'écran, pas une fois par jour.
    # Nullable pour les lignes créées avant cette colonne — services/messaging.py retombe alors
    # sur le gabarit statique reconstruit depuis le prénom actuel.
    prompt = Column(String, nullable=True)
    # "interest" / "city" / "bio" (services/messaging.py._eligible_categories) — pas consommé par
    # la logique de correction (correct_answer/options suffisent), seulement pour pouvoir observer
    # après coup quelles catégories se déclenchent réellement (debug, futur KPI). Nullable pour les
    # lignes créées avant cette colonne, et pour celles créées avant l'introduction des catégories
    # ville/bio (implicitement "interest" dans ce cas).
    category = Column(String, nullable=True)
    answered = Column(Boolean, nullable=False, default=False)
    is_correct = Column(Boolean, nullable=True)
    created_at = Column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False
    )
    answered_at = Column(DateTime(timezone=True), nullable=True)
