import uuid
from collections import defaultdict

from fastapi import WebSocket


class ConnectionManager:
    """Registre en mémoire des connexions WebSocket actives, par match.

    Suffisant pour un seul processus backend (le cas de ce MVP en local). Une fois plusieurs
    instances backend nécessaires, ce registre doit être remplacé par quelque chose de partagé
    (Centrifugo/Redis pub-sub, cf. cahier des charges D.4) — pas juste dupliqué par instance.
    """

    def __init__(self) -> None:
        self._connections: dict[uuid.UUID, set[WebSocket]] = defaultdict(set)

    async def connect(self, match_id: uuid.UUID, websocket: WebSocket) -> None:
        await websocket.accept()
        self._connections[match_id].add(websocket)

    def disconnect(self, match_id: uuid.UUID, websocket: WebSocket) -> None:
        self._connections[match_id].discard(websocket)
        if not self._connections[match_id]:
            del self._connections[match_id]

    async def broadcast(self, match_id: uuid.UUID, payload: dict) -> None:
        dead: list[WebSocket] = []
        for websocket in self._connections.get(match_id, ()):
            try:
                await websocket.send_json(payload)
            except Exception:
                dead.append(websocket)
        for websocket in dead:
            self.disconnect(match_id, websocket)


manager = ConnectionManager()
