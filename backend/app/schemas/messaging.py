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
    # Vrai dès que le destinataire (jamais l'émetteur) a marqué le match comme lu après l'envoi
    # de ce message — voir services/matches.message_is_read.
    read: bool


class DailyQuestionOut(BaseModel):
    # Jamais persisté (voir services/messaging._build_prompt) : dérivé à la volée du nom actuel
    # de l'autre côté, à chaque lecture.
    prompt: str
    options: list[str]
    answered: bool
    is_correct: bool | None


class DailyQuestionAnswerIn(BaseModel):
    selected: str = Field(min_length=1, max_length=100)


class DailyQuestionResultOut(BaseModel):
    correct: bool
    correct_answer: str
    flame_count: int
