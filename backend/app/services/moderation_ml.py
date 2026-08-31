"""Classifieur léger (scikit-learn) pour détecter les commentaires de notation "de rancune"
(dévalorisation liée au physique découvert tardivement, insultes) — cahier des charges D.5.

Le jeu d'exemples chargé depuis data/rating_comments_fr.csv est un jeu de démarrage écrit à la
main, pas des données réelles : suffisant pour que l'architecture (TF-IDF + régression
logistique, entraîné en local, aucun appel externe) soit en place et utile dès le MVP, mais à
réentraîner sur les vraies notations de la bêta dès qu'il y en a assez (même pipeline, mêmes
poids de fonctionnement — voir docs/ROADMAP.md Phase 4). Ne pas traiter ces phrases comme une
vérité de fond : c'est un point de départ, pas un modèle validé.
"""

import csv
from pathlib import Path

from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.pipeline import Pipeline

RANCOR_LABEL = "rancor"
AUTHENTIC_LABEL = "authentic"

DATASET_PATH = Path(__file__).parent / "data" / "rating_comments_fr.csv"

# Seuil volontairement prudent (> 0.5) : sur un jeu d'exemples aussi petit, mieux vaut laisser un
# commentaire ambigu passer en revue humaine plutôt que le signaler à tort. Choix quantifié dans
# backend/scripts/evaluate_moderation_model.py (P5.1) plutôt que posé à l'instinct — voir
# docs/MODEL_EVALUATION.md pour le compromis précision/rappel mesuré à ce seuil vs. 0.5.
RANCOR_PROBABILITY_THRESHOLD = 0.6


def load_dataset() -> tuple[list[str], list[str]]:
    with DATASET_PATH.open(newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    texts = [row["text"] for row in rows]
    labels = [row["label"] for row in rows]
    assert set(labels) <= {AUTHENTIC_LABEL, RANCOR_LABEL}, f"label inattendu dans {DATASET_PATH}"
    return texts, labels


def build_pipeline() -> Pipeline:
    """Factory plutôt qu'une instance construite une fois ici : backend/scripts/
    evaluate_moderation_model.py (P5.1) doit pouvoir entraîner des copies fraîches par pli de
    validation croisée avec exactement la même architecture que celle réellement servie en
    production — jamais une copie à la main qui pourrait diverger en silence.
    """
    return Pipeline(
        [
            ("tfidf", TfidfVectorizer(ngram_range=(1, 2), min_df=1)),
            # class_weight="balanced" : les deux classes n'ont pas vocation à rester de même
            # taille au fil des ajouts au CSV, or un déséquilibre biaise sinon le seuil de
            # décision côté majoritaire plutôt que de rester ancré aux mots réellement
            # discriminants.
            ("clf", LogisticRegression(max_iter=1000, class_weight="balanced")),
        ]
    )


_texts, _labels = load_dataset()
_pipeline = build_pipeline()
_pipeline.fit(_texts, _labels)
_rancor_index = list(_pipeline.classes_).index(RANCOR_LABEL)


def predict_is_rancor(comment: str) -> bool:
    if not comment.strip():
        return False
    proba = _pipeline.predict_proba([comment])[0][_rancor_index]
    return proba >= RANCOR_PROBABILITY_THRESHOLD
