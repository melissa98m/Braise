"""Collecte des avis Google Play (français) d'apps de rencontre concurrentes, pour constituer un
jeu de données d'entraînement plus réaliste pour services/moderation_ml.py que les quelques
dizaines d'exemples écrits à la main.

Pourquoi cette source : aucun dataset public existant (hate speech FR générique, Jigsaw traduit,
CyberAgressionAdo...) ne couvre le cas précis visé — déception exprimée en français à propos du
physique d'une personne dans un contexte de rencontre. Les avis Play Store des apps concurrentes
contiennent naturellement ce vocabulaire ("pas comme sur les photos", "catfish", "physique déçu"),
en français, dans le bon domaine.

Usage (dans le conteneur backend, jamais sur l'hôte — cf. CLAUDE.md) :
    docker compose run --rm backend python scripts/scrape_dating_reviews.py --count 200

Ce script ne fait qu'extraire et pré-trier (mot-clé = candidat, pas un label) : les résultats sont
un point de départ à relire et annoter à la main avant tout usage pour l'entraînement — voir la
sortie CSV, colonne `keyword_hit`. Ne jamais committer la sortie brute (avis Play Store = contenu
utilisateur tiers, cf. .gitignore) ; ne recopier dans moderation_ml.py que des phrases reformulées
ou explicitement choisies comme exemples, pas un dump en masse.
"""

import argparse
import csv
import sys
import time
from pathlib import Path

from google_play_scraper import Sort, reviews

APP_IDS = {
    "adopte": "com.adopteunmec.androidfr",
    "once": "com.once.android",
    "fruitz": "com.flashgap.fruitz",
    "bumble": "com.bumble.app",
    "happn": "com.ftw_and_co.happn",
    "tinder": "com.tinder",
}

# Signale les avis qui mentionnent une déception liée au physique/aux photos — le schéma de
# "rancune" ciblé par le classifieur (cahier des charges A.4.5) — sans préjuger du verdict final :
# c'est un filtre de candidats à relire, pas un label automatique.
RANCOR_KEYWORDS = [
    "physique",
    "pas comme sur les photos",
    "pas comme sur la photo",
    "catfish",
    "photos trompeuses",
    "arnaque",
    "déçu",
    "decu",
    "moche",
    "vieilli",
    "ressemble pas",
    "ressemble à rien",
    "tromperie",
    "menteur",
    "menteuse",
]

OUTPUT_DIR = Path(__file__).parent / "data"


def fetch_reviews(app_id: str, count: int) -> list[dict]:
    collected: list[dict] = []
    token = None
    while len(collected) < count:
        batch, token = reviews(
            app_id,
            lang="fr",
            country="fr",
            sort=Sort.NEWEST,
            count=min(200, count - len(collected)),
            continuation_token=token,
        )
        if not batch:
            break
        collected.extend(batch)
        if token is None:
            break
        time.sleep(1)  # laisse respirer l'API non-officielle plutôt que d'enchaîner en rafale
    return collected


def matches_keyword(content: str) -> str | None:
    lowered = content.lower()
    for keyword in RANCOR_KEYWORDS:
        if keyword in lowered:
            return keyword
    return None


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--count", type=int, default=200, help="avis par app (défaut: 200)")
    parser.add_argument(
        "--apps",
        nargs="+",
        choices=list(APP_IDS),
        default=list(APP_IDS),
        help="sous-ensemble d'apps à interroger (défaut: toutes)",
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=OUTPUT_DIR / "dating_reviews_fr.csv",
        help="chemin du CSV de sortie",
    )
    args = parser.parse_args()

    args.out.parent.mkdir(parents=True, exist_ok=True)
    total = 0
    total_flagged = 0

    with args.out.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["app", "score", "keyword_hit", "content"])
        for app_key in args.apps:
            app_id = APP_IDS[app_key]
            print(f"[{app_key}] collecte de {args.count} avis ({app_id})...", file=sys.stderr)
            for review in fetch_reviews(app_id, args.count):
                content = (review.get("content") or "").strip()
                if not content:
                    continue
                hit = matches_keyword(content)
                writer.writerow([app_key, review.get("score"), hit or "", content])
                total += 1
                total_flagged += hit is not None

    print(
        f"{total} avis écrits dans {args.out} — {total_flagged} candidats "
        "rancune-physique à relire manuellement.",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
