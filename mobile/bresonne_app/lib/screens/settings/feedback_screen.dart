import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_exception.dart';
import '../../state/app_services.dart';
import '../../theme/braise_tokens.dart';

/// Retour de bêta : un bug, une idée, une impression — envoyé tel quel à l'équipe (file
/// « Retours » du tableau de bord staff, backend/app/api/v1/feedback.py). Atteint depuis
/// Paramètres ; volontairement court (une catégorie, un texte) pour qu'en donner un ne coûte
/// rien. Même structure que ReportScreen, sans rien de ce qui en fait une procédure de
/// modération : ici rien n'agit sur un compte.
class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  static const categories = {
    'bug': 'Quelque chose ne marche pas',
    'idea': 'Une idée, une suggestion',
    'other': 'Autre chose à nous dire',
  };

  static const minLength = 5;
  static const maxLength = 2000;

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _messageController = TextEditingController();
  String _category = 'bug';
  bool _submitting = false;
  String? _error;

  Future<void> _submit() async {
    final message = _messageController.text.trim();
    if (message.length < FeedbackScreen.minLength) {
      setState(() => _error = 'Dites-nous en un peu plus (quelques mots suffisent).');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await context.read<AppServices>().feedbackApi.sendFeedback(
        category: _category,
        message: message,
        context: 'settings',
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Merci ! Votre retour a bien été envoyé.')),
      );
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = BraiseTokens.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Envoyer un retour')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(BraiseSpacing.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'VERSION BÊTA',
              style: textTheme.labelSmall?.copyWith(color: tokens.braiseInk, letterSpacing: 12 * 0.16),
            ),
            const SizedBox(height: BraiseSpacing.sm),
            Text('Votre avis compte', style: textTheme.headlineMedium),
            const SizedBox(height: BraiseSpacing.sm),
            Text(
              'Un bug, une idée, une impression : tout est lu par l\'équipe. Pour un problème avec '
              'une personne, utilisez plutôt « Signaler » depuis la conversation.',
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: BraiseSpacing.xl),
            Wrap(
              spacing: BraiseSpacing.sm,
              runSpacing: BraiseSpacing.sm,
              children: [
                // Un seul choix possible : annoncé comme un groupe de boutons radio, pas comme les
                // cases à cocher que `ChoiceChip` expose par défaut (qui laisseraient croire à un
                // lecteur d'écran qu'on peut en cocher plusieurs) — même motif que P15.
                for (final entry in FeedbackScreen.categories.entries)
                  Semantics(
                    container: true,
                    excludeSemantics: true,
                    label: entry.value,
                    inMutuallyExclusiveGroup: true,
                    checked: _category == entry.key,
                    onTap: () => setState(() => _category = entry.key),
                    child: ChoiceChip(
                      label: Text(entry.value),
                      selected: _category == entry.key,
                      onSelected: (_) => setState(() => _category = entry.key),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: BraiseSpacing.lg),
            TextField(
              controller: _messageController,
              maxLines: 6,
              maxLength: FeedbackScreen.maxLength,
              decoration: const InputDecoration(
                labelText: 'Votre message',
                hintText: 'Que s\'est-il passé ? Sur quel écran ?',
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: BraiseSpacing.sm),
                child: Text(_error!, style: textTheme.bodyMedium?.copyWith(color: tokens.erreur)),
              ),
            const SizedBox(height: BraiseSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                child: const Text('Envoyer'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
