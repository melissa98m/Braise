import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_exception.dart';
import '../../models/discovery.dart';
import '../../models/public_profile.dart';
import '../../state/app_services.dart';
import '../../theme/braise_tokens.dart';
import '../../widgets/braise_page_route.dart';
import '../moderation/report_screen.dart';
import '../rating/rating_screen.dart';

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final revealDuration = MediaQuery.of(context).disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 500);

    return Scaffold(
      appBar: AppBar(title: const Text('Profil privé'), backgroundColor: Colors.transparent),
      extendBodyBehindAppBar: true,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        // Halo chaud radial derrière l'écran de déblocage — même geste que la maquette
        // (radial-gradient), jamais un fond plat pour ce moment.
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.4),
            radius: 0.9,
            colors: isDark
                ? [const Color(0xFF2A1A12), tokens.surfaceRoot]
                : [const Color(0xFFFFEEDC), tokens.surfaceRoot],
          ),
        ),
        child: _loading
            ? const Center(child: CircularProgressIndicator(semanticsLabel: 'Chargement en cours.'))
            : _error != null
            ? Center(child: Text(_error!, style: TextStyle(color: tokens.erreur)))
            : SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    BraiseSpacing.xxl,
                    BraiseSpacing.xxxl,
                    BraiseSpacing.xxl,
                    BraiseSpacing.xxxl,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        '3 / 3 flammes · le voile cède',
                        textAlign: TextAlign.center,
                        style: textTheme.labelSmall?.copyWith(
                          color: tokens.braiseInk,
                          letterSpacing: 12 * 0.18,
                        ),
                      ),
                      const SizedBox(height: BraiseSpacing.md),
                      Text(
                        'Vous vous connaissiez déjà. Voici son visage.',
                        textAlign: TextAlign.center,
                        style: textTheme.displayLarge,
                      ),
                      const SizedBox(height: BraiseSpacing.xl),
                      if (_photos.isEmpty)
                        Text(
                          "${widget.match.otherDisplayName} n'a pas encore ajouté de photo privée.",
                          textAlign: TextAlign.center,
                          style: textTheme.bodyLarge,
                        )
                      else
                        // Le moment-clé de toute l'app : le voile qui se lève pour de vrai. Un
                        // simple fondu ne suffisait pas pour ce que la maquette et l'onboarding
                        // (ConceptIntroScreen) décrivent comme "silhouette, puis flou léger, puis
                        // net" — donc un flou qui se dissipe en même temps que le fondu/scale,
                        // pas seulement une apparition.
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: 1),
                          duration: revealDuration,
                          curve: Curves.easeOutCubic,
                          builder: (context, t, child) => Opacity(
                            opacity: t,
                            child: Transform.scale(
                              scale: 0.94 + 0.06 * t,
                              child: ImageFiltered(
                                imageFilter: ImageFilter.blur(
                                  sigmaX: (1 - t) * 18,
                                  sigmaY: (1 - t) * 18,
                                ),
                                child: child,
                              ),
                            ),
                          ),
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            spacing: BraiseSpacing.md,
                            runSpacing: BraiseSpacing.md,
                            children: [
                              for (final photo in _photos)
                                Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(BraiseRadii.media),
                                    border: Border.all(color: tokens.braiseInk, width: 1.75),
                                    boxShadow: [
                                      BoxShadow(
                                        color: tokens.braiseInk.withValues(alpha: 0.25),
                                        blurRadius: 60,
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(BraiseRadii.media - 1.75),
                                    child: Image.network(
                                      photo.url,
                                      width: 160,
                                      height: 200,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      const SizedBox(height: BraiseSpacing.xxl),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(
                            context,
                          ).push(braiseRoute(context, RatingScreen(match: widget.match))),
                          child: const Text('Noter cet échange'),
                        ),
                      ),
                      const SizedBox(height: BraiseSpacing.sm),
                      TextButton(
                        onPressed: () => Navigator.of(
                          context,
                        ).push(braiseRoute(context, ReportScreen(match: widget.match))),
                        child: Text(
                          'Signaler un problème',
                          style: textTheme.labelSmall?.copyWith(color: tokens.inkSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
