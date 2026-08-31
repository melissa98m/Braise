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
