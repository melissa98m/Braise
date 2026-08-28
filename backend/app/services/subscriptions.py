from datetime import datetime, timedelta, timezone

from sqlalchemy.orm import Session

from app.models.match import Match
from app.models.subscription import Subscription
from app.models.user import User

# Palier unique (cahier des charges C.1). Durée arbitraire de dev : en prod, la durée réelle
# viendrait du store (StoreKit/Play Billing) — voir D.8, non branché tant qu'il n'y a pas de
# vraie build store.
DEBUG_ACTIVATION_DAYS = 30

# "Limite de conversations/matchs en version gratuite" (cahier des charges A.8/C.1). Un match
# gratuit reste utilisable indéfiniment une fois créé ; la limite ne bloque que la création de
# *nouveaux* matchs au-delà du palier gratuit.
FREE_MATCH_LIMIT = 5


def get_or_create_subscription(db: Session, user: User) -> Subscription:
    subscription = db.get(Subscription, user.id)
    if subscription is None:
        subscription = Subscription(user_id=user.id, is_active=False)
        db.add(subscription)
        db.commit()
        db.refresh(subscription)
    return subscription


def _is_currently_active(subscription: Subscription, now: datetime) -> bool:
    if not subscription.is_active or subscription.expires_at is None:
        return False
    return subscription.expires_at > now


def is_premium(db: Session, user_id) -> bool:
    subscription = db.get(Subscription, user_id)
    if subscription is None:
        return False
    return _is_currently_active(subscription, datetime.now(timezone.utc))


def debug_activate(db: Session, user: User) -> Subscription:
    subscription = get_or_create_subscription(db, user)
    now = datetime.now(timezone.utc)
    subscription.is_active = True
    subscription.started_at = now
    subscription.expires_at = now + timedelta(days=DEBUG_ACTIVATION_DAYS)
    subscription.cancel_at_period_end = False
    subscription.canceled_at = None
    db.commit()
    db.refresh(subscription)
    return subscription


def cancel(db: Session, user: User) -> Subscription:
    subscription = get_or_create_subscription(db, user)
    # Résiliation = pas de renouvellement, pas de coupure immédiate : l'utilisateur garde son
    # Premium jusqu'à expires_at, comme un vrai abonnement de store (mockup : "résiliable en
    # 2 taps", jamais "perdu immédiatement").
    subscription.cancel_at_period_end = True
    subscription.canceled_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(subscription)
    return subscription


def to_subscription_out(subscription: Subscription) -> dict:
    now = datetime.now(timezone.utc)
    return {
        "is_premium": _is_currently_active(subscription, now),
        "expires_at": subscription.expires_at,
        "cancel_at_period_end": subscription.cancel_at_period_end,
    }


def count_active_matches(db: Session, user_id) -> int:
    return (
        db.query(Match)
        .filter((Match.user_a_id == user_id) | (Match.user_b_id == user_id))
        .count()
    )


def can_create_new_match(db: Session, user: User) -> bool:
    if is_premium(db, user.id):
        return True
    return count_active_matches(db, user.id) < FREE_MATCH_LIMIT
