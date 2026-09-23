import uuid
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field

ReportDecision = Literal["founded", "unfounded"]
BanAppealDecision = Literal["upheld", "overturned"]
RatingReviewDecision = Literal["confirmed", "cleared"]


class UserSummaryOut(BaseModel):
    id: uuid.UUID
    phone: str | None
    display_name: str | None
    is_verified: bool
    is_banned: bool
    trust_score: int | None
    trust_label: str | None


class QueueCountsOut(BaseModel):
    reports_pending: int
    ban_appeals_pending: int
    flagged_ratings_pending: int


class ReportListItemOut(BaseModel):
    id: uuid.UUID
    reason: str
    comment: str
    status: str
    created_at: datetime


class ReportDetailOut(BaseModel):
    id: uuid.UUID
    match_id: uuid.UUID
    reason: str
    comment: str
    status: str
    created_at: datetime
    reporter: UserSummaryOut
    reported: UserSummaryOut
    prior_reports_against_reported: int


class ReportResolveIn(BaseModel):
    decision: ReportDecision
    note: str | None = Field(default=None, max_length=1000)
    ban_reported: bool = False


class BanAppealListItemOut(BaseModel):
    id: uuid.UUID
    message: str
    status: str
    created_at: datetime


class BanAppealDetailOut(BaseModel):
    id: uuid.UUID
    message: str
    status: str
    created_at: datetime
    decided_at: datetime | None
    decision_note: str | None
    user: UserSummaryOut
    prior_appeals_count: int


class BanAppealResolveIn(BaseModel):
    decision: BanAppealDecision
    note: str | None = Field(default=None, max_length=1000)


class FlaggedRatingListItemOut(BaseModel):
    id: uuid.UUID
    score: int
    comment: str
    created_at: datetime


class FlaggedRatingDetailOut(BaseModel):
    id: uuid.UUID
    match_id: uuid.UUID
    score: int
    comment: str
    suspected_rancor: bool
    created_at: datetime
    rater: UserSummaryOut
    ratee: UserSummaryOut
    rancor_probability: float
    flagged_post_unlock_rule: bool


class RatingReviewIn(BaseModel):
    decision: RatingReviewDecision
    note: str | None = Field(default=None, max_length=1000)
