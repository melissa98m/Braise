"""Accorde (ou retire) le rôle staff à un compte existant, identifié par numéro de téléphone.

Pas de flux applicatif ni d'endpoint pour ça, délibérément (voir docs/V2_FEATURES.md §2) : un
seul niveau de droits élevés à distinguer pour l'instant, donc un accès direct à la base — même
raisonnement que compute_kpis.py pour l'absence de rôle staff avant ce palier. Flipper is_staff
via Adminer marche tout aussi bien ; ce script n'est qu'un raccourci pratique.

Usage :
    docker compose run --rm backend python scripts/grant_staff.py +33612345678
    docker compose run --rm backend python scripts/grant_staff.py +33612345678 --revoke
"""

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.db.session import SessionLocal
from app.models.user import User


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("phone", help="Numéro de téléphone du compte (format E.164, ex: +33612345678)")
    parser.add_argument("--revoke", action="store_true", help="Retire le rôle staff au lieu de l'accorder")
    args = parser.parse_args()

    db = SessionLocal()
    try:
        user = db.query(User).filter(User.phone == args.phone).one_or_none()
        if user is None:
            print(f"Aucun compte pour {args.phone}.")
            return
        user.is_staff = not args.revoke
        db.commit()
        verb = "retiré de" if args.revoke else "accordé à"
        print(f"Rôle staff {verb} {args.phone} (user_id={user.id}).")
    finally:
        db.close()


if __name__ == "__main__":
    main()
