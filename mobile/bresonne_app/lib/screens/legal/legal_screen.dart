import 'package:flutter/material.dart';

import '../../theme/braise_tokens.dart';

/// Contenu affiché ici mis à jour manuellement en même temps que
/// `docs/legal/CGU.md`/`POLITIQUE_CONFIDENTIALITE.md`/`MENTIONS_LEGALES.md`/
/// `REGLES_COMMUNAUTE.md`, sources de référence pour une relecture juridique — les quatre
/// doivent rester cohérents si l'un change. Texte en dur (pas d'asset Markdown chargé au
/// runtime) : ce projet n'a pas de pipeline d'assets, et un texte aussi court ne le justifie
/// pas. Nom de marque : « Bresonne » (renommé depuis « Braise », voir `pubspec.yaml`/
/// `docker-compose.yml`) — le vocabulaire thématique braise/flamme (le verbe "braiser", les
/// tokens `braiseInk`/`braiseFill`/`braiseTint`, les classes `Braise*` internes) reste inchangé
/// à dessein : ce n'est pas le nom du produit, voir `docs/DESIGN_TOKENS.md`.
class _LegalSection {
  const _LegalSection(this.title, this.body);
  final String title;
  final String body;
}

const _betaNotice =
    'Version bêta — document de travail, pas encore relu par un·e professionnel·le du droit. '
    'Reflète fidèlement ce que l\'app fait réellement aujourd\'hui.';

const _cguSections = <_LegalSection>[
  _LegalSection(
    'Statut bêta',
    "L'application tourne sur une infrastructure de test, sans garantie de disponibilité "
        'continue. La vérification par SMS est simulée : le code s\'affiche directement dans '
        'l\'app plutôt que d\'être envoyé par un vrai SMS — aucun numéro n\'est communiqué à un '
        'opérateur tiers pendant cette phase. L\'abonnement Bresonne+ est un stub gratuit : '
        'aucun paiement réel n\'est traité. Vos données peuvent être réinitialisées sans '
        'préavis pendant cette phase de test.',
  ),
  _LegalSection(
    'Éligibilité',
    "Réservé aux personnes majeures (18 ans ou plus) : confirmé dès l'inscription (case à "
        'cocher dédiée), puis vérifié une seconde fois via votre date de naissance à la création '
        'du profil. Une seule inscription par personne.',
  ),
  _LegalSection(
    'Fonctionnement du service',
    'Profil public (nom, bio, intérêts, avatar généré — jamais une photo) visible en découverte. '
        'Profil privé (jusqu\'à 3 photos chiffrées) révélé uniquement à un match mutuel, '
        'progressivement, via les flammes gagnées en répondant à la question quotidienne — une '
        'mauvaise réponse n\'entraîne aucune pénalité. Un match n\'existe que si les deux '
        'personnes se sont mutuellement choisies.',
  ),
  _LegalSection(
    'Confiance et modération',
    'Après un échange, chacun·e peut noter l\'autre (commentaire obligatoire) ; ces notes '
        'alimentent un score de confiance visible des autres. Un signalement peut être déposé à '
        'tout moment. Un compte peut être suspendu automatiquement si son score tombe à zéro '
        'après au moins 3 notes reçues — jamais sur 1 ou 2 avis isolés. Un compte suspendu garde '
        'un droit de recours : contester directement depuis l\'application. Le détail des '
        'comportements interdits et des mesures possibles est dans nos règles de communauté, '
        'onglet suivant.',
  ),
  _LegalSection(
    'Prudence et arnaques',
    "Bresonne n'exige jamais d'argent en dehors de l'abonnement Bresonne+. Toute demande "
        "d'argent, d'informations bancaires ou de documents d'identité venant d'un autre "
        "utilisateur·rice est interdite et à signaler. Avant une première rencontre : lieu "
        'public, prévenir un proche, prudence sur les informations partagées trop tôt.',
  ),
  _LegalSection(
    'Suppression de compte',
    'Supprimable à tout moment depuis Paramètres. Anonymise votre profil et votre numéro ; ne '
        'supprime pas les messages déjà lus par vos interlocuteur·rice·s ni les notes/'
        'signalements déjà émis ou reçus, qui portent aussi les droits d\'un tiers — détail '
        'complet dans la politique de confidentialité.',
  ),
  _LegalSection(
    'Responsabilité',
    'Service en phase de test : l\'exactitude des profils publiés et l\'issue d\'une rencontre '
        'ne sont pas garanties. Chaque utilisateur·rice reste seul·e responsable de son '
        'comportement, y compris lors de rencontres organisées en dehors de l\'application.',
  ),
];

const _privacySections = <_LegalSection>[
  _LegalSection(
    'Quelles données, pourquoi',
    'Téléphone (créer/sécuriser votre compte), bio/intérêts/avatar (profil public), date de '
        'naissance (vérifier vos 18 ans — jamais affichée telle quelle, seulement l\'âge '
        'calculé), genre et genre recherché si vous les renseignez (donnée sensible : leur '
        'combinaison relève de l\'orientation sexuelle, traitée avec votre consentement exprès '
        'et dédié, recueilli séparément à l\'inscription), préférences d\'âge/ville facultatives, '
        'photos privées et messages (le cœur du service), notes/commentaires/signalements '
        '(score de confiance et sécurité de la communauté). Aucune géolocalisation précise par '
        'défaut (une ville choisie dans une liste) — si vous appuyez sur « Utiliser ma '
        'position », votre position sert uniquement, sur l\'instant, à retrouver la ville la '
        'plus proche, jamais enregistrée telle quelle. Aucune photo publique de votre visage.',
  ),
  _LegalSection(
    'À qui vos données sont transmises',
    'À personne d\'autre. Aucun sous-traitant commercial externe pendant la bêta : pas de '
        'fournisseur SMS réel, pas de Firebase/Google, pas de service de modération externe — '
        'tout tourne sur notre propre infrastructure.',
  ),
  _LegalSection(
    'Sécurité',
    'Photos privées chiffrées au repos. Liens de téléchargement valables quelques minutes '
        'seulement. Une photo n\'est accessible à quelqu\'un d\'autre que si le match est '
        'mutuellement débloqué, et chaque accès est journalisé. Un compte supprimé ou suspendu '
        'perd immédiatement l\'accès à toute donnée.',
  ),
  _LegalSection(
    'Vos droits',
    'Export complet de vos données depuis Paramètres. Suppression de compte à tout moment : '
        'profil vidé, photos supprimées, numéro anonymisé ; vos messages restent visibles pour '
        'vos interlocuteur·rice·s mais leur contenu original n\'est plus lisible par personne ; '
        'les matchs/notes/signalements restent en base (ils portent aussi les droits d\'un '
        'tiers) mais détachés de votre identité. Réclamation possible auprès de la CNIL '
        '(cnil.fr).',
  ),
  _LegalSection(
    'Notifications et stockage local',
    'Les notifications ne s\'activent que sur votre action explicite, avec la permission de '
        'votre navigateur — jamais sans confirmation, et seulement quand l\'app est ouverte. '
        'Seuls votre jeton de connexion et vos préférences d\'affichage sont stockés sur votre '
        'appareil, jamais de cookie publicitaire ni de traceur tiers.',
  ),
];

const _mentionsSections = <_LegalSection>[
  _LegalSection(
    'Éditeurs',
    'Bresonne (« Avec qui résonnes-tu ? ») est éditée par Loris Gonzales (13011 Marseille) et '
        'Melissa Mangione (38190 Champ-près-Froges), agissant en leur nom propre — aucune '
        'structure juridique constituée à ce jour. Contact : bresonne@hotmail.com.',
  ),
  _LegalSection(
    'Hébergement',
    "L'infrastructure de production est prévue chez LWS (Ligne Web Services, 10 rue "
        'Penthièvre, 75008 Paris). Pendant la bêta actuelle, l\'application tourne en réalité '
        "sur une infrastructure de développement/test, pas encore sur cet hébergement — cette "
        'mention sera mise à jour au premier déploiement réel.',
  ),
  _LegalSection(
    'Propriété intellectuelle',
    'Le nom « Bresonne », son identité visuelle, son interface et ses contenus sont protégés '
        'par les dispositions applicables en matière de propriété intellectuelle. Toute '
        'reproduction ou exploitation non autorisée est interdite, sauf dans les limites '
        'prévues par la loi.',
  ),
];

const _communitySections = <_LegalSection>[
  _LegalSection(
    'Sois toi-même, respecte les autres',
    'Utilise tes propres photos et informations : usurpation et faux profils sont interdits. '
        "Insultes, menaces, propos haineux, discriminations, humiliations et harcèlement ne "
        'sont pas tolérés — le désaccord n\'est pas un problème, le manque de respect l\'est. '
        'Un refus doit être respecté : si une personne ne veut plus échanger, arrête de la '
        'contacter.',
  ),
  _LegalSection(
    'Pas d\'arnaques, pas de sollicitations non désirées',
    "Ne demande jamais d'argent aux autres utilisateur·rice·s (faux investissements, fausses "
        'urgences, virements, chantage). Évite de communiquer trop vite ton adresse, tes '
        'informations bancaires ou tes documents d\'identité. Toute sollicitation sexuelle non '
        'souhaitée est interdite ; Bresonne est exclusivement réservée aux 18 ans et plus, et '
        'tout contenu sexuel impliquant un mineur est strictement interdit.',
  ),
  _LegalSection(
    'Vraies photos, signalement et blocage',
    'Tu dois disposer des droits sur les photos publiées dans ton profil privé — jamais celles '
        "d'une autre personne. Tu peux signaler un profil, un message ou un comportement "
        'contraire à ces règles depuis l\'écran de signalement. Une fonctionnalité de blocage '
        'sera proposée dès qu\'elle sera disponible.',
  ),
  _LegalSection(
    'Nos mesures',
    'En cas de violation, Bresonne peut notamment supprimer un contenu, envoyer un '
        'avertissement, limiter certaines fonctionnalités, suspendre ou supprimer un compte — '
        'selon la gravité et les circonstances. Bresonne doit rester un espace de rencontre, '
        'pas un espace de pression, de fraude ou de harcèlement.',
  ),
];

class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, this.initialTab = 0});

  /// 0 = CGU, 1 = Confidentialité, 2 = Mentions légales, 3 = Règles de communauté — les 2
  /// premiers index sont figés (déjà référencés par `ConsentScreen`), les 2 nouveaux sont
  /// ajoutés à la suite plutôt qu'insérés, pour ne pas décaler les appels existants. Permet à un
  /// lien précis (ex: la case CGU ou la case confidentialité de `ConsentScreen`) d'ouvrir
  /// directement le bon onglet plutôt que de toujours retomber sur CGU.
  final int initialTab;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      initialIndex: initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Informations légales'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'CGU'),
              Tab(text: 'Confidentialité'),
              Tab(text: 'Mentions légales'),
              Tab(text: 'Règles de communauté'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _LegalDocument(sections: _cguSections),
            _LegalDocument(sections: _privacySections),
            _LegalDocument(sections: _mentionsSections),
            _LegalDocument(sections: _communitySections),
          ],
        ),
      ),
    );
  }
}

class _LegalDocument extends StatelessWidget {
  const _LegalDocument({required this.sections});

  final List<_LegalSection> sections;

  @override
  Widget build(BuildContext context) {
    final tokens = BraiseTokens.of(context);
    final textTheme = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.all(BraiseSpacing.xxl),
      children: [
        Container(
          padding: const EdgeInsets.all(BraiseSpacing.md),
          decoration: BoxDecoration(
            color: tokens.surface1,
            border: Border.all(color: tokens.borderHairline),
            borderRadius: BorderRadius.circular(BraiseRadii.card),
          ),
          child: Text(
            _betaNotice,
            style: textTheme.bodyMedium?.copyWith(color: tokens.inkSecondary),
          ),
        ),
        for (final section in sections) ...[
          const SizedBox(height: BraiseSpacing.xl),
          Text(section.title, style: textTheme.titleMedium),
          const SizedBox(height: BraiseSpacing.sm),
          Text(section.body, style: textTheme.bodyLarge),
        ],
        const SizedBox(height: BraiseSpacing.xxl),
      ],
    );
  }
}
