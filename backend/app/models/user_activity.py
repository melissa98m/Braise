from sqlalchemy import Column, Date, ForeignKey
from sqlalchemy.dialects.postgresql import UUID

from app.db.base import Base


class UserActivity(Base):
    """Une ligne par personne et par jour où elle a utilisé l'app (services/activity.py).

    Le minimum pour mesurer une vraie rétention J1/J7/J30 (scripts/compute_kpis.py) — jusqu'ici
    seulement approximée faute de tout journal d'activité. Volontairement grossier : un jour, pas
    d'heure, pas de durée, pas de détail de ce qui a été fait. Clé primaire composite, donc au plus
    une ligne par jour quel que soit le nombre de requêtes. Purgée après 13 mois (tâche
    quotidienne) et supprimée avec le compte.
    """

    __tablename__ = "user_activity"

    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), primary_key=True)
    day = Column(Date, primary_key=True, index=True)
