import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_exception.dart';
import '../../models/discovery.dart';
import '../../models/moderation.dart';
import '../../models/public_profile.dart';
import '../../state/app_services.dart';
import '../../theme/braise_tokens.dart';
import '../../widgets/avatar_sigil.dart';
import '../../widgets/braise_page_route.dart';
import '../../widgets/flame_diamonds.dart';
import '../../widgets/sign_shapes.dart';
import '../paywall/paywall_screen.dart';
import '../settings/settings_screen.dart';
import 'profile_setup_screen.dart';

/// Écran 07 — le score se lit de trois façons (chiffre, barres, mot), jamais un simple
/// rouge/vert (cahier des charges, accessibilité). Les outils RGPD (export / suppression) vivent
/// désormais dans Paramètres (icône réglages ci-dessous), pas ici : cet écran reste centré sur
/// les informations de confiance du profil, pas sur les réglages de compte.
class ProfileTrustScreen extends StatefulWidget {
  const ProfileTrustScreen({super.key});

  @override
  State<ProfileTrustScreen> createState() => _ProfileTrustScreenState();
}

class _ProfileTrustScreenState extends State<ProfileTrustScreen> {
  PublicProfile? _profile;
  TrustScore? _trust;
  List<MatchSummary> _matches = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final services = context.read<AppServices>();
    try {
      final results = await Future.wait([
        services.profilesApi.getMyPublicProfile(),
        services.moderationApi.getTrustScore(),
        services.discoveryApi.getMatches(),
      ]);
      if (!mounted) return;
      setState(() {
        _profile = results[0] as PublicProfile;
        _trust = results[1] as TrustScore;
        _matches = results[2] as List<MatchSummary>;
        _loading = false;
      });
    } on ApiException catch (e) {
      // Sans ce catch, une erreur transitoire sur n'importe lequel des 3 appels laissait cet
      // onglet bloqué sur un spinner infini : `_loading` ne repassait jamais à `false`, et rien
      // n'était scrollable pour déclencher un nouveau tirer-pour-rafraîchir — l'utilisateur
      // n'avait aucun moyen de réessayer sans redémarrer l'app (RootShell garde cet écran monté
      // en permanence via IndexedStack, `initState` ne se relance jamais).
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  int get _totalFlames => _matches.fold(0, (sum, m) => sum + m.flameCount);

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator(semanticsLabel: 'Chargement en cours.')));

    final tokens = BraiseTokens.of(context);
    final textTheme = Theme.of(context).textTheme;

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Moi')),
        // ListView (pas juste Center) : reste scrollable donc tirer-pour-rafraîchir marche même
        // depuis l'état d'erreur, seul moyen de réessayer sans redémarrer l'app.
        body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(BraiseSpacing.xxl),
            children: [
              Text(_error!, style: textTheme.bodyMedium?.copyWith(color: tokens.erreur)),
            ],
          ),
        ),
      );
    }

    final profile = _profile!;
    final trust = _trust!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Moi'),
        actions: [
          IconButton(
            onPressed: () =>
                Navigator.of(context).push(braiseRoute(context, const SettingsScreen())),
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Paramètres',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(BraiseSpacing.xxl),
          children: [
            Row(
              children: [
                AvatarSigil(spec: profile.avatar, size: 72),
                const SizedBox(width: BraiseSpacing.lg),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(profile.displayName, style: textTheme.titleLarge),
                    const SizedBox(height: BraiseSpacing.xs),
                    Wrap(
                      spacing: BraiseSpacing.sm,
                      children: [
                        // `excludeSemantics` : `Chip` porte par défaut une sémantique de type
                        // "checkbox" même sans onTap ni onDeleted, trompeur pour un lecteur
                        // d'écran sur un badge de statut purement informatif.
                        if (profile.isVerified)
                          Semantics(
                            label: 'Profil vérifié',
                            excludeSemantics: true,
                            child: Chip(
                              avatar: SignSquareCore(color: tokens.foiInk, size: 14),
                              label: const Text('VÉRIFIÉ'),
                              backgroundColor: tokens.foiInk.withValues(alpha: 0.1),
                              side: BorderSide(color: tokens.foiInk),
                            ),
                          ),
                        if (profile.isPremium)
                          Semantics(
                            label: 'Abonné Braise+',
                            excludeSemantics: true,
                            child: Chip(
                              label: const Text('BRAISE+'),
                              backgroundColor: tokens.alerte.withValues(alpha: 0.12),
                              side: BorderSide(color: tokens.alerte),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: BraiseSpacing.xxl),
            Container(
              padding: const EdgeInsets.all(BraiseSpacing.xl),
              decoration: BoxDecoration(
                color: tokens.surface1,
                border: Border.all(color: tokens.borderHairline),
                borderRadius: BorderRadius.circular(BraiseRadii.keyCard),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SCORE DE CONFIANCE',
                    style: textTheme.labelSmall?.copyWith(letterSpacing: 13 * 0.14),
                  ),
                  const SizedBox(height: BraiseSpacing.xs),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        trust.score?.toString() ?? '—',
                        style: textTheme.labelSmall?.copyWith(fontSize: 38, color: tokens.inkPrimary),
                      ),
                      Text('/100', style: textTheme.bodyMedium),
                      const Spacer(),
                      if (trust.score != null)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _TrustBars(score: trust.score!),
                            if (trust.label != null) ...[
                              const SizedBox(height: BraiseSpacing.sm),
                              Text(
                                trust.label!,
                                style: textTheme.labelSmall?.copyWith(color: tokens.inkPrimary),
                              ),
                            ],
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: BraiseSpacing.sm),
                  Text(
                    'Calculé sur ${trust.ratingCount} avis'
                    '${trust.flaggedCount > 0 ? ' (${trust.flaggedCount} exclus par prudence)' : ''}.',
                    style: textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(height: BraiseSpacing.xl),
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    label: 'FLAMMES',
                    semanticValue: '$_totalFlames',
                    // Les diamants restent un motif décoratif plafonné à 5 (docs/DESIGN_TOKENS.md),
                    // mais le vrai total est toujours affiché en chiffres au-dessus — sans lui,
                    // au-delà de 5 flammes cumulées l'affichage "5/5 rempli" ne permet plus de
                    // distinguer quelqu'un qui vient d'atteindre 5 de quelqu'un qui en a 50.
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$_totalFlames',
                          style: textTheme.labelSmall?.copyWith(fontSize: 22, color: tokens.inkPrimary),
                        ),
                        const SizedBox(height: BraiseSpacing.xs),
                        FlameDiamonds(filled: _totalFlames.clamp(0, 5), total: 5),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: BraiseSpacing.md),
                Expanded(
                  child: _StatCard(label: 'ÉCHANGES ACTIFS', value: '${_matches.length}'),
                ),
              ],
            ),
            const SizedBox(height: BraiseSpacing.xxl),
            OutlinedButton(
              onPressed: () => Navigator.of(context)
                  .push(braiseRoute(context, const ProfileSetupScreen()))
                  .then((_) => _load()),
              child: const Text('Modifier mon profil public'),
            ),
            const SizedBox(height: BraiseSpacing.sm),
            ElevatedButton(
              onPressed: () =>
                  Navigator.of(context).push(braiseRoute(context, const PaywallScreen())),
              style: ElevatedButton.styleFrom(backgroundColor: tokens.alerte, foregroundColor: tokens.surfaceRoot),
              child: const Text('Braise+'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 5 barres croissantes, pleines jusqu'à `score / 20` puis en contour — le score se lit par
/// forme et par hauteur, jamais par une seule couleur (docs/DESIGN_TOKENS.md, accessibilité).
class _TrustBars extends StatelessWidget {
  const _TrustBars({required this.score});

  final int score;

  @override
  Widget build(BuildContext context) {
    final tokens = BraiseTokens.of(context);
    final filled = (score / 20).round();
    final duration = MediaQuery.of(context).disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 300);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 1; i <= 5; i++)
          Padding(
            padding: const EdgeInsets.only(left: 5),
            child: AnimatedContainer(
              duration: duration,
              curve: Curves.easeOutCubic,
              width: 7,
              height: 16 + i * 6,
              decoration: BoxDecoration(
                color: i <= filled ? tokens.foiInk : null,
                border: i <= filled ? null : Border.all(color: tokens.foiInk, width: 1.75),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  // `semanticValue` couvre le cas `child` (widget libre, ex. les diamants FLAMMES) où il n'y a
  // pas de `value` textuel simple à lire — sans lui, `container: true` ci-dessous forcerait quand
  // même une frontière sémantique, mais avec un contenu vide/décoratif plutôt qu'un vrai chiffre.
  const _StatCard({required this.label, this.value, this.child, this.semanticValue});

  final String label;
  final String? value;
  final Widget? child;
  final String? semanticValue;

  @override
  Widget build(BuildContext context) {
    final tokens = BraiseTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      // `container: true` : sans frontière explicite, les deux `_StatCard` voisines (FLAMMES,
      // ÉCHANGES ACTIFS) se lisaient comme une seule phrase ("7 FLAMMES 2 ÉCHANGES ACTIFS") côté
      // lecteur d'écran — trouvé en inspectant l'arbre d'accessibilité réel de l'app, pas en
      // relisant le code.
      container: true,
      label: '${semanticValue ?? value} $label',
      // Sans ça, le label explicite ci-dessus s'ajouterait à la lecture des `Text` descendants
      // au lieu de la remplacer — double annonce ("7 FLAMMES" puis "7" puis "FLAMMES").
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(BraiseSpacing.lg),
        decoration: BoxDecoration(
          color: tokens.surface1,
          border: Border.all(color: tokens.borderHairline),
          borderRadius: BorderRadius.circular(BraiseRadii.card),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            child ?? Text(value!, style: textTheme.labelSmall?.copyWith(fontSize: 22, color: tokens.inkPrimary)),
            const SizedBox(height: BraiseSpacing.sm),
            Text(label, style: textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}
