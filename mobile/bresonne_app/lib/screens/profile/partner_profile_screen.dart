import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_exception.dart';
import '../../models/discovery.dart';
import '../../models/public_profile.dart';
import '../../state/app_services.dart';
import '../../theme/braise_tokens.dart';
import '../../widgets/avatar_sigil.dart';
import '../../widgets/sign_shapes.dart';

/// Le profil du/de la partenaire, vu depuis une conversation — mêmes informations que la carte
/// du feed de découverte (bio, centres d'intérêt, badges vérifié/confiance), jamais les photos
/// privées : celles-ci restent sous leur propre gate (UnlockScreen, `blur_stage == 'net'`), ce
/// que cet écran ne change pas.
class PartnerProfileScreen extends StatefulWidget {
  const PartnerProfileScreen({super.key, required this.match});

  final MatchSummary match;

  @override
  State<PartnerProfileScreen> createState() => _PartnerProfileScreenState();
}

class _PartnerProfileScreenState extends State<PartnerProfileScreen> {
  PartnerProfile? _profile;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await context.read<AppServices>().profilesApi.getPartnerProfile(
        widget.match.matchId,
      );
      if (!mounted) return;
      setState(() {
        _profile = profile;
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

  @override
  Widget build(BuildContext context) {
    final tokens = BraiseTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return Scaffold(
      appBar: AppBar(title: Text(widget.match.otherDisplayName)),
      body: _loading
          ? const Center(child: CircularProgressIndicator(semanticsLabel: 'Chargement en cours.'))
          : _error != null
          ? ListView(
              padding: const EdgeInsets.all(BraiseSpacing.xxl),
              children: [
                Text(_error!, style: TextStyle(color: tokens.erreur)),
                const SizedBox(height: BraiseSpacing.lg),
                OutlinedButton(onPressed: _load, child: const Text('Réessayer')),
              ],
            )
          // Fondu + léger glissement vers le haut à l'arrivée du profil — ce sous-arbre n'est
          // construit qu'une fois le chargement terminé, donc ce montage (et l'animation qui
          // l'accompagne) ne se répète pas à chaque `setState` ultérieur qui ne toucherait pas
          // `_loading`/`_error`.
          : TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 380),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) => Opacity(
                opacity: value,
                child: Transform.translate(offset: Offset(0, (1 - value) * 16), child: child),
              ),
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(BraiseSpacing.xxl),
                  children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AvatarSigil(spec: _profile!.avatar, size: 72),
                      const SizedBox(width: BraiseSpacing.lg),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_profile!.displayName} · ${_profile!.age}',
                              style: textTheme.titleLarge,
                            ),
                            if (_profile!.isVerified || _profile!.trustScore != null) ...[
                              const SizedBox(height: BraiseSpacing.xs),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_profile!.isVerified) ...[
                                    SignSquareCore(color: tokens.foiInk, size: 14),
                                    const SizedBox(width: BraiseSpacing.xs),
                                  ],
                                  Flexible(
                                    child: Text(
                                      [
                                        if (_profile!.isVerified) 'VÉRIFIÉ',
                                        if (_profile!.trustScore != null)
                                          'CONFIANCE ${_profile!.trustScore}',
                                      ].join(' · '),
                                      style: textTheme.labelSmall?.copyWith(
                                        color: tokens.foiInk,
                                        letterSpacing: 10 * 0.08,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: BraiseSpacing.xl),
                  Text(
                    _profile!.bio.isEmpty
                        ? "${_profile!.displayName} n'a pas encore écrit de bio."
                        : '« ${_profile!.bio} »',
                    style: _profile!.bio.isEmpty
                        ? textTheme.bodyLarge?.copyWith(color: tokens.inkSecondary)
                        : textTheme.bodyLarge,
                  ),
                  if (_profile!.interests.isNotEmpty) ...[
                    const SizedBox(height: BraiseSpacing.lg),
                    Wrap(
                      spacing: BraiseSpacing.sm,
                      runSpacing: BraiseSpacing.sm,
                      children: [
                        for (final interest in _profile!.interests)
                          Semantics(
                            label: interest,
                            excludeSemantics: true,
                            child: Chip(
                              label: Text(interest),
                              backgroundColor: tokens.surface2,
                              side: BorderSide(color: tokens.borderHairline),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
    );
  }
}
