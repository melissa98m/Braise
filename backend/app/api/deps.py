import uuid

from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from jose import JWTError
from sqlalchemy.orm import Session

from app.core.security import decode_access_token
from app.db.session import get_db
from app.models.user import User
from app.services import activity as activity_service

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/verify-otp", auto_error=False)


def _resolve_user(token: str | None, db: Session) -> User:
    credentials_error = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Identifiants invalides ou expirés.",
        headers={"WWW-Authenticate": "Bearer"},
    )
    if token is None:
        raise credentials_error

    try:
        payload = decode_access_token(token)
        user_id = uuid.UUID(payload.get("sub"))
    except (JWTError, ValueError, TypeError):
        raise credentials_error

    user = db.get(User, user_id)
    if user is None:
        raise credentials_error
    if user.deleted_at is not None:
        # Un token émis avant la suppression reste cryptographiquement valide jusqu'à expiration
        # (pas de révocation de JWT) — c'est ce garde-fou qui empêche de continuer à l'utiliser.
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Compte supprimé.")
    return user


def user_from_token(token: str | None, db: Session) -> User:
    user = _resolve_user(token, db)
    if user.is_banned:
        # Choix délibéré : couper l'accès partout (y compris /auth/me) plutôt que de garder un
        # cas particulier pour afficher un écran "compte suspendu" — cahier des charges A.4.4.
        # La seule exception volontaire est get_current_user_even_if_banned ci-dessous, réservée
        # à la contestation de bannissement (A.9) : sans elle, le bannissement automatique n'a
        # aucune voie de recours joignable.
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Compte suspendu.")
    return user


def get_current_user(
    token: str | None = Depends(oauth2_scheme), db: Session = Depends(get_db)
) -> User:
    user = user_from_token(token, db)
    # Ici (requêtes HTTP authentifiées) plutôt que dans user_from_token : le WebSocket de
    # messagerie s'en sert aussi, mais une conversation ouverte implique déjà des appels HTTP le
    # même jour — inutile de payer ce coût par connexion WS. Au plus une écriture par jour et par
    # personne (services/activity.py).
    activity_service.record_activity(db, user.id)
    return user


def get_optional_user(
    token: str | None = Depends(oauth2_scheme), db: Session = Depends(get_db)
) -> User | None:
    """La personne connectée si le jeton est valide, sinon `None` — jamais une erreur. Réservé à
    `POST /client-errors` : une erreur peut survenir avant la connexion, ou justement à cause
    d'un jeton expiré, et doit pouvoir être remontée quand même."""
    if token is None:
        return None
    try:
        return user_from_token(token, db)
    except HTTPException:
        return None


def get_current_user_even_if_banned(
    token: str | None = Depends(oauth2_scheme), db: Session = Depends(get_db)
) -> User:
    """Ne pas réutiliser ailleurs — le reste de l'API doit continuer à passer par
    get_current_user/user_from_token. Réservé aux endpoints POST /moderation/ban-appeal et
    GET /moderation/ban-appeal/mine : c'est le seul point d'accès qu'un compte banni doit
    pouvoir atteindre."""
    return _resolve_user(token, db)


def get_current_staff_user(
    token: str | None = Depends(oauth2_scheme), db: Session = Depends(get_db)
) -> User:
    """Réservé à api/v1/admin.py — ne pas réutiliser ailleurs. Passe par user_from_token (pas
    _resolve_user) : un compte staff banni perd quand même l'accès, is_banned reste prioritaire
    sur is_staff. is_staff n'est jamais fait confiance côté client, toujours re-dérivé de la base
    via le JWT, comme is_banned."""
    user = user_from_token(token, db)
    if not user.is_staff:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Accès réservé au personnel.")
    return user
