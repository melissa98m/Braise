import uuid
from datetime import datetime, timezone

from sqlalchemy import Boolean, Column, DateTime, ForeignKey, String
from sqlalchemy.dialects.postgresql import UUID

from app.db.base import Base


class PushSubscription(Base):
    """Un abonnement Web Push (RFC 8030/8291) par appareil/navigateur — voir services/notifications.py
    et docs/V2_FEATURES.md §6. `endpoint` est unique *seul*, pas `(user_id, endpoint)` : une URL
    d'endpoint est déjà attribuée par le service de push du navigateur de façon unique par
    combinaison navigateur+origine+appareil, donc deux comptes ne peuvent jamais légitimement
    partager la même ligne — et sur un appareil partagé où un second compte se connecte plus tard,
    ré-abonner ce même navigateur doit réaffecter la ligne existante au nouveau compte (upsert sur
    `endpoint`, voir upsert_subscription) plutôt que d'en créer une orpheline en double.
    `p256dh`/`auth` sont les clés de chiffrement (RFC 8291) que pywebpush utilise pour chiffrer
    chaque notification — jamais transmises ailleurs qu'à ce serveur et au service de push du
    navigateur lui-même. `last_seen_at` est purement informatif (mis à jour après un envoi réussi,
    jamais lu par une tâche de purge) : le seul mécanisme de nettoyage est réactif, sur un 404/410
    constaté lors d'un envoi (voir _is_subscription_dead) — pas de job planifié à faire tourner.
    """

    __tablename__ = "push_subscriptions"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    endpoint = Column(String(500), nullable=False, unique=True)
    p256dh = Column(String(255), nullable=False)
    auth = Column(String(255), nullable=False)
    user_agent = Column(String(255), nullable=True)
    # Préférences par catégorie, tenues côté serveur plutôt que dans un cache navigateur (ex.
    # IndexedDB, seul stockage qu'un Service Worker peut lire sans passer par le thread principal)
    # : un abonnement dessert les 3 catégories, mais le filtrage se fait ici, dans la requête qui
    # sélectionne les abonnements à notifier (voir send_push_to_user) — plus simple à faire juste
    # et à tester qu'un mécanisme de synchronisation client dédié, pour le même résultat (une
    # bascule "Messages" désactivée n'entraîne plus de push pour cette catégorie, sur cet appareil).
    notify_match = Column(Boolean, nullable=False, default=True)
    notify_question = Column(Boolean, nullable=False, default=True)
    notify_messages = Column(Boolean, nullable=False, default=True)
    created_at = Column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False
    )
    last_seen_at = Column(DateTime(timezone=True), nullable=True)
