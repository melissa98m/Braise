import uuid
from datetime import datetime, timezone

from sqlalchemy import Boolean, Column, DateTime, Integer, String, text
from sqlalchemy.dialects.postgresql import UUID

from app.db.base import Base


class User(Base):
    __tablename__ = "users"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    phone = Column(String, unique=True, nullable=False, index=True)
    otp_code = Column(String, nullable=True)
    otp_expires_at = Column(DateTime(timezone=True), nullable=True)
    # Anti brute-force (P6.1) : `otp_requested_at` impose un délai minimum entre deux demandes de
    # code pour le même numéro (services/otp.py::MIN_RESEND_INTERVAL_SECONDS) ; `otp_attempts`
    # compte les essais de vérification ratés sur le code courant et le neutralise après
    # `MAX_OTP_ATTEMPTS` — sans ça, un code à 6 chiffres (10^6 possibilités, 10 min de validité)
    # se force par brute force sans aucun frein.
    otp_requested_at = Column(DateTime(timezone=True), nullable=True)
    otp_attempts = Column(Integer, default=0, nullable=False, server_default=text("0"))
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
