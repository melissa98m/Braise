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
- [x] **Phase 4 — Module 4 Confiance & Modération.** Notation (note 1-5 + commentaire ≥ 4 mots
  obligatoire, une note par match) alimentant un score de confiance calculé à la volée (moyenne des
  notes non suspectes, labels EXEMPLAIRE/SOLIDE/EN CONSTRUCTION/FRAGILE repris des maquettes).
  Rancune détectée par deux signaux combinés : règle métier (note basse dans les 24h suivant le
  déblocage du match) + classifieur scikit-learn maison (TF-IDF + régression logistique, jeu de
  départ écrit à la main, à réentraîner sur des données réelles — voir
  `backend/app/services/moderation_ml.py`). Bannissement automatique si le score tombe à 0,
  garde-fou à 3 notes minimum pour ne pas bannir sur un ou deux avis malveillants (cahier des
  charges A.9). Signalement avec motif qualifié + commentaire libre, statut `pending` systématique
  — pas de tri automatique ni d'interface de revue humaine : hors périmètre MVP (cahier des charges
  C.1/C.2), à consulter via Adminer en attendant un vrai outillage de modération.
- [x] **Phase 5 — Modules 5/6 Monétisation (stub) & Sécurité.** Palier Premium unique
  (`Subscription`, activation `/subscriptions/debug-activate` en attendant une vraie build store —
  D.8), limite de 5 matchs gratuits appliquée au moment du "like" (contournée par Premium), badge
  `is_premium` sur le profil public. Déblocage réel des photos privées d'un match
  (`GET /profiles/matches/{id}/partner-photos`, verrouillé tant que `Match.unlocked_at` est vide —
  la pièce manquante du parcours flammes → déblocage posé en Phases 2-3), journalisé
  (`PhotoAccessLog`, seulement les accès à *autrui*). Chiffrement au repos réel des photos
  (SSE-S3 via la clé KMS locale `MINIO_KMS_SECRET_KEY`, aucune dépendance externe), vérifié en
  direct via `mc stat` (`Encryption: SSE-S3`). Droit à la portabilité (`GET /auth/me/export`) et à
  l'oubli (`DELETE /auth/me`, anonymisation — pas de cascade destructive sur les données d'un
  tiers). Refactor : `get_match_or_404`/`other_user_id`, dupliqués trois fois depuis la Phase 3,
  centralisés dans `services/matches.py`.
- [x] **Phase 6 — Mobile.** Flutter (conteneur `ghcr.io/cirruslabs/flutter:stable`, cible web,
  servi sur `localhost:5000`) implémente les 8 écrans du cahier des charges avec fidélité
  fonctionnelle sur le thème dark/light complet (`docs/DESIGN_TOKENS.md` porté 1:1 dans
  `BraiseTokens`/`buildBraiseTheme`). Une passe de polish ultérieure (mêmes 4 documents de
  maquette re-fournis en pièce jointe) a ajouté : l'alphabet de signes (`widgets/sign_shapes.dart`
  — cercle/carré/cercle plein pour la barre d'onglets, carré-à-noyau, diamant) plutôt que des
  icônes Material génériques ; des transitions d'écran fondu+glissement communes
  (`widgets/braise_page_route.dart`, désactivées si `MediaQuery.disableAnimations`) ; le halo
  ambré sous les CTA primaires (`elevation`/`shadowColor` du thème) ; les coins de bulle
  asymétriques et le halo de la carte "question du jour" en conversation ; le fond radial et le
  cadre lumineux des photos à l'écran de déblocage ; les 5 barres de confiance croissantes
  (calculées côté client depuis `TrustScore.score`, jamais un badge "vérifié" fictif — la donnée
  n'existe pas côté backend) ; l'aperçu du prochain profil en découverte (déjà présent dans la
  réponse de feed, simplement pas affiché avant) ; le diamant Braise+ pulsé
  (`@keyframes braisePulse` de la maquette). Écran d'onboarding adapté en saisie OTP (pas de scan KYC : le backend n'en a pas).
  Découverte à carte unique, pas de grille de swipe (principe "pas de catalogue" du cahier des
  charges). Conversation branchée sur le WebSocket réel (`ChatSocket`, même schéma token-en-query
  que le backend Phase 3) fusionné à l'historique REST, question quotidienne, bannières de
  déblocage et de notation. Écran Profil/Confiance ajouté avec upload/suppression des 3 photos
  privées et actions RGPD (export, suppression de compte) : aucune UI n'exposait ces endpoints
  avant cette phase. Navigation à 3 onglets (Découvrir/Échanges/Moi) au lieu des 4 de la maquette —
  pas d'onglet "Braises" séparé sans contenu propre côté backend. `CORSMiddleware` ajouté au
  backend (`CORS_ORIGINS`, `core/config.py`) pour l'appel cross-origin depuis le web Flutter.
  Vérifié : `flutter analyze` propre, `flutter test` (3/3, thème + contraste WCAG), rendu live
  confirmé par capture d'écran de l'app servie contre le backend réel. Pas de tests HTTP mockés en
  Dart pour cette passe (aucune infra de mock construite) — l'app démarre contre l'API réelle,
  observée manuellement plutôt qu'automatisée bout en bout.

Chaque phase se clôt par une vérification locale gratuite (pytest + un passage Swagger UI, puis
`run`/`audit` une fois le mobile en jeu) avant de passer à la suivante. Détail complet des choix
techniques : cahier des charges sections A, B, C, D.
