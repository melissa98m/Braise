import uuid


def unique_phone() -> str:
    # Les tests tournent contre le vrai Postgres de dev (pas de base jetable) : un numéro
    # unique par appel évite les collisions avec les données laissées par un run précédent.
    return "+336" + uuid.uuid4().hex[:8]
