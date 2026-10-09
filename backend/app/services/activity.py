import logging
import uuid
from datetime import date, timedelta

import redis
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.models.user_activity import UserActivity

logger = logging.getLogger(__name__)

_LOCK_TTL_SECONDS = 2 * 24 * 3600


def record_activity(db: Session, user_id: uuid.UUID) -> None:
    """Note que `user_id` a utilisé l'app aujourd'hui — appelé à chaque requête authentifiée
    (api/deps.get_current_user), donc doit coûter quasi rien : un `SET NX` Redis fait que seule la
    première requête du jour touche Postgres. Si Redis est injoignable, on écrit directement (un
    `INSERT ... ON CONFLICT DO NOTHING` reste bon marché) ; une erreur ici n'interrompt jamais la
    requête — une mesure d'audience ne vaut pas une requête en échec."""
    today = date.today()
    try:
        client = redis.Redis.from_url(get_settings().redis_url, socket_timeout=1)
        with client:
            key = f"bresonne:active:{today.isoformat()}:{user_id}"
            if not client.set(key, "1", nx=True, ex=_LOCK_TTL_SECONDS):
                return
    except redis.RedisError:
        pass
    try:
        db.execute(
            insert(UserActivity).values(user_id=user_id, day=today).on_conflict_do_nothing()
        )
        db.commit()
    except Exception:
        db.rollback()
        logger.exception("Activité du jour non enregistrée pour %s", user_id)


# 13 mois : la durée de conservation que la CNIL retient pour les mesures d'audience — largement
# assez pour une rétention à J30 et une comparaison d'une année sur l'autre, pas au-delà.
RETENTION_DAYS = 395


def purge_old_activity(db: Session) -> int:
    cutoff = date.today() - timedelta(days=RETENTION_DAYS)
    deleted = db.query(UserActivity).filter(UserActivity.day < cutoff).delete()
    db.commit()
    return deleted
