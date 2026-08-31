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

- [x] **Post-MVP P0 — Durcissement opérationnel.** Le cahier des charges (B.3, D.7, D.12) posait
  les sauvegardes automatisées/testées et la supervision comme dépendance critique avant toute
  bêta ; aucune des phases 0-6 ne l'avait traitée. Service `backup` (`infra/backup/`) : dump
  Postgres quotidien + miroir des photos MinIO, avec purge des dumps > `BACKUP_RETENTION_DAYS`,
  et surtout **testé par restauration réelle** (`test_restore.sh` : sauvegarde → restauration dans
  une base/bucket jetables → comparaison des lignes/objets avec la source → nettoyage — vérifié en
  conditions réelles, pas seulement écrit). Supervision basique via `uptime-kuma` (moniteurs
  HTTP/TCP sur backend, MinIO, Postgres — configuration manuelle au premier lancement, ce produit
  n'a pas de format déclaratif). `docs/DPIA.md` : AIPD couvrant l'inventaire des données, les
  mesures déjà en place et les risques résiduels — notamment l'absence de procédure de
  contestation de bannissement pourtant exigée par A.9, à traiter dans un prochain palier (P1).
  Volontairement hors de ce palier : réplication du volume de sauvegarde hors de l'hôte Docker
  local (n'a de sens qu'une fois sur un vrai VPS, D.7) et notification effective sur les moniteurs
  Uptime Kuma (étape manuelle documentée dans le README, pas automatisable sans API dédiée).

- [x] **Post-MVP P1.1 — Procédure de contestation de bannissement.** Le bannissement automatique
  existait depuis la Phase 4 (`services/moderation.create_rating`) mais sans la voie de recours
  humaine explicitement exigée par le cahier des charges A.9 — `docs/DPIA.md` l'avait classé
  "risque élevé". Modèle `BanAppeal` (même schéma que `Report` : démarre `pending`, revue via
  Adminer, pas d'outillage de tri automatique — cohérent avec le reste de la modération MVP).
  `api/deps.get_current_user_even_if_banned` est la seule exception délibérée à la coupure totale
  d'accès d'un compte banni (`user_from_token` continue de bloquer partout ailleurs, y compris
  `/auth/me`) : sans elle, `POST /moderation/ban-appeal` serait lui-même inatteignable par la
  personne qui en a besoin. Un seul appel non-bannissant peut avoir une contestation `pending` à
  la fois. Côté mobile, `AuthController` distingue désormais "banni" (403 détail exact
  `Compte suspendu.`, token conservé) de "token invalide/compte supprimé" (déconnexion normale) —
  avant ce correctif, un compte banni était silencieusement renvoyé à l'écran OTP sans explication
  ni recours possible, ce qui rendait la procédure inatteignable en pratique malgré son existence
  côté API. `BanAppealScreen` (nouvel état `AuthStatus.banned` routé depuis `main.dart`) affiche le
  statut de la dernière contestation ou le formulaire pour en déposer une. Vérifié par un scénario
  bout en bout réel contre le backend qui tourne (bannissement via 3 notes basses de 3 comptes
  distincts → 403 partout → contestation acceptée → doublon rejeté en 409), pas seulement par les
  tests pytest (63/63 passent, dont 5 nouveaux pour ce palier).

- [x] **Post-MVP P1.2 — Filtres de découverte de base.** A.5 Module 2 les liste explicitement en
  MVP ("tranche d'âge, distance, genre recherché") ; seule la distance reste hors scope (aucune
  capture de géolocalisation n'existe dans l'app — l'ajouter serait un projet à part : permission,
  géocodage, calcul de distance, pas une extension d'un après-midi). `PublicProfile` gagne
  `gender`/`looking_for_gender`/`age_min`/`age_max`, tous nullable : un profil qui ne les
  renseigne pas n'est filtré par rien, exactement le comportement d'avant ces colonnes — pas de
  migration de données à risque sur les profils existants. `services/discovery.get_feed` pousse le
  filtre de genre en SQL (égalité simple, réduit le pool avant le tri) et applique la tranche d'âge
  en Python dans la boucle de scoring existante, cohérent avec le choix déjà documenté de ne pas
  interroger SQL sur un âge qui n'est pas une colonne stockée. Réglages exposés dans
  `ProfileSetupScreen` (Écran 02) plutôt qu'un nouvel écran dédié — 4 champs facultatifs ne
  justifiaient pas une route de plus ; tranche d'âge en `RangeSlider` où la position pleine (18–99)
  équivaut à "pas de préférence" côté client, pour matcher exactement la sémantique `null` du
  backend. Vérifié par 5 nouveaux tests pytest (68/68) et un scénario réel contre le backend qui
  tourne (préférence "femme" exclut un homme, inclut une femme, un genre invalide est rejeté 422).

- [x] **Post-MVP P1.3 — Écran d'onboarding pédagogique.** Dernier point du plan d'action initial :
  A.4.1.5 exige un "écran d'onboarding dédié" expliquant pourquoi le physique est différé et
  comment fonctionnent les flammes — l'onboarding sautait jusqu'ici directement de la création du
  profil à la découverte, sans jamais l'expliquer. `screens/onboarding/concept_intro_screen.dart` :
  3 pages (`PageView`) — inversion personnalité/physique, mécanique des flammes (bonne réponse =
  +1 flamme, mauvaise = relecture sans pénalité, jamais une punition — ton A.7), puis le voile
  progressif (silhouette → flou léger → net, déblocage simultané pour les deux). Affiché une seule
  fois : `ProfileSetupScreen._save` n'y route que si `isOnboarding == true`, donc jamais revu par
  quelqu'un qui modifie juste son profil plus tard. Clôt le plan d'action P1 initial (filtres +
  contestation + onboarding pédagogique) dans son intégralité.

- [x] **Post-MVP P3 — Infrastructure de mock HTTP côté Flutter.** Les deux items restants du P2
  (interface de revue humaine pour les signalements, réentraînement du modèle ML) n'étaient pas
  actionnables maintenant : le premier contredit le périmètre V2 explicite du cahier des charges
  (C.1/C.2), le second suppose des données de bêta réelles qui n'existent pas encore. Bascule sur
  le P3 le plus concret : `ApiClient` prenait `http.get`/`.post`/etc. en appels de fonctions
  top-level, ce qui rendait tout mock impossible sans réécrire l'app. Un seul changement — accepter
  un `http.Client` injectable, `httpClient` optionnel, défaut inchangé en dehors des tests — ouvre
  `package:http/testing.dart` (déjà fourni par la dépendance `http` existante, pas besoin de
  mockito). `test/state/auth_controller_test.dart` (8 tests) est la première chose construite
  dessus : couvre `AuthController.restoreSession`/`verifyOtp` contre un `/auth/me` mocké, y compris
  la branche `AuthStatus.banned` ajoutée en P1.1 qui n'avait jusqu'ici aucune couverture de test.
  11/11 tests Flutter au total (3 thème + 8 nouveaux).

- [x] **Post-MVP P3 — Statut de lecture et indicateur de saisie.** A.5 Module 3 les listait tous
  les deux comme scope MVP ; reportés en Phase 3, faute de nécessité pour valider le cœur du
  mécanisme flammes/déblocage. `Match.last_read_at_a`/`last_read_at_b` : un timestamp "lu jusqu'à"
  par côté plutôt qu'un flag par message, suffisant pour un chat 1-to-1, pas de table séparée.
  `services.matches.message_is_read` est symétrique — un fait sur le message (le destinataire
  l'a-t-il lu), jamais dépendant de qui consulte. `chat_ws` distingue désormais 3 types de frames
  (`message`/`typing`/`read`), `message` restant le défaut implicite si absent pour ne pas casser
  le protocole existant. `typing` est un pur relai, jamais persisté. `read` pose le timestamp et
  rediffuse aux autres connexions du match. Côté Flutter, `ChatSocket` démultiplexe un seul flux
  brut en 3 (`messages`/`typingEvents`/`readEvents`) via le champ `type` déjà tagué serveur.
  `ConversationScreen` envoie `markRead()` au chargement de l'historique et à chaque message reçu
  pendant que l'écran est ouvert — il n'existe pas d'action "marquer comme lu" explicite dans
  cette UI, avoir la conversation ouverte en tient lieu. `sendTyping()` est throttlé à 1 envoi/2s
  sur `onChanged`, pas un envoi par frappe. Le tick de lecture ("Envoyé"/"Lu") ne s'affiche que
  sous le tout dernier message envoyé, jamais par bulle. Vérifié par 3 nouveaux tests pytest
  (71/71 au total) exerçant le vrai WebSocket (pas mocké) contre la vraie base.

- [x] **Post-MVP P3 — Badge « profil vérifié ».** A.5 Module 1 le liste en scope MVP et les
  maquettes l'affichent partout (découverte, profil) ; `User.is_verified` existait et était posé
  depuis la Phase 1 (premier OTP réussi) mais n'était jamais sorti de `/auth/me` — aucun schéma
  public ne l'exposait, donc aucun badge nulle part malgré la donnée déjà correcte en base.
  `PublicProfileOut` et `DiscoveryCandidateOut` gagnent `is_verified` ; `get_feed` le résout en un
  seul `IN (...)` batché sur le pool de candidats (même principe anti-N+1 que
  `list_my_matches`). Badge rendu avec le signe carré-à-noyau existant
  (`widgets/sign_shapes.dart::SignSquareCore`, déjà utilisé nulle part avant ça) sur l'écran Profil
  et la carte de découverte — jamais une couleur seule, cohérent avec le reste du langage de
  signes. Vérifié par 2 nouveaux tests pytest (72/72 au total) et une vérification directe du
  schéma OpenAPI exposé par le backend qui tourne.

- [x] **Post-MVP P3 — Éditeur de bio guidé.** A.5 Module 1 : "suggestions de questions pour éviter
  les bios vides type « demandez-moi »" — l'éditeur n'avait qu'un texte d'exemple statique en
  hint, jamais de vraies suggestions. `ProfileSetupScreen` affiche désormais une question tirée de
  `_bioPrompts` (8 questions, ton A.7) uniquement tant que la bio est vide — elle disparaît dès la
  première frappe, jamais un encombrement une fois que l'utilisateur a commencé à écrire. "Une
  autre question" fait tourner la suggestion, "Utiliser" la insère comme point de départ éditable,
  jamais un texte imposé. Mobile seul, aucun changement backend.

- [x] **Post-MVP P3 — Score de confiance visible en découverte.** A.3/A.4.4 : le score de confiance
  doit informer la découverte avant même un match ("gage de fiabilité auprès des futurs matchs"),
  et la maquette 03 l'affiche sur chaque carte ("VÉRIFIÉE · CONFIANCE 88"). Ce n'était pas un
  effet de bord du correctif IDOR précédent (P1) : `discovery.get_feed` n'a jamais référencé le
  score de confiance, ni avant ni après ce correctif — celui-ci coupait juste la seule route qui
  permettait de lire le score de n'importe qui en devinant un UUID, sans rapport avec ce qui
  manque ici. `compute_trust_score` délègue désormais à `compute_trust_scores_batch` (une requête
  `ratee_id IN (...)` groupée en Python), pour que `get_feed` résolve tout le pool de candidats en
  un aller-retour plutôt qu'un par candidat. `DiscoveryCandidateOut` n'expose que `trust_score`/
  `trust_label` — jamais `rating_count`/`flagged_count`, plus granulaires que ce qu'un tiers doit
  voir, même logique de minimisation que l'âge calculé sans date de naissance brute. Rendu combiné
  au badge vérifié sur la carte de découverte ("VÉRIFIÉ · CONFIANCE 88"). Vérifié par un nouveau
  test pytest (73/73 au total) et une lecture directe du schéma OpenAPI du backend qui tourne.

- [x] **Post-MVP P4.1 — Instrumentation des KPIs (A.10).** Aucun des 9 indicateurs de succès
  n'était mesurable nulle part ; sans ça, le jalon "Bilan bêta" du planning (B.2) n'a rien à
  produire. `backend/scripts/compute_kpis.py` les calcule directement depuis les tables
  existantes — aucun ne nécessitait de nouvelle infra de tracking. Pas de nouvel endpoint API :
  ce projet n'a pas de notion de rôle staff (`Report`/`BanAppeal` se consultent déjà via Adminer,
  jamais via une route protégée), donc un script cohérent avec le reste de l'outillage
  opérationnel plutôt qu'une route à qui il faudrait inventer un contrôle d'accès. La rétention
  J7/J30 est un proxy explicitement documenté (pas de journal de connexion/session dans ce
  projet) — approximée par "a swipé de nouveau au moins N jours après l'inscription", à ne pas
  citer hors contexte de debug interne sans cette réserve. Chaque nombre vérifié à la main contre
  des requêtes SQL directes sur la base de dev (complétion de profil 65/5395, déblocage 120/1999,
  matchs → 3 jours 0/1999 — tous exacts).

## Backlog V2 (hors périmètre MVP)

- [ ] **KYC renforcé — vérification d'identité via France Identité / FranceConnect+.** Déjà
  identifié comme hors périmètre MVP dans `docs/DPIA.md` (section 1 : "le KYC renforcé par pièce
  d'identité est explicitement hors périmètre MVP, réservé à une option V2"). Le KYC MVP reste
  l'OTP téléphone (cahier des charges D.6). Intégration envisagée : FranceConnect+ (niveau de
  garantie substantiel/élevé) avec France Identité comme fournisseur d'identité — un flux
  OIDC standard côté code, mais qui suppose d'être accrédité "fournisseur de service" par l'État
  (personne morale, convention, homologation RGS, domaine de prod en HTTPS) avant même de pouvoir
  tester contre le vrai service ; à défaut, un prestataire KYC privé (Onfido, Veriff — payant,
  accréditation en jours plutôt qu'en mois) reste l'alternative. Aucune des deux options n'est
  compatible avec la contrainte MVP "tout tourne en Docker, gratuit/local uniquement" (`CLAUDE.md`)
  — à ne considérer qu'une fois le produit validé et prêt à passer en bêta réelle avec une entité
  juridique constituée.
