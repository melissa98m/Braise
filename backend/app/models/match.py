import uuid
from datetime import datetime, timezone

from sqlalchemy import Column, DateTime, ForeignKey, Integer, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID

from app.db.base import Base


class Match(Base):
    __tablename__ = "matches"
    # user_a_id/user_b_id sont toujours stockés dans un ordre canonique (voir
    # services/discovery._ordered_pair) pour qu'une paire ne puisse jamais matcher deux fois.
    __table_args__ = (UniqueConstraint("user_a_id", "user_b_id", name="uq_match_pair"),)

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_a_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    user_b_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    # Le comptage des flammes arrive en Phase 3 (question quotidienne) ; ces colonnes vivent ici
    # car le déblocage progressif est une propriété du match lui-même (Module 2 du cahier des
    # charges), pas du mécanisme qui l'incrémente.
    flame_count = Column(Integer, nullable=False, default=0)
    unlock_threshold = Column(Integer, nullable=False, default=5)
    # Posé quand flame_count franchit unlock_threshold pour la première fois (Phase 3) ; sert de
    # point de référence en Phase 4 pour repérer une note très négative postée juste après la
    # découverte du physique (cahier des charges A.4.5 : "corrélation temporelle entre rejet et
    # note négative").
    unlocked_at = Column(DateTime(timezone=True), nullable=True)
    matched_at = Column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False
    )
