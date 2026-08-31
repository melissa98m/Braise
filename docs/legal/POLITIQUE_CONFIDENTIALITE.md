# Politique de confidentialité — Braise

**Version bêta — document de travail.** Reflète fidèlement ce que le code fait réellement
aujourd'hui (voir `docs/DPIA.md`, l'analyse d'impact technique dont ce document est la version
lisible côté utilisateur·rice — les deux doivent rester cohérents si l'un change). **À faire
relire par un·e professionnel·le du droit avant toute ouverture au public au-delà d'un cercle
restreint de bêta-testeur·se·s.**

Dernière mise à jour : 31 août 2026.

## Qui traite vos données

[Éditeur — nom/raison sociale à renseigner], responsable de traitement au sens du RGPD.
Contact : [adresse e-mail à renseigner].

## Quelles données, pourquoi, combien de temps

| Donnée | Pourquoi | Base légale | Conservée jusqu'à |
|---|---|---|---|
| Numéro de téléphone + code de vérification | Créer et sécuriser votre compte (seul identifiant) | Exécution du contrat | Suppression du compte (anonymisé ensuite) |
| Bio, centres d'intérêt, avatar généré | Votre profil public, le matching | Exécution du contrat | Suppression du compte |
| Date de naissance | Vérifier que vous avez 18 ans, calculer l'âge affiché (jamais la date elle-même) | Exécution du contrat, obligation légale (protection des mineurs) | Suppression du compte |
| Genre, préférences de recherche, ville (facultatifs) | Filtres de découverte que vous choisissez d'activer | Consentement (facultatif — rien n'est filtré si vous ne renseignez rien) | Suppression du compte |
| Photos privées | Se révéler à un match une fois débloqué | Exécution du contrat | Suppression du compte |
| Messages échangés | La messagerie de vos matchs | Exécution du contrat | Suppression du compte (voir « Suppression de compte » plus bas — la conversation reste lisible pour l'autre personne) |
| Notes et commentaires sur vos échanges | Le score de confiance affiché aux autres | Intérêt légitime (sécurité de la communauté) | Conservés (ils font partie de l'historique de confiance d'un tiers) |
| Signalements déposés ou reçus | Modération, sécurité | Intérêt légitime / obligation légale | Conservés |
| Journal des accès à des photos privées d'autrui | Traçabilité en cas de litige | Obligation légale | Conservé |

Ce que nous ne collectons **pas** : aucune donnée de géolocalisation précise (une ville choisie
dans une liste, pas votre position réelle), aucune photo publique de votre visage, jamais votre
date de naissance brute affichée à qui que ce soit d'autre que vous.

## À qui vos données sont-elles transmises

À personne d'autre. Aucun sous-traitant commercial externe pendant la bêta : pas de fournisseur
SMS réel (vérification simulée), pas de Firebase/Google, pas de service de modération externe —
tout tourne sur notre propre infrastructure. Vos photos et messages ne sont jamais utilisés pour
entraîner un modèle autrement que sur des données déjà collectées avec votre consentement
d'utilisation du service (le modèle de détection de commentaires abusifs n'analyse que le texte
des notes, jamais vos messages privés).

## Sécurité

- Vos photos privées sont chiffrées au repos.
- Les liens de téléchargement de vos photos expirent au bout de quelques minutes — jamais un accès
  permanent.
- Une photo privée n'est accessible à quelqu'un d'autre que vous que si vous avez mutuellement
  débloqué ce match, et chaque accès est journalisé.
- Un compte supprimé ou suspendu perd immédiatement l'accès à toute donnée, pas seulement à la
  fonctionnalité qui a déclenché la suspension.

## Vos droits

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
    exemple) — ils sont simplement détachés de votre identité.
- **Opposition/rectification** : modifiez votre profil à tout moment depuis l'application ;
  contactez-nous pour toute donnée que l'application ne permet pas de corriger vous-même.
- **Réclamation** : vous pouvez saisir la CNIL (cnil.fr) si vous estimez que vos droits ne sont pas
  respectés.

## Notifications

Si vous activez les notifications dans Paramètres, votre navigateur vous demandera une permission
explicite — jamais activées sans votre action. Elles ne fonctionnent que lorsque l'application est
ouverte dans un onglet (pas de notification si l'application est complètement fermée pendant la
phase de bêta).

## Cookies / stockage local

L'application stocke uniquement votre jeton de connexion et vos préférences d'affichage
(thème clair/sombre, préférences de notification) sur votre propre appareil — aucun cookie
publicitaire ni traceur tiers.

## Modifications

Cette politique peut évoluer pendant la phase de bêta ; la version en vigueur est toujours celle
publiée dans l'application (Paramètres → CGU & confidentialité).
