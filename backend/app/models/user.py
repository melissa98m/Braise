import uuid
from datetime import datetime, timezone

from sqlalchemy import Boolean, Column, DateTime, String, text
from sqlalchemy.dialects.postgresql import UUID

from app.db.base import Base


class User(Base):
    __tablename__ = "users"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    phone = Column(String, unique=True, nullable=False, index=True)
    otp_code = Column(String, nullable=True)
    otp_expires_at = Column(DateTime(timezone=True), nullable=True)
    is_verified = Column(Boolean, default=False, nullable=False)
    # server_default (pas seulement default=) : cette colonne a été ajoutée à une table déjà
    # peuplée — sans valeur par défaut côté base, l'ALTER TABLE NOT NULL échoue sur les lignes
    # existantes (voir la migration 2228d479fbdd).
    is_banned = Column(Boolean, default=False, nullable=False, server_default=text("false"))
    banned_at = Column(DateTime(timezone=True), nullable=True)
    # Droit à l'oubli (cahier des charges A.9) : suppression = anonymisation, pas un hard-delete
    # cascadé — les Match/Message/Rating d'un tiers restent intacts (voir services/account.py).
    deleted_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False
    )
