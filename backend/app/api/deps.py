import uuid

from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from jose import JWTError
from sqlalchemy.orm import Session

from app.core.security import decode_access_token
from app.db.session import get_db
from app.models.user import User

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/verify-otp", auto_error=False)


def user_from_token(token: str | None, db: Session) -> User:
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
    if user.is_banned:
        # Choix délibéré : couper l'accès partout (y compris /auth/me) plutôt que de garder un
        # cas particulier pour afficher un écran "compte suspendu" — cahier des charges A.4.4.
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Compte suspendu.")
    if user.deleted_at is not None:
        # Un token émis avant la suppression reste cryptographiquement valide jusqu'à expiration
        # (pas de révocation de JWT) — c'est ce garde-fou qui empêche de continuer à l'utiliser.
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Compte supprimé.")
    return user


def get_current_user(
    token: str | None = Depends(oauth2_scheme), db: Session = Depends(get_db)
) -> User:
    return user_from_token(token, db)
