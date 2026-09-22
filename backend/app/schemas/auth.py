import re

from pydantic import BaseModel, Field, field_validator

# Le backend ne normalise jamais le numéro (comparaison exacte à chaque requête, voir
# services/otp.py) — cette regex n'attrape donc qu'une saisie clairement invalide (lettres,
# numéro tronqué...), pas un format que le backend imposerait lui-même. Même règle que
# mobile/bresonne_app/lib/utils/validators.dart::validatePhoneNumber ; garder les deux
# synchronisées si l'une change.
_PHONE_PATTERN = re.compile(r"^\+?[0-9]{8,15}$")


def _validate_phone(value: str) -> str:
    digits_only = re.sub(r"[\s.\-()]", "", value.strip())
    if not _PHONE_PATTERN.match(digits_only):
        raise ValueError("Numéro de téléphone invalide.")
    return value


class OTPRequest(BaseModel):
    phone: str = Field(min_length=1)

    @field_validator("phone")
    @classmethod
    def phone_is_valid(cls, value: str) -> str:
        return _validate_phone(value)


class OTPRequestResponse(BaseModel):
    message: str
    debug_code: str | None = None


class OTPVerify(BaseModel):
    phone: str = Field(min_length=1)
    # Le code OTP fait toujours 6 chiffres (core/security.generate_otp_code) — un format
    # vérifiable avant même de toucher la base, plutôt que de laisser un simple mismatch faire
    # tout le travail pour une saisie qui n'a de toute façon aucune chance d'être correcte.
    code: str = Field(min_length=6, max_length=6, pattern=r"^[0-9]{6}$")

    @field_validator("phone")
    @classmethod
    def phone_is_valid(cls, value: str) -> str:
        return _validate_phone(value)


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
