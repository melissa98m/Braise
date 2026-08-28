import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_exception.dart';
import '../../models/discovery.dart';
import '../../models/public_profile.dart';
import '../../state/app_services.dart';
import '../../theme/braise_tokens.dart';

/// Écran 05 — le voile est une matière (dégradé + trame côté maquette), jamais un flou de
/// censure ; ici la maquette est déjà levée pour de vrai (accès conditionnel réel, Phase 5),
/// donc l'écran affiche directement les photos débloquées plutôt qu'un voile progressif simulé.
class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key, required this.match});

  final MatchSummary match;

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  List<PrivatePhoto> _photos = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final photos = await context.read<AppServices>().profilesApi.getPartnerPhotos(
        widget.match.matchId,
      );
      setState(() {
        _photos = photos;
        _loading = false;
      });
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = BraiseTokens.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Profil privé')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!, style: TextStyle(color: tokens.erreur)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(BraiseSpacing.xxl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '3 / 3 flammes · le voile cède',
                    style: textTheme.labelSmall?.copyWith(color: tokens.braiseInk),
                  ),
                  const SizedBox(height: BraiseSpacing.md),
                  Text('Vous vous connaissiez déjà. Voici son visage.', style: textTheme.headlineMedium),
                  const SizedBox(height: BraiseSpacing.xl),
                  if (_photos.isEmpty)
                    Text(
                      "${widget.match.otherDisplayName} n'a pas encore ajouté de photo privée.",
                      style: textTheme.bodyLarge,
                    )
                  else
                    Wrap(
                      spacing: BraiseSpacing.md,
                      runSpacing: BraiseSpacing.md,
                      children: [
                        for (final photo in _photos)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(BraiseRadii.media),
                            child: Image.network(
                              photo.url,
                              width: 160,
                              height: 200,
                              fit: BoxFit.cover,
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
    );
  }
}
