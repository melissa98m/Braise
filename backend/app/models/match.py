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
    # Statut de lecture (cahier des charges A.5 Module 3 : "avec statut de lecture") — un
    # timestamp "lu jusqu'à" par côté plutôt qu'un flag par message : suffisant pour un chat 1-to-1
    # (services/matches.mark_read/message_is_read), pas de table séparée à gérer.
    last_read_at_a = Column(DateTime(timezone=True), nullable=True)
    last_read_at_b = Column(DateTime(timezone=True), nullable=True)
    # Même principe pour l'accusé de réception ("reçu"), distinct de la lecture : posé dès que le
    # client de ce côté a effectivement reçu la trame WS d'un message, avant même de l'avoir lu
    # (services/matches.mark_delivered/message_is_delivered). mark_read fait toujours progresser
    # ces deux colonnes en même temps que last_read_at_* : lire implique avoir reçu, donc
    # last_delivered_at_* ne doit jamais rester en retard sur last_read_at_* même si le client
    # n'envoie jamais l'accusé "delivered" explicite (ex. un client plus ancien).
    last_delivered_at_a = Column(DateTime(timezone=True), nullable=True)
    last_delivered_at_b = Column(DateTime(timezone=True), nullable=True)
