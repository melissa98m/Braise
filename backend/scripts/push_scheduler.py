"""Planificateur des notifications push récurrentes — aujourd'hui, le rappel de la question du jour.

Tourne en continu dans son propre conteneur (`push-scheduler`, docker-compose.yml) : dort jusqu'au
prochain DAILY_REMINDER_HOUR (heure de Paris), envoie les rappels, recommence. Pas de cron dans
l'image ni de bibliothèque de planification : une boucle de quelques lignes suffit pour un seul
envoi quotidien, même choix que le service `backup` (infra/backup/backup.sh). Envoyer deux fois
le même jour est impossible même si ce conteneur redémarre ou tourne en double : chaque rappel
prend un verrou Redis par personne et par jour (services/notifications.py).

Usage :
    docker compose run --rm backend python scripts/push_scheduler.py           # boucle
    docker compose run --rm backend python scripts/push_scheduler.py --once    # un envoi immédiat
"""

import argparse
import logging
import os
import sys
import time
from datetime import datetime, timedelta, timezone

from zoneinfo import ZoneInfo

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.core.config import get_settings  # noqa: E402
from app.services.notifications import send_daily_question_reminders  # noqa: E402

PARIS = ZoneInfo("Europe/Paris")
# 18 h : après la journée de travail, avant la soirée — un rappel de jeu, pas une alerte.
DAILY_REMINDER_HOUR = int(os.environ.get("DAILY_REMINDER_HOUR", "18"))

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger("push_scheduler")


def seconds_until_next_run(now: datetime) -> float:
    target = now.replace(hour=DAILY_REMINDER_HOUR, minute=0, second=0, microsecond=0)
    if target <= now:
        target = (target + timedelta(days=1)).replace(hour=DAILY_REMINDER_HOUR)
    # Soustraction en UTC, pas entre deux datetimes Europe/Paris : Python compare alors l'heure
    # murale et ignore le changement d'heure — la nuit du passage à l'heure d'été, le rappel
    # serait parti à 19 h au lieu de 18 h.
    return (target.astimezone(timezone.utc) - now.astimezone(timezone.utc)).total_seconds()


def run_once() -> None:
    if not get_settings().push_enabled:
        logger.info("PUSH_ENABLED=false : aucun rappel envoyé.")
        return
    reminded = send_daily_question_reminders()
    logger.info("Rappels de la question du jour envoyés : %d", len(reminded))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--once", action="store_true", help="Envoie les rappels maintenant puis s'arrête")
    args = parser.parse_args()
    if args.once:
        run_once()
        return
    while True:
        delay = seconds_until_next_run(datetime.now(PARIS))
        logger.info("Prochain rappel dans %.0f min (%dh, heure de Paris).", delay / 60, DAILY_REMINDER_HOUR)
        time.sleep(delay)
        try:
            run_once()
        except Exception:
            # Une erreur un jour (base momentanément injoignable...) ne doit jamais arrêter la
            # boucle : on journalise et on attend le lendemain.
            logger.exception("Échec de l'envoi des rappels quotidiens")
        time.sleep(60)


if __name__ == "__main__":
    main()
