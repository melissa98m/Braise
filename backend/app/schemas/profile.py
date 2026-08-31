from datetime import date
from typing import Literal

from pydantic import BaseModel, Field, field_validator, model_validator

Gender = Literal["homme", "femme", "non_binaire"]

MIN_FEED_AGE = 18
MAX_FEED_AGE = 99


class AvatarSpec(BaseModel):
    seed: str
    from_color: str
    to_color: str
    angle_deg: int


class PublicProfileIn(BaseModel):
    display_name: str = Field(min_length=1, max_length=40)
    birth_date: date
    bio: str = Field(default="", max_length=90)
    interests: list[str] = Field(default_factory=list)
    is_published: bool = False
    # Filtres de découverte de base (cahier des charges A.5). Tous optionnels : ne rien renseigner
    # = pas de filtre, comme avant l'existence de ces champs (voir services/discovery.get_feed).
    gender: Gender | None = None
    looking_for_gender: Gender | None = None
    age_min: int | None = Field(default=None, ge=MIN_FEED_AGE, le=MAX_FEED_AGE)
    age_max: int | None = Field(default=None, ge=MIN_FEED_AGE, le=MAX_FEED_AGE)
    # Distance (P9.3) : `city` doit être une ville de la liste fermée exposée par
    # `GET /profiles/cities` — voir services/geo.py — sinon elle est acceptée mais ne résout à
    # aucune coordonnée (donc ignorée comme filtre, jamais une erreur 422 : une ville hors liste
    # reste un nom d'affichage valide, seul son usage comme filtre de distance est concerné).
    city: str | None = Field(default=None, max_length=80)
    max_distance_km: int | None = Field(default=None, ge=1, le=1000)

    @field_validator("birth_date")
    @classmethod
    def must_be_adult(cls, value: date) -> date:
        today = date.today()
        age = today.year - value.year - ((today.month, today.day) < (value.month, value.day))
        if age < 18:
            raise ValueError("Il faut avoir 18 ans ou plus pour utiliser Braise.")
        return value

    @field_validator("interests")
    @classmethod
    def limit_interests(cls, value: list[str]) -> list[str]:
        if len(value) > 10:
            raise ValueError("10 centres d'intérêt maximum.")
        return value

    @model_validator(mode="after")
    def age_range_is_coherent(self) -> "PublicProfileIn":
        if self.age_min is not None and self.age_max is not None and self.age_min > self.age_max:
            raise ValueError("age_min ne peut pas dépasser age_max.")
        return self


class PublicProfileOut(BaseModel):
    display_name: str
    age: int
    bio: str
    interests: list[str]
    avatar: AvatarSpec
    is_published: bool
    is_premium: bool
    # Badge "profil vérifié" (cahier des charges A.5 Module 1) — reflète User.is_verified (KYC
    # léger MVP : OTP téléphone, posé à true dès la première vérification réussie, voir
    # services/otp.py). Jamais la date de naissance ni aucune autre donnée KYC brute : uniquement
    # ce booléen, même règle de minimisation que le reste de ce schéma.
    is_verified: bool
    gender: Gender | None
    looking_for_gender: Gender | None
    age_min: int | None
    age_max: int | None
    city: str | None
    max_distance_km: int | None


class PrivatePhotoOut(BaseModel):
    key: str
    url: str


class PrivateProfileOut(BaseModel):
    photos: list[PrivatePhotoOut]
