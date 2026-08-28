# Braise — Roadmap d'exécution

Toutes les phases tournent en local, gratuitement, sous Docker Compose. Aucun service payant
(SMS, Apple/Google, Firebase, cloud) n'est requis avant que le MVP ne soit validé en local.
Référence stack : cahier des charges, section D.11.

- [x] **Phase 0 — Environnement.** Docker Compose (Postgres, MinIO, backend FastAPI, Adminer,
  conteneur Flutter en attente), Alembic, smoke tests pytest, README de démarrage.
- [x] **Phase 1 — Module 1 Identité & Profils.** Séparation profil public (`PublicProfile` :
  display_name, bio, intérêts, avatar-sigil déterministe régénérable) / privé (`PrivateProfile` :
  jusqu'à 3 photos, stockées chiffrées dans MinIO, URLs signées à courte durée de vie),
  `GET /auth/me` pour compléter l'auth OTP. Contrôle d'âge (18+) au niveau schéma Pydantic.
- [x] **Phase 2 — Module 2 Matching & Découverte.** Feed de découverte scoré par recouvrement
  d'intérêts (Jaccard), swipe like/pass (`Swipe`, contrainte unique anti-double-vote), match mutuel
  (`Match`, id de paire canonique) exposant l'état de déblocage (`flame_count`/`unlock_threshold` —
  l'incrémentation par la question quotidienne arrive en Phase 3). Pas de filtres démographiques
  (âge/genre/distance) : hors du périmètre choisi pour cette phase, à reconsidérer plus tard.
- [x] **Phase 3 — Module 3 Messagerie & Flammes.** Chat WebSocket custom (`/messaging/ws/{match_id}`,
  auth par token en query string, diffusion en mémoire — un seul process backend pour l'instant),
  historique REST paginé. Question quotidienne dérivée des intérêts publics de l'autre (QCM à 4
  choix, seed déterministe, une par utilisateur/match/jour) ; bonne réponse = +1 flamme partagée
  sur le `Match` posé en Phase 2. Pas de statut de lecture ni d'indicateur de saisie : reporté,
  pas nécessaire pour valider le cœur du mécanisme flammes/déblocage.
- [ ] **Phase 4 — Module 4 Confiance & Modération.** Notation (note + commentaire ≥ 4 mots
  obligatoire), classifieur scikit-learn (authenticité), signalement + file de revue humaine.
- [ ] **Phase 5 — Modules 5/6 Monétisation (stub) & Sécurité.** Toggle Premium local, URLs signées
  courtes pour les photos privées (MinIO), chiffrement au repos.
- [ ] **Phase 6 — Mobile.** Flutter (dans son conteneur, cible web d'abord) implémente les écrans
  01→08 dans l'ordre du cahier des charges, à partir de `docs/DESIGN_TOKENS.md`.

Chaque phase se clôt par une vérification locale gratuite (pytest + un passage Swagger UI, puis
`run`/`audit` une fois le mobile en jeu) avant de passer à la suivante. Détail complet des choix
techniques : cahier des charges sections A, B, C, D.
