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
    # Figé à la création de la question (voir services/messaging._generate_prompt), jamais
    # régénéré sur une relecture — un appel LLM à chaque GET serait payé à chaque ouverture
    # d'écran, pas une fois par jour.
    prompt: str
    options: list[str]
    answered: bool
    is_correct: bool | None
    # "interest" / "city" / "bio" — None sur les lignes créées avant l'ajout de cette colonne
    # (implicitement "interest" dans ce cas, la seule catégorie qui existait alors).
    category: str | None = None


class DailyQuestionAnswerIn(BaseModel):
    selected: str = Field(min_length=1, max_length=100)


class DailyQuestionResultOut(BaseModel):
    correct: bool
    correct_answer: str
    flame_count: int
