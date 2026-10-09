from pydantic import BaseModel


class PushSubscriptionKeysIn(BaseModel):
    p256dh: str
    auth: str


class PushSubscribeIn(BaseModel):
    # Reprend tel quel le format renvoyé par PushSubscription.toJSON() côté navigateur (endpoint +
    # keys.p256dh/keys.auth) — pas de reformatage côté client, voir lib/api/notifications_api.dart.
    endpoint: str
    keys: PushSubscriptionKeysIn
    user_agent: str | None = None
    # Par défaut toutes activées : un premier abonnement (au premier toggle activé dans
    # Paramètres) reflète les préférences déjà cochées à ce moment côté client.
    notify_match: bool = True
    notify_question: bool = True
    notify_messages: bool = True


class PushSubscribeOut(BaseModel):
    ok: bool = True


class VapidPublicKeyOut(BaseModel):
    public_key: str
