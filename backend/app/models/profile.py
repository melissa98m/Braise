from datetime import datetime, timezone

from sqlalchemy import Boolean, Column, Date, DateTime, ForeignKey, Integer, String
from sqlalchemy.dialects.postgresql import JSONB, UUID

from app.db.base import Base


class PublicProfile(Base):
    __tablename__ = "public_profiles"

    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), primary_key=True)
    display_name = Column(String(40), nullable=False, default="")
    birth_date = Column(Date, nullable=False)
    bio = Column(String(90), nullable=False, default="")
    interests = Column(JSONB, nullable=False, default=list)
    avatar_seed = Column(String, nullable=False)
    is_published = Column(Boolean, nullable=False, default=False, index=True)
    # Filtres de découverte de base (cahier des charges A.5 Module 2 : "tranche d'âge, distance,
    # genre recherché" — la distance est hors scope ici, aucune capture de géolocalisation
    # n'existe dans l'app). Tous nullable : un profil qui ne les renseigne pas n'est filtré par
    # rien, exactement le comportement d'avant ces colonnes (voir services/discovery.get_feed).
    gender = Column(String(20), nullable=True)
    looking_for_gender = Column(String(20), nullable=True, index=True)
    age_min = Column(Integer, nullable=True)
    age_max = Column(Integer, nullable=True)
    created_at = Column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False
    )
    updated_at = Column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
        nullable=False,
    )


class PrivateProfile(Base):
    __tablename__ = "private_profiles"

    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), primary_key=True)
    photo_keys = Column(JSONB, nullable=False, default=list)
    updated_at = Column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
        nullable=False,
    )
