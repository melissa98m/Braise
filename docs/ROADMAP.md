# Braise — Roadmap d'exécution

> Le produit s'appelle désormais **Bresonne** (renommé en septembre 2026, voir `CLAUDE.md` §
> Project) — ce journal garde volontairement « Braise » partout ci-dessous, nom réel du produit
> au moment où chaque phase a été faite ; ce n'est pas une coquille à corriger.

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

- [x] **P9.3 — Filtre de découverte par distance (cahier des charges A.5).** Explicitement hors
  périmètre jusqu'ici ("aucune capture de géolocalisation n'existe dans l'app"). Pas de GPS, pas
  d'API de géocodage payante : l'utilisateur choisit une ville dans une liste fermée d'environ 50
  grandes villes françaises (`backend/app/services/geo.py` +
  `services/data/french_cities.csv`, coordonnées connues du domaine public, précision suffisante
  pour un filtre de rayon, pas un usage cartographique). Résolution en `city_lat`/`city_lon` une
  seule fois à l'enregistrement du profil (`upsert_public_profile`), jamais recalculée à chaque
  requête de feed — une ville hors liste reste acceptée comme simple texte d'affichage
  (`city`), sans jamais résoudre de coordonnées, donc silencieusement ignorée comme filtre plutôt
  que rejetée en erreur. `max_distance_km` est ma préférence de recherche, symétrique à
  `age_min`/`age_max` : nulle = pas de filtre. `get_feed` l'applique dans la même boucle Python
  que la tranche d'âge (`services/geo.haversine_km`, distance à vol d'oiseau) ; un candidat sans
  coordonnées résolues est exclu d'une recherche filtrée par distance, faute de pouvoir vérifier
  qu'il est dans le rayon. `GET /profiles/cities` (sans authentification — donnée de référence
  statique, rien de propre à un utilisateur) peuple le sélecteur mobile. 4 nouveaux tests backend
  (liste des villes, exclusion au-delà du rayon, exclusion d'un candidat sans ville, absence de
  filtrage sans `max_distance_km`).

  Côté mobile, `ProfileSetupScreen` ajoute un sélecteur de ville et un curseur de distance à la
  section "Préférences de découverte" existante. Piège trouvé en écrivant le test de publication :
  le curseur affiche "100 km" par défaut tant que l'utilisateur ne l'a jamais touché, mais
  `_maxDistanceKm` restait `null` dans ce cas — `_save()` publiait alors *aucun* filtre de
  distance malgré ce que l'écran affichait clairement à l'instant de publier. Corrigé avec un
  repli `_maxDistanceKm ?? _defaultMaxDistanceKm` au moment d'envoyer, pour que ce qui part vers
  le serveur corresponde toujours à ce qui était affiché. `PublicProfile.city`/`.maxDistanceKm`
  sont des paramètres de constructeur optionnels (pas `required`) spécifiquement pour que
  `_regenerateAvatar()` (qui reconstruit un `PublicProfile` à la main) n'ait pas à changer à
  chaque nouveau champ du modèle — il les recopie quand même explicitement depuis l'ancien
  profil, sinon régénérer son avatar aurait silencieusement effacé la ville/le rayon choisis.

  87/87 tests Flutter au total, `flutter analyze` propre, `flutter build web` réussi, 85/85 tests
  backend, `ruff check .` propre — clôt le plan d'action P9 dans son intégralité (P9.1
  notifications locales, P9.2 badge de messages non lus, P9.3 filtre de découverte par distance).

- [x] **P10 — Couverture de test de `ConversationScreen`, le dernier écran restant.** Seul écran
  encore non testé après P8 : il parle en WebSocket réel (`ChatSocket`), sans fabrique de canal
  injectable — un refactor à part entière, explicitement laissé de côté à l'époque.

  `ChatSocket` (`api/messaging_api.dart`) accepte désormais un `channel` optionnel (typé
  `StreamChannel<dynamic>`, pas `WebSocketChannel` — ce que renvoie `WebSocketChannel.connect`,
  qui EST un `StreamChannel`, mais le champ doit aussi accepter un factice sans vraie connexion
  réseau derrière), par défaut la vraie `WebSocketChannel.connect`. `ConversationScreen` accepte
  de même un `chatSocketFactory` optionnel. Même motif d'injection que
  `AppServices(httpClient: ...)` partout ailleurs dans ce projet. Les tests construisent un
  `StreamChannelController<dynamic>()` (`package:stream_channel`), donnent son bout `.local` à
  `ChatSocket`, et utilisent `.foreign.sink.add(...)` pour simuler des frames serveur /
  `.foreign.stream` pour observer ce que l'écran envoie réellement.

  Deux pièges trouvés en écrivant ces tests :
  - Un `.foreign.stream.listen((data) => ...)` posé à la main bloquait systématiquement
    `pumpAndSettle()` indéfiniment — pas un simple timeout, un vrai blocage propre au mélange du
    contrôleur `stream_channel` avec la zone `FakeAsync` de `flutter_test` ; `expectLater(stream,
    emits(...))` (ou `emitsThrough`), la façon officiellement recommandée d'asserter sur un flux
    dans `test`/`flutter_test`, n'a pas ce problème. Leçon retenue : préférer `expectLater`/les
    matchers de flux à un `.listen()` manuel pour vérifier un flux dans un test de widget.
  - `emits(matcher)` ne vérifie que le tout premier événement, or cet écran envoie des frames
    "de service" en passant — `_loadHistory()` envoie toujours un `read` au chargement, le
    composeur envoie un `typing` avant le `message` réellement testé. `emitsThrough(matcher)`
    (ignorer jusqu'à trouver une correspondance, plutôt qu'exiger que le premier événement
    corresponde) est ce qu'il fallait ici.

  6 tests : chargement de l'historique, réception d'un message via le socket (apparaît + déclenche
  un "read" en retour), envoi d'un message (composeur vidé + frame "message" envoyée), question du
  jour (affichage + réponse + résultat), indicateur de saisie (apparaît sur un événement "typing",
  disparaît après 3 s de silence), et un événement "read" qui fait passer "Envoyé" à "Lu" sur le
  dernier message envoyé.

  93/93 tests Flutter au total, `flutter analyze` propre, `flutter build web` réussi, 85/85 tests
  backend inchangés — clôt entièrement la couverture de test des écrans mobiles (13/13, en
  comptant `RootShell` qui n'était pas un écran de module dédié mais est maintenant lui aussi
  couvert via P9).

- [x] **P11 — Écran d'accueil et session longue durée (demande explicite, hors cahier des
  charges).** Deux changements de parcours utilisateur demandés directement, pas déduits des
  maquettes :
  1. `screens/onboarding/welcome_screen.dart` — premier écran vu à l'installation (avant, l'app
     ouvrait directement sur `OtpScreen`), avec deux CTA ("Créer un compte" / "J'ai déjà un
     compte"). Les deux mènent au même `OtpScreen` sans paramètre : l'OTP téléphone ne distingue
     techniquement pas inscription et connexion (`POST /auth/verify-otp` crée le compte au
     premier succès, connecte ensuite — `services/otp.py`), donc simuler une différence côté
     client aurait été malhonnête pour un flux réellement unifié. Atteint via un vrai
     `Navigator.push`, pas replié dans le switch de `_AuthGate` — le `pushReplacement`
     d'`OtpScreen` en cas de succès remplace alors cette route poussée, pas la route que
     `_AuthGate` lui-même affiche, ce qui empêche tout retour arrière vers l'accueil/l'OTP une
     fois connecté (comportement voulu, pas un oubli).
  2. `ACCESS_TOKEN_EXPIRE_MINUTES` passé de 60 (1h) à 21600 (15 jours) — rester connecté d'une
     session à l'autre plutôt qu'une expiration courte. Vérifié sur un vrai jeton émis contre la
     stack qui tourne (décodage du payload JWT, `exp` mesuré à 14j 23h59 après émission).
     `AuthController.restoreSession()` gérait déjà correctement l'expiration (redirige vers
     `WelcomeScreen`/`OtpScreen`, reconnexion par OTP téléphone) — aucun changement nécessaire là,
     seule la durée de validité du jeton a changé. Pas de refresh token séparé : un seul JWT
     longue durée reste le choix le plus simple, cohérent avec le reste du projet.

  3 nouveaux tests (`test/screens/welcome_screen_test.dart`), 96/96 tests Flutter au total,
  `flutter analyze` propre, 85/85 tests backend, `ruff check .` propre.

- [x] **P12.1 — CGU et politique de confidentialité (DPIA, action 3).** Rédigées à partir de
  l'inventaire de données de `docs/DPIA.md` (pas un texte générique) :
  `docs/legal/CGU.md`/`POLITIQUE_CONFIDENTIALITE.md`, toutes deux marquées explicitement "version
  bêta, pas encore relue par un juriste" — à faire avant toute ouverture au-delà d'un cercle
  restreint. Affichées dans l'app (`screens/legal/legal_screen.dart`, contenu dupliqué à la main
  en Dart plutôt que chargé depuis les fichiers Markdown — pas de pipeline d'assets dans ce
  projet, texte assez court pour ne pas le justifier), reliées depuis `WelcomeScreen` (mention
  sous les CTA, avant toute inscription) et Paramètres (section RGPD). 2 nouveaux tests
  (`legal_screen_test.dart` + un test ajouté à `welcome_screen_test.dart`), 99/99 tests Flutter
  au total, `flutter analyze` propre.

- [x] **P12.2 — Alerting Uptime Kuma scripté (DPIA, action 1).** Uptime Kuma n'a pas de format de
  config déclaratif, mais son API interne (Socket.IO) est atteignable hors de l'UI web via le
  paquet `uptime-kuma-api` (client pour l'API déjà exposée par le conteneur, pas un service
  tiers) — `infra/uptime-kuma/setup.py` configure donc le compte admin et les 3 moniteurs
  (backend, MinIO, Postgres) par script plutôt qu'à la main, idempotent, exécuté et vérifié
  contre l'instance réelle (les 3 moniteurs confirmés `UP` via l'API après coup). Le canal
  d'alerte webhook (Discord/Slack/générique — noms de champs vérifiés dans le
  `notification_providers.py` du paquet installé, pas devinés) est scripté aussi, configuré via
  `UPTIME_KUMA_WEBHOOK_URL` — alerte Discord posée et vérifiée avec une vraie notification de
  test (`test_notification` → `Sent Successfully.`, reçue dans le salon Discord). Supervision et
  alerte toutes deux en place de bout en bout, plus aucune étape manuelle restante.

- [x] **P13 — « Qui vous a déjà braisé » (demande explicite, hors cahier des charges).** Moteur
  d'engagement/conversion classique des apps de rencontre (le "Who Likes You" de Tinder Gold),
  proposé puis demandé directement plutôt que déduit des maquettes — s'appuie entièrement sur des
  données déjà en base (`Swipe`), aucune nouvelle table.
  - `services/discovery.get_likes_received` : profils qui ont liké l'utilisateur et qu'il/elle n'a
    pas encore swipés dans un sens ou l'autre (même exclusion `already_swiped` que `get_feed` — un
    match ou un pass déjà posé sort naturellement de la liste). Le compte est toujours renvoyé
    (incitation gratuite) ; le détail des profils (`DiscoveryCandidateOut`, même forme que le feed)
    n'est renvoyé que pour un compte Braise+ (`is_premium`) — un gate liste vide/pleine, pas un
    flou par carte, plus simple et suffisant pour créer l'incitation. `_candidate_dict` a été
    extrait de `get_feed` pour être partagé par les deux fonctions plutôt que dupliqué.
    `GET /discovery/likes-received` (`LikesReceivedOut`) est le seul nouvel endpoint ; « braiser en
    retour » et « passer » réutilisent tels quels `POST /discovery/swipe` — `record_swipe` gère
    déjà correctement le cas "like mutuel = match" quelle que soit la surface UI qui l'a déclenché,
    aucune nouvelle logique de match nécessaire.
  - Mobile : `LikesReceivedScreen` (`screens/discovery/`), accessible depuis une icône avec badge
    (même motif `Badge.count` que le badge messages non lus de `RootShell`) dans l'AppBar de
    `DiscoveryScreen`. Palier gratuit : compte + CTA vers `PaywallScreen`. Palier premium : cartes
    avec « Braiser en retour »/« Passer », dialogue de célébration de match identique à celui de
    `DiscoveryScreen` en cas de like mutuel.
  - 5 nouveaux tests pytest (27/27 sur `test_discovery.py`, 90/90 backend au total), 4 nouveaux
    tests Flutter (`likes_received_screen_test.dart`), 103/103 tests Flutter au total,
    `flutter analyze` et `ruff check .` propres, `flutter build web` vérifié.

- [x] **P14 — Revue UX en conditions réelles (demande explicite, hors cahier des charges).**
  Parcours complet piloté par un vrai navigateur headless (Chrome via `playwright-core`, pas de
  lecture de code) contre l'app qui tourne sur `localhost:5000` : inscription, remplissage de
  profil, découverte, matchs existants (`+33600000099`, `seed_beta_tester.py`), question
  quotidienne, « Qui vous a braisé », Braise+, Paramètres. 5 problèmes réels trouvés et corrigés :
  1. **Question quotidienne sans énoncé.** `models/daily_question.py` n'avait jamais eu de champ
     texte — seulement `options`/`correct_answer` — donc la carte affichait "QUESTION DU JOUR"
     suivi de 4 boutons sans dire ce qu'il fallait deviner. `services/messaging._build_prompt`
     dérive maintenant la question à la volée ("Lequel de ces centres d'intérêt appartient
     vraiment à {prénom} ?") à partir du prénom actuel de l'autre côté — jamais persisté, pour ne
     pas geler une question déjà répondue sur un ancien nom si le profil change entretemps.
     `get_or_create_daily_question` récupère `other_profile` avant la branche "déjà existante",
     puisque les deux cas ont besoin du prénom. Nouveau champ `prompt` sur `DailyQuestionOut`
     (backend) et `DailyQuestion` (mobile), rendu dans `_DailyQuestionCard` juste avant les
     options.
  2. **Sélecteur de date de naissance non localisé.** `MaterialApp` n'avait aucun
     `localizationsDelegates`/`supportedLocales` : le date picker Material s'affichait 100% en
     anglais ("Select date", "Enter Date", "OK"/"Cancel") dans une app entièrement en français, et
     surtout attendait un format de saisie clavier **MM/JJ/AAAA** (américain) — une date tapée en
     réflexe français (JJ/MM) était silencieusement mal interprétée, sur un champ qui sert au
     contrôle 18+. Ajout de `flutter_localizations` (paquet du SDK Flutter, pas de version à
     épingler) et `locale: const Locale('fr')` fixé en dur dans `main.dart` — l'app n'a qu'une
     langue, pas de raison de suivre la locale de l'appareil/du navigateur plutôt que de garantir
     un comportement cohérent pour tout le monde. Vérifié en direct : le picker affiche désormais
     "Sélectionner une date", jours L/M/M/J/V/S/D, et une saisie "05/12/1994" est bien interprétée
     comme le 5 décembre (pas le 12 mai).
  3. **Texte trompeur sur l'écran OTP.** "Sans vérification : découverte limitée." était un
     `Text` statique non cliquable — aucun mode "sans vérification" n'existe dans le backend,
     `verify-otp` est l'unique porte d'entrée (pas de compte invité). Supprimé plutôt
     qu'implémenté : un mode invité serait une vraie décision produit, pas un correctif de bug.
  4. **Bio vide affichée comme un rendu cassé.** `'« ${candidate.bio} »'` sur une bio vide donnait
     juste "«  »" flanqué d'un grand espace vide — a toutes les apparences d'un bug de rendu
     plutôt que d'un profil incomplet. Les 3 endroits qui affichent une bio (carte de découverte,
     aperçu du suivant, carte "Qui vous a braisé") basculent maintenant sur un texte de substitution
     ("Cette personne n'a pas encore écrit de bio." / "Pas encore de bio.") quand `bio.isEmpty`.
  5. **Compteur FLAMMES plafonné sans jamais afficher le vrai total.**
     `FlameDiamonds(filled: _totalFlames.clamp(0, 5), total: 5)` sur `ProfileTrustScreen` : au-delà
     de 5 flammes cumulées sur tous les matchs, l'affichage "5/5 rempli" est identique quel que
     soit le vrai total (7, 20, 200...), contrairement à "ÉCHANGES ACTIFS" juste à côté qui affiche
     un vrai chiffre. Les diamants restent (motif décoratif de `docs/DESIGN_TOKENS.md`), mais le
     vrai total (`_totalFlames`) s'affiche désormais en chiffres au-dessus.
  - **Bonus trouvé en creusant la navigation** : une flèche "retour" fantôme apparaissait parfois
    sur l'AppBar "Découvrir" juste après connexion, alors que c'est censé être l'écran racine.
    Cause : `WelcomeScreen` pousse `OtpScreen` via `Navigator.push`, et la chaîne
    `OtpScreen`/`ProfileSetupScreen`/`ConceptIntroScreen` qui suit utilisait `pushReplacement` —
    qui ne remplace que la route immédiatement précédente, jamais la route racine (`_AuthGate`,
    qui affiche déjà `RootShell` de façon réactive une fois connecté). Résultat : deux copies de
    `RootShell` empilées, la flèche pop l'une pour révéler l'autre (identique visuellement, d'où
    la confusion). Les deux points d'arrivée terminaux sur `RootShell` (retour d'un profil déjà
    publié dans `otp_screen.dart`, fin de l'onboarding dans `concept_intro_screen.dart`) utilisent
    désormais `pushAndRemoveUntil(..., (_) => false)` à la place, qui vide toute la pile.
  - **Fiabilité du conteneur `mobile` découverte en marge de ce travail** : `entrypoint.sh`
    appelait `flutter build web` directement, en comptant sur sa résolution de dépendances
    implicite — intermittente dans ce conteneur (pub cache jamais persisté entre redémarrages,
    voir `docker-compose.yml`), avec des échecs de compilation aléatoires ("fichier introuvable"
    sur des paquets pourtant bien réels) à chaque redémarrage. Un `flutter pub get` explicite et
    bloquant avant la commande de build élimine la course ; jamais échoué depuis en pratique.
  - 1 nouveau test pytest (`test_daily_question_correct_answer_increments_shared_flame_count`
    étendu, 90/90 backend au total), 1 nouveau test Flutter (bio vide sur `DiscoveryScreen`) + 1
    assertion étendue (prompt de la question quotidienne), 104/104 tests Flutter au total,
    `flutter analyze`/`ruff check .` propres, `flutter build web` vérifié, les 5 correctifs
    confirmés un par un contre l'app réelle (captures + appels API directs).

- [x] **P15 — Audit accessibilité (demande explicite, hors cahier des charges).** L'app n'a
  jamais eu de passe accessibilité dédiée. Vérifié contre l'arbre d'accessibilité réel de l'app
  qui tourne (`page.locator('body').ariaSnapshot()` via `playwright-core`, pas une lecture de
  code), avec un contrôle en profondeur au niveau DOM brut (`flt-semantics`, attributs `aria-*`)
  chaque fois que le rendu compact de Playwright laissait un doute. 6 problèmes réels trouvés et
  corrigés :
  1. **Flutter web restait muet au premier chargement.** Flutter web ne construit son arbre
     sémantique qu'à la demande (première interaction, ou détection d'une techno d'assistance) —
     sans rien pour contourner ça, une personne utilisant un lecteur d'écran n'entendait que le
     bouton caché "Enable accessibility" au premier chargement, sans indice qu'autre chose existe.
     `main()` appelle désormais `SemanticsBinding.instance.ensureSemantics()` avant `runApp` (le
     `SemanticsHandle` renvoyé n'est jamais conservé ni disposé — le disposer redésactiverait
     l'arbre) : vérifié en direct, le contenu complet de `WelcomeScreen` est maintenant exposé dès
     le chargement, sans activation manuelle.
  2. **Deux boutons "+" sans nom accessible.** `IconButton(onPressed: _addInterest, icon:
     Icon(Icons.add))` (`profile_setup_screen.dart`) n'avait pas de `tooltip` — un lecteur d'écran
     annonçait juste "button". Même défaut sur le `InkWell` d'ajout de photo. Tooltip/`Semantics`
     ajoutés aux deux.
  3. **Bouton de suppression de photo trop petit et invisible en lecture d'écran.** `GestureDetector`
     nu de 24×24px (`CircleAvatar(radius: 12)`), bien en dessous du minimum recommandé de 44px pour
     une action de suppression, sans aucune sémantique. Rayon porté à 16 (32px — reste modeste pour
     ne pas empiéter sur la vignette 96×120, mais une vraie amélioration), `Semantics(button: true,
     label: 'Supprimer cette photo')` ajouté, `HitTestBehavior.opaque` pour que toute la zone
     élargie réagisse au tap.
  4. **Badges décoratifs exposés comme des cases à cocher.** `Chip` porte par défaut une sémantique
     de type "checkbox" même sans `onTap`/`onDeleted` — trompeur sur les chips purement informatifs
     ("X intérêts en commun", intérêts d'un candidat en découverte, badge "VÉRIFIÉ"/"BRAISE+" sur
     l'écran Moi). `Semantics(excludeSemantics: true, label: ...)` autour de chaque `Chip`
     remplace cette sémantique interne par un simple label neutre, sans toucher au rendu visuel.
  5. **Les 3 réglages de notification fusionnés en un seul bloc.** `_NotifRow`
     (`settings_screen.dart`) n'avait aucune frontière sémantique : un lecteur d'écran annonçait
     les 3 lignes comme un seul bloc ("Nouveau match Un like réciproque Question du jour Rappel
     quotidien Messages Nouveaux messages reçus"), impossible de savoir quel interrupteur
     correspond à quoi en y naviguant. `Semantics(container: true, label: '$label. $desc',
     toggled: value, onTap: () => onChanged(!value), excludeSemantics: true)` autour de chaque
     ligne : label et état séparés par ligne, `onTap` explicite car `excludeSemantics` masque
     aussi le `Switch` sous-jacent (sans lui, plus aucun moyen d'activer le réglage par lecteur
     d'écran).
  6. **Stats FLAMMES/ÉCHANGES ACTIFS lues comme une seule phrase.** `_StatCard`
     (`profile_trust_screen.dart`) n'avait pas de frontière entre les deux cartes voisines,
     lues comme "7 FLAMMES 2 ÉCHANGES ACTIFS" d'un bloc. Même motif `Semantics(container: true,
     label: ..., excludeSemantics: true)`, avec un nouveau paramètre `semanticValue` pour le cas
     `child` (widget libre — les diamants FLAMMES n'ont pas de `value` textuel simple).
     Confirmé au niveau DOM brut : deux nœuds `flt-semantics` bien distincts et bornés
     ("0 FLAMMES", "0 ÉCHANGES ACTIFS"), même si le rendu compact de `ariaSnapshot()` les
     réaffiche fusionnés dans le texte environnant par souci de concision — pas un signe d'échec
     du correctif, juste une limite de ce format d'affichage condensé.
  - **Fausse piste écartée après vérification** : le sélecteur de thème ("Système"/"Clair"/
    "Sombre") semblait n'exposer aucun état sélectionné dans le rendu compact de `ariaSnapshot()`
    — mais l'inspection du DOM brut a montré que `SegmentedButton` expose déjà correctement l'état
    actif via `aria-current` (`false`/`false`/`true`). Aucun correctif nécessaire ; la piste
    initiale était un faux positif du format de rendu condensé, pas un vrai defect.
  - **Bonus UX** : faute d'accord "1 intérêts en commun" → "1 intérêt en commun" (accord
    singulier/pluriel), sur les cartes de découverte et l'écran "Qui vous a braisé" — visible par
    tout le monde, pas seulement en lecture d'écran.
  - 2 nouveaux tests Flutter (accessible name des boutons "+" ; labels/état des 3 réglages de
    notification via `matchesSemantics`), 106/106 tests Flutter au total, `flutter analyze` propre,
    `flutter build web` vérifié, chaque correctif reconfirmé contre l'app réelle après redéploiement.

- [x] **P16 — Passe accessibilité/UX approfondie (demande explicite, hors cahier des charges).**
  Suite directe de P15, sur des dimensions non couvertes la première fois (clavier, mouvement,
  langue, métadonnées) plutôt qu'un nouveau passage sur les mêmes écrans. 4 problèmes trouvés,
  tous corrigés et reconfirmés en direct :
  1. **Aucune langue déclarée sur la page.** `web/index.html:2` avait `<html>` sans `lang` —
     un lecteur d'écran peut choisir une prononciation anglaise par défaut pour du contenu
     entièrement en français, un problème qui touche tout le texte de l'app, pas un écran en
     particulier. `<html lang="fr">`.
  2. **L'anneau de focus clavier existait dans le thème mais était quasiment invisible.**
     `docs/DESIGN_TOKENS.md` définit un vrai anneau de focus (violet, 3px) et `braise_theme.dart`
     le câblait déjà — mais seulement via `ThemeData.focusColor`, qui ne fait qu'un survol de
     teinte. Mesuré au pixel près (diff d'images focus/non-focus) : ~24/255 de variation de
     couleur au maximum sur "Créer un compte", imperceptible sur un fond orange saturé. Un
     utilisateur clavier (sans souris/tactile) n'avait aucun moyen fiable de savoir sur quel
     bouton il se trouvait, dans toute l'app. Nouvelle fonction `_focusRingSide` dans
     `braise_theme.dart` : bordure de 3px `tokens.focusRing` sur l'état focus, appliquée aux 4
     thèmes de bouton (`Elevated`/`Outlined`/`Text`/`Icon`) via `.copyWith(side: ...)` sur le
     `ButtonStyle` existant plutôt que de reconstruire chaque style depuis zéro. Vérifié en
     direct : anneau violet net et visible sur les deux CTA de l'écran d'accueil après tabulation.
  3. **L'animation de swipe en Découverte ignorait "réduire les animations".** Contrairement à
     `braise_page_route.dart` et au halo pulsant de `PaywallScreen`, qui respectent déjà
     `MediaQuery.disableAnimations`, `_exitController` et l'`AnimatedSwitcher` de
     `discovery_screen.dart` avaient des durées figées (280ms/260ms) — sur l'écran le plus utilisé
     de l'app. Les deux durées passent à `Duration.zero` quand `disableAnimations` est actif
     (calculé une fois en tête de `build()`, `_exitController.duration` réassigné à chaque frame —
     un `AnimationController.duration` est mutable, pas besoin de reconstruire le controller).
     Vérifié avec l'émulation `reducedMotion: 'reduce'` de Playwright : la carte suivante s'affiche
     déjà totalement stable 150ms après le tap sur "Passer", sans image intermédiaire de
     transition.
  4. **Onglet du navigateur et métadonnées jamais personnalisés depuis le scaffold Flutter.**
     `web/index.html` (`<title>braise_app</title>`, `meta description` = "A new Flutter
     project.", `apple-mobile-web-app-title` = "braise_app") et `web/manifest.json` (`name`/
     `short_name` = "braise_app", `theme_color`/`background_color` = bleu Flutter par défaut
     `#0175C2`) portaient encore le texte et les couleurs du modèle de projet, jamais remplacés
     pendant les 6 phases + travaux post-MVP précédents. Titre/nom passés à "Braise", description
     reprise du texte réel de l'écran d'accueil, couleurs alignées sur les tokens existants
     (`background_color` = `surface/root` sombre `#07090E`, `theme_color` = `braise/fill`
     `#FF8C42`) — visible dans l'onglet du navigateur, les favoris, et le nom de l'icône si l'app
     est ajoutée à l'écran d'accueil (PWA), pas seulement un point d'accessibilité.
  - **Vérifié solide, aucun correctif nécessaire** : le reflow à zoom navigateur élevé (testé en
    simulant un viewport deux fois plus étroit, WCAG 1.4.10 — le texte se réajuste proprement,
    rien ne déborde), le thème clair (contraste et cohérence bons sur tous les écrans vérifiés),
    l'annonce des `SnackBar` d'erreur et la restauration du focus après une boîte de dialogue
    (garanties par le framework Flutter lui-même, pas un point faible de cette app), et l'ordre de
    tabulation clavier sur l'écran d'accueil.
  - Aucun nouveau test automatisé (les 4 points sont soit visuels — pas facilement assertable en
    test de widget sans capturer des pixels —, soit déjà couverts par les tests d'écran
    existants), mais chaque correctif reconfirmé un par un contre l'app réelle après
    reconstruction du conteneur : `lang`/titre lus directement depuis le DOM, anneau de focus et
    absence d'image de transition capturés par capture d'écran, `manifest.json` relu depuis le
    serveur qui tourne. `flutter analyze` propre, 106/106 tests Flutter (inchangé), `flutter build
    web` vérifié.

- [x] **P17 — Troisième passe accessibilité/UX (demande explicite, hors cahier des charges).**
  Encore un cran plus loin que P16 : chargements, mouvement dans les écrans jamais couverts
  jusqu'ici, et structure des formulaires. 3 points trouvés puis corrigés (un 4e, l'absence de
  balise `<meta viewport>`, écarté après comparaison directe avec le template Flutter par défaut
  de la version installée — il n'en a pas non plus, le canvas se dimensionne par JS, pas par le
  mécanisme de zoom CSS classique) :
  1. **Les 10 indicateurs de chargement de l'app étaient muets pour un lecteur d'écran.**
     `CircularProgressIndicator` a un paramètre `semanticsLabel` prévu pour ça ; aucune des 10
     occurrences (Découverte, Paramètres, Moi, Échanges, Braise+, "Qui vous a braisé", création de
     profil, contestation de bannissement, déblocage de profil, `main.dart`) ne le renseignait.
     `'Chargement en cours.'` ajouté partout via un remplacement global (le même
     `const CircularProgressIndicator()` littéral apparaissait identique aux 10 endroits).
  2. **"Réduire les animations" restait ignoré sur 7 animations locales de plus**, en plus du swipe
     de Découverte corrigé en P16 : les étoiles de notation (`rating_screen.dart`, x2), les 2
     transitions de l'écran OTP — barre de progression et changement d'étape (`otp_screen.dart`,
     x3), le défilement entre les 3 pages "Le concept" et sa barre de progression
     (`concept_intro_screen.dart`, x2), les barres de score de confiance qui montent en s'animant
     (`profile_trust_screen.dart`), la révélation du profil débloqué (`unlock_screen.dart`), et le
     défilement automatique vers le dernier message (`conversation_screen.dart`). Même motif
     partout : une valeur `Duration.zero` calculée une fois via `MediaQuery.of(context)
     .disableAnimations`, réutilisée pour chaque `Animated*`/`TweenAnimationBuilder` de l'écran —
     `PageController.animateToPage`/`ScrollController.animateTo` acceptent nativement une durée
     nulle (vérifié dans le code source du SDK avant d'appliquer le correctif, pas supposé), ils
     sautent alors instantanément à la position cible plutôt que de rejeter l'appel.
  3. **Les 9 champs de texte de l'app utilisaient un placeholder comme seul repère visuel, sans
     label persistant.** Le motif classique : le repère disparaît dès la première frappe, donc
     rien n'indique plus ce que contient le champ en y revenant. Numéro de téléphone et code OTP
     (`otp_screen.dart`) séparés en un vrai label (« Numéro de téléphone », « Code reçu par SMS »)
     et, pour le téléphone, un `hintText` qui redevient un simple exemple de format plutôt que le
     label lui-même — au passage, `autofillHints` ajouté sur les deux (`telephoneNumber`,
     `oneTimeCode`) pour l'auto-remplissage réel et le remplissage SMS automatique sur mobile.
     Même traitement pour l'ajout d'intérêt (`profile_setup_screen.dart`), le texte de contestation
     de bannissement (`ban_appeal_screen.dart`) et la description de signalement
     (`report_screen.dart`). Délibérément laissés tels quels : le champ de saisie du chat
     (`conversation_screen.dart`, « Écrire à {nom}… ») suit une convention universelle de
     messagerie où aucune app connue n'affiche de label flottant, et le sélecteur de ville
     (`profile_setup_screen.dart`) est un bouton qui affiche déjà la valeur choisie en permanence
     (jamais un texte libre qui disparaît), pas le même problème.
  - Aucun nouveau test automatisé (mêmes raisons qu'en P16 — changements visuels/déclaratifs,
    faible risque de régression, framework-vérifiés), mais chaque correctif reconfirmé contre
    l'app réelle après reconstruction du conteneur : label persistant du téléphone capturé en
    capture d'écran + relu dans l'arbre d'accessibilité (nom accessible "Numéro de téléphone" avec
    l'exemple de format relégué en `/placeholder`, valeur tapée distincte des deux). `flutter
    analyze` propre, 106/106 tests Flutter (inchangé), `flutter build web` vérifié.

- [x] **P18 — Quatrième passe accessibilité : régression corrigée dans le correctif P16
  lui-même.** Cette fois, la question de départ était différente : "le correctif précédent a-t-il
  vraiment tenu ses promesses ?", pas "quel nouvel écran vérifier ?". Résultat : les 3 lignes de
  réglages de notification (`settings_screen.dart`, corrigées en P16 pour la lecture au lecteur
  d'écran) étaient devenues **totalement inatteignables au clavier seul, sans lecteur d'écran**.
  `excludeSemantics: true` — nécessaire pour éviter la double lecture du label — masquait aussi le
  focus clavier natif du `Switch` sous-jacent, dont Flutter se sert normalement à la fois pour la
  sémantique et pour la tabulation. Repéré en parcourant l'ordre de tabulation réel de l'app
  (script Playwright dédié : Tab répété + lecture de `document.activeElement`) plutôt qu'en
  supposant que le correctif sémantique de P16 suffisait à lui seul — ce qui a permis de
  distinguer les contrôles réellement atteignables ("Système"/"Clair"/"Sombre",
  "Exporter mes données"...) des 3 lignes totalement absentes de la séquence.
  - **Correctif** : chaque ligne enveloppée dans un `Focus` explicite (`onKeyEvent` gérant
    Entrée/Espace en appelant `onChanged(!value)`), en plus du `Semantics` existant — le premier
    redonne un arrêt de tabulation réel et une activation clavier physique, le second reste
    responsable de l'annonce et de l'action côté lecteur d'écran ; les deux coexistent sans se
    marcher dessus. Vérifié à deux niveaux : un test de widget qui prend le focus par programme
    (`Focus.of(...).requestFocus()`) et envoie un vrai événement clavier
    (`tester.sendKeyEvent(LogicalKeyboardKey.space)`), *et* contre l'app réelle reconstruite — un
    script qui tabule jusqu'à chaque ligne et appuie sur Espace confirme que les 3 préférences
    (`braise_notif_match`/`_question`/`_messages`) basculent bien, sans lecteur d'écran, à la
    seule tabulation.
  - **Non résolu, mineur** : chaque ligne occupe désormais 2 arrêts de tabulation (le nouveau
    `Focus` et le `Switch` sous-jacent, toujours présent dans l'arbre, gardent chacun leur propre
    focusabilité) plutôt qu'un seul — les deux activent correctement le même réglage, donc pas
    d'incohérence fonctionnelle, juste 3 tabulations de plus pour traverser l'écran. Laissé tel
    quel : supprimer complètement la focusabilité propre du `Switch` sans risquer une nouvelle
    régression aurait demandé plus de certitude sur le mécanisme exact que ce qui a pu être
    vérifié dans le temps disponible.
  - 1 nouveau test Flutter (focus + activation clavier des lignes de notification), 107/107 tests
    Flutter au total, `flutter analyze` propre, `flutter build web` vérifié, correctif reconfirmé
    contre l'app réelle après reconstruction du conteneur.

- [x] **P19 — Question du jour personnalisée par un modèle Ollama local (optionnel).** Demandé
  directement, hors cahier des charges : un modèle IA local (gratuit, dans Docker — cohérent avec
  la contrainte "aucun service payant") pour formuler la question du jour de façon plus naturelle
  que le gabarit statique fixe ("Lequel de ces centres d'intérêt appartient vraiment à {nom} ?").
  Décision structurante avant tout code : `answer_daily_question` incrémente `Match.flame_count`
  (donc le déblocage des photos) sur la base d'une `correct_answer` vérifiable — y introduire un
  jugement LLM non déterministe aurait fragilisé le mécanisme central du produit. Le LLM n'écrit
  donc que la phrase, jamais la bonne réponse : `_build_question` (le tirage par `random.Random`
  de l'intérêt réel + des leurres) reste inchangé, et `services/question_llm.py` ne reçoit même
  pas l'intérêt correct en entrée — seulement le prénom et la bio de l'autre côté.
  Second choix structurant, pour la performance : le prompt était recalculé à chaque `GET` avec
  l'ancien gabarit statique (gratuit, volontairement non persisté pour ne jamais figer un ancien
  prénom). Un appel LLM à chaque ouverture d'écran aurait été inacceptable — `DailyQuestion` gagne
  donc une colonne `prompt` (migration `7674a5626f45`), écrite une seule fois à la création de la
  ligne, jamais recalculée sur une relecture.
  `docker-compose.yml` : service `ollama` + `ollama-init` (télécharge le modèle une fois,
  idempotent) derrière un profil `ai` optionnel, jamais démarré par défaut — `backend` n'a aucune
  dépendance dessus, donc son absence ne change rien au comportement de l'app (repli silencieux
  sur le gabarit). `OLLAMA_ENABLED=false` par défaut partout, y compris en CI et dans
  `.env.prod.example`. `question_llm.generate_personalized_prompt` ne lève jamais : désactivé,
  conteneur injoignable, dépassement de `OLLAMA_TIMEOUT_SECONDS` (3s), sortie vide/trop
  longue/sans point d'interrogation (un modèle 1B ne suit pas toujours l'instruction "pose une
  question") retombent tous sur le gabarit statique. Amorcer la génération par "Question :" en
  suffixe du prompt (plutôt que de compter sur la seule instruction système) a nettement réduit ce
  taux d'échec en test manuel — la vérification `"?" in text` reste le filet de sécurité réel.
  Vérifié en conditions réelles, pas seulement en interne : modèle `llama3.2:1b` (1,3 Go) tiré,
  deux comptes créés via le vrai flux OTP → publication → swipe, match réel créé, question du jour
  récupérée via l'endpoint HTTP réel (~2,1s à froid, question authentique générée par le modèle,
  bonne réponse noyée dans les leurres), relue une seconde fois (~11ms, confirmant l'absence de
  second appel LLM), répondue correctement, `flame_count` incrémenté sans changement de
  comportement. Remis dans l'état par défaut (flag et conteneur éteints) après vérification :
  90/90 tests pytest, `ruff check .` propre sur ce chemin par défaut.

- [x] **P20 — Question du jour : catégories ville et bio en plus des intérêts.** Demandé
  directement après P19 : le quiz ne devait pas se limiter aux centres d'intérêt. Même règle de
  sécurité non négociable qu'en P19, appliquée à deux catégories de plus — la bonne réponse reste
  toujours une vraie donnée déjà stockée, jamais une affirmation du LLM. `_eligible_categories`
  (`services/messaging.py`) construit la liste des catégories utilisables à partir du profil réel
  de l'autre côté : "interest" (inchangé), "city" (bonne réponse = la vraie ville du profil,
  leurres = d'autres villes de la liste fermée déjà posée en P9.3, `services/geo.py`), "bio"
  (bonne réponse = la bio réelle, leurres = de vraies bios d'*autres* profils publiés — jamais
  inventées, même principe que le pool `_DECOY_INTERESTS` existant). `question_llm.py` reçoit
  désormais la catégorie pour choisir la bonne instruction de formulation, et ne reçoit plus la
  bio de la personne quand la catégorie est justement "bio" (elle serait alors la réponse, pas
  juste une couleur de contexte comme pour les deux autres catégories). `MIN_BIO_DECOYS = 3`
  conditionne l'éligibilité de "bio" : si moins de 3 autres bios distinctes existent, cette
  catégorie n'est simplement pas proposée ce jour-là. Le garde 404 change de "pas d'intérêts" à
  "aucune catégorie éligible" : un profil avec seulement une ville ou seulement une bio (aucun
  intérêt) obtient désormais quand même une question.
  Un vrai bug trouvé en testant contre l'app réelle, pas en le cherchant délibérément :
  `_decoy_bios` n'avait pas de `.distinct()`, donc quand plusieurs profils publiés partageaient le
  même texte de bio, la même option pouvait apparaître plusieurs fois dans les choix proposés —
  repéré en lisant une vraie question générée qui affichait trois fois la même phrase-leurre,
  corrigé avec `.distinct()` sur la requête, et figé par un nouveau test qui vérifie
  `len(set(options)) == len(options)`.
  Vérifié en conditions réelles : plusieurs vrais matchs créés avec profils complets
  (bio + ville + intérêts), les trois catégories observées apparaître sur des matchs différents le
  même jour (la catégorie est choisie de façon déterministe par match/utilisateur/jour, donc un
  seul match ne voit jamais qu'une catégorie par jour). La qualité de formulation du LLM sur les
  nouvelles catégories s'est révélée visiblement moins fiable que sur les intérêts (une génération
  réelle en catégorie "ville" a dérivé vers un lieu absent des options proposées) — accepté comme
  la même limite déjà documentée des petits modèles : la vérification `"?"` reste un filet de
  sécurité structurel, pas une garantie de pertinence, et le gabarit statique par catégorie
  (`_FALLBACK_PROMPT_TEMPLATES`) reste le vrai plancher de qualité. `tests/helpers.py` :
  `create_match`/`create_published_user` gagnent des paramètres `bio`/`city` optionnels, sans
  rien casser des appels existants. 92/92 tests backend, `ruff check .` propre.

  **Trois lacunes corrigées après relecture à froid** (demandée explicitement — "la fonctionnalité
  est-elle logique et complète ?" — pas trouvées en la codant) :
  1. *Démarrage à froid de la catégorie "bio".* `MIN_BIO_DECOYS` exigeait des leurres réels
     (d'autres profils publiés) : quasiment inatteignable tôt dans la vie de l'app, avant qu'il y
     ait assez d'utilisateurs. `_DECOY_BIOS` (10 bios génériques statiques, même principe que
     `_DECOY_INTERESTS`) complète désormais le pool de vrais leurres, rendant "bio" éligible dès
     qu'un profil a une bio, indépendamment de la taille de la base.
  2. *Tableau du DPIA incomplet.* La ligne bio/intérêts ne mentionnait que la relecture par Ollama,
     pas la réutilisation de la bio/ville d'un profil comme option de quiz montrée à un tiers non
     apparié (déjà une donnée publique visible en découverte, donc pas une nouvelle fuite, mais une
     finalité distincte que le tableau ne reflétait pas). Corrigé dans `docs/DPIA.md`.
  3. *Catégorie jamais tracée.* `DailyQuestion` ne stockait que la réponse/les options/le prompt,
     jamais la catégorie retenue — impossible de vérifier après coup si "bio" se déclenche
     vraiment. Colonne `category` ajoutée (migration `fd8392ab076d`), écrite à la création comme le
     reste, exposée dans `DailyQuestionOut`. Nullable pour les lignes antérieures, implicitement
     "interest" dans ce cas (la seule catégorie qui existait avant P20).

  92/92 tests backend (inchangé), `ruff check .` propre, vérifié en direct contre l'app réelle
  (catégorie "bio" confirmée éligible et renvoyée dans la réponse HTTP).

- [x] **P21 — Interface de revue de modération humaine.** Premier point du backlog V2
  (`docs/V2_FEATURES.md` §2) à graduer : cahier des charges C.1/C.2 plaçait explicitement le tri
  automatique et l'interface de revue humaine en V2, le MVP consultant `Report`/`BanAppeal`/les
  notes `suspected_rancor` directement via Adminer faute de toute notion de rôle staff. Ce palier
  introduit ce rôle et remplace Adminer par un vrai outil pour ces trois files spécifiquement
  (Adminer reste l'outil pour tout le reste, sans UI dédiée).
  `User.is_staff` (bool, `False` par défaut, migration `e7bbb5321976`) — un seul niveau de droits
  élevés à distinguer, donc pas de table de rôles séparée. `api/deps.get_current_staff_user`
  suit exactement le patron de `get_current_user_even_if_banned` : passe par `user_from_token`
  (un compte staff banni perd quand même l'accès) puis 403 si `not is_staff`. Pas de flux
  applicatif pour accorder ce rôle (délibéré, comme pour le reste de la gestion des rôles) :
  Adminer, ou `backend/scripts/grant_staff.py <phone>` en raccourci.
  Trois files, chacune avec de vraies décisions qui changent l'état plutôt qu'un simple archivage :
  `POST /admin/reports/{id}/resolve` (fondé/non fondé, avec un bannissement optionnel — pas
  automatique — du compte signalé), `POST /admin/ban-appeals/{id}/resolve` (maintenu/annulé,
  annulé lève immédiatement `is_banned`), `POST /admin/flagged-ratings/{id}/review` (confirmé/levé
  sur les notes `suspected_rancor` — lever réintègre la note dans le calcul du score de confiance
  via `compute_trust_score`, sans rien à recalculer ni mettre en cache). `Rating` gagne
  `moderation_reviewed_at`/`_by`, découplés de `suspected_rancor` lui-même (qui doit rester
  mutable) pour distinguer "triée par un humain" de "toujours considérée comme rancunière".
  Chaque décision, sur les trois files, écrit une ligne dans la nouvelle table
  `moderation_actions` (staff, cible, décision, note) — journal d'audit append-only, généralisant
  ce que `docs/V2_FEATURES.md` §2 demandait pour les notes seules, et futur jeu d'entraînement réel
  pour `moderation_ml.py` une fois qu'il y aura du volume. Chaque endpoint de résolution revérifie
  que l'élément est encore `pending` avant d'écrire (409 sinon) — protection contre la course entre
  deux membres du personnel, même esprit que le `SAVEPOINT` de création de match.
  `services/moderation_ml.py` gagne `rancor_probability()` (score brut, extrait de la logique déjà
  interne à `predict_is_rancor`) pour que la fiche de détail affiche *pourquoi* une note a été
  signalée, pas seulement qu'elle l'est.
  Tableau de bord : HTML/CSS/JS statique sans dépendance ni étape de build
  (`backend/app/static/admin/`), servi par le conteneur `backend` lui-même sur `/staff` (`/admin`
  reste le préfixe de l'API — pas de collision) via `StaticFiles` dans `main.py`, cohérent avec la
  contrainte "tout tourne en Docker, aucun outillage superflu" et avec la suggestion de
  `docs/V2_FEATURES.md` §2 ("une page web à part, pas Flutter"). Connexion par le vrai flux OTP
  téléphone existant, jeton en `sessionStorage` (pas `localStorage` : fenêtre d'exposition plus
  courte pour un identifiant privilégié, au prix de reconnexions plus fréquentes). CSP stricte
  (`default-src 'self'`, aucune police/script tiers) posée à la fois en `<meta>` et, pour
  `frame-ancestors` (silencieusement ignoré via `<meta>`), via un vrai en-tête HTTP
  (`main.py`'s `staff_dashboard_security_headers`). Toute donnée utilisateur est rendue via
  `textContent`, jamais `innerHTML`. Trois onglets (Signalements / Contestations / Notes
  signalées) avec badge de comptage (`GET /admin/queue-counts`), liste → détail → formulaire de
  décision (motif obligatoire) → confirmation dans un `<dialog>` natif (piégeage de focus et
  fermeture Échap gérés par le navigateur) avant tout envoi. Accessibilité : HTML sémantique
  (`<table>`, `<button>`, `<label for>` — jamais un placeholder en guise de label, la leçon P17),
  anneau de focus visible (token `focus/ring`, jamais supprimé — la régression que P16 avait
  corrigée côté Flutter), région `aria-live` pour les résultats asynchrones, `lang="fr"`,
  navigation clavier complète des onglets (flèches gauche/droite, patron ARIA tabs standard).
  Vérifié de bout en bout contre l'app réelle, pas seulement les tests : un compte élevé en staff
  via `grant_staff.py`, connexion par navigateur réel (Playwright), signalement réel créé →
  résolu "non fondé" via l'interface (validation du motif obligatoire testée, dialogue de
  confirmation, toast de succès, retour à la liste) ; en HTTP direct, signalement fondé + banni →
  compte banni perd l'accès → contestation déposée → annulée par le staff → accès restauré,
  confirmant que les décisions de l'interface produisent les mêmes effets que le bannissement
  automatique existant. 115/115 tests backend (`tests/test_admin_moderation.py`, 15 nouveaux —
  contrôle d'accès, chaque décision par file, conflit sur double résolution, décompte des files),
  `ruff check .` propre.
  `docs/V2_FEATURES.md` §2 et `docs/DPIA.md` mis à jour pour refléter ce qui a été livré.

- [x] **P22 — Messagerie temps réel multi-instance (Redis pub/sub).** Deuxième point du backlog
  V2 (`docs/V2_FEATURES.md` §3) livré en avance sur son propre déclencheur documenté ("seulement
  une fois plusieurs instances réellement en service") — demandé directement, même schéma que
  P21. `ws/connection_manager.py`'s `ConnectionManager` était un `dict[match_id, set[WebSocket]]`
  en mémoire, correct pour un seul process backend mais aveugle entre deux instances (cahier des
  charges D.4). Nouveau service `redis:7-alpine` (`docker-compose.yml`, aucun port publié — jamais
  joignable hors du réseau compose), `backend` en dépend au démarrage (`condition:
  service_healthy`), au même titre que `db`/`minio`.
  Choix retenu après question directe (Redis vs PostgreSQL LISTEN/NOTIFY vs Centrifugo) : Redis
  pub/sub, un canal par match (`bresonne:chat:{match_id}`) — Redis fait le tri, une connexion ne
  reçoit jamais le trafic d'un autre match, pas de filtrage côté client sur un canal global.
  Conception non triviale, revue deux fois après des bugs réels trouvés en testant contre l'app,
  pas en écrivant le code : la première version gardait un unique client Redis + une unique tâche
  d'écoute partagés pour tout le process (comme le registre en mémoire qu'elle remplaçait) — cassé
  silencieusement dès que deux connexions WebSocket s'exécutent sur des event loops différents, ce
  qui arrive en pratique sous `TestClient.websocket_connect()` (utilisé par toute la suite de
  tests existante sans `with TestClient(app) as client:`, la forme qui partagerait un seul
  portail/event loop) : chaque connexion y ouvre son propre thread + event loop, et un objet
  redis-py créé sur l'un puis réutilisé depuis l'autre plante ou reste bloqué en silence. Diagnostiqué
  via `py-spy dump` sur le process de test bloqué (toutes les tâches idle en `select()`, aucun
  deadlock — juste un message jamais livré), pas en lisant le code. Corrigé en scopant un client +
  un abonnement Redis à *chaque connexion WebSocket*, jamais partagés au-delà — même principe que
  `SessionLocal()` par opération déjà établi dans `chat_ws` (P4.3), appliqué ici à Redis pour la
  même raison. Un second bug, plus subtil, a survécu à cette première correction et n'apparaissait
  qu'une fois sur plusieurs dizaines de lancements complets de la suite (jamais en lançant
  `test_messaging.py` seul) : `connect()` appelait `websocket.accept()` *avant* de terminer
  l'abonnement Redis, laissant une fenêtre où le pair côté test pouvait publier un message avant
  que cette connexion-ci n'ait fini de s'abonner — Redis ne livre jamais rétroactivement à un
  abonné pas encore enregistré. Reproduit à nouveau via `py-spy dump` (bloqué exactement sur
  `test_websocket_typing_broadcasts_to_other_participant`, le seul test à n'avoir aucun échange de
  "mise en route" avant le message qu'il vérifie), corrigé en abonnant *avant* d'accepter la
  connexion plutôt qu'après — confirmé stable sur 15 lancements complets consécutifs après coup.
  Une régression réelle trouvée au passage dans `tests/test_discovery.py` (pas la messagerie
  elle-même) : `test_match_list_reports_unread_count_from_the_other_side_only` envoyait un
  événement `"read"` puis fermait la connexion immédiatement, sans jamais attendre d'accusé de
  réception — un test déjà fragile qui ne survivait que par coïncidence de timing avec l'ancien
  code (aucun I/O asynchrone dans `connect()`), maintenant exposé par le nouveau
  `connect()`/`disconnect()` réellement asynchrones. Corrigé en attendant l'écho du broadcast
  avant de fermer, même patron déjà suivi par les autres tests WebSocket du dépôt.
  Vérifié en conditions réelles, pas seulement via les tests (qui tournent tous dans un seul
  process, donc ne peuvent jamais prouver le cas multi-instance) : deux conteneurs `backend`
  indépendants lancés côte à côte sur le même réseau Docker (sans passer par `--scale`, qui
  entre en conflit avec le port hôte déjà publié — deux conteneurs nommés directement à la
  place), un client WebSocket connecté à chacun pour le même match, message envoyé depuis
  l'instance A et reçu sur l'instance B dans les deux sens. 115/115 tests backend, `ruff check .`
  propre, 15 lancements complets consécutifs de la suite sans échec après le second correctif.
  `infra/uptime-kuma/setup.py` gagne un moniteur TCP `redis:6379`, même principe que celui déjà
  posé pour `db:5432`. `docs/V2_FEATURES.md` §3 et `docs/DPIA.md` mis à jour.

  **Test de charge réel, demandé directement après coup** ("voir les limites, si ça peut
  tenir") — `backend/scripts/load_test_messaging.py` gagne `--backend-urls` (liste séparée par
  des virgules) pour répartir délibérément les deux participants de chaque match sur deux
  instances différentes, au lieu du DNS round-robin de `backend` sous `--scale` (pas fiable pour
  garantir qu'une paire traverse vraiment le relais Redis). Un vrai bug préexistant corrigé au
  passage, sans rapport avec ce palier : ce script n'appelait jamais `POST /auth/consent` avant
  de publier un profil — l'écran de consentement RGPD a été ajouté après son écriture initiale
  (P4.3) et personne ne l'avait relancé depuis, donc chaque tentative de publication se prenait un
  403 jusqu'à ce correctif.
  Montée en charge sur deux vrais conteneurs `backend` : 100/400/800/1600 matchs concurrents
  (100 → 3200 connexions WebSocket) tous livrés à 100 %, mais une vraie limite trouvée aux
  alentours de 700-800 connexions WebSocket simultanées *par instance* :
  `redis.exceptions.ConnectionError: ... Too many open files`. Cause : ce design coûte un
  descripteur de fichier de plus par connexion WebSocket (sa propre socket Redis d'abonnement, en
  plus de la socket WS elle-même) comparé à l'ancien registre en mémoire qui n'en coûtait aucun —
  divise à peu près par deux le nombre de connexions qu'un conteneur peut tenir sous le
  `ulimit -n` par défaut de Docker (1024, hérité de l'hôte). Corrigé par `ulimits.nofile: 65536`
  sur le service `backend` (`docker-compose.yml`) — un réglage opérationnel standard, sans aucun
  inconvénient au repos, pas un changement de code applicatif. Reconfirmé propre (100 %) à 1600 et
  3200 matchs concurrents (3200 et 6400 utilisateurs) après correctif.
  Deux constats supplémentaires, ni l'un ni l'autre une régression de ce palier :
  la latence de connexion se dégrade nettement sous une rafale de connexions simultanées (p50
  environ 2,8 s à 1600 matchs, environ 5,8 s à 3200) — le coût réel d'une poignée de main Redis
  par connexion, acceptable pour une croissance organique du trafic mais un vrai risque pour une
  reconnexion de masse simultanée (ex. juste après un déploiement), à surveiller plus tard si ça
  devient une plainte réelle, pas avant ; et pousser jusqu'à 3200 créations de match concurrentes
  (6400 inscriptions via REST, pas WebSocket) a fait ressortir le `QueuePool limit of size 5
  overflow 10 reached` déjà documenté en P4.3 — la même contrainte connue, cette fois sous une
  rafale REST plutôt que des sessions WS tenues longtemps, pas une nouvelle limite introduite ici,
  et hors périmètre de ce palier (redimensionner le pool ou limiter le débit d'inscription est une
  décision distincte du relais des messages).

- [x] **P23 — Connexion par OTP email (remplace l'OTP téléphone).** Prérequis d'un test avec un
  vrai groupe d'utilisateur·rice·s : avec `DEBUG_OTP=true`, le code était renvoyé à quiconque le
  demandait, donc taper le numéro de quelqu'un d'autre suffisait à prendre son compte ; et un vrai
  SMS est payant. L'email remplace complètement le téléphone (choix produit : aucun numéro collecté,
  minimisation RGPD). Resend en SMTP en bêta/prod (offre gratuite), console ou Mailpit en local.
  Sécurité renforcée au passage, au-delà de l'existant P6.1 : code haché (HMAC à clé) au lieu d'être
  stocké en clair, table `otp_challenges` séparée (plus aucun compte créé avant une vérification
  réussie), code à usage unique, plafonds par adresse (30 s, 5/heure) et par IP (Redis), réponse et
  temps de réponse identiques qu'un compte existe ou non, et un validateur de démarrage qui refuse
  une config dangereuse hors développement (`ENVIRONMENT=beta|production`). Détail dans
  `CLAUDE.md`. Vérifié de bout en bout : vrai email reçu dans Mailpit via SMTP, parcours complet
  dans Chrome (adresse invalide refusée côté client, code, « Modifier l'adresse », connexion avec
  une casse différente retrouvant le bon compte). CGU, politique de confidentialité (+ copie in-app)
  et DPIA mises à jour (Resend nommé comme seul sous-traitant, DPA et région UE à confirmer à la
  souscription). 149/149 tests backend, 129/129 tests Flutter, `ruff`/`flutter analyze` propres.

- [x] **P24 — HTTPS sur une origine unique (Caddy) et app web sans aucune ressource tierce.**
  Choix produit : VPS chez LWS (hébergeur déjà nommé dans les mentions légales) plutôt qu'un
  tunnel, dont le fournisseur déchiffre le trafic. Un seul domaine sert l'app (`/`), l'API
  (`/api`, WebSocket compris), le tableau de bord staff (`/api/staff/`) et les photos (lectures
  signées uniquement) : plus de CORS, un certificat, un enregistrement DNS. En-têtes de sécurité
  et CSP stricte. Écrire cette CSP a révélé que l'app chargeait CanvasKit et toutes ses polices
  depuis les serveurs de Google à chaque ouverture, contrairement à ce qu'affirme la politique de
  confidentialité : tout est désormais servi par nous (polices de la charte embarquées, polices
  de secours téléchargées au build). Le bootstrap personnalisé corrige au passage un conflit
  entre le Service Worker de Flutter et celui des notifications push, sur la même portée. Vérifié
  sur la vraie configuration Caddy en local : parcours complet dans Chrome sans aucune requête
  externe ni erreur de console, IP `X-Forwarded-For` falsifiée ignorée. `docs/DEPLOYMENT.md`
  réécrit (LWS, DNS + Resend, `infra/deploy/build_web.sh`). Pas encore exécuté sur le vrai VPS
  (pas encore loué) : `provision.sh` reste relu mais non vérifié.

## Backlog V2 (hors périmètre MVP)

Liste complète, avec pour chaque point le pourquoi et une piste d'implémentation concrète :
`docs/V2_FEATURES.md`. Ce qui suit ici n'est qu'un résumé du premier point (KYC), historiquement
le seul détaillé dans ce fichier avant que `docs/V2_FEATURES.md` ne couvre tout le reste
(graduation des stubs OTP/paiement/push vers de vrais services, réentraînement du modèle de
modération, builds mobiles natives, géolocalisation réelle, et les actions de conformité DPIA
restantes — la revue de modération humaine et le scaling multi-instance de la messagerie, qui
figuraient aussi dans cette liste, sont livrés depuis P21/P22 ci-dessus).

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
