import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class MessageOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    match_id: uuid.UUID
    sender_id: uuid.UUID
    body: str
    created_at: datetime


class DailyQuestionOut(BaseModel):
    options: list[str]
    answered: bool
    is_correct: bool | None


class DailyQuestionAnswerIn(BaseModel):
    selected: str = Field(min_length=1, max_length=100)


class DailyQuestionResultOut(BaseModel):
    correct: bool
    correct_answer: str
    flame_count: int
