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

- [x] **Post-MVP P4.3 — Test de charge sur la messagerie WebSocket.** Explicitement exigé par le
  planning (B.1, Phase 4 : "tests de charge sur la messagerie temps réelle") avant le jalon
  "Go/No-go bêta" (B.2), jamais fait jusqu'ici. `backend/scripts/load_test_messaging.py` simule N
  matchs concurrents (chacun avec ses 2 participants connectés) et mesure latence de connexion,
  latence de diffusion, et taux de succès. Premier run à 100 matchs (200 connexions) : **échec
  total** — `sqlalchemy.exc.TimeoutError: QueuePool limit of size 5 overflow 10 reached` a
  bloqué non seulement la messagerie mais toute l'API, y compris des routes REST sans rapport,
  jusqu'à nécessiter un redémarrage du conteneur. Cause racine : `chat_ws` gardait une seule
  session DB ouverte pour toute la durée de la connexion (potentiellement des heures) au lieu
  d'une par opération — corrigé (`api/v1/messaging.py`, détail dans `CLAUDE.md`). Après correctif,
  vérifié à 400 matchs concurrents (800 connexions WS simultanées) sans le moindre échec, backend
  resté réactif pendant et après le test. À 800 matchs, le *script client* lui-même a atteint sa
  limite de descripteurs de fichiers (`OSError: Too many open files`, un seul process ouvrant
  1600 sockets) avant que le serveur ne montre le moindre signe de faiblesse — limite de
  l'outil de test, pas du serveur, pas encore poussée plus loin faute de temps. Un vrai bug de
  capacité trouvé et corrigé par un vrai test de charge, pas juste une case cochée.

- [x] **Post-MVP P4.4 — Scripts et guide de déploiement VPS.** D.7/D.11 recommandent un VPS
  auto-géré (Hetzner/OVH/Scaleway) + Docker Compose. `docs/DEPLOYMENT.md` + `docker-compose.prod.yml`
  (surcouche, jamais utilisée seule) + `infra/deploy/provision.sh` + `infra/deploy/Caddyfile` +
  `.env.prod.example`. Pas un vrai déploiement — aucun VPS disponible dans cet environnement pour
  le tester en conditions réelles ; chaque pièce vérifiable localement l'a été (la fusion Compose
  avec `docker compose config`, le Caddyfile avec `caddy validate`, la suite pytest après les
  changements de code). En préparant la config prod, deux vrais problèmes trouvés et corrigés,
  pas seulement documentés :
  - `MINIO_SECURE` pilotait à la fois le client interne (réseau Docker privé, doit rester `http`)
    et le client public qui signe les URLs des photos (doit suivre le vrai schéma externe,
    `https` derrière un reverse proxy TLS) — un seul réglage pour deux schémas qui n'ont aucune
    raison d'être identiques. Séparé en `minio_secure`/`minio_public_secure`
    (`core/config.py`/`services/storage.py`), défaut `false` des deux côtés pour ne rien changer
    en dev.
  - Docker Compose ne fusionne pas les listes (`ports`, `volumes`) entre fichiers par défaut : un
    override `ports: []` ne vide *pas* la liste de base (elle reste inchangée), il faut le tag
    `!reset` explicite pour vider et `!override` pour remplacer par un nouveau contenu — piège
    vérifié par l'usage (`docker compose config` avant/après), pas supposé.
  Réseau prod : seuls Caddy (80/443, TLS Let's Encrypt automatique) touche Internet — `db`, la
  console MinIO, Adminer et Uptime Kuma repassent en `127.0.0.1` uniquement (tunnel SSH), jamais
  publics. CGU/politique de confidentialité et vrai fournisseur SMS restent explicitement hors de
  ce palier — décisions produit/juridiques, pas des artefacts techniques à improviser.

- [x] **Post-MVP P5.1 — Évaluation du modèle de classification (jalon B.2).** Le planning exige
  explicitement un "modèle de classification v0 évalué" avant le jalon "Go/No-go bêta" ; jusqu'ici
  le pipeline s'entraînait sur les 490 exemples du CSV en entier, sans jeu de test séparé —
  jamais mesuré, seulement supposé correct parce qu'il s'entraînait sans erreur.
  `backend/scripts/evaluate_moderation_model.py` : validation croisée stratifiée à 5 plis
  (`cross_val_predict`, prédictions hors-échantillon poolées sur les 490 exemples plutôt qu'un
  split fixe bruyant à cette taille), réévaluée au seuil de décision réellement servi en
  production (0,6, pas le 0,5 par défaut de scikit-learn) pour mesurer le comportement exact de
  `predict_is_rancor`. Résultat : **0 % de faux positifs** sur les commentaires authentiques
  (0/295), 9,7 % de rancune manquée (19/195) — exactement le compromis visé par le choix de seuil
  documenté dans `moderation_ml.py`, maintenant mesuré au lieu d'affirmé. `build_pipeline()`/
  `load_dataset()` extraits du module (n'étaient pas exposés avant) pour que le script évalue
  l'architecture *réellement* servie, jamais une copie qui pourrait diverger en silence.
  `docs/MODEL_EVALUATION.md` consigne méthode et résultats ; `tests/test_moderation_ml.py`
  ajoute un garde-fou de non-régression (même validation croisée, échoue si le taux de faux
  positifs dépasse 2 %) — 76/76 tests backend désormais.

- [x] **Post-MVP P5.2 — Couverture de tests des écrans (en cours).** L'infra de mock HTTP (P3)
  n'avait servi qu'à `AuthController` — les 10 dossiers d'écrans avaient zéro test.
  `AppServices` accepte désormais un `httpClient` optionnel, ce qui permet de pumper un écran
  entier sous un vrai `Provider<AppServices>` sans toucher le réseau.
  `test/screens/ban_appeal_screen_test.dart` (5 tests) est le premier écran couvert — choisi
  parce que c'est l'écran le plus dommageable à casser en silence : le seul recours d'un compte
  banni (A.9). En l'écrivant, un vrai piège trouvé : `package:http`'s `Response(String, ...)`
  choisit l'encodage du corps depuis l'en-tête `Content-Type` de la réponse, pas depuis le
  contenu réel de la chaîne — sans en-tête, retombe sur Latin-1, et n'importe quel accent
  (partout, cette app est en français) casse alors `utf8.decode` côté `ApiClient._decode` avec un
  `FormatException` confus. `auth_controller_test.dart` (P3) en souffrait déjà sans qu'aucun test
  ne l'ait remarqué — `'Compte suspendu.'` n'a pas d'accent donc passait par accident,
  `'Compte supprimé.'` en a un et décodait silencieusement vers un message générique jamais
  comparé par ce fichier, seul le statut final l'était (qui retombait juste au bon endroit par
  coïncidence). Corrigé dans les deux fichiers de test.
  `test/screens/report_screen_test.dart` (4 tests) couvre le deuxième écran — `ReportScreen`,
  partagé par 3 points d'entrée (conversation, déblocage, notation). Piège différent cette fois :
  ses 5 tuiles de motif + champ texte + bouton dépassent la hauteur du viewport de test par défaut
  (800×600), donc `tester.tap()` sur le bouton "Envoyer le signalement" échouait silencieusement
  (avertissement de hit-test hors bornes du render tree, pas d'exception) — corrigé avec un
  helper `_tapAfterScrollingTo` qui appelle `tester.ensureVisible()` avant chaque tap sur un motif
  ou le bouton, plutôt qu'agrandir artificiellement le viewport de test (qui masquerait le même
  bug si un écran réel a une hauteur similaire). 20/20 tests Flutter au total.
  `test/screens/otp_screen_test.dart` (5 tests) couvre `OtpScreen` — le tout premier écran que
  traverse chaque utilisateur, donc l'un des plus coûteux à casser en silence : demande de code
  (débogage local pré-rempli, erreur API), puis vérification vers ses deux destinations réelles
  (`ProfileSetupScreen` pour un profil jamais publié, `RootShell` pour un profil déjà publié) et
  l'erreur de code invalide. `OtpScreen` épingle son bouton en bas via `Spacer` plutôt qu'un
  `SingleChildScrollView` (contrairement à `ReportScreen`) : son étape 2 (bandeau debug compris)
  déborde de 1px sur le viewport de test 800×600, un écran réel n'ayant jamais cette contrainte —
  élargir le viewport de test (`tester.binding.setSurfaceSize`) est donc le bon correctif ici,
  pas la même situation que `ReportScreen` où l'agrandir aurait masqué un vrai bug de scroll.
  En écrivant le scénario "profil déjà publié -> `RootShell`", un vrai bug de production trouvé :
  `DiscoveryScreen._exitController` (l'animation de sortie de carte, Phase 6 tardive) était un
  champ `late final = AnimationController(vsync: this, ...)` — jamais lu dans `build()`, seulement
  dans `_swipe()` et `dispose()`. Un utilisateur qui ouvre Découvrir sans jamais swiper puis quitte
  l'écran (déconnexion, navigation, `RootShell` démonté) fait de `dispose()` le tout premier accès
  à ce champ paresseux : `AnimationController(vsync: this)` tente alors de remonter l'arbre pour
  trouver un `TickerMode`, ce qui échoue puisque l'élément est déjà désactivé à ce stade
  ("Looking up a deactivated widget's ancestor is unsafe."). Corrigé en construisant
  `_exitController` dans `initState()` (où le widget est garanti monté) plutôt que via
  l'initialiseur paresseux du champ — un bug qui existait en production depuis l'introduction du
  swipe animé (`e7da7df`), jamais remarqué faute de test déclenchant ce chemin de démontage sans
  swipe préalable. 25/25 tests Flutter au total, `flutter analyze` propre (à l'exception d'un
  avertissement `info` préexistant et sans rapport dans `moderation_api.dart`).

- [x] **Post-MVP P5.3 — Lint backend (ruff).** Le mobile a `flutter_lints` depuis la Phase 6 ; le
  backend Python n'avait aucun linter. `backend/ruff.toml` (E/F/W/I/UP, `line-length = 110` —
  suffit à couvrir le code existant sans forcer une reformatée massive des commentaires "pourquoi"
  déjà soigneusement écrits). Premier passage : 14 signalements réels, tous corrigés à la main
  plutôt qu'un `--fix` en masse — un import mal trié, un f-string sans placeholder, un import
  inutilisé, le reste des lignes trop longues à retourner. `app/models/__init__.py` exempté du tri
  d'imports (`per-file-ignores`) : son ordre chronologique par phase est délibéré, pas un oubli.
  `docker compose run --rm backend ruff check .` — clôt le plan d'action P5 dans son intégralité
  (P5.1 modèle évalué, P5.2 tests d'écran amorcés, P5.3 lint).

- [x] **Post-MVP P6.1 — Protection anti-brute-force sur l'OTP.** `services/otp.py` n'avait
  aucune limite : un code à 6 chiffres (10^6 possibilités) valide 10 minutes, sans plafond de
  tentatives, se force par brute force en pratique — une vraie faille de prise de compte, pas un
  simple manque de robustesse, dès qu'un attaquant connaît le numéro de la victime. Deux garde-fous
  indépendants, tous les deux sur `User` (pas de Redis/service externe — cohérent avec le reste du
  projet, tout en Postgres) : `MIN_RESEND_INTERVAL_SECONDS = 30` (`otp_requested_at`) rejette avec
  429 une nouvelle demande de code trop rapprochée pour le même numéro ; `MAX_OTP_ATTEMPTS = 5`
  (`otp_attempts`) neutralise le code courant (`otp_code` mis à `None`) après ce nombre d'échecs de
  vérification — pas un simple rejet : sans invalider le code, le bon code resterait valable après
  la limite, donc `MAX_OTP_ATTEMPTS` ne ferait que ralentir l'attaque plutôt que l'arrêter. Les deux
  compteurs repartent à zéro à chaque nouvelle demande de code, pour ne pas pénaliser un
  utilisateur légitime qui s'est trompé sur son *prochain* essai. Migration Alembic
  `608fde81428f` (deux colonnes ajoutées à `users`) générée et appliquée contre le Postgres de dev
  réel. 4 nouveaux tests (`test_auth_otp.py` : throttle actif, throttle levé après la fenêtre,
  verrouillage après `MAX_OTP_ATTEMPTS`, remise à zéro par un code frais) — 80/80 tests backend,
  `ruff check .` propre. Aucun changement mobile requis : `OtpScreen` n'a pas de bouton "renvoyer"
  tant qu'un code est en attente (le bouton est désactivé via `_loading` pendant l'appel), donc ce
  chemin de throttle n'est pas atteignable depuis l'UI actuelle — c'est un filet de sécurité
  purement côté serveur.

- [x] **Post-MVP P6.2 — Intégration continue (GitHub Actions).** Rien n'exécutait
  `pytest`/`ruff`/`flutter analyze`/`flutter test` automatiquement ; cette session a trouvé
  plusieurs régressions réelles (épuisement du pool DB en P4.3, crash au `dispose()` de
  `DiscoveryScreen` en P5.2/P6, décodage Latin-1 par défaut) uniquement en les faisant tourner à
  la main. `.github/workflows/ci.yml` (deux jobs, `backend`/`mobile`, en parallèle) lance sur
  chaque push/PR exactement les commandes Docker déjà documentées dans `README.md`/`CLAUDE.md` —
  pas de mock, les mêmes conteneurs Postgres/MinIO réels qu'en local. Gratuit (minutes GitHub
  Actions), conforme à la contrainte "pas de service payant" (`CLAUDE.md`).
  Deux correctifs nécessaires pour que le pipeline parte vert dès le premier commit, tous les deux
  de vrais bugs et pas des artefacts CI : (1) `docker-compose.yml` — le service `backend` ne
  dépendait que de `minio: service_healthy`, pas de `minio-init`, donc `docker compose run backend
  ...` pouvait démarrer avant que le bucket `braise-photos` existe (course locale bénigne la
  plupart du temps vu la rapidité de `minio-init`, mais réelle en CI où rien n'a encore "réchauffé"
  les conteneurs) — ajout de `minio-init: condition: service_completed_successfully` comme
  dépendance explicite, ce qui fiabilise aussi `docker compose up backend` en local, pas seulement
  la CI. (2) `flutter analyze` retourne un code de sortie non-nul même pour un simple finding de
  niveau `info` — un avertissement `use_null_aware_elements` préexistant et sans rapport dans
  `moderation_api.dart:19` (`if (comment != null) 'comment': comment`) aurait fait échouer le job
  mobile dès le premier run ; corrigé avec la syntaxe null-aware native de Dart 3.8+
  (`'comment': ?comment`), qui omet l'entrée si `comment` est `null` — comportement identique,
  zéro `info` restant. 80/80 tests backend, `ruff check .` propre, 25/25 tests Flutter,
  `flutter analyze` propre (0 issue), les deux jobs vérifiés localement dans les mêmes conditions
  qu'en CI avant de committer le workflow.

- [x] **Post-MVP P6.3 — Couverture de test de `DiscoveryScreen`.** L'écran le plus fréquenté
  (feed, swipe, célébration de match) restait sans test direct — c'est justement en le traversant
  *indirectement* (navigation post-OTP vers `RootShell`, P5.2/P6) que le crash `_exitController`
  corrigé en P6 a été trouvé. 6 tests : chargement du feed (candidat affiché + aperçu du suivant),
  feed vide, erreur de chargement, "passer" qui vide le feed, "braiser" avec match mutuel (le
  dialogue de célébration s'ouvre, se referme sans naviguer vers la conversation — hors périmètre
  de ce test), et un swipe refusé (402, limite de matchs gratuits) qui affiche un snackbar sans
  faire disparaître la carte. Contrairement à `OtpScreen`/`ReportScreen`, aucun piège de viewport
  ni de scroll ici : le corps de l'écran utilise `Expanded`/`AnimatedSwitcher`, pas une hauteur de
  contenu fixe. 31/31 tests Flutter au total, `flutter analyze` propre — clôt le plan d'action P6
  dans son intégralité (P6.1 anti-brute-force OTP, P6.2 CI, P6.3 couverture Discovery).

- [x] **Post-MVP P7.1 — Couverture de test de `MatchesListScreen`.** Onglet racine ("Échanges")
  sans aucun test — contrairement à `ConversationScreen` (WebSocket réel, pas mockable avec
  l'infra HTTP existante `httpClient`), ce n'est qu'un `GET /discovery/matches`, donc même
  gabarit que `discovery_screen_test.dart`. 4 tests : distinction match débloqué (`blurStage ==
  'net'`) vs verrouillé (sous-titre différent — "Profil privé débloqué" vs le pourcentage), liste
  vide ("Direction Découvrir !"), erreur de chargement, et tirer-pour-rafraîchir
  (`tester.fling` sur le `ListView`, compteur d'appels vérifié à 2). 35/35 tests Flutter au
  total, `flutter analyze` propre.

- [x] **Post-MVP P7.2 — Couverture de test de `ProfileTrustScreen`, et vrai bug corrigé au
  passage.** Onglet "Moi" : `_load()` attendait 3 appels en parallèle (profil, score de
  confiance, matchs) via `Future.wait` sans aucun `try/catch` — une erreur transitoire sur
  n'importe lequel des trois laissait `_loading` bloqué à `true` pour toujours, sans rien de
  scrollable pour déclencher un nouveau tirer-pour-rafraîchir (`RootShell` garde cet écran monté
  en permanence via `IndexedStack`, `initState` ne se relance jamais) — un spinner infini sans
  recours pour l'utilisateur, découvert en écrivant le scénario d'erreur de ce fichier de test,
  pas en l'y cherchant délibérément. Corrigé : `_load()` capture désormais l'`ApiException`,
  bascule vers un état d'erreur (`_error`) affiché dans un `ListView` (donc toujours
  rafraîchissable par tirer-pour-rafraîchir), au lieu de laisser l'exception se propager dans le
  vide. 2 tests : chargement réussi (profil, badges VÉRIFIÉ/BRAISE+, score, flammes agrégées,
  échanges actifs) et échec sur un des trois appels suivi d'un tirer-pour-rafraîchir qui réussit
  cette fois — la preuve que la sortie de l'état bloqué fonctionne réellement, pas seulement que
  l'erreur s'affiche. 37/37 tests Flutter au total, `flutter analyze` propre.

- [x] **Post-MVP P8 — Couverture de test de tous les écrans restants (hors `ConversationScreen`),
  et deux nouveaux vrais bugs corrigés.** Six écrans couverts en une passe :
  `ConceptIntroScreen` (3 pages, navigation finale vers `RootShell` — sans crash grâce au
  correctif P7.2, plus mocké ici), `RatingScreen` (même gabarit que `ReportScreen`, score par
  défaut vs choisi explicitement, rancune suspectée), `UnlockScreen` (état vide et erreur
  seulement — le cas "photos présentes" utilise `Image.network`, qui taperait le vrai réseau
  dans le bac à sable de test), `PaywallScreen`, `SettingsScreen`, et `ProfileSetupScreen`
  (le plus gros : pré-remplissage, intérêts, prompts de bio, genre, régénération d'avatar,
  publication — sans jamais toucher `ImagePicker`/`showDatePicker`, deux flux réels non
  mockables ici ; `_save()` n'exige `_birthDate` que si `_profile` est encore `null`, donc
  publier après un chargement réussi n'a jamais besoin d'interagir avec le sélecteur de date).

  Deux vrais bugs trouvés et corrigés, même famille que celui de `ProfileTrustScreen` (P7.2) :
  - `PaywallScreen._load()` n'avait aucun `try/catch` — même spinner infini sans recours qu'avait
    `ProfileTrustScreen` avant son correctif. `_activate()`/`_cancel()` avalaient aussi
    silencieusement toute erreur au lieu de l'afficher, contrairement à chaque autre action
    mutante de l'app. Les trois méthodes capturent désormais `ApiException` et l'affichent
    (état d'erreur rafraîchissable pour `_load()`, `SnackBar` pour les deux autres).
  - `SettingsScreen._exportData()`/`_deleteAccount()` n'avaient pas non plus de gestion
    d'erreur : un échec réseau disparaissait sans aucun retour utilisateur. Corrigé avec le même
    motif `catch (ApiException e) -> SnackBar(e.message)` déjà utilisé partout ailleurs dans
    l'app.

  Deux nouveaux pièges de test découverts au passage (documentés dans les fichiers concernés) :
  `PaywallScreen`'s `_PulsingDiamond` tourne en boucle infinie (`AnimationController.repeat()`)
  si `MediaQuery.disableAnimations` n'est pas explicitement forcé à `true` dans le harnais de
  test — sinon `pumpAndSettle()` n'atteint jamais une frame sans animation active et échoue par
  timeout ; et `SettingsScreen`'s long `ListView` ne construit même pas les éléments trop loin
  sous la ligne de flottaison (au-delà du `cacheExtent` du `Sliver` sous-jacent), donc
  `tester.ensureVisible()` ne peut rien cibler qui n'existe pas encore — un viewport de test
  assez haut pour que tout tienne évite le problème plutôt que de le contourner.

  68/68 tests Flutter au total, `flutter analyze` propre, 80/80 tests backend inchangés. Seul
  `ConversationScreen` reste sans test direct : il parle en WebSocket réel (`ChatSocket`), qui
  n'a pas de fabrique de canal injectable — un refactor à part entière, hors périmètre de cette
  passe de couverture d'écrans.

- [x] **P9.1 — Notifications locales réelles.** Les 3 bascules de `SettingsScreen` ne faisaient
  que mémoriser une préférence, honnêtement documentées comme sans effet ("prochaine version") —
  jamais aucune notification n'était réellement envoyée. Contrainte découverte en démarrant ce
  chantier : ce projet ne tourne qu'en Flutter **web** (voir CLAUDE.md, section Mobile — tous les
  dossiers de plateforme existent parce que `flutter create` les scaffold par défaut, mais seul
  `web` est jamais réellement servi), ce qui exclut `flutter_local_notifications` d'office
  (aucune implémentation web). Mécanisme retenu : l'API `Notification` native du navigateur via
  `dart:js_interop`/`package:web` (gratuit, local, sans Firebase/APNs) — mais fondamentalement
  limitée au premier plan : une page web ne peut pas programmer une notification à une heure
  future si son onglet est fermé, ça demande un Service Worker (+ souvent Web Push), un chantier
  distinct et plus lourd, hors périmètre de cette passe.

  Piège de compilation trouvé en le posant : `dart:js_interop` est une vraie bibliothèque Dart,
  mais uniquement sur les cibles de compilation web — un fichier qui l'importe ne compile même
  pas pour la VM, celle sur laquelle tournent `flutter test`/`flutter analyze` par défaut.
  `lib/notifications/notification_platform.dart` résout ça par un export conditionnel
  (`if (dart.library.js_interop) ...`, le remplaçant standard de l'ancien `dart.library.html`) :
  `notification_platform_web.dart` sur le web, `notification_platform_stub.dart` (no-op) partout
  ailleurs. `flutter build web` (exécuté et vérifié avant ce commit) est ce qui prouve réellement
  que le code d'interop compile pour la vraie cible — `flutter test` ne peut pas du tout
  l'exercer, tournant sur la VM. `NotificationsService` enveloppe ces deux fonctions de
  plateforme derrière des callbacks injectables — même motif que `ApiClient(httpClient: ...)` —
  pour que les tests d'écran vérifient "déclenché au bon moment, avec le bon message" sans jamais
  toucher un vrai navigateur ni dépendre d'une permission réellement accordée.
  `NotificationPrefs` centralise les 3 clés SharedPreferences (déclarées avant comme constantes
  privées dans `SettingsScreen`, maintenant une source unique lue aussi par les points de
  déclenchement). La permission est demandée depuis `SettingsScreen` uniquement quand une bascule
  passe sur "activé" par un tap explicite, jamais au démarrage de l'app ni au chargement de
  l'écran — les navigateurs traitent souvent une demande de permission hors d'un geste utilisateur
  comme du spam et la refusent d'office.

  Trois points de déclenchement, chacun honnête sur ce qu'il peut et ne peut pas faire vu la
  contrainte "premier plan uniquement" : `DiscoveryScreen._celebrateMatch` (nouveau match mutuel —
  en plus du dialogue de célébration déjà affiché, pas à sa place), `ConversationScreen`'s
  `socket.messages.listen` (message de l'autre côté pendant que cette conversation précise est
  ouverte — pas d'écoute globale sur tous les matchs à la fois, seulement la conversation
  activement ouverte), et `RootShell.initState` (rappel "question du jour", au plus une fois par
  jour calendaire, suivi par un horodatage dans `shared_preferences` plutôt que réellement
  programmé — l'approximation honnête la plus proche d'un "rappel quotidien" atteignable sans
  Service Worker).

  81/81 tests Flutter au total (13 nouveaux : 6 tests unitaires sur `NotificationsService`/
  `NotificationPrefs`, 7 sur les points de déclenchement Discovery/Settings/RootShell),
  `flutter analyze` propre, `flutter build web` réussi, 80/80 tests backend inchangés.

- [x] **P9.2 — Badge de messages non lus.** Le statut lu/non lu par message existait déjà côté
  backend depuis la Phase 3 (`last_read_at_a`/`last_read_at_b`, `services/matches.message_is_read`)
  mais rien ne l'agrégeait ni ne l'affichait : ni compteur sur l'onglet "Échanges", ni indicateur
  par match dans `MatchesListScreen`. `services/discovery.list_my_matches` calcule désormais
  `unread_count` par match (nouveau champ sur `MatchOut`) — une seule requête batchée sur tous les
  messages de l'autre côté à travers tous mes matchs, comparaison à mon "lu jusqu'à" (par match,
  donc en Python après cette requête unique) plutôt qu'une requête par match, même principe que le
  scoring de compatibilité du feed. Test backend dédié
  (`test_match_list_reports_unread_count_from_the_other_side_only`) : mes propres messages ne
  comptent jamais comme non lus pour moi, et marquer comme lu remet le compteur à 0.

  Côté mobile, `MatchSummary.unreadCount` s'affiche en `Badge.count` sur chaque ligne de
  `MatchesListScreen` et, agrégé, sur l'icône de l'onglet "Échanges" dans `RootShell`. `RootShell`
  appelle `getMatches()` une troisième fois pour ce total — `MatchesListScreen` et
  `ProfileTrustScreen` l'appellent déjà chacun indépendamment pour leurs propres besoins, donc un
  troisième appelant suit le même principe pragmatique plutôt que d'inventer un état partagé entre
  3 écrans pour une fonctionnalité à l'échelle MVP. Cet appel est protégé par un `try/catch`
  (contrairement au reste de `RootShell`, qui ne dépend de rien de bloquant) : un badge est
  purement décoratif, une erreur ne doit jamais remonter comme une exception non gérée —
  `MatchesListScreen` affiche déjà sa propre erreur si le problème persiste réellement. Pas de
  rafraîchissement en direct pendant qu'une conversation est ouverte (aucun bus d'événements
  inter-écrans n'existe) : le badge se met à jour au montage et en quittant l'onglet Échanges, ce
  qui couvre le cas réel (il se vide en revenant de la messagerie) sans machinerie d'état partagé
  supplémentaire.

  84/84 tests Flutter au total, `flutter analyze` propre, `flutter build web` réussi, 81/81 tests
  backend, `ruff check .` propre.

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
