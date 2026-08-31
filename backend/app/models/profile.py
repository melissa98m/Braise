from datetime import datetime, timezone

from sqlalchemy import Boolean, Column, Date, DateTime, Float, ForeignKey, Integer, String
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
    # genre recherché"). Tous nullable : un profil qui ne les renseigne pas n'est filtré par rien,
    # exactement le comportement d'avant ces colonnes (voir services/discovery.get_feed).
    gender = Column(String(20), nullable=True)
    looking_for_gender = Column(String(20), nullable=True, index=True)
    age_min = Column(Integer, nullable=True)
    age_max = Column(Integer, nullable=True)
    # Distance (P9.3) : pas de géocodage payant ni de capture GPS — `city` est le nom choisi dans
    # une liste fermée de villes françaises (services/geo.py), `city_lat`/`city_lon` sa position
    # résolue une seule fois à l'enregistrement du profil (services/profiles.upsert_public_profile)
    # plutôt qu'à chaque requête de feed. `max_distance_km` est ma propre préférence de recherche,
    # symétrique à `age_min`/`age_max` : nulle = pas de filtre.
    city = Column(String(80), nullable=True)
    city_lat = Column(Float, nullable=True)
    city_lon = Column(Float, nullable=True)
    max_distance_km = Column(Integer, nullable=True)
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
