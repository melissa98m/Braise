import uuid
from datetime import datetime
from typing import Literal

from pydantic import BaseModel

from app.schemas.profile import AvatarSpec


class DiscoveryCandidateOut(BaseModel):
    user_id: uuid.UUID
    display_name: str
    age: int
    bio: str
    interests: list[str]
    avatar: AvatarSpec
    common_interests: list[str]
    compatibility_score: float
    is_verified: bool
    # Score seul (jamais rating_count/flagged_count, plus granulaires) — cahier des charges
    # A.3/A.4.4 : le score de confiance doit informer la découverte, pas seulement son propre
    # profil. None tant que personne n'a encore noté ce profil (voir services/moderation.py).
    trust_score: int | None
    trust_label: str | None


class LikesReceivedOut(BaseModel):
    # Le compte est toujours renvoyé (incitation gratuite) ; `candidates` reste vide tant que
    # `is_premium` est faux — pas un "teaser" flouté par carte, un simple gate liste vide/pleine.
    count: int
    is_premium: bool
    candidates: list[DiscoveryCandidateOut]


class SwipeIn(BaseModel):
    to_user_id: uuid.UUID
    decision: Literal["like", "pass"]


class SwipeOut(BaseModel):
    decision: str
    matched: bool


class MatchOut(BaseModel):
    match_id: uuid.UUID
    other_user_id: uuid.UUID
    other_display_name: str
    flame_count: int
    unlock_threshold: int
    unlock_pct: int
    blur_stage: Literal["silhouette", "flou_leger", "net"]
    matched_at: datetime
    # Badge de messages non lus (P9.2) : messages de l'autre côté envoyés après mon "lu jusqu'à"
    # sur ce match (services/matches.mark_read) — voir list_my_matches pour le calcul batché.
    unread_count: int
