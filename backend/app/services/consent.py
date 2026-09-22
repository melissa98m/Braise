from datetime import datetime, timezone

from sqlalchemy.orm import Session

from app.models.user import User
from app.schemas.auth import ConsentIn


def consents_complete(user: User) -> bool:
    """Les 4 consentements (majorité, CGU, confidentialité, données sensibles — voir
    models/user.py) doivent tous avoir été donnés au moins une fois. Utilisé pour gater
    `PUT /profiles/me/public` (services/profiles.upsert_public_profile appelle cette fonction en
    amont) : impossible de renseigner gender/looking_for_gender (la donnée sensible elle-même)
    sans être passé par l'écran de consentement.
    """
    return (
        user.consent_age_at is not None
        and user.consent_cgu_at is not None
        and user.consent_privacy_at is not None
        and user.consent_sensitive_data_at is not None
    )


def record_consent(db: Session, user: User, payload: ConsentIn) -> User:
    """Chaque case cochée doit valoir `true` explicitement — un `false` (ou l'absence du champ)
    ne fait pas régresser un consentement déjà donné, mais n'en enregistre pas un nouveau non
    plus, cohérent avec le principe qu'un consentement ne peut être qu'affirmatif et univoque
    (jamais déduit d'une case non cochée)."""
    now = datetime.now(timezone.utc)
    if payload.age_confirmed and user.consent_age_at is None:
        user.consent_age_at = now
    if payload.cgu_accepted and user.consent_cgu_at is None:
        user.consent_cgu_at = now
    if payload.privacy_acknowledged and user.consent_privacy_at is None:
        user.consent_privacy_at = now
    if payload.sensitive_data_consented and user.consent_sensitive_data_at is None:
        user.consent_sensitive_data_at = now
    db.commit()
    db.refresh(user)
    return user
