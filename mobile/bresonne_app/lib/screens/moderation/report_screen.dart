import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_exception.dart';
import '../../models/discovery.dart';
import '../../models/moderation.dart';
import '../../state/app_services.dart';
import '../../theme/braise_tokens.dart';

/// Écran Signalement — motif obligatoire (jamais un simple bouton "Signaler" sans détail) et
/// description obligatoire, pour que la revue humaine systématique (cahier des charges C.1) ait
/// toujours de quoi juger. Remplace la boîte de dialogue sommaire qui vivait auparavant dans
/// RatingScreen : une seule surface de signalement, réutilisée depuis Conversation, Déblocage
/// et Notation plutôt que trois implémentations différentes.
class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key, required this.match});

  final MatchSummary match;

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final _descriptionController = TextEditingController();
  String? _reason;
  bool _submitting = false;
  String? _error;

  Future<void> _submit() async {
    if (_reason == null) {
      setState(() => _error = 'Choisissez un motif de signalement.');
      return;
    }
    if (_descriptionController.text.trim().isEmpty) {
      setState(() => _error = 'Décrivez ce qui s\'est passé — obligatoire pour la revue.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await context.read<AppServices>().moderationApi.report(
        widget.match.matchId,
        _reason!,
        _descriptionController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Signalement envoyé, merci de votre vigilance.')),
      );
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = BraiseTokens.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Signalement')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(BraiseSpacing.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SIGNALEMENT',
              style: textTheme.labelSmall?.copyWith(color: tokens.erreur, letterSpacing: 12 * 0.16),
            ),
            const SizedBox(height: BraiseSpacing.sm),
            Text('Signaler ${widget.match.otherDisplayName}', style: textTheme.headlineMedium),
            const SizedBox(height: BraiseSpacing.sm),
            Text(
              'Un motif est obligatoire. La revue humaine est systématique sur les cas sensibles.',
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: BraiseSpacing.xl),
            for (final entry in reportReasons.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: BraiseSpacing.sm),
                child: _MotifTile(
                  label: entry.value,
                  selected: _reason == entry.key,
                  onTap: () => setState(() => _reason = entry.key),
                ),
              ),
            const SizedBox(height: BraiseSpacing.md),
            Text(
              'DÉCRIVEZ CE QUI S\'EST PASSÉ',
              style: textTheme.labelSmall?.copyWith(letterSpacing: 13 * 0.14),
            ),
            const SizedBox(height: BraiseSpacing.sm),
            TextField(
              controller: _descriptionController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText: 'Décrivez les faits factuellement.',
              ),
            ),
            const SizedBox(height: BraiseSpacing.lg),
            Container(
              padding: const EdgeInsets.all(BraiseSpacing.md),
              decoration: BoxDecoration(
                color: tokens.surface1,
                border: Border.all(color: tokens.borderHairline),
                borderRadius: BorderRadius.circular(BraiseRadii.card),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    margin: const EdgeInsets.only(top: 1),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: tokens.voileInk, width: 1.75),
                    ),
                  ),
                  const SizedBox(width: BraiseSpacing.sm),
                  Expanded(
                    child: Text(
                      'Les signalements déposés juste après une déception physique sont détectés '
                      'et traités avec prudence.',
                      style: textTheme.bodyMedium,
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
            const SizedBox(height: BraiseSpacing.xxl),
            ElevatedButton(
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: tokens.erreur,
                foregroundColor: tokens.surfaceRoot,
              ),
              child: const Text('Envoyer le signalement'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }
}

class _MotifTile extends StatelessWidget {
  const _MotifTile({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = BraiseTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    // Même garde `disableAnimations` que le reste de l'app — la sélection d'un motif était un
    // remplacement instantané de couleur/bordure, maintenant une transition d'état de 180ms
    // (fourchette "state change" du système d'animation), plus le point du radio qui pop.
    final duration = MediaQuery.of(context).disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 180);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(BraiseRadii.card),
      child: AnimatedContainer(
        duration: duration,
        curve: Curves.easeOutCubic,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: BraiseSpacing.lg, vertical: BraiseSpacing.md),
        decoration: BoxDecoration(
          color: selected ? tokens.erreur.withValues(alpha: 0.1) : tokens.surface1,
          border: Border.all(color: selected ? tokens.erreur : tokens.borderHairline, width: 1.75),
          borderRadius: BorderRadius.circular(BraiseRadii.card),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: duration,
              curve: Curves.easeOutCubic,
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: selected ? tokens.erreur : tokens.borderStrong, width: 1.75),
                color: selected ? tokens.erreur : Colors.transparent,
              ),
              child: Center(
                child: AnimatedScale(
                  scale: selected ? 1 : 0,
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: tokens.surfaceRoot),
                  ),
                ),
              ),
            ),
            const SizedBox(width: BraiseSpacing.md),
            Text(
              label,
              style: textTheme.bodyLarge?.copyWith(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
