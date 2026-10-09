import uuid
from datetime import datetime, timezone

from sqlalchemy import Column, DateTime, ForeignKey, String, Text
from sqlalchemy.dialects.postgresql import UUID

from app.db.base import Base


class Feedback(Base):
    """Un retour de testeur·se envoyé depuis l'app (Paramètres → Envoyer un retour).

    Pas une donnée de modération : jamais d'effet sur un compte, seulement un statut « traité »
    pour que l'équipe s'y retrouve (file « Retours » du tableau de bord staff). Supprimé avec le
    compte de son auteur·rice (services/account.py) — le texte peut contenir n'importe quoi.
    """

    __tablename__ = "feedback"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    # "bug" / "idea" / "other" (schemas/feedback.py).
    category = Column(String(20), nullable=False)
    message = Column(Text, nullable=False)
    # Où dans l'app (facultatif, ex. "settings") et sur quel navigateur/appareil — de quoi
    # reproduire un bug sans redemander à la personne.
    context = Column(String(100), nullable=True)
    user_agent = Column(String(255), nullable=True)
    # "new" / "done".
    status = Column(String(10), nullable=False, default="new", index=True)
    created_at = Column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False
    )
    handled_at = Column(DateTime(timezone=True), nullable=True)
    handled_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
