# Braise — Roadmap d'exécution

Toutes les phases tournent en local, gratuitement, sous Docker Compose. Aucun service payant
(SMS, Apple/Google, Firebase, cloud) n'est requis avant que le MVP ne soit validé en local.
Référence stack : cahier des charges, section D.11.

- [x] **Phase 0 — Environnement.** Docker Compose (Postgres, MinIO, backend FastAPI, Adminer,
  conteneur Flutter en attente), Alembic, smoke tests pytest, README de démarrage.
- [ ] **Phase 1 — Module 1 Identité & Profils.** Séparation profil public/privé, avatar-sigil
  généré côté serveur (dégradé déterministe, pas de service externe), complétion de l'auth OTP.
- [ ] **Phase 2 — Module 2 Matching & Découverte.** Scoring de compatibilité (intérêts communs +
  questionnaire court), feed de découverte, floutage progressif piloté par le nombre de flammes.
- [ ] **Phase 3 — Module 3 Messagerie & Flammes.** Chat WebSocket custom, question quotidienne,
  compteur de flammes, seuil de déblocage.
- [ ] **Phase 4 — Module 4 Confiance & Modération.** Notation (note + commentaire ≥ 4 mots
  obligatoire), classifieur scikit-learn (authenticité), signalement + file de revue humaine.
- [ ] **Phase 5 — Modules 5/6 Monétisation (stub) & Sécurité.** Toggle Premium local, URLs signées
  courtes pour les photos privées (MinIO), chiffrement au repos.
- [ ] **Phase 6 — Mobile.** Flutter (dans son conteneur, cible web d'abord) implémente les écrans
  01→08 dans l'ordre du cahier des charges, à partir de `docs/DESIGN_TOKENS.md`.

Chaque phase se clôt par une vérification locale gratuite (pytest + un passage Swagger UI, puis
`run`/`audit` une fois le mobile en jeu) avant de passer à la suivante. Détail complet des choix
techniques : cahier des charges sections A, B, C, D.
