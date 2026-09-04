# AIPD / DPIA — Braise

Analyse d'impact relative à la protection des données, engagée dès la phase de cadrage comme
l'exige le cahier des charges (section A.9 et dépendance critique B.3), avant l'ouverture de toute
bêta avec des utilisateurs réels. Document de travail — à revoir avant chaque évolution touchant
aux données sensibles (nouveau champ profil, nouvelle finalité de traitement, changement
d'hébergeur).

## 1. Contexte et champ d'application

Braise traite des données susceptibles d'être qualifiées de sensibles au sens large : photos de
profil privé, contenu de conversations privées, numéro de téléphone (identifiant d'authentification
via OTP), commentaires de notation et de signalement. Aucune donnée biométrique n'est traitée à ce
stade (le KYC MVP est un OTP téléphone/email — cahier des charges D.6 ; le KYC renforcé par pièce
d'identité est explicitement hors périmètre MVP, réservé à une option V2 — piste envisagée :
France Identité / FranceConnect+, voir `docs/ROADMAP.md` § Backlog V2 pour les contraintes
d'accréditation qui la reportent au-delà du MVP).

Périmètre : l'ensemble du backend `backend/app/` et du stockage associé (Postgres, MinIO). Le
frontend Flutter ne fait que consommer l'API ; il ne stocke localement que le JWT de session
(`shared_preferences`, côté appareil de l'utilisateur — hors périmètre de cette AIPD, qui porte sur
les traitements côté serveur).

## 2. Description des traitements

| Donnée | Finalité | Base légale | Où (code) | Conservation |
|---|---|---|---|---|
| Téléphone + code OTP | Authentification, unicité de compte | Exécution du contrat (CGU) | `models/user.py`, `services/otp.py` | Jusqu'à suppression de compte (anonymisé ensuite) |
| Bio, centres d'intérêt, avatar-sigil | Profil public, matching ; question du jour du quiz flammes — bio/ville/intérêts servent d'options réelles (bonne réponse comme leurres, voir `services/messaging.py::_eligible_categories`) proposées à l'*autre* participant d'un match, y compris un utilisateur non apparié quand sa bio est piochée comme leurre pour le quiz de quelqu'un d'autre (déjà visible de la même façon en découverte, même audience) ; prénom + bio (jamais quand la bio est elle-même le sujet du quiz) également relus par le modèle Ollama local pour personnaliser la formulation (optionnel, off par défaut — voir ci-dessous) | Exécution du contrat | `models/profile.py` (`PublicProfile`), `services/messaging.py`, `services/question_llm.py` | Jusqu'à suppression de compte |
| Date de naissance | Calcul de l'âge affiché, contrôle 18+ | Exécution du contrat / obligation légale (protection des mineurs, A.9) | `models/profile.py`, schéma `PublicProfileOut` (n'expose jamais la date brute, seulement l'âge calculé) | Jusqu'à suppression de compte |
| Genre déclaré + préférences de découverte (genre recherché, tranche d'âge) | Filtres de base du feed de découverte (A.5) | Exécution du contrat, consentement (champs facultatifs) | `models/profile.py` (`PublicProfile.gender`/`looking_for_gender`/`age_min`/`age_max`) | Jusqu'à suppression de compte |
| Photos privées | Déblocage du profil physique après flammes | Exécution du contrat | `models/profile.py` (`PrivateProfile.photo_keys`), fichiers dans MinIO | Jusqu'à suppression de compte |
| Messages | Messagerie du match | Exécution du contrat | `models/message.py` | Jusqu'à suppression de compte (contenu de l'auteur supprimé anonymisé, pas le fil pour l'autre participant) |
| Notes + commentaires | Score de confiance, modération | Intérêt légitime (sécurité de la plateforme) | `models/rating.py`, `services/moderation.py` | Conservés (nécessaires à l'historique de confiance d'un tiers) |
| Signalements | Modération, sécurité | Intérêt légitime / obligation légale | `models/report.py` | Conservés pour l'historique de modération |
| Journal d'accès aux photos | Traçabilité RGPD des divulgations entre utilisateurs | Obligation légale (auditabilité) | `models/photo_access_log.py` — uniquement les accès *à autrui*, jamais à ses propres photos | Conservé |

Aucune donnée n'est transmise à un tiers commercial : pas de SMS provider réel, pas de Firebase, pas
de service de modération externe (cahier des charges D.11 — tout est auto-hébergé/interne dès le
MVP, voir aussi `CLAUDE.md` section « Stubs »). Le seul flux sortant en V2 sera la commission de
paiement des stores Apple/Google (D.8), qui ne transite par aucune donnée personnelle sensible.
Le modèle Ollama (question du jour personnalisée, optionnel — voir `CLAUDE.md` section
messagerie) reste dans cette même catégorie « aucun tiers » : conteneur auto-hébergé sur le réseau
Docker interne (`ollama:11434`, jamais exposé publiquement), aucune donnée ne quitte
l'infrastructure. Il ne lit que le prénom et la bio (déjà des données de profil public), jamais
l'identité complète, le téléphone ou les messages.

## 3. Principes fondamentaux

- **Minimisation.** `PublicProfileOut` n'expose que l'âge calculé, jamais la date de naissance
  brute — évite la désanonymisation croisée (cahier des charges A.6, exigence explicite). Un swipe
  vers un profil inexistant et un swipe vers un profil non publié renvoient la même 404
  (`services/discovery.py`), pour ne pas laisser fuiter l'existence d'un compte.
- **Consentement / information.** CGU + politique de confidentialité rédigées et affichées dans
  l'app (voir action 3, § 5 plus bas) ; l'écran d'onboarding pédagogique (`ConceptIntroScreen`,
  plan P1) reste le bon endroit pour la pédagogie du concept, distincte du consentement RGPD
  posé par les CGU.
- **Sécurité par construction.**
  - Chiffrement au repos des photos privées (SSE-S3 via `MINIO_KMS_SECRET_KEY`, clé locale — voir
    `services/storage.py`), vérifiable avec `mc stat` (`Encryption: SSE-S3`).
  - URLs de téléchargement de photos signées à courte durée de vie (`presigned_get_url`), jamais
    d'accès direct au bucket.
  - Accès aux photos d'autrui gated sur `Match.unlocked_at` (403 sinon) et systématiquement
    journalisé (`PhotoAccessLog`) — mais uniquement l'accès à *autrui*, la consultation de ses
    propres photos n'est pas un événement de divulgation à auditer.
  - JWT vérifié à chaque requête protégée (`api/deps.user_from_token`), y compris sur le WebSocket
    de messagerie (le token voyage en query string faute d'en-tête possible côté navigateur sur un
    handshake WS — accepté après vérification, jamais accepté-puis-fermé).
  - Un compte banni ou supprimé (`is_banned` / `deleted_at`) perd l'accès à *tous* les endpoints
    protégés dès la vérification du token, pas seulement à l'endpoint qui a déclenché le
    bannissement/la suppression.
- **Droits des personnes.**
  - Portabilité : `GET /auth/me/export` (`services/account.export_my_data`) — export JSON complet
    (profil, matches, messages envoyés, notes données/reçues, signalements déposés). Les octets des
    photos ne sont pas inclus dans l'export (redondant avec `/profiles/me/private`), seules leurs
    clés le sont.
  - Effacement : `DELETE /auth/me` (`services/account.delete_my_account`) — anonymisation, pas un
    cascade destructif : photos supprimées de MinIO, profil public vidé, téléphone remplacé par un
    tombstone `deleted-{uuid}`, messages de l'auteur remplacés par un placeholder (la conversation
    reste lisible pour l'autre participant — c'est aussi sa donnée). Les lignes `Match`/`Rating`/
    `Report` impliquant ce compte restent, car elles portent aussi les droits d'un tiers.

## 4. Étude des risques

| Risque | Donnée concernée | Mesures déjà en place | Résiduel |
|---|---|---|---|
| Accès illégitime aux photos privées | Photos | Chiffrement au repos, URLs signées courtes, gating sur déblocage mutuel, journal d'accès | Faible — dépend de la robustesse du JWT/secret (`JWT_SECRET` doit être un vrai secret en prod, pas la valeur de dev) |
| Perte de données (panne serveur, corruption) | Tout | **Comblé par ce palier P0** : sauvegardes Postgres + réplication photos, testées par restauration réelle (voir `infra/backup/`) | Résiduel tant que le volume de sauvegarde n'est pas répliqué hors du même hôte Docker (à faire au moment du passage en VPS de prod, D.7) |
| Ré-identification via le profil public | Bio, intérêts, avatar | Pas de photo réelle en public, pas de date de naissance brute exposée | Faible, à revalider si de nouveaux champs sont ajoutés au profil public |
| Rancune / abus du système de notation | Commentaires de notation | Détection combinée règle + modèle ML (`services/moderation_ml.py`), exclusion du score plutôt que sanction directe | Modéré — modèle entraîné sur un jeu de données jouet, à réentraîner sur données réelles de bêta avant d'en faire un signal fort |
| Bannissement automatique à tort | Score de confiance | Seuil `MIN_RATINGS_FOR_AUTO_BAN = 3` (pas de ban sur 1-2 avis). **Comblé (P1.1)** : `BanAppeal` + `api/deps.get_current_user_even_if_banned` + `BanAppealScreen` — un compte banni peut désormais déposer une contestation et voir son statut, revue via Adminer | Résiduel : la revue reste manuelle (pas de délai de traitement garanti côté produit) |
| Disponibilité / supervision | Tout | **Comblé (P0 + P12.2)** : Uptime Kuma sur backend/DB/MinIO, compte admin et 3 moniteurs posés par script (`infra/uptime-kuma/setup.py`), les 3 confirmés UP, alerte Discord configurée et testée avec succès (`test_notification` → `Sent Successfully.`) | Faible — supervision et alerte toutes deux en place et vérifiées de bout en bout |

## 5. Actions restant à mener avant une bêta avec des utilisateurs externes

1. ~~Configurer une notification réelle (email ou webhook) sur les moniteurs Uptime Kuma~~ — fait :
   compte admin, 3 moniteurs et alerte Discord (`infra/uptime-kuma/setup.py`, P12.2), scriptés
   plutôt que posés à la main, notification de test envoyée et reçue avec succès.
2. Répliquer `backup_data` hors de l'hôte Docker local dès le passage en VPS de production
   (rclone/rsync vers un second emplacement physique, D.7).
3. ~~Rédiger et publier les CGU / la politique de confidentialité côté produit~~ — fait :
   `docs/legal/CGU.md` et `docs/legal/POLITIQUE_CONFIDENTIALITE.md`, affichées dans l'app
   (`screens/legal/legal_screen.dart`, liées depuis `WelcomeScreen` et Paramètres). **Reste à
   faire** : les deux sont explicitement marquées "version bêta, pas encore relue par un
   juriste" — à faire relire avant toute ouverture au-delà d'un cercle restreint de
   bêta-testeur·se·s, et à compléter avec le nom/l'entité réel·le de l'éditeur (actuellement un
   placeholder `[Éditeur]`).
4. Réentraîner `moderation_ml.py` dès que la bêta produit un premier volume réel de commentaires.
5. Générer un vrai `JWT_SECRET` et un vrai `MINIO_KMS_SECRET_KEY` avant tout déploiement hors
   poste de dev — les valeurs actuelles dans `.env` sont explicitement des valeurs de dev.

## 6. Suivi

À revoir : à chaque nouvelle donnée personnelle collectée, avant l'ouverture de la bêta fermée
(jalon « Go/No-go bêta », `docs/ROADMAP.md`), puis à chaque changement d'hébergeur ou de sous-traitant.
