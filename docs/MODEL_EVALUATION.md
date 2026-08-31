# Évaluation du modèle de classification v0 — détection de rancune

Jalon B.2 du planning ("Go/No-go bêta") : *"Rapport de tests (fonctionnel, charge, sécurité),
modèle de classification v0 évalué"*. Jusqu'à ce palier (P5.1), le pipeline
(`backend/app/services/moderation_ml.py`) était entraîné sur l'intégralité du jeu de données,
sans jeu de test séparé — son comportement réel (précision, rappel, taux de faux positifs)
n'avait jamais été mesuré, seulement supposé à partir de la lecture du code.

## Méthode

Validation croisée stratifiée à 5 plis (`backend/scripts/evaluate_moderation_model.py`,
reproductible : `docker compose run --rm backend python scripts/evaluate_moderation_model.py`)
plutôt qu'un split fixe train/test — sur 490 exemples, un split 80/20 (98 exemples de test)
donnerait une estimation bruitée d'un tirage à l'autre. La validation croisée utilise chaque
exemple comme test exactement une fois (`cross_val_predict`), ce qui donne une matrice de
confusion sur les 490 exemples sans qu'aucun n'ait été vu par le modèle qui le prédit.

Les prédictions sont réévaluées au **seuil réellement utilisé en production**
(`RANCOR_PROBABILITY_THRESHOLD = 0.6`), pas au seuil par défaut de scikit-learn (0.5) — c'est la
seule mesure qui reflète le comportement exact de `predict_is_rancor()`.

**Jeu de données** : 490 exemples (295 authentiques, 195 rancune) — un jeu de démarrage écrit à la
main (`backend/scripts/generate_rating_dataset.py`), pas des données réelles de bêta. Les
résultats ci-dessous mesurent la capacité du modèle à généraliser sur *ce style d'écriture*, pas
sur la variété réelle des commentaires d'utilisateurs. À réentraîner et ré-évaluer avec ce même
script dès qu'un volume réel de notations existe (voir `docs/ROADMAP.md`).

## Résultats (seuil de production, 0.6)

| | Prédit authentique | Prédit rancune |
|---|---|---|
| **Vrai authentique** (295) | 295 | 0 |
| **Vrai rancune** (195) | 19 | 176 |

- **Faux positifs** (commentaire authentique signalé à tort) : **0 / 295 (0,0 %)**
- **Faux négatifs** (rancune manquée, laissée au score de confiance normal) : 19 / 195 (9,7 %)
- Précision (classe rancune) : 1,000 — Rappel (classe rancune) : 0,903 — F1 : 0,949
- Exactitude globale : 96,1 %

## Interprétation

Le seuil prudent (0,6, documenté dans `moderation_ml.py`) atteint exactement l'objectif qu'il
visait : **zéro commentaire authentique signalé à tort** sur ce jeu, au prix de rater environ 1
commentaire de rancune sur 10 — qui reste alors compté normalement dans le score de confiance au
lieu d'être exclu de la moyenne (`services/moderation.compute_trust_score`), donc pas une perte
totale, juste un signal manqué. C'est le compromis explicitement voulu par le cahier des charges
(A.4.5 : mieux vaut sous-détecter que sanctionner à tort) et maintenant **mesuré**, pas seulement
affirmé.

À titre de comparaison, au seuil par défaut de scikit-learn (0,5) : 6/295 (2,0 %) faux positifs
et 4/195 (2,1 %) faux négatifs — plus équilibré mais moins aligné avec l'objectif produit
(A.9 : limiter les faux positifs qui peuvent mener à un bannissement injustifié).

## Limite assumée

Un modèle à 96-100 % de justesse sur un jeu de 490 exemples écrits à la main pour être
discriminants ne dit rien de sa performance sur des commentaires réels, plus ambigus, plus courts,
avec des fautes de frappe, du sarcasme, etc. C'est un point de départ vérifié, pas un modèle
validé sur données réelles — cette limite était déjà documentée dans `moderation_ml.py` avant ce
palier ; ce rapport la rend simplement mesurable plutôt qu'un aveu qualitatif.
