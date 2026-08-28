import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/discovery.dart';
import '../../models/moderation.dart';
import '../../models/public_profile.dart';
import '../../state/app_services.dart';
import '../../theme/braise_tokens.dart';
import '../../widgets/avatar_sigil.dart';
import '../../widgets/braise_page_route.dart';
import '../../widgets/flame_diamonds.dart';
import '../onboarding/otp_screen.dart';
import '../paywall/paywall_screen.dart';
import 'profile_setup_screen.dart';

/// Écran 07 — le score se lit de trois façons (chiffre, barres, mot), jamais un simple
/// rouge/vert (cahier des charges, accessibilité). Regroupe aussi les outils RGPD de la Phase 5
/// (export / suppression), qui n'avaient sinon aucune surface visible dans l'app.
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final services = context.read<AppServices>();
    final userId = services.authController.userId!;
    final results = await Future.wait([
      services.profilesApi.getMyPublicProfile(),
      services.moderationApi.getTrustScore(userId),
      services.discoveryApi.getMatches(),
    ]);
    if (!mounted) return;
    setState(() {
      _profile = results[0] as PublicProfile;
      _trust = results[1] as TrustScore;
      _matches = results[2] as List<MatchSummary>;
      _loading = false;
    });
  }

  int get _totalFlames => _matches.fold(0, (sum, m) => sum + m.flameCount);

  Future<void> _exportData() async {
    final services = context.read<AppServices>();
    await services.apiClient.get('/auth/me/export');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Export généré côté serveur (droit à la portabilité, RGPD).')),
    );
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer votre compte ?'),
        content: const Text(
          'Votre profil et vos photos privées seront effacés. Vos échanges avec vos matchs '
          'restent visibles pour eux, sans votre nom. Action irréversible.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final services = context.read<AppServices>();
    await services.apiClient.delete('/auth/me');
    await services.authController.signOut();
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushAndRemoveUntil(braiseRoute(context, const OtpScreen()), (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final tokens = BraiseTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    final profile = _profile!;
    final trust = _trust!;

    return Scaffold(
      appBar: AppBar(title: const Text('Moi')),
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
                        if (profile.isPremium)
                          Chip(
                            label: const Text('BRAISE+'),
                            backgroundColor: tokens.alerte.withValues(alpha: 0.12),
                            side: BorderSide(color: tokens.alerte),
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
                    child: FlameDiamonds(filled: _totalFlames.clamp(0, 5), total: 5),
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
            const SizedBox(height: BraiseSpacing.xxl),
            Text('Vos données', style: textTheme.titleMedium),
            const SizedBox(height: BraiseSpacing.sm),
            OutlinedButton(onPressed: _exportData, child: const Text('Exporter mes données')),
            const SizedBox(height: BraiseSpacing.sm),
            OutlinedButton(
              onPressed: _deleteAccount,
              style: OutlinedButton.styleFrom(
                foregroundColor: tokens.erreur,
                side: BorderSide(color: tokens.erreur),
              ),
              child: const Text('Supprimer mon compte'),
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 1; i <= 5; i++)
          Padding(
            padding: const EdgeInsets.only(left: 5),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
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
  const _StatCard({required this.label, this.value, this.child});

  final String label;
  final String? value;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final tokens = BraiseTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Container(
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
    );
  }
}
