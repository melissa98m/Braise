import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_exception.dart';
import '../../models/discovery.dart';
import '../../state/app_services.dart';
import '../../theme/braise_tokens.dart';
import '../../widgets/braise_page_route.dart';
import '../moderation/report_screen.dart';

/// Écran 06 — note en chiffres (pas d'étoiles, non ambigu), commentaire obligatoire ≥ 4 mots
/// expliqué plutôt que subi (cahier des charges A.4.4).
class RatingScreen extends StatefulWidget {
  const RatingScreen({super.key, required this.match});

  final MatchSummary match;

  @override
  State<RatingScreen> createState() => _RatingScreenState();
}

class _RatingScreenState extends State<RatingScreen> {
  final _commentController = TextEditingController();
  int _score = 4;
  bool _submitting = false;
  String? _error;

  int get _wordCount =>
      _commentController.text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

  Future<void> _submit() async {
    if (_wordCount < 4) {
      setState(() => _error = 'Le commentaire doit contenir au moins 4 mots.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await context.read<AppServices>().moderationApi.rate(
        widget.match.matchId,
        _score,
        _commentController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.suspectedRancor
                ? 'Avis envoyé — signalé pour revue humaine par prudence.'
                : 'Avis envoyé, merci.',
          ),
        ),
      );
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _report() {
    Navigator.of(context).push(braiseRoute(context, ReportScreen(match: widget.match)));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = BraiseTokens.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text("Après l'échange")),
      body: Padding(
        padding: const EdgeInsets.all(BraiseSpacing.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Comment ${widget.match.otherDisplayName} s\'est-il/elle comporté(e) ?',
              style: textTheme.headlineMedium,
            ),
            const SizedBox(height: BraiseSpacing.sm),
            Text(
              'Votre avis alimente son score de confiance. Il/elle ne verra jamais qui a écrit quoi.',
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: BraiseSpacing.xl),
            Row(
              children: [
                for (var i = 1; i <= 5; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: BraiseSpacing.sm),
                    child: _ScoreChip(
                      value: i,
                      selected: i == _score,
                      onTap: () => setState(() => _score = i),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: BraiseSpacing.xl),
            TextField(
              controller: _commentController,
              maxLines: 4,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Commentaire · obligatoire (min. 4 mots)',
              ),
            ),
            const SizedBox(height: BraiseSpacing.sm),
            Container(
              padding: const EdgeInsets.all(BraiseSpacing.md),
              decoration: BoxDecoration(
                color: tokens.alerte.withValues(alpha: 0.1),
                border: Border.all(color: tokens.alerte),
                borderRadius: BorderRadius.circular(BraiseRadii.card),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border.all(color: tokens.alerte, width: 1.75),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '!',
                      style: textTheme.labelSmall?.copyWith(color: tokens.alerte, fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: BraiseSpacing.sm),
                  Expanded(
                    child: Text(
                      "Une note sans commentaire n'est pas enregistrée : c'est ce qui rend le "
                      "score fiable pour tout le monde.",
                      style: textTheme.bodyMedium?.copyWith(color: tokens.inkPrimary),
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: BraiseSpacing.lg),
                child: Text(_error!, style: textTheme.bodyMedium?.copyWith(color: tokens.erreur)),
              ),
            const Spacer(),
            ElevatedButton(
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: tokens.foiFill,
                foregroundColor: tokens.foiFillText,
              ),
              child: const Text('Envoyer mon avis'),
            ),
            const SizedBox(height: BraiseSpacing.sm),
            OutlinedButton(
              onPressed: _report,
              style: OutlinedButton.styleFrom(
                foregroundColor: tokens.erreur,
                side: BorderSide(color: tokens.erreur),
              ),
              child: const Text('Signaler un problème'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }
}

class _ScoreChip extends StatelessWidget {
  const _ScoreChip({required this.value, required this.selected, required this.onTap});

  final int value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = BraiseTokens.of(context);
    final duration = MediaQuery.of(context).disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 150);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(BraiseRadii.field),
      child: AnimatedContainer(
        duration: duration,
        width: 52,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? tokens.braiseFill : Colors.transparent,
          border: Border.all(
            color: selected ? tokens.inkPrimary : tokens.borderStrong,
            width: selected ? 2 : 1.75,
          ),
          borderRadius: BorderRadius.circular(BraiseRadii.field),
        ),
        child: AnimatedDefaultTextStyle(
          duration: duration,
          style: TextStyle(
            color: selected ? tokens.braiseFillText : tokens.inkSecondary,
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
          child: Text('$value'),
        ),
      ),
    );
  }
}
