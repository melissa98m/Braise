import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/subscription.dart';
import '../../state/app_services.dart';
import '../../theme/braise_tokens.dart';

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
            Icon(Icons.diamond_outlined, color: tokens.alerte, size: 28),
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
      child: Row(
        children: [
          Icon(Icons.check_box_outlined, color: tokens.alerte, size: 20),
          const SizedBox(width: BraiseSpacing.sm),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyLarge)),
        ],
      ),
    );
  }
}
