import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_exception.dart';
import '../../models/moderation.dart';
import '../../state/app_services.dart';
import '../../theme/braise_tokens.dart';
import '../../widgets/braise_page_route.dart';
import '../onboarding/otp_screen.dart';

/// Écran atteint uniquement quand AuthController.status == AuthStatus.banned (voir main.dart) —
/// la seule chose qu'un compte banni peut encore faire (cahier des charges A.9 : "possibilité de
/// contestation humaine"). Avant ce palier, un compte banni était simplement déconnecté sans
/// explication ni recours, ce qui ne satisfaisait pas l'exigence du cahier des charges.
class BanAppealScreen extends StatefulWidget {
  const BanAppealScreen({super.key});

  @override
  State<BanAppealScreen> createState() => _BanAppealScreenState();
}

class _BanAppealScreenState extends State<BanAppealScreen> {
  final _messageController = TextEditingController();
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  BanAppeal? _latestAppeal;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final appeals = await context.read<AppServices>().moderationApi.getMyBanAppeals();
      if (!mounted) return;
      setState(() {
        _latestAppeal = appeals.isEmpty ? null : appeals.first;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _submit() async {
    final message = _messageController.text.trim();
    if (message.length < 10) {
      setState(() => _error = 'Expliquez votre situation en quelques mots (10 caractères min.).');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final appeal = await context.read<AppServices>().moderationApi.fileBanAppeal(message);
      if (!mounted) return;
      setState(() {
        _latestAppeal = appeal;
        _messageController.clear();
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _signOut() async {
    final services = context.read<AppServices>();
    await services.authController.signOut();
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushAndRemoveUntil(braiseRoute(context, const OtpScreen()), (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = BraiseTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    final appeal = _latestAppeal;
    final showForm = appeal == null || !appeal.isPending;
    final crossfadeDuration = MediaQuery.of(context).disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 280);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Compte suspendu'),
        automaticallyImplyLeading: false,
        actions: [
          TextButton(onPressed: _signOut, child: const Text('Se déconnecter')),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(semanticsLabel: 'Chargement en cours.'))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(BraiseSpacing.xxl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Votre compte a été suspendu',
                    style: textTheme.headlineMedium,
                  ),
                  const SizedBox(height: BraiseSpacing.sm),
                  Text(
                    'Le score de confiance de ce compte est tombé à zéro après plusieurs notes '
                    'négatives concordantes. Vous pouvez contester cette décision — une personne '
                    'de l\'équipe l\'examinera.',
                    style: textTheme.bodyMedium,
                  ),
                  const SizedBox(height: BraiseSpacing.xxl),
                  // Le passage "formulaire" -> "contestation en cours d'examen" (juste après un
                  // envoi réussi) était un remplacement instantané — un fondu croisé le rend
                  // lisible comme une vraie transition d'état, pas un flash de contenu.
                  AnimatedSwitcher(
                    duration: crossfadeDuration,
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeOutCubic,
                    child: Column(
                      key: ValueKey('${appeal?.id}|${appeal?.status}|$showForm'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (appeal != null) _AppealStatusCard(appeal: appeal),
                        if (appeal != null) const SizedBox(height: BraiseSpacing.xxl),
                        if (showForm) ...[
                          Text(
                            appeal == null
                                ? 'EXPLIQUEZ VOTRE SITUATION'
                                : 'DÉPOSER UNE NOUVELLE CONTESTATION',
                            style: textTheme.labelSmall?.copyWith(letterSpacing: 13 * 0.14),
                          ),
                          const SizedBox(height: BraiseSpacing.sm),
                          TextField(
                            controller: _messageController,
                            maxLines: 5,
                            decoration: const InputDecoration(
                              labelText: 'Votre contestation',
                              hintText:
                                  'Pourquoi pensez-vous que cette suspension n\'est pas justifiée ?',
                            ),
                          ),
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: BraiseSpacing.lg),
                              child: Text(
                                _error!,
                                style: textTheme.bodyMedium?.copyWith(color: tokens.erreur),
                              ),
                            ),
                          const SizedBox(height: BraiseSpacing.xl),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _submitting ? null : _submit,
                              child: Text(_submitting ? 'Envoi…' : 'Envoyer ma contestation'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }
}

class _AppealStatusCard extends StatelessWidget {
  const _AppealStatusCard({required this.appeal});

  final BanAppeal appeal;

  @override
  Widget build(BuildContext context) {
    final tokens = BraiseTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    final (label, color) = switch (appeal.status) {
      'pending' => ('EN COURS D\'EXAMEN', tokens.alerte),
      'overturned' => ('BANNISSEMENT LEVÉ', tokens.foiInk),
      _ => ('CONTESTATION EXAMINÉE — MAINTENUE', tokens.erreur),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(BraiseSpacing.lg),
      decoration: BoxDecoration(
        color: tokens.surface1,
        border: Border.all(color: tokens.borderHairline),
        borderRadius: BorderRadius.circular(BraiseRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: textTheme.labelSmall?.copyWith(color: color, letterSpacing: 12 * 0.16)),
          const SizedBox(height: BraiseSpacing.sm),
          Text('« ${appeal.message} »', style: textTheme.bodyMedium),
          if (appeal.decisionNote != null) ...[
            const SizedBox(height: BraiseSpacing.md),
            Text('Réponse : ${appeal.decisionNote}', style: textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}
