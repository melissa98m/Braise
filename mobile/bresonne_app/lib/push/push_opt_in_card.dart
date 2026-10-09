import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../state/app_services.dart';
import '../theme/braise_tokens.dart';
import 'push_availability.dart';

/// Pré-permission (« soft ask ») des notifications push, comme dans une app mobile native : notre
/// propre carte explique ce qu'on y gagne, et l'invite système n'apparaît que si la personne
/// accepte ici. Un refus dans l'invite système est quasi définitif (le navigateur ne la réaffiche
/// plus) ; un « Plus tard » ici ne coûte rien et la carte reviendra.
///
/// Affichée en tête d'Échanges (MatchesListScreen), donc seulement une fois qu'il existe au moins
/// un match — le moment où être prévenu·e d'un message a une valeur évidente. Sur iPhone/iPad
/// dans Safari, le Web Push n'existe qu'après « Sur l'écran d'accueil » : la carte guide alors cet
/// ajout au lieu de proposer une permission impossible (PushAvailability.needsInstall).
class PushOptInCard extends StatefulWidget {
  const PushOptInCard({super.key});

  static const snoozedUntilKey = 'braise_push_optin_snoozed_until';

  @override
  State<PushOptInCard> createState() => _PushOptInCardState();
}

class _PushOptInCardState extends State<PushOptInCard> {
  PushAvailability? _availability;
  bool _snoozed = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final availability = context.read<AppServices>().pushSubscriptionService.availability;
    final prefs = await SharedPreferences.getInstance();
    final until = DateTime.tryParse(prefs.getString(PushOptInCard.snoozedUntilKey) ?? '');
    if (!mounted) return;
    setState(() {
      _availability = availability;
      _snoozed = until != null && DateTime.now().isBefore(until);
    });
  }

  Future<void> _snooze(Duration duration) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PushOptInCard.snoozedUntilKey, DateTime.now().add(duration).toIso8601String());
    if (mounted) setState(() => _snoozed = true);
  }

  Future<void> _enable() async {
    final services = context.read<AppServices>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    final enabled = await services.pushSubscriptionService.enable(
      services.notificationsApi,
      services.notificationsService.requestPermission,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _availability = services.pushSubscriptionService.availability;
    });
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          enabled
              ? 'Notifications activées sur cet appareil.'
              : 'Notifications non autorisées — modifiable dans les réglages de votre navigateur.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final availability = _availability;
    final show =
        !_snoozed &&
        (availability == PushAvailability.canAsk || availability == PushAvailability.needsInstall);
    if (!show) return const SizedBox.shrink();

    final tokens = BraiseTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    final needsInstall = availability == PushAvailability.needsInstall;

    return Padding(
      padding: const EdgeInsets.only(bottom: BraiseSpacing.lg),
      child: Container(
        padding: const EdgeInsets.all(BraiseSpacing.lg),
        decoration: BoxDecoration(
          color: tokens.surface1,
          border: Border.all(color: tokens.braiseInk),
          borderRadius: BorderRadius.circular(BraiseRadii.card),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ne laissez pas une braise s\'éteindre', style: textTheme.titleMedium),
            const SizedBox(height: BraiseSpacing.sm),
            Text(
              needsInstall
                  ? 'Sur iPhone, les notifications demandent d\'ajouter Bresonne à votre écran '
                        'd\'accueil : touchez le bouton Partager de Safari, puis « Sur l\'écran '
                        'd\'accueil », et ouvrez Bresonne depuis cette icône.'
                  : 'Soyez prévenu·e d\'un nouveau match, d\'un message ou de votre question du '
                        'jour, même application fermée. Le contenu de vos messages n\'apparaît '
                        'jamais dans une notification.',
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: BraiseSpacing.md),
            Wrap(
              spacing: BraiseSpacing.sm,
              runSpacing: BraiseSpacing.sm,
              children: needsInstall
                  ? [
                      TextButton(
                        onPressed: () => _snooze(const Duration(days: 14)),
                        child: const Text('Compris'),
                      ),
                    ]
                  : [
                      ElevatedButton(
                        onPressed: _busy ? null : _enable,
                        child: const Text('Activer'),
                      ),
                      TextButton(
                        onPressed: _busy ? null : () => _snooze(const Duration(days: 7)),
                        child: const Text('Plus tard'),
                      ),
                    ],
            ),
          ],
        ),
      ),
    );
  }
}
