import numpy as np
from sklearn.model_selection import StratifiedKFold, cross_val_predict

from app.services.moderation_ml import (
    AUTHENTIC_LABEL,
    RANCOR_LABEL,
    RANCOR_PROBABILITY_THRESHOLD,
    build_pipeline,
    load_dataset,
    predict_is_rancor,
)


def test_predict_is_rancor_on_clear_cases():
    assert predict_is_rancor("Franchement une grosse arnaque niveau physique, quelle tromperie.")
    assert not predict_is_rancor(
        "Une conversation vraiment agréable et respectueuse du début à la fin."
    )


def test_predict_is_rancor_empty_comment_is_never_flagged():
    assert not predict_is_rancor("")
    assert not predict_is_rancor("   ")


def test_model_false_positive_rate_at_production_threshold():
    """Garde-fou de non-régression pour docs/MODEL_EVALUATION.md (P5.1) : si un changement au
    dataset ou à l'architecture du pipeline fait remonter le taux de faux positifs mesuré au
    seuil de production, ce test doit le faire échouer plutôt que le laisser passer inaperçu
    jusqu'à ce que quelqu'un relance evaluate_moderation_model.py à la main.

    Validation croisée à 5 plis (même méthode que le script d'évaluation), seed fixe pour un
    résultat reproductible d'un run à l'autre — la tolérance (≤ 2 %) laisse une petite marge à
    d'éventuelles variations mineures du pipeline sans être un test qui ne peut jamais échouer.
    """
    texts, labels = load_dataset()
    y = np.array(labels)
    cv = StratifiedKFold(n_splits=5, shuffle=True, random_state=42)

    proba = cross_val_predict(build_pipeline(), texts, y, cv=cv, method="predict_proba")
    rancor_index = sorted(set(labels)).index(RANCOR_LABEL)
    predicted = np.where(
        proba[:, rancor_index] >= RANCOR_PROBABILITY_THRESHOLD, RANCOR_LABEL, AUTHENTIC_LABEL
    )

    authentic_mask = y == AUTHENTIC_LABEL
    false_positive_rate = (predicted[authentic_mask] == RANCOR_LABEL).mean()

    assert false_positive_rate <= 0.02, (
        f"Taux de faux positifs mesuré : {false_positive_rate:.1%} — au-delà de la tolérance de "
        "2 %, voir docs/MODEL_EVALUATION.md. Un commentaire authentique signalé à tort peut mener "
        "à un bannissement injustifié (cahier des charges A.9)."
    )
