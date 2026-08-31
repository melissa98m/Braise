import uuid
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator

MIN_WORDS_IN_RATING_COMMENT = 4

ReportReasonLiteral = Literal[
    "harcelement", "faux_profil", "contenu_inapproprie", "comportement_suspect", "autre"
]


class RatingIn(BaseModel):
    score: int = Field(ge=1, le=5)
    comment: str = Field(min_length=1, max_length=1000)

    @field_validator("comment")
    @classmethod
    def must_have_enough_words(cls, value: str) -> str:
        word_count = len([word for word in value.strip().split() if word])
        if word_count < MIN_WORDS_IN_RATING_COMMENT:
            raise ValueError(
                f"Le commentaire doit contenir au moins {MIN_WORDS_IN_RATING_COMMENT} mots."
            )
        return value


class RatingOut(BaseModel):
    suspected_rancor: bool
    trust_score: int | None


class TrustScoreOut(BaseModel):
    score: int | None
    label: str | None
    rating_count: int
    flagged_count: int


class ReportIn(BaseModel):
    reason: ReportReasonLiteral
    comment: str | None = Field(default=None, max_length=1000)


class ReportOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    reason: str
    status: str
    created_at: datetime


class BanAppealIn(BaseModel):
    message: str = Field(min_length=10, max_length=1000)


class BanAppealOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    status: str
    message: str
    created_at: datetime
    decided_at: datetime | None
    decision_note: str | None
