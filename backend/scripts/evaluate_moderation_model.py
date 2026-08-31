"""Évalue le classifieur de rancune (services/moderation_ml.py) par validation croisée — le
"modèle de classification v0 évalué" que le planning (docs/ROADMAP.md, jalon B.2 "Go/No-go
bêta") exige avant la bêta. Jusqu'ici le pipeline était entraîné sur les 490 exemples du CSV
*en entier*, sans jeu de test séparé : personne n'avait jamais mesuré sa précision, son rappel,
ni son taux de faux positifs — seulement vérifié qu'il s'entraînait sans erreur.

Validation croisée stratifiée à 5 plis plutôt qu'un simple split train/test : sur un jeu de 490
exemples, un split fixe (ex. 80/20 = 98 exemples de test) donne une estimation bruitée d'un tirage
à l'autre. La validation croisée utilise chaque exemple comme donnée de test exactement une fois
(prédictions hors-échantillon poolées via cross_val_predict), ce qui donne une matrice de
confusion sur les 490 exemples sans qu'aucun n'ait jamais été vu par le modèle qui le prédit — la
mesure la plus stable qu'on puisse tirer d'un jeu de cette taille.

Les prédictions sont réévaluées au seuil de décision réellement utilisé en production
(RANCOR_PROBABILITY_THRESHOLD = 0.6, pas le 0.5 par défaut de scikit-learn) : c'est la seule
mesure qui reflète le comportement réel de predict_is_rancor(), pas une approximation.

Usage :
    docker compose run --rm backend python scripts/evaluate_moderation_model.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import numpy as np
from sklearn.metrics import classification_report, confusion_matrix
from sklearn.model_selection import StratifiedKFold, cross_val_predict

from app.services.moderation_ml import (
    AUTHENTIC_LABEL,
    RANCOR_LABEL,
    RANCOR_PROBABILITY_THRESHOLD,
    build_pipeline,
    load_dataset,
)

N_FOLDS = 5
RANDOM_STATE = 42
DATASET_NOTE = (
    "jeu de démarrage écrit à la main, pas des données réelles de bêta — voir "
    "moderation_ml.py et docs/ROADMAP.md"
)


def _report_at_threshold(y_true: np.ndarray, rancor_proba: np.ndarray, threshold: float) -> None:
    y_pred = np.where(rancor_proba >= threshold, RANCOR_LABEL, AUTHENTIC_LABEL)

    print(f"\n--- Seuil = {threshold} ---")
    print(
        classification_report(
            y_true, y_pred, labels=[AUTHENTIC_LABEL, RANCOR_LABEL], digits=3, zero_division=0
        )
    )

    cm = confusion_matrix(y_true, y_pred, labels=[AUTHENTIC_LABEL, RANCOR_LABEL])
    tn, fp, fn, tp = cm.ravel()
    print("Matrice de confusion (lignes = vérité, colonnes = prédiction) :")
    print("                 prédit authentic   prédit rancor")
    print(f"  vrai authentic       {tn:>5}             {fp:>5}")
    print(f"  vrai rancor          {fn:>5}             {tp:>5}")
    print(
        f"\nCommentaires authentiques signalés à tort comme rancune (faux positifs) : "
        f"{fp}/{tn + fp} ({fp / (tn + fp) * 100:.1f} %)"
        if (tn + fp) > 0
        else ""
    )
    print(
        f"Commentaires de rancune manqués (faux négatifs, laissés au score de confiance normal) : "
        f"{fn}/{fn + tp} ({fn / (fn + tp) * 100:.1f} %)"
        if (fn + tp) > 0
        else ""
    )


def main() -> None:
    texts, labels = load_dataset()
    y = np.array(labels)
    print(f"Jeu de données : {len(texts)} exemples ({(y == RANCOR_LABEL).sum()} rancune, "
          f"{(y == AUTHENTIC_LABEL).sum()} authentiques) — {DATASET_NOTE}")

    cv = StratifiedKFold(n_splits=N_FOLDS, shuffle=True, random_state=RANDOM_STATE)

    proba = cross_val_predict(
        build_pipeline(), texts, y, cv=cv, method="predict_proba", n_jobs=None
    )
    classes_sorted = sorted(set(labels))
    rancor_index = classes_sorted.index(RANCOR_LABEL)
    rancor_proba = proba[:, rancor_index]

    print(f"\n=== Validation croisée à {N_FOLDS} plis, prédictions hors-échantillon poolées ===")
    _report_at_threshold(y, rancor_proba, 0.5)
    _report_at_threshold(y, rancor_proba, RANCOR_PROBABILITY_THRESHOLD)

    print(
        f"\nLe seuil de production ({RANCOR_PROBABILITY_THRESHOLD}) vs. 0.5 par défaut : "
        "comparer les deux blocs ci-dessus pour voir le compromis réellement obtenu (moins de "
        "faux positifs sur les commentaires authentiques, au prix de rater plus de rancune "
        "réelle — cohérent avec le choix documenté dans moderation_ml.py de préférer laisser "
        "passer un cas ambigu en revue humaine plutôt que sanctionner à tort)."
    )


if __name__ == "__main__":
    main()
