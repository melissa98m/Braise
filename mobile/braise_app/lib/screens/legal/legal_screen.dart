import 'package:flutter/material.dart';

import '../../theme/braise_tokens.dart';

/// Contenu affiché ici mis à jour manuellement en même temps que
/// `docs/legal/CGU.md`/`POLITIQUE_CONFIDENTIALITE.md`, sources de référence pour une relecture
/// juridique — les deux doivent rester cohérents si l'un change. Texte en dur (pas d'asset
/// Markdown chargé au runtime) : ce projet n'a pas de pipeline d'assets, et un texte aussi court
/// ne le justifie pas.
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
        'opérateur tiers pendant cette phase. L\'abonnement Braise+ est un stub gratuit : aucun '
        'paiement réel n\'est traité. Vos données peuvent être réinitialisées sans préavis '
        'pendant cette phase de test.',
  ),
  _LegalSection(
    'Éligibilité',
    "Réservé aux personnes majeures (18 ans ou plus), vérifié à la création du profil. Une "
        'seule inscription par personne.',
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
        'un droit de recours : contester directement depuis l\'application.',
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
        'calculé), genre/préférences/ville si vous les renseignez (filtres facultatifs), photos '
        'privées et messages (le cœur du service), notes/commentaires/signalements (score de '
        'confiance et sécurité de la communauté). Rien de plus : aucune géolocalisation précise, '
        'aucune photo publique de votre visage.',
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

class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('CGU & confidentialité'),
          bottom: const TabBar(
            tabs: [Tab(text: 'CGU'), Tab(text: 'Confidentialité')],
          ),
        ),
        body: const TabBarView(
          children: [
            _LegalDocument(sections: _cguSections),
            _LegalDocument(sections: _privacySections),
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
