import uuid

from sqlalchemy import Column, DateTime, Integer, String, text
from sqlalchemy.dialects.postgresql import UUID

from app.db.base import Base


class OtpChallenge(Base):
    """Un code OTP en attente pour une adresse email — séparé de `users` à dessein.

    Tant que le code n'a pas été vérifié, aucun `User` n'existe : demander un code pour une
    adresse quelconque ne crée jamais de compte (contrairement à l'ancien flux téléphone, où
    `request_otp` insérait un `User` pour n'importe quel numéro saisi). Une ligne par adresse,
    réécrite à chaque nouvelle demande, supprimée dès la vérification réussie.
    """

    __tablename__ = "otp_challenges"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    email = Column(String, unique=True, nullable=False, index=True)
    # HMAC du code (core/security.hash_otp_code), jamais le code en clair. Nullable : vidé quand
    # le code est neutralisé (trop d'essais ratés) sans perdre les compteurs de débit ci-dessous.
    code_hash = Column(String, nullable=True)
    expires_at = Column(DateTime(timezone=True), nullable=True)
    # Essais de vérification ratés sur le code courant (MAX_OTP_ATTEMPTS, services/otp.py).
    attempts = Column(Integer, default=0, nullable=False, server_default=text("0"))
    # Dernière demande (délai minimum entre deux envois, MIN_RESEND_INTERVAL_SECONDS).
    requested_at = Column(DateTime(timezone=True), nullable=False)
    # Fenêtre glissante d'une heure pour MAX_REQUESTS_PER_EMAIL_PER_HOUR : début de la fenêtre
    # courante + nombre de codes envoyés depuis — protège la boîte de quelqu'un contre un envoi
    # en rafale (et le quota gratuit Resend contre l'épuisement).
    window_started_at = Column(DateTime(timezone=True), nullable=False)
    window_count = Column(Integer, default=0, nullable=False, server_default=text("0"))
