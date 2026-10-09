from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.core.config import get_settings
from app.db.session import get_db
from app.models.user import User
from app.schemas.notifications import PushSubscribeIn, PushSubscribeOut, VapidPublicKeyOut
from app.services import notifications as notifications_service

router = APIRouter(prefix="/notifications", tags=["notifications"])


@router.get("/vapid-public-key", response_model=VapidPublicKeyOut)
def get_vapid_public_key():
    # Non authentifié délibérément, comme /health : une clé publique VAPID n'est pas un secret
    # (elle est de toute façon envoyée à chaque navigateur lors de PushManager.subscribe()), et
    # l'exiger forcerait le client à être déjà connecté avant même de préparer un abonnement.
    return VapidPublicKeyOut(public_key=get_settings().vapid_public_key)


@router.post("/subscribe", response_model=PushSubscribeOut)
def subscribe(
    payload: PushSubscribeIn,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    notifications_service.upsert_subscription(db, user, payload)
    return PushSubscribeOut()


@router.delete("/subscribe", response_model=PushSubscribeOut)
def unsubscribe(
    endpoint: str = Query(...),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    notifications_service.delete_subscription(db, user, endpoint)
    return PushSubscribeOut()
