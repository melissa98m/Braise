from pydantic import BaseModel, EmailStr, Field, field_validator


def _normalize_email(value: str) -> str:
    # EmailStr a déjà validé le format (et mis le domaine en minuscules) ; on met aussi la partie
    # locale en minuscules : "Lea@Gmail.com" et "lea@gmail.com" désignent la même boîte chez la
    # quasi-totalité des fournisseurs, et deux comptes distincts pour la même personne seraient
    # pires que l'hypothétique fournisseur sensible à la casse. Comparaison exacte ensuite
    # partout (services/otp.py), jamais de `lower()` à refaire côté requête.
    return value.strip().lower()


class OTPRequest(BaseModel):
    email: EmailStr = Field(max_length=254)

    @field_validator("email")
    @classmethod
    def email_is_normalized(cls, value: str) -> str:
        return _normalize_email(value)


class OTPRequestResponse(BaseModel):
    message: str
    debug_code: str | None = None


class OTPVerify(BaseModel):
    email: EmailStr = Field(max_length=254)
    # Le code OTP fait toujours 6 chiffres (core/security.generate_otp_code) — un format
    # vérifiable avant même de toucher la base, plutôt que de laisser un simple mismatch faire
    # tout le travail pour une saisie qui n'a de toute façon aucune chance d'être correcte.
    code: str = Field(min_length=6, max_length=6, pattern=r"^[0-9]{6}$")

    @field_validator("email")
    @classmethod
    def email_is_normalized(cls, value: str) -> str:
        return _normalize_email(value)


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"


class ConsentIn(BaseModel):
    age_confirmed: bool = False
    cgu_accepted: bool = False
    privacy_acknowledged: bool = False
    sensitive_data_consented: bool = False


class ConsentOut(BaseModel):
    consents_given: bool
    consent_age_at: str | None = None
    consent_cgu_at: str | None = None
    consent_privacy_at: str | None = None
    consent_sensitive_data_at: str | None = None
