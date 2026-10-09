"""Garde-fou commun aux scripts de seed et de charge : jamais hors développement.

La base de bêta démarre vide (choix produit) : de faux profils y feraient swiper de vrais
testeur·se·s sur des personnages fictifs, et un test de charge y créerait des milliers de comptes.
Ces scripts échoueraient de toute façon sans DEBUG_OTP — mais par accident, au milieu d'un
traitement ; ce garde-fou refuse proprement, avant le moindre appel.
"""

import os
import sys


def require_development(script: str) -> None:
    environment = os.environ.get("ENVIRONMENT", "development")
    if environment != "development":
        sys.exit(
            f"{script} : refusé avec ENVIRONMENT={environment}. Script réservé au développement "
            "(la base de bêta/prod démarre vide, voir docs/DEPLOYMENT.md)."
        )
