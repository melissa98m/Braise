import uuid
from datetime import datetime, timezone

from sqlalchemy import Boolean, Column, DateTime, ForeignKey, Integer, String, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID

from app.db.base import Base


class Rating(Base):
    __tablename__ = "ratings"
    # Une note par match et par notateur (chacun des deux participants ne note l'autre qu'une
    # fois) — appliqué en base, pas seulement côté application (voir services/moderation.py).
    __table_args__ = (UniqueConstraint("match_id", "rater_id", name="uq_rating_once_per_match"),)

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    match_id = Column(UUID(as_uuid=True), ForeignKey("matches.id"), nullable=False, index=True)
    rater_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    ratee_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    score = Column(Integer, nullable=False)
    comment = Column(String(1000), nullable=False)
    # Sortie combinée règle métier + classifieur scikit-learn (services/moderation_ml.py) : une
    # note suspecte pèse moins dans le score de confiance plutôt que d'être rejetée d'office —
    # la revue humaine reste seule habilitée à trancher (cahier des charges A.4.5).
    suspected_rancor = Column(Boolean, nullable=False, default=False)
    created_at = Column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False
    )
