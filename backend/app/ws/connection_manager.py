import asyncio
import json
import uuid

import redis.asyncio as redis
from fastapi import WebSocket

from app.core.config import get_settings

_CHANNEL_PREFIX = "bresonne:chat:"


def _channel(match_id: uuid.UUID) -> str:
    return f"{_CHANNEL_PREFIX}{match_id}"


class ConnectionManager:
    """Relais WebSocket par match, via Redis pub/sub, pour que deux utilisateurs connectés à deux
    instances backend différentes se voient quand même (cahier des charges D.4) — avant ce
    palier, le registre était un simple `dict[match_id, set[WebSocket]]` en mémoire, correct pour
    un seul process backend mais aveugle entre instances (voir docs/V2_FEATURES.md §3).

    Une souscription/un client Redis *par connexion WebSocket*, jamais un seul partagé pour tout
    le process : chaque connexion peut s'exécuter sur son propre event loop, pas seulement en
    théorie — `TestClient.websocket_connect()` (utilisé dans tests/test_messaging.py sans
    `with TestClient(app) as client:`) ouvre un portail anyio, donc un thread et un event loop
    *distincts*, à chaque connexion. Un objet redis-py créé sur un loop et réutilisé depuis un
    autre casse silencieusement (deadlock ou "attached to a different loop"). Scoper une ressource
    à la durée de vie exacte de la connexion qui en a besoin, plutôt que de la partager au-delà,
    c'est exactement la leçon déjà tirée pour `SessionLocal()` dans `chat_ws`
    (api/v1/messaging.py, P4.3) — appliquée ici à Redis pour la même raison.

    Canal par match (`bresonne:chat:{match_id}`), pas un canal global filtré côté client : Redis
    fait déjà le tri, une connexion ne reçoit jamais le trafic d'un autre match.
    """

    def __init__(self) -> None:
        self._listener_tasks: dict[WebSocket, asyncio.Task] = {}
        self._subscribers: dict[WebSocket, redis.Redis] = {}

    async def connect(self, match_id: uuid.UUID, websocket: WebSocket) -> None:
        # L'abonnement Redis est établi *avant* d'accepter la connexion, jamais après : accept()
        # est ce qui débloque le côté client (sous TestClient comme dans un vrai navigateur), et
        # Redis ne livre jamais rétroactivement un message à un abonné pas encore enregistré — si
        # accept() avait lieu en premier, l'autre participant pourrait envoyer et recevoir un
        # accusé de son propre message avant que cette connexion-ci n'ait fini de s'abonner,
        # perdant silencieusement l'événement qui lui était destiné. Trouvé via un vrai hang
        # intermittent en test (py-spy dump : les deux event loops idle en select(), aucun
        # deadlock — juste un message jamais livré), pas anticipé à la conception.
        client = redis.from_url(get_settings().redis_url)
        pubsub = client.pubsub()
        await pubsub.subscribe(_channel(match_id))
        await websocket.accept()
        self._subscribers[websocket] = client
        self._listener_tasks[websocket] = asyncio.create_task(self._listen(pubsub, websocket))

    async def disconnect(self, match_id: uuid.UUID, websocket: WebSocket) -> None:
        task = self._listener_tasks.pop(websocket, None)
        if task is not None:
            task.cancel()
        client = self._subscribers.pop(websocket, None)
        if client is not None:
            await client.aclose()

    async def _listen(self, pubsub: "redis.client.PubSub", websocket: WebSocket) -> None:
        try:
            async for message in pubsub.listen():
                if message["type"] != "message":  # ignore la confirmation de subscribe elle-même
                    continue
                try:
                    await websocket.send_json(json.loads(message["data"]))
                except Exception:
                    # Connexion cliente déjà morte côté envoi : disconnect() (appelé par chat_ws
                    # dès que sa propre boucle de réception le remarque) fera le ménage.
                    return
        except asyncio.CancelledError:
            pass
        finally:
            await pubsub.aclose()

    async def broadcast(self, match_id: uuid.UUID, payload: dict) -> None:
        # Client éphémère, ouvert puis refermé pour cette seule publication — jamais partagé
        # entre event loops (voir la docstring de classe). Chaque connexion abonnée à ce match
        # (via connect() ci-dessus) la reçoit, y compris les siennes propres sur ce même process :
        # une seule voie de livraison, locale ou distante.
        client = redis.from_url(get_settings().redis_url)
        try:
            await client.publish(_channel(match_id), json.dumps(payload))
        finally:
            await client.aclose()


manager = ConnectionManager()
