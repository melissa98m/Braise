import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/subscription.dart';
import '../../state/app_services.dart';
import '../../theme/braise_tokens.dart';
import '../../widgets/sign_shapes.dart';

/// Écran 08 — Braise+ vend du temps de qualité, jamais l'accès aux photos : l'activation ne
/// débloque jamais un profil directement (cahier des charges, positionnement anti-superficialité).
/// `debug-activate` est un stub gratuit/local (pas de StoreKit/Play Billing — voir CLAUDE.md).
class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  SubscriptionStatus? _status;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final status = await context.read<AppServices>().subscriptionsApi.me();
    if (!mounted) return;
    setState(() {
      _status = status;
      _loading = false;
    });
  }

  Future<void> _activate() async {
    final status = await context.read<AppServices>().subscriptionsApi.debugActivate();
    if (!mounted) return;
    setState(() => _status = status);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Braise+ activé (stub local — aucun paiement réel).')),
    );
  }

  Future<void> _cancel() async {
    final status = await context.read<AppServices>().subscriptionsApi.cancel();
    if (!mounted) return;
    setState(() => _status = status);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final tokens = BraiseTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    final status = _status!;

    return Scaffold(
      appBar: AppBar(title: const Text('Braise+')),
      body: Padding(
        padding: const EdgeInsets.all(BraiseSpacing.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PulsingDiamond(color: tokens.alerte),
            const SizedBox(height: BraiseSpacing.md),
            Text('Plus de questions. Pas plus de raccourcis.', style: textTheme.displayLarge),
            const SizedBox(height: BraiseSpacing.lg),
            Text(
              "Braise+ n'achète jamais le déblocage d'un profil privé. Il vous donne plus de "
              'matière pour mériter la confiance.',
              style: textTheme.bodyLarge?.copyWith(color: tokens.inkSecondary),
            ),
            const SizedBox(height: BraiseSpacing.xl),
            const _Feature(text: 'Filtres avancés pour la découverte'),
            const _Feature(text: 'Badge Braise+ visible sur votre profil public'),
            const _Feature(text: 'Détail de votre score de confiance'),
            const SizedBox(height: BraiseSpacing.xl),
            if (status.isPremium)
              Container(
                padding: const EdgeInsets.all(BraiseSpacing.lg),
                decoration: BoxDecoration(
                  color: tokens.foiInk.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(BraiseRadii.card),
                  border: Border.all(color: tokens.foiInk),
                ),
                child: Text(
                  status.cancelAtPeriodEnd
                      ? 'Actif jusqu\'au ${_formatDate(status.expiresAt!)} (résilié, pas de renouvellement).'
                      : 'Actif jusqu\'au ${_formatDate(status.expiresAt!)}.',
                  style: textTheme.bodyLarge,
                ),
              ),
            const Spacer(),
            if (!status.isPremium)
              ElevatedButton(
                onPressed: _activate,
                style: ElevatedButton.styleFrom(
                  backgroundColor: tokens.alerte,
                  foregroundColor: tokens.surfaceRoot,
                ),
                child: const Text('Activer Braise+'),
              )
            else if (!status.cancelAtPeriodEnd)
              OutlinedButton(onPressed: _cancel, child: const Text('Résilier')),
            const SizedBox(height: BraiseSpacing.sm),
            Text(
              "Sans engagement · l'app reste entièrement utilisable gratuitement.",
              textAlign: TextAlign.center,
              style: textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) => '${date.day}/${date.month}/${date.year}';
}

class _Feature extends StatelessWidget {
  const _Feature({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = BraiseTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: BraiseSpacing.sm),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: tokens.surface1,
          border: Border.all(color: tokens.borderHairline),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SignSquareOutline(color: tokens.alerte, size: 22, strokeWidth: 1.75),
            const SizedBox(width: BraiseSpacing.md),
            Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyLarge)),
          ],
        ),
      ),
    );
  }
}

/// Halo de braise animé (`@keyframes braisePulse` de la maquette) : léger scale + fondu en boucle,
/// désactivé si l'utilisateur préfère un mouvement réduit.
class _PulsingDiamond extends StatefulWidget {
  const _PulsingDiamond({required this.color});
  final Color color;

  @override
  State<_PulsingDiamond> createState() => _PulsingDiamondState();
}

class _PulsingDiamondState extends State<_PulsingDiamond> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.of(context).disableAnimations) return;
      _controller.repeat(reverse: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_controller.value);
        return Opacity(
          opacity: 0.85 + 0.15 * t,
          child: Transform.scale(scale: 1 + 0.08 * t, child: child),
        );
      },
      child: SignDiamond(color: widget.color, size: 26),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
