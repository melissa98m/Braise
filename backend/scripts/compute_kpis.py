"""Calcule les KPIs de succès du cahier des charges (section A.10) à partir des tables réelles.

Aucun de ces 9 indicateurs n'a de tableau de bord dédié — ils sont tous dérivables des tables
existantes, donc pas de nouvelle infra de tracking à construire pour le jalon "Bilan bêta" du
planning (docs/ROADMAP.md, B.2). Accès direct à la base plutôt que via l'API : il n'existe pas de
notion de rôle staff dans ce projet (voir CLAUDE.md — Reports/BanAppeal se consultent déjà via
Adminer, pas via un endpoint protégé qui n'existe pas), donc un script plutôt qu'une route est le
choix cohérent avec le reste de l'outillage opérationnel (voir seed_test_data.py à côté).

Usage :
    docker compose run --rm backend python scripts/compute_kpis.py
    docker compose run --rm backend python scripts/compute_kpis.py --recent-days 30
"""

import argparse
import os
import sys
from datetime import datetime, timedelta, timezone

# `python scripts/compute_kpis.py` puts scripts/ (not /app) on sys.path[0], so `import app.*`
# fails unless invoked as `python -m scripts.compute_kpis` — inserting the backend root
# explicitly works regardless of how the script is launched (matches how pytest, run as its own
# console-script entry point, resolves `app.*` for tests/ without needing this).
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import func

from app.db.session import SessionLocal
from app.models.ban_appeal import BanAppeal
from app.models.daily_question import DailyQuestion
from app.models.match import Match
from app.models.message import Message
from app.models.report import Report
from app.models.subscription import Subscription
from app.models.swipe import Swipe
from app.models.user import User
from app.models.profile import PublicProfile


def _pct(numerator: int, denominator: int) -> str:
    if denominator == 0:
        return "n/a (0 dans l'échantillon)"
    return f"{numerator / denominator * 100:.1f} % ({numerator}/{denominator})"


def acquisition_signups_by_month(db) -> dict[str, int]:
    rows = (
        db.query(
            func.to_char(User.created_at, "YYYY-MM").label("month"),
            func.count(User.id),
        )
        .filter(User.is_verified.is_(True))
        .group_by("month")
        .order_by("month")
        .all()
    )
    return dict(rows)


def activation_profile_completion(db) -> tuple[int, int]:
    verified_total = db.query(func.count(User.id)).filter(User.is_verified.is_(True)).scalar()
    completed = (
        db.query(func.count(PublicProfile.user_id))
        .join(User, User.id == PublicProfile.user_id)
        .filter(
            User.is_verified.is_(True),
            func.length(func.trim(PublicProfile.bio)) > 0,
            func.jsonb_array_length(PublicProfile.interests) > 0,
        )
        .scalar()
    )
    return completed, verified_total


def engagement_daily_question_response_rate(db, since: datetime | None) -> tuple[int, int]:
    query = db.query(DailyQuestion)
    if since is not None:
        query = query.filter(DailyQuestion.created_at >= since)
    total = query.count()
    answered = query.filter(DailyQuestion.answered.is_(True)).count()
    return answered, total


def engagement_matches_reaching_three_days(db) -> tuple[int, int]:
    total_matches = db.query(func.count(Match.id)).scalar()
    # "3 jours d'échange" = 3 dates civiles distinctes avec au moins un message, pas 3 messages.
    active_days_per_match = (
        db.query(
            Message.match_id,
            func.count(func.distinct(func.date(Message.created_at))).label("active_days"),
        )
        .group_by(Message.match_id)
        .subquery()
    )
    reaching_three_days = (
        db.query(func.count(active_days_per_match.c.match_id))
        .filter(active_days_per_match.c.active_days >= 3)
        .scalar()
    )
    return reaching_three_days, total_matches


def retention_proxy(db, days: int) -> tuple[int, int]:
    """Proxy, pas une vraie rétention : aucun événement de connexion/session n'est journalisé
    dans ce projet (pas de table d'audit de login). On approxime "actif à J+N" par "a swipé au
    moins une fois au moins N jours après son inscription" — le swipe est l'action récurrente la
    plus proche d'un signal de session active dont on dispose. À remplacer par un vrai suivi de
    session avant de citer ce chiffre en dehors d'un contexte de debug interne.
    """
    cutoff = datetime.now(timezone.utc) - timedelta(days=days)
    eligible = db.query(func.count(User.id)).filter(User.created_at <= cutoff).scalar()
    if eligible == 0:
        return 0, 0
    retained = (
        db.query(func.count(func.distinct(Swipe.from_user_id)))
        .join(User, User.id == Swipe.from_user_id)
        .filter(
            User.created_at <= cutoff,
            Swipe.created_at >= User.created_at + timedelta(days=days),
        )
        .scalar()
    )
    return retained, eligible


def trust_report_founded_rate(db) -> tuple[int, int]:
    reviewed = db.query(func.count(Report.id)).filter(Report.status != "pending").scalar()
    founded = db.query(func.count(Report.id)).filter(Report.status == "founded").scalar()
    return founded, reviewed


def trust_ban_false_positive_rate(db) -> tuple[int, int]:
    resolved = db.query(func.count(BanAppeal.id)).filter(BanAppeal.status != "pending").scalar()
    overturned = (
        db.query(func.count(BanAppeal.id)).filter(BanAppeal.status == "overturned").scalar()
    )
    return overturned, resolved


def monetization_conversion_rate(db) -> tuple[int, int]:
    verified_total = db.query(func.count(User.id)).filter(User.is_verified.is_(True)).scalar()
    premium = db.query(func.count(Subscription.user_id)).filter(
        Subscription.is_active.is_(True)
    ).scalar()
    return premium, verified_total


def product_unlock_rate(db) -> tuple[int, int]:
    total_matches = db.query(func.count(Match.id)).scalar()
    unlocked = db.query(func.count(Match.id)).filter(Match.unlocked_at.isnot(None)).scalar()
    return unlocked, total_matches


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--recent-days",
        type=int,
        default=None,
        help="Restreint le taux de réponse à la question quotidienne aux N derniers jours "
        "(par défaut : toute la période).",
    )
    parser.add_argument(
        "--retention-days",
        type=int,
        default=7,
        help="Fenêtre de la rétention proxy en jours (défaut : 7, cf. --retention-days 30).",
    )
    args = parser.parse_args()
    since = (
        datetime.now(timezone.utc) - timedelta(days=args.recent_days)
        if args.recent_days
        else None
    )

    db = SessionLocal()
    try:
        print("=== KPIs de succès (cahier des charges A.10) ===\n")

        print("--- Acquisition ---")
        by_month = acquisition_signups_by_month(db)
        if not by_month:
            print("Inscriptions vérifiées / mois : aucune donnée")
        for month, count in by_month.items():
            print(f"Inscriptions vérifiées {month} : {count}")

        print("\n--- Activation ---")
        completed, verified = activation_profile_completion(db)
        print(f"Taux de complétion du profil public (bio + intérêts) : {_pct(completed, verified)} — objectif > 80 %")

        print("\n--- Engagement ---")
        answered, questions = engagement_daily_question_response_rate(db, since)
        window = f" (derniers {args.recent_days} j)" if since else ""
        print(f"Taux de réponse à la question quotidienne{window} : {_pct(answered, questions)} — objectif > 60 %")
        reaching, matches = engagement_matches_reaching_three_days(db)
        print(f"Taux de match -> 3 jours d'échange : {_pct(reaching, matches)} — objectif > 40 %")

        print("\n--- Rétention (proxy, voir docstring retention_proxy) ---")
        retained, eligible = retention_proxy(db, args.retention_days)
        print(f"Rétention proxy à J{args.retention_days} : {_pct(retained, eligible)}")

        print("\n--- Confiance ---")
        founded, reviewed = trust_report_founded_rate(db)
        print(f"Taux de signalements jugés fondés (parmi ceux traités) : {_pct(founded, reviewed)}")
        overturned, resolved = trust_ban_false_positive_rate(db)
        print(f"Taux de faux positifs de bannissement (parmi les contestations tranchées) : {_pct(overturned, resolved)} — objectif < 5 %")

        print("\n--- Monétisation ---")
        premium, verified2 = monetization_conversion_rate(db)
        print(f"Taux de conversion vers Braise+ : {_pct(premium, verified2)} — objectif 3-8 %")

        print("\n--- Produit ---")
        unlocked, total_matches = product_unlock_rate(db)
        print(f"Taux de déblocage effectif du profil privé parmi les matchs : {_pct(unlocked, total_matches)} — indicateur clé")
    finally:
        db.close()


if __name__ == "__main__":
    main()
