from datetime import date

from pydantic import BaseModel, Field, field_validator


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


class PublicProfileOut(BaseModel):
    display_name: str
    age: int
    bio: str
    interests: list[str]
    avatar: AvatarSpec
    is_published: bool
    is_premium: bool


class PrivatePhotoOut(BaseModel):
    key: str
    url: str


class PrivateProfileOut(BaseModel):
    photos: list[PrivatePhotoOut]
