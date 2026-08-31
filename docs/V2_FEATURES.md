# Fonctionnalités restantes — V2 / MVP complet

Ce document liste tout ce qui reste réellement à construire pour dépasser le MVP actuel (phases
0-6 + post-MVP P4-P10, voir `docs/ROADMAP.md`), avec pour chaque point : pourquoi ce n'est pas
déjà fait, ce que ça demande concrètement, et une piste d'implémentation compatible avec les
patterns déjà en place dans ce dépôt. Trié par section, pas par priorité — voir la note de
priorisation à la fin.

Trois catégories, pour ne pas mélanger "le cahier des charges l'exige mais c'est hors périmètre
MVP" et "c'est juste une idée d'extension" :

- **[Spec V2]** — explicitement listé comme hors périmètre MVP dans le cahier des charges, déjà
  documenté comme tel dans ce dépôt (`CLAUDE.md`, `docs/ROADMAP.md`, `docs/DPIA.md`).
- **[Stub → réel]** — une fonctionnalité MVP existe déjà en version gratuite/locale simulée
  (cahier des charges D.11) ; ce qui manque est le vrai service payant/externe derrière.
- **[Extension]** — une idée d'amélioration produit qui n'est mandatée par aucune section connue
  du cahier des charges. À valider avant de s'y engager, contrairement aux deux premières
  catégories qui sont déjà des engagements pris.

## 1. KYC renforcé — vérification d'identité *(Spec V2)*

**Pourquoi ce n'est pas fait** : le cahier des charges (section D.6) place explicitement le KYC
par pièce d'identité en option V2, le MVP se limitant à l'OTP téléphone (`services/otp.py`).
`docs/DPIA.md` le confirme.

**Ce que ça demande** : deux voies, aucune compatible avec la contrainte "tout tourne en
Docker, gratuit/local" tant que le produit n'est pas validé :
- **FranceConnect+** (niveau de garantie substantiel/élevé, France Identité comme fournisseur
  d'identité) — flux OIDC standard côté code, mais suppose d'être accrédité "fournisseur de
  service" par l'État : personne morale, convention, homologation RGS, domaine de production en
  HTTPS. Des mois de démarches avant de pouvoir tester contre le vrai service.
- **Prestataire KYC privé** (Onfido, Veriff) — payant, accréditation en jours plutôt qu'en mois,
  mais un vrai budget récurrent.

**Comment l'implémenter (une fois l'entité juridique et le choix de fournisseur faits)** :
1. Nouveau champ `User.kyc_status` (`none` / `pending` / `verified` / `rejected`) et
   `User.kyc_verified_at`, migration Alembic classique.
2. Nouveau service `services/kyc.py` : initialise le flux (redirection OIDC ou upload de
   document selon le fournisseur), reçoit le callback/webhook, met à jour `kyc_status`.
3. Nouvel endpoint `POST /auth/kyc/callback` (ou équivalent) — jamais exposé sans vérifier la
   signature du webhook fournisseur.
4. `PublicProfileOut`/`DiscoveryCandidateOut` : ajouter un badge "identité vérifiée" distinct du
   badge "profil vérifié" actuel (`is_verified`, qui ne reflète que l'OTP) — ne jamais réutiliser
   le même champ, sémantique différente (cahier des charges A.5 Module 1 traite les deux comme
   des niveaux de confiance distincts).
5. Mobile : nouvel écran (`screens/kyc/`) déclenché depuis Paramètres, pas depuis l'onboarding —
   ne jamais bloquer la première utilisation sur un KYC qui prend des jours à traiter.

## 2. Interface de revue de modération humaine *(Spec V2)*

**Pourquoi ce n'est pas fait** : cahier des charges C.1/C.2 place explicitement le tri
automatique et l'interface de revue humaine en V2. Le MVP consulte `Report`/`BanAppeal`/les notes
signalées `suspected_rancor` directement via Adminer (`CLAUDE.md`, sections Confiance &
modération) — cohérent avec le fait que ce projet n'a aucune notion de rôle staff/admin.

**Ce que ça demande** : la vraie décision de design ici n'est pas technique mais organisationnelle
— introduire un rôle staff signifie un nouveau modèle de contrôle d'accès qui n'existe nulle part
ailleurs dans ce projet (`api/deps.py` n'a que "utilisateur authentifié" et "utilisateur banni").

**Comment l'implémenter** :
1. `User.is_staff` (bool, `False` par défaut) — le moyen le plus simple, pas de table de rôles
   séparée tant qu'il n'y a qu'un seul niveau de droits élevés à distinguer.
2. `api/deps.py` : `get_current_staff_user` (même pattern que `get_current_user`/
   `get_current_user_even_if_banned`), 403 si `not user.is_staff`.
3. Nouveau routeur `api/v1/admin.py` : `GET /admin/reports` (filtrable par `status`),
   `POST /admin/reports/{id}/resolve` (motif + décision), idem pour `BanAppeal`, et une vue en
   lecture sur les notes `suspected_rancor=True` avec le score du classifieur
   (`moderation_ml.predict_is_rancor`) pour que le staff voie *pourquoi* une note a été signalée,
   pas juste qu'elle l'a été.
4. Chaque décision de review devient un signal d'entraînement potentiel — journaliser
   `(rating_id, décision_staff)` dès le départ, ce jeu de données réel remplacera un jour le jeu
   d'entraînement écrit à la main de `moderation_ml.py` (voir point 6 plus bas).
5. Mobile/web : un dashboard staff séparé plutôt qu'une section cachée dans l'app grand public —
   probablement une page web à part (pas Flutter), plus rapide à faire évoluer pour un usage
   interne à faible trafic.

## 3. Messagerie temps réel à l'échelle (multi-instance) *(Spec V2 / scaling)*

**Pourquoi ce n'est pas fait** : `ws/connection_manager.py` est un
`dict[match_id, set[WebSocket]]` en mémoire — correct pour un seul process backend (le MVP,
cahier des charges D.11), mais deux utilisateurs connectés à deux instances différentes du
backend ne se verraient plus (cahier des charges D.4 anticipe explicitement ce palier).

**Quand s'en préoccuper** : seulement au moment de faire tourner plus d'une instance backend
(scaling horizontal réel, pas avant — ne pas anticiper ce chantier tant que le trafic ne le
justifie pas).

**Comment l'implémenter** :
1. Remplacer `ConnectionManager` par un pub/sub partagé — deux options réalistes :
   - **Redis** (`redis-py` + `pubsub()`) : chaque instance backend s'abonne au canal
     `match:{id}`, publie dessus au lieu d'itérer sur ses propres WebSockets locales. Gratuit/
     local en Docker (`redis:7-alpine`), cohérent avec la contrainte du projet.
   - **Centrifugo** (explicitement nommé par le cahier des charges D.4) : serveur de pub/sub
     dédié au temps réel, plus de fonctionnalités (présence, historique) mais une pièce d'infra
     de plus à opérer.
2. `chat_ws` (déjà refactoré en P4.3 pour ouvrir une session DB courte par opération — voir
   `CLAUDE.md`) change peu : au lieu d'itérer `manager.connections[match_id]`, publier l'événement
   sur le canal partagé ; chaque instance qui a une connexion locale pour ce match la relaie.
3. Tester avec `backend/scripts/load_test_messaging.py` (déjà existant, P4.3) contre *plusieurs*
   instances backend derrière un load balancer, pas une seule — c'est spécifiquement le scénario
   qu'un test single-instance ne peut pas révéler.

## 4. OTP par vrai SMS *(Stub → réel)*

**État actuel** : `services/otp.py` logue le code sur stdout, l'API le renvoie dans la réponse si
`DEBUG_OTP=true`.

**Comment l'implémenter** :
1. Compte chez un opérateur SMS (Twilio, Vonage, ou un opérateur français type Octopush pour de
   meilleurs taux de délivrabilité locale) — budget réel, à activer seulement après validation
   produit (contrainte explicite du projet).
2. `core/config.py` : nouveaux settings (`SMS_PROVIDER_API_KEY`, etc.), jamais en dur.
3. `services/otp.py::request_otp` : remplacer le `print()` par un appel HTTP au fournisseur ;
   garder le paramètre `DEBUG_OTP` pour continuer à permettre le développement local sans
   consommer de crédit SMS — ne jamais le supprimer, juste ne plus le mettre à `true` en prod.
4. Gérer l'échec d'envoi explicitement (fournisseur en panne, numéro invalide) — actuellement
   `request_otp` ne peut pas échouer côté fournisseur puisqu'il n'y en a pas ; un vrai appel
   réseau peut, et il ne doit jamais laisser l'utilisateur bloqué sans message clair.
5. La protection anti-brute-force posée en P6.1 (`MIN_RESEND_INTERVAL_SECONDS`,
   `MAX_OTP_ATTEMPTS`) devient encore plus importante une fois qu'un SMS a un coût réel par envoi
   — la revérifier reste valide telle quelle, aucun changement nécessaire là.

## 5. Paiement réel (StoreKit / Play Billing) *(Stub → réel)*

**État actuel** : `Subscription` et toute la logique free/premium existent réellement (Phase 5),
mais l'activation passe par `POST /subscriptions/debug-activate`, pas un vrai achat.

**Pourquoi ce n'est pas fait** : StoreKit (iOS) et Play Billing (Android) exigent une build
native publiée sur les stores respectifs — un compte développeur Apple (payant, ~100 $/an) et
Google Play (payant, frais unique) — aucun des deux n'existe pour ce projet Flutter **web only**
(voir `CLAUDE.md`, section Mobile).

**Comment l'implémenter (une fois une build store envisagée)** :
1. Ce n'est plus seulement un changement de endpoint — Flutter web ne peut pas parler à
   StoreKit/Play Billing du tout, ces API n'existent que sur les builds natives. Implique de
   sortir du "web only" (voir aussi point 8) : générer les cibles `ios`/`android` réelles
   (`flutter create` les a déjà scaffoldées mais jamais utilisées, voir `CLAUDE.md`).
2. Package `in_app_purchase` (officiel Flutter) côté mobile : initie l'achat, reçoit le reçu.
3. Backend : nouvel endpoint `POST /subscriptions/verify-receipt` qui valide le reçu auprès
   d'Apple/Google (jamais faire confiance au client sur le statut premium) avant de poser
   `Subscription.is_active = true` — remplace `debug-activate`, qui reste utile en dev/test
   (`DEBUG_OTP`-style flag pour le garder accessible uniquement hors production).
4. Webhooks App Store Server Notifications / Google RTDN pour les renouvellements/annulations
   côté serveur — sans ça, `Subscription.expires_at` ne se met à jour que quand l'utilisateur
   rouvre l'app, ce qui est fragile pour un abonnement récurrent.

## 6. Push notifications réelles *(Stub → réel, différent de P9.1)*

**État actuel** : P9.1 a ajouté de vraies notifications navigateur (`Notification` API,
`notifications/`) mais **seulement au premier plan** — la page doit être ouverte. Aucun Service
Worker n'est enregistré, donc rien n'arrive tant que l'onglet est fermé ; c'est une limite
fondamentale de web + `dart:js_interop`, pas un oubli.

**Comment l'implémenter** :
1. **Web Push** (si le web reste la cible) : enregistrer un Service Worker
   (`web/flutter_service_worker.js` généré par Flutter, à étendre ou remplacer par un vrai SW
   personnalisé), s'abonner via `PushManager.subscribe()`, envoyer les clés VAPID au backend
   (`POST /notifications/subscribe`, nouveau modèle `PushSubscription` par utilisateur), et côté
   serveur utiliser `pywebpush` pour pousser un message chiffré à l'abonnement — gratuit, aucun
   service tiers payant, mais un vrai chantier d'infra (Service Worker + endpoint de gestion des
   abonnements + clés VAPID à générer et stocker).
2. **Ou Firebase Cloud Messaging** si une build mobile native est de toute façon envisagée (point
   8) — plus simple à intégrer côté mobile (`firebase_messaging`), mais introduit une dépendance
   Google explicitement exclue par la contrainte actuelle du projet ("pas de Firebase" —
   `CLAUDE.md`), à ne lever qu'après validation produit.
3. Quel que soit le choix, les 3 points de déclenchement déjà posés en P9.1
   (`DiscoveryScreen._celebrateMatch`, `ConversationScreen`'s message listener,
   `RootShell`'s rappel quotidien) restent les bons endroits côté client — seul le mécanisme de
   livraison change, pas la logique produit qui décide quand notifier.

## 7. Réentraînement du modèle de modération sur données réelles *(DPIA, action 4)*

**État actuel** : `moderation_ml.py` s'entraîne sur un jeu de données écrit à la main
(`services/data/rating_comments_fr.csv`, 490 exemples), évalué et documenté
(`docs/MODEL_EVALUATION.md`) mais jamais vu de vraie donnée de production.

**Comment l'implémenter** :
1. Dès qu'un volume réel de notes existe (post-bêta), exporter les commentaires + le statut de
   revue humaine décidé au point 2 ci-dessus (`(comment, décision_staff)`).
2. Réentraîner via `build_pipeline()`/`load_dataset()` (déjà factorées pour ça,
   `services/moderation_ml.py`) sur ce nouveau jeu, en gardant `evaluate_moderation_model.py`
   comme protocole de validation croisée inchangé.
3. Revoir `RANCOR_PROBABILITY_THRESHOLD` (actuellement 0.6, calibré sur le jeu d'exemple) une
   fois qu'un vrai taux de faux positifs/négatifs sur données réelles est mesurable —
   `test_model_false_positive_rate_at_production_threshold` sert de garde-fou de non-régression,
   à mettre à jour avec les nouveaux chiffres de référence.

## 8. Builds mobiles natives (iOS / Android) *(Extension, prérequis de plusieurs points ci-dessus)*

**État actuel** : Flutter **web only** — `flutter create` a scaffoldé tous les dossiers de
plateforme (`android/`, `ios/`, etc.) mais aucun n'a jamais été buildé ni testé
(`docker-compose.yml`'s `mobile` service ne sert que `flutter run -d web-server`).

**Pourquoi ça compte** : plusieurs points ci-dessus (paiement réel, push réel via FCM/APNs, GPS
réel pour la distance) ne sont *possibles* que depuis une build native — le web n'a pas accès à
StoreKit/Play Billing/APNs, et l'API de géolocalisation web est moins fiable que le GPS natif.

**Comment l'implémenter** :
1. `docker compose run --rm --entrypoint bash mobile -c "flutter build apk"` /
   `flutter build ios` (nécessite un Mac pour la partie iOS — un vrai blocage d'environnement,
   pas seulement de configuration, pour cette machine de dev).
2. Revoir chaque écran pour le responsive mobile réel (la charte `docs/DESIGN_TOKENS.md` a été
   pensée web-first ; les tailles tactiles, le clavier natif, les gestes systèmes n'ont jamais
   été vérifiés en usage réel sur un écran de téléphone).
3. `image_picker`/`shared_preferences` sont déjà multiplateforme (utilisés tels quels), mais
   `dart:js_interop`/`package:web` (notifications, P9.1) ne compilent que pour le web — prévoir
   l'équivalent `flutter_local_notifications` pour les cibles natives à ce moment-là, pas avant
   (voir `notification_platform.dart`'s export conditionnel, déjà structuré pour accueillir une
   troisième implémentation par plateforme).

## 9. Géolocalisation réelle (upgrade de P9.3) *(Extension)*

**État actuel** (P9.3) : distance calculée depuis une ville choisie dans une liste fermée d'une
cinquantaine de grandes villes françaises, coordonnées approximatives statiques
(`services/geo.py`) — pas de GPS, pas de géocodage payant.

**Comment l'améliorer, si le produit le justifie** :
1. Géolocalisation GPS réelle (native, ou l'API `Geolocation` du navigateur en web) — bien plus
   précise qu'une ville, mais introduit une vraie donnée sensible (position exacte) : revoir
   `docs/DPIA.md` avant de l'ajouter, pas après.
2. Géocodage inverse pour couvrir plus que ~50 villes — un service gratuit à quota limité (Base
   Adresse Nationale, gratuite et française, couvre bien ce cas) plutôt qu'une API payante type
   Google Geocoding, cohérent avec la contrainte du projet.
3. Ne stocker que des coordonnées arrondies (quelques centaines de mètres de précision) même en
   passant au GPS réel — le rayon de recherche n'a jamais eu besoin d'une précision plus fine, et
   minimiser la donnée stockée reste le principe déjà appliqué partout ailleurs dans ce projet
   (âge jamais exposé en date de naissance brute, etc.).

## 10. Conformité & exploitation avant bêta externe *(DPIA, actions 1/2/3/5 — non-code)*

Déjà listées dans `docs/DPIA.md`, rappelées ici pour la vue d'ensemble — aucune n'est du code :

1. **Alerting Uptime Kuma** : configurer une vraie notification (email/webhook) sur les 3
   moniteurs déjà posés (P0) — sans ça la supervision existe mais personne n'est prévenu.
2. **Réplication des sauvegardes** : `backup_data` (P0, `infra/backup/`) doit être répliqué hors
   de l'hôte Docker local dès le passage en VPS de production (rclone/rsync vers un second
   emplacement physique).
3. **CGU / politique de confidentialité** : rédaction et publication, hors périmètre code —
   nécessaire avant toute collecte de données sur de vrais utilisateurs externes.
4. **Vrais secrets** : générer un vrai `JWT_SECRET` et un vrai `MINIO_KMS_SECRET_KEY` avant tout
   déploiement hors poste de dev — les valeurs actuelles dans `.env`/`.env.example` sont
   explicitement des valeurs de dev, jamais à réutiliser telles quelles.

## Note de priorisation

Pas d'ordre imposé ici, mais un ordre de dépendance naturel si le produit avance vers une vraie
bêta externe :

1. D'abord la conformité (§10) — c'est un prérequis légal, pas une option, dès qu'un vrai
   utilisateur externe touche l'app.
2. Puis les stubs qui bloquent une vraie bêta (§4 OTP SMS en premier — sans ça, aucun utilisateur
   externe ne peut même s'inscrire ; §7 le réentraînement suit naturellement une fois qu'il y a du
   volume réel).
3. Le reste (KYC, modération humaine, paiement réel, push réel, scaling multi-instance, builds
   natives) dépend directement de la traction produit observée pendant cette bêta — les
   construire avant d'avoir ce signal serait le genre de travail spéculatif que ce projet a
   justement évité jusqu'ici (voir la contrainte "gratuit/local jusqu'à validation",
   `CLAUDE.md`).
