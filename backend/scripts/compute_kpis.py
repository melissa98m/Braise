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
from datetime import date, datetime, timedelta, timezone

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
from app.models.profile import PublicProfile
from app.models.report import Report
from app.models.subscription import Subscription
from app.models.user import User
from app.models.user_activity import UserActivity


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


def retention(db, days: int) -> tuple[int, int]:
    """Rétention classique à J+N : parmi les personnes inscrites depuis au moins N jours, la part
    active précisément le N-ième jour après leur inscription (`user_activity`, une ligne par
    personne et par jour d'utilisation — services/activity.py). Cohorte limitée aux inscriptions
    postérieures au premier jour suivi : un compte créé avant l'existence de ce suivi n'a aucune
    trace possible et fausserait le taux vers le bas. Comptes supprimés exclus (leurs jours
    d'activité sont effacés avec eux)."""
    first_tracked = db.query(func.min(UserActivity.day)).scalar()
    if first_tracked is None:
        return 0, 0
    signup_day = func.date(User.created_at)
    cohort = db.query(User.id).filter(
        signup_day >= first_tracked,
        signup_day <= date.today() - timedelta(days=days),
        User.deleted_at.is_(None),
    )
    eligible = cohort.count()
    if eligible == 0:
        return 0, 0
    retained = (
        db.query(func.count(func.distinct(User.id)))
        .join(UserActivity, UserActivity.user_id == User.id)
        .filter(
            User.id.in_(cohort.subquery().select()),
            UserActivity.day == signup_day + days,
        )
        .scalar()
    )
    return retained, eligible


def active_users(db, days: int) -> int:
    """Personnes distinctes actives sur les `days` derniers jours, aujourd'hui compris
    (1 = DAU, 7 = WAU, 30 = MAU)."""
    since = date.today() - timedelta(days=days - 1)
    return (
        db.query(func.count(func.distinct(UserActivity.user_id))).filter(UserActivity.day >= since).scalar()
    )


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
    # Même critère que services/subscriptions.is_premium (is_active ET expires_at > now) — pas
    # seulement is_active, qui reste vrai jusqu'à ce qu'un abonnement expiré soit désactivé et
    # surcompterait donc des conversions déjà retombées côté produit (voir CLAUDE.md).
    premium = (
        db.query(func.count(Subscription.user_id))
        .filter(
            Subscription.is_active.is_(True),
            Subscription.expires_at.isnot(None),
            Subscription.expires_at > datetime.now(timezone.utc),
        )
        .scalar()
    )
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
        print(
            f"Taux de complétion du profil public (bio + intérêts) : "
            f"{_pct(completed, verified)} — objectif > 80 %"
        )

        print("\n--- Engagement ---")
        answered, questions = engagement_daily_question_response_rate(db, since)
        window = f" (derniers {args.recent_days} j)" if since else ""
        print(
            f"Taux de réponse à la question quotidienne{window} : "
            f"{_pct(answered, questions)} — objectif > 60 %"
        )
        reaching, matches = engagement_matches_reaching_three_days(db)
        print(f"Taux de match -> 3 jours d'échange : {_pct(reaching, matches)} — objectif > 40 %")

        print("\n--- Rétention (jours d'activité réels, voir docstring retention) ---")
        for days in (1, 7, 30):
            retained, eligible = retention(db, days)
            print(f"Rétention à J{days} : {_pct(retained, eligible)}")
        print(
            f"Actifs aujourd'hui / 7 j / 30 j : {active_users(db, 1)} / {active_users(db, 7)} / "
            f"{active_users(db, 30)}"
        )

        print("\n--- Confiance ---")
        founded, reviewed = trust_report_founded_rate(db)
        print(f"Taux de signalements jugés fondés (parmi ceux traités) : {_pct(founded, reviewed)}")
        overturned, resolved = trust_ban_false_positive_rate(db)
        print(
            f"Taux de faux positifs de bannissement (parmi les contestations tranchées) : "
            f"{_pct(overturned, resolved)} — objectif < 5 %"
        )

        print("\n--- Monétisation ---")
        premium, verified2 = monetization_conversion_rate(db)
        print(f"Taux de conversion vers Bresonne+ : {_pct(premium, verified2)} — objectif 3-8 %")

        print("\n--- Produit ---")
        unlocked, total_matches = product_unlock_rate(db)
        print(
            f"Taux de déblocage effectif du profil privé parmi les matchs : "
            f"{_pct(unlocked, total_matches)} — indicateur clé"
        )
    finally:
        db.close()


if __name__ == "__main__":
    main()
