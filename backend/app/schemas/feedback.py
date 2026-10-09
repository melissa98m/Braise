from typing import Literal

from pydantic import BaseModel, Field


class FeedbackIn(BaseModel):
    category: Literal["bug", "idea", "other"]
    message: str = Field(min_length=5, max_length=2000)
    context: str | None = Field(default=None, max_length=100)


class FeedbackOut(BaseModel):
    message: str


class ClientErrorIn(BaseModel):
    # Limites larges à la réception (une pile Flutter peut être longue), tronquées ensuite au
    # stockage (services/client_errors.py) : refuser une erreur trop longue reviendrait à perdre
    # précisément les plantages les plus spectaculaires.
    message: str = Field(min_length=1, max_length=4000)
    stack: str | None = Field(default=None, max_length=50000)
    source: Literal["flutter", "platform"]
    path: str | None = Field(default=None, max_length=500)
