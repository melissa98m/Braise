import uuid
from datetime import datetime, timezone

from sqlalchemy import Boolean, Column, DateTime, String, text
from sqlalchemy.dialects.postgresql import UUID

from app.db.base import Base


class User(Base):
    __tablename__ = "users"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    # Identifiant de connexion (OTP par email, services/otp.py) — toujours normalisé en
    # minuscules avant d'arriver ici (schemas/auth.py), donc une comparaison exacte suffit. Le
    # code OTP lui-même ne vit pas sur User mais dans `otp_challenges` (models/otp_challenge.py) :
    # un compte n'est créé qu'après une vérification réussie, jamais à la simple demande d'un code.
    email = Column(String, unique=True, nullable=False, index=True)
    is_verified = Column(Boolean, default=False, nullable=False)
    # server_default (pas seulement default=) : cette colonne a été ajoutée à une table déjà
    # peuplée — sans valeur par défaut côté base, l'ALTER TABLE NOT NULL échoue sur les lignes
    # existantes (voir la migration 2228d479fbdd).
    is_banned = Column(Boolean, default=False, nullable=False, server_default=text("false"))
    banned_at = Column(DateTime(timezone=True), nullable=True)
    # Interface de revue de modération humaine (cahier des charges C.1/C.2, V2) : un seul niveau
    # de droits élevés à distinguer pour l'instant, donc un booléen sur User plutôt qu'une table
    # de rôles séparée — revisiter seulement si un vrai besoin de rôles multiples apparaît, même
    # logique que le choix "un seul JWT longue durée" en core/config.py.
    is_staff = Column(Boolean, default=False, nullable=False, server_default=text("false"))
    # Droit à l'oubli (cahier des charges A.9) : suppression = anonymisation, pas un hard-delete
    # cascadé — les Match/Message/Rating d'un tiers restent intacts (voir services/account.py).
    deleted_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False
    )
    # Consentement RGPD à l'inscription (recommandation CNIL pour les apps de rencontre) : 4
    # horodatages distincts plutôt qu'un seul booléen "consentement donné", pour pouvoir prouver
    # quoi a été consenti et quand en cas de contrôle — un booléen unique ne le permettrait pas.
    # `consent_sensitive_data_at` est délibérément séparé des 3 autres (voir
    # services/consent.py) : c'est le seul qui porte sur une donnée sensible au sens RGPD art. 9
    # (orientation sexuelle, révélée par la combinaison gender/looking_for_gender — voir
    # schemas/profile.py), donc le seul qui doit rester "libre, spécifique, éclairé et univoque"
    # via une case dédiée, jamais groupée avec l'acceptation des CGU. Tous nullable : un compte
    # créé avant l'existence de cette fonctionnalité n'a simplement encore rien consenti.
    consent_age_at = Column(DateTime(timezone=True), nullable=True)
    consent_cgu_at = Column(DateTime(timezone=True), nullable=True)
    consent_privacy_at = Column(DateTime(timezone=True), nullable=True)
    consent_sensitive_data_at = Column(DateTime(timezone=True), nullable=True)
