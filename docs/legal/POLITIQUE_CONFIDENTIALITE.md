# Politique de confidentialité — Bresonne

**Version bêta — document de travail.** Reflète fidèlement ce que le code fait réellement
aujourd'hui (voir `docs/DPIA.md`, l'analyse d'impact technique dont ce document est la version
lisible côté utilisateur·rice — les deux doivent rester cohérents si l'un change). **À faire
relire par un·e professionnel·le du droit avant toute ouverture au public au-delà d'un cercle
restreint de bêta-testeur·se·s.**

Dernière mise à jour : 22 septembre 2026.

Nous avons conçu Bresonne avec le principe de minimisation des données : nous cherchons à ne
collecter et utiliser que les informations nécessaires au fonctionnement des fonctionnalités
proposées.

## 1. Qui traite vos données

Les responsables du traitement sont **Loris Gonzales** et **Melissa Mangione**, éditeurs de
Bresonne — voir les [mentions légales](./MENTIONS_LEGALES.md) pour leurs coordonnées complètes.

Contact relatif aux données personnelles : bresonne@hotmail.com.

## 2. Quelles données, pourquoi, combien de temps

| Donnée | Pourquoi | Base légale | Conservée jusqu'à |
|---|---|---|---|
| Numéro de téléphone + code de vérification | Créer et sécuriser votre compte (seul identifiant) | Exécution du contrat | Suppression du compte (anonymisé ensuite) |
| Bio, centres d'intérêt, avatar généré | Votre profil public, le matching, et la question quotidienne du jeu des flammes (bio/ville/intérêts servent d'options réelles, bonnes ou leurres, proposées à l'*autre* participant d'un match — y compris à un utilisateur non apparié quand sa bio est piochée comme leurre, déjà visible de la même façon en découverte) | Exécution du contrat | Suppression du compte |
| Date de naissance | Vérifier que vous avez 18 ans, calculer l'âge affiché (jamais la date elle-même) | Exécution du contrat, obligation légale (protection des mineurs) | Suppression du compte |
| Genre et genre recherché (facultatifs) — la combinaison des deux relève de l'orientation sexuelle, une donnée sensible au sens RGPD | Filtres de base de la découverte que vous choisissez d'activer | Consentement explicite et dédié, recueilli séparément des CGU à l'inscription (case à cocher spécifique, jamais pré-cochée ni groupée avec les autres) | Suppression du compte |
| Préférences d'âge, ville recherchée (facultatifs) | Filtres de découverte que vous choisissez d'activer | Consentement (facultatif — rien n'est filtré si vous ne renseignez rien) | Suppression du compte |
| Position GPS ponctuelle, uniquement si vous appuyez sur « Utiliser ma position » | Retrouver automatiquement la ville la plus proche dans notre liste fermée d'une cinquantaine de grandes villes françaises, sans la saisir à la main | Consentement (permission de votre navigateur, demandée avec une explication avant l'invite système) | Non conservée — seule la ville qui en résulte est enregistrée, comme si vous l'aviez choisie vous-même dans la liste |
| Photos privées | Se révéler à un match une fois débloqué | Exécution du contrat | Suppression du compte |
| Messages échangés | La messagerie de vos matchs | Exécution du contrat | Suppression du compte (voir « Suppression de compte » plus bas — la conversation reste lisible pour l'autre personne) |
| Notes et commentaires sur vos échanges | Le score de confiance affiché aux autres | Intérêt légitime (sécurité de la communauté) | Conservés (ils font partie de l'historique de confiance d'un tiers) |
| Signalements déposés ou reçus | Modération, sécurité | Intérêt légitime / obligation légale | Conservés |
| Journal des accès à des photos privées d'autrui | Traçabilité en cas de litige | Obligation légale | Conservé |
| Données techniques (adresse IP, informations sur l'appareil, système d'exploitation, journaux techniques, informations de connexion) | Fonctionnement et sécurité de l'application | Intérêt légitime | Durée limitée, nécessaire à la sécurité |

Par défaut, aucune géolocalisation précise n'est utilisée : vous choisissez une ville dans une
liste fermée. Bresonne n'a pas vocation à afficher votre position GPS précise aux autres
utilisateur·rice·s, et lorsque cela est techniquement possible, nous cherchons à ne conserver que
l'information nécessaire au fonctionnement de cette fonctionnalité plutôt qu'une position précise
permanente. L'autorisation de localisation peut être gérée dans les paramètres de votre appareil.

Ce que nous ne collectons **pas** : aucune photo publique de votre visage (le profil public
n'affiche qu'un avatar généré, jamais une photo), jamais votre date de naissance brute affichée à
qui que ce soit d'autre que vous.

## 3. Orientation sexuelle : donnée particulièrement protégée

Bresonne ne demande pas directement votre « orientation sexuelle » comme champ de profil : elle
peut être révélée par la combinaison de votre genre déclaré et du genre que vous recherchez,
utilisée pour les filtres de base de la découverte. Il s'agit d'une donnée personnelle relevant
d'une catégorie particulière au sens du RGPD (article 9).

Ce traitement repose sur votre consentement explicite, recueilli séparément des CGU et de la
présente politique, dans une case à part de l'écran de consentement, jamais pré-cochée ni groupée
avec les autres. Vous pouvez à tout moment retirer ce consentement en laissant ces champs vides
dans votre profil ; le retrait peut entraîner l'impossibilité d'utiliser les filtres de découverte
correspondants. Nous ne vendons pas cette information et ne la transmettons pas à des partenaires
publicitaires. Elle n'est rendue accessible aux autres utilisateur·rice·s qu'au strict nécessaire
au fonctionnement de la découverte, jamais publiée au-delà.

## 4. Comment nous recueillons votre consentement

À l'inscription (et pour tout compte n'étant pas encore passé par cet écran), vous confirmez
séparément, via 4 cases distinctes et non pré-cochées : votre majorité, les CGU, la présente
politique, et le traitement de votre genre et de vos préférences de recherche (article 3
ci-dessus). Chaque consentement est horodaté côté serveur, pour rester opposable en cas de
contrôle. Vous pouvez à tout moment cesser d'utiliser les filtres de genre/recherche en les
laissant vides dans votre profil.

## 5. À qui vos données sont-elles transmises

Vos données peuvent être accessibles, lorsque cela est nécessaire, à Loris Gonzales et Melissa
Mangione, à des prestataires techniques et d'hébergement intervenant pour le compte de Bresonne
(voir « Hébergement » ci-dessous), et aux autorités compétentes lorsque la loi l'impose. Nous ne
vendons pas vos données personnelles et ne les utilisons actuellement pas à des fins de publicité
ciblée par des tiers.

Pendant la phase de bêta actuelle, aucun sous-traitant commercial externe n'est utilisé : pas de
fournisseur SMS réel (vérification simulée), pas de Firebase/Google, pas de service de modération
externe — tout tourne sur notre propre infrastructure. Vos photos et messages ne sont jamais
utilisés pour entraîner un modèle autrement que sur des données déjà collectées avec votre
consentement d'utilisation du service (le modèle de détection de commentaires abusifs n'analyse
que le texte des notes, jamais vos messages privés ; le modèle local, optionnel, de formulation de
la question quotidienne ne lit que votre prénom et votre bio, jamais votre identité complète, votre
téléphone ou vos messages, et reste hébergé sur notre propre infrastructure).

## 6. Hébergement et infrastructure

Bresonne utilise notamment des services d'hébergement et d'infrastructure fournis par **LWS
(Ligne Web Services)**. Pendant la phase de bêta actuelle, l'application tourne en réalité sur une
infrastructure de développement/test, et non sur l'hébergement de production prévu — voir les
[mentions légales](./MENTIONS_LEGALES.md). Les données susceptibles d'être stockées ou traitées
par les infrastructures techniques sont protégées dans les conditions prévues par les mesures
décrites à la section « Sécurité » ci-dessous.

## 7. Sécurité

- Vos photos privées sont chiffrées au repos.
- Les liens de téléchargement de vos photos expirent au bout de quelques minutes — jamais un accès
  permanent.
- Une photo privée n'est accessible à quelqu'un d'autre que vous que si vous avez mutuellement
  débloqué ce match, et chaque accès est journalisé.
- Un compte supprimé ou suspendu perd immédiatement l'accès à toute donnée, pas seulement à la
  fonctionnalité qui a déclenché la suspension.
- Les mots de passe et identifiants d'authentification sont stockés sous une forme sécurisée et
  non en clair. Les accès aux données sont limités aux personnes et prestataires qui en ont besoin
  pour leurs missions.

## 8. Vos droits

Conformément au RGPD, vous disposez notamment d'un droit d'accès, de rectification, d'effacement,
de limitation du traitement, d'opposition, de portabilité (lorsque ce droit est applicable), et du
droit de retirer un consentement lorsqu'un traitement repose sur celui-ci.

- **Accès et portabilité** : téléchargez l'intégralité de vos données (profil, matchs, messages
  envoyés, notes données et reçues, signalements) depuis Paramètres → Exporter mes données.
- **Effacement** : supprimez votre compte à tout moment depuis Paramètres. Ce que ça fait
  précisément :
  - votre profil public est vidé, vos photos privées supprimées, votre numéro de téléphone
    remplacé par un identifiant anonyme ;
  - vos messages restent visibles pour vos interlocuteur·rice·s (leur conversation est aussi leur
    donnée), mais leur contenu est remplacé par un texte générique — votre message d'origine n'est
    plus lisible par personne ;
  - les matchs, notes et signalements impliquant votre compte restent en base, parce qu'ils
    portent aussi les droits d'un tiers (l'historique de confiance d'une autre personne, par
    exemple) — ils sont simplement détachés de votre identité ;
  - une conservation peut néanmoins subsister lorsqu'elle est nécessaire au respect d'une
    obligation légale, à l'établissement, l'exercice ou la défense d'un droit en justice, ou à la
    sécurité de la plateforme.
- **Opposition/rectification** : modifiez votre profil à tout moment depuis l'application ;
  contactez-nous pour toute donnée que l'application ne permet pas de corriger vous-même.
- **Exercice de vos droits** : bresonne@hotmail.com. Nous pouvons demander des informations
  permettant de vérifier votre identité lorsque cela est nécessaire à la protection des données.
- **Réclamation** : vous pouvez saisir la Commission nationale de l'informatique et des libertés
  (CNIL, cnil.fr) si vous estimez que vos droits n'ont pas été respectés après nous avoir
  contactés.

## 9. Visibilité du profil

Certaines informations sont destinées à être visibles par d'autres utilisateur·rice·s afin de
permettre le fonctionnement de Bresonne (profil public, score de confiance). Nous cherchons à
limiter la visibilité des informations sensibles au strict nécessaire pour le fonctionnement des
fonctionnalités concernées — votre orientation sexuelle, en particulier, n'est jamais rendue
publiquement accessible au-delà de ce qui est nécessaire à la découverte et de vos propres choix
de filtres (voir article 3).

## 10. Notifications

Si vous activez les notifications dans Paramètres, votre navigateur vous demandera une permission
explicite — jamais activées sans votre action. Elles ne fonctionnent que lorsque l'application est
ouverte dans un onglet (pas de notification si l'application est complètement fermée pendant la
phase de bêta).

## 11. Cookies et stockage local

L'application stocke uniquement votre jeton de connexion et vos préférences d'affichage (thème
clair/sombre, préférences de notification) sur votre propre appareil — aucun cookie publicitaire
ni traceur tiers. Les traceurs soumis au consentement, le cas échéant à l'avenir, ne seraient
utilisés qu'après recueil de ce consentement.

## 12. Transferts internationaux

Certains prestataires techniques pourraient être amenés à traiter des données depuis des pays
situés en dehors de l'Espace économique européen. Aucun n'est utilisé à ce jour pendant la bêta
(voir article 5) ; si cela devenait le cas, les garanties requises par la réglementation seraient
mises en place et cette politique serait mise à jour en conséquence.

## 13. Modifications

Cette politique peut évoluer, notamment pendant la phase de bêta ; la version en vigueur est
toujours celle publiée dans l'application (Paramètres → CGU & confidentialité). En cas de
modification importante, vous serez informé·e dans des conditions appropriées.

## 14. Contact

Pour toute question relative à la protection de vos données personnelles ou au fonctionnement
général de Bresonne : bresonne@hotmail.com.
