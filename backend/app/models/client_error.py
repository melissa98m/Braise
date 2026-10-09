import uuid
from datetime import datetime, timezone

from sqlalchemy import Column, DateTime, ForeignKey, Integer, String, Text, text
from sqlalchemy.dialects.postgresql import UUID

from app.db.base import Base


class ClientError(Base):
    """Une erreur remontée par l'app (services/client_errors.py), regroupée par empreinte.

    Une ligne par erreur distincte, pas par occurrence : `occurrences` compte les répétitions,
    pour qu'un plantage récurrent ne noie pas la file « Erreurs » du tableau de bord staff sous
    des centaines de doublons. Une erreur marquée « traitée » qui réapparaît repasse « nouvelle »
    (régression). Purgée 90 jours après sa dernière occurrence (tâche quotidienne).
    """

    __tablename__ = "client_errors"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    # SHA-256 du message normalisé + première ligne de pile — voir client_errors._fingerprint.
    fingerprint = Column(String(64), nullable=False, unique=True)
    message = Column(Text, nullable=False)
    stack = Column(Text, nullable=True)
    # "flutter" (FlutterError.onError) / "platform" (PlatformDispatcher.onError, erreurs async).
    source = Column(String(20), nullable=False)
    # Chemin de la page sans paramètres (jamais la query string, qui peut porter un identifiant).
    path = Column(String(200), nullable=True)
    user_agent = Column(String(255), nullable=True)
    # Dernière personne touchée, s'il y en avait une de connectée — de quoi recontacter un·e
    # testeur·se, sans historique complet de qui a rencontré quoi. Effacé à la suppression du
    # compte (services/account.py).
    last_user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    occurrences = Column(Integer, nullable=False, default=1, server_default=text("1"))
    # "new" / "done".
    status = Column(String(10), nullable=False, default="new", index=True)
    first_seen_at = Column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False
    )
    last_seen_at = Column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False, index=True
    )
