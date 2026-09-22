from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.core.config import get_settings
from app.db.session import get_db
from app.models.user import User
from app.schemas.subscription import SubscriptionOut
from app.services import subscriptions as subscriptions_service

router = APIRouter(prefix="/subscriptions", tags=["subscriptions"])
settings = get_settings()


@router.get("/me", response_model=SubscriptionOut)
def get_my_subscription(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    subscription = subscriptions_service.get_or_create_subscription(db, user)
    return subscriptions_service.to_subscription_out(subscription)


@router.post("/debug-activate", response_model=SubscriptionOut)
def debug_activate_subscription(
    user: User = Depends(get_current_user), db: Session = Depends(get_db)
):
    # Stub gratuit/local : remplace StoreKit/Google Play Billing tant qu'il n'y a pas de vraie
    # build store (cahier des charges D.8). Jamais exposé comme un vrai moyen de paiement — coupé
    # par défaut (enable_debug_subscription_endpoint, core/config.py) pour qu'un déploiement qui
    # oublierait de le désactiver ne laisse pas n'importe quel compte s'accorder le Premium
    # gratuitement.
    if not settings.enable_debug_subscription_endpoint:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Endpoint indisponible.")
    subscription = subscriptions_service.debug_activate(db, user)
    return subscriptions_service.to_subscription_out(subscription)


@router.post("/cancel", response_model=SubscriptionOut)
def cancel_subscription(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    subscription = subscriptions_service.cancel(db, user)
    return subscriptions_service.to_subscription_out(subscription)
