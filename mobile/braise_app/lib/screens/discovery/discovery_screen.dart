import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_exception.dart';
import '../../models/discovery.dart';
import '../../notifications/notification_prefs.dart';
import '../../state/app_services.dart';
import '../../theme/braise_tokens.dart';
import '../../widgets/avatar_sigil.dart';
import '../../widgets/braise_page_route.dart';
import '../../widgets/sign_shapes.dart';
import '../messaging/conversation_screen.dart';
import 'likes_received_screen.dart';

/// Écran 03 — pas de swipe façon catalogue : une carte à la fois, hiérarchie phrase > intérêts
/// > avatar (cahier des charges A.7 : refuse le tri purement visuel).
class DiscoveryScreen extends StatefulWidget {
  const DiscoveryScreen({super.key});

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen> with SingleTickerProviderStateMixin {
  List<DiscoveryCandidate> _feed = [];
  bool _loading = true;
  String? _error;

  // Pas un initialiseur `late final = AnimationController(...)` : ce champ n'est lu que dans
  // `_swipe()` et `dispose()`, jamais `build()` — un `late` paresseux le construirait pour la
  // première fois *dans* `dispose()` si l'utilisateur quitte l'écran sans jamais swiper, à un
  // moment où l'élément est déjà désactivé (`vsync: this` a besoin de remonter l'arbre pour
  // trouver un `TickerMode`, ce qui échoue une fois désactivé — "Looking up a deactivated
  // widget's ancestor is unsafe."). Construit dans `initState()` à la place, où le widget est
  // garanti monté.
  late final AnimationController _exitController;
  // -1 = "Passer" (sort à gauche), 1 = "Braise" (sort à droite) — même sens que le swipe
  // Tinder classique, même si le geste de glisser n'existe pas ici (cahier des charges A.7).
  int _exitSign = 0;
  bool _isSwiping = false;
  int _likesReceivedCount = 0;

  @override
  void initState() {
    super.initState();
    _exitController = AnimationController(vsync: this, duration: const Duration(milliseconds: 280));
    _loadFeed();
    unawaited(_refreshLikesReceivedBadge());
  }

  /// Purement décoratif (badge) : une erreur ici ne doit jamais bloquer l'écran de découverte
  /// lui-même — même principe que RootShell._refreshUnreadBadge pour le badge Échanges.
  Future<void> _refreshLikesReceivedBadge() async {
    try {
      final likes = await context.read<AppServices>().discoveryApi.getLikesReceived();
      if (!mounted) return;
      setState(() => _likesReceivedCount = likes.count);
    } on ApiException {
      // Ignoré volontairement.
    }
  }

  Future<void> _loadFeed() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final feed = await context.read<AppServices>().discoveryApi.getFeed();
      setState(() {
        _feed = feed;
        _loading = false;
      });
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _swipe(String decision) async {
    if (_feed.isEmpty || _isSwiping) return;
    final candidate = _feed.first;
    final services = context.read<AppServices>();
    setState(() {
      _isSwiping = true;
      _exitSign = decision == 'like' ? 1 : -1;
    });
    final exitAnimation = _exitController.forward(from: 0);
    try {
      final matched = await services.discoveryApi.swipe(candidate.userId, decision);
      // La carte doit avoir fini de sortir de l'écran avant qu'on ne dévoile la suivante —
      // sinon la fin d'animation coupe une requête réseau lente, jamais l'inverse.
      await exitAnimation;
      if (!mounted) return;
      setState(() {
        _feed = _feed.sublist(1);
        _isSwiping = false;
      });
      _exitController.value = 0;
      if (matched && mounted) {
        unawaited(_celebrateMatch(services, candidate));
      }
    } on ApiException catch (e) {
      // Refusé (ex. 402 limite gratuite) : la carte revient à sa place plutôt que de rester
      // hors-écran — l'utilisateur garde ce profil sous les yeux pour décider quoi faire.
      await _exitController.reverse();
      if (!mounted) return;
      setState(() => _isSwiping = false);
      if (e.isPaymentRequired && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      } else {
        setState(() => _error = e.message);
      }
    }
  }

  /// Les deux ont braisé : on va chercher le match fraîchement créé (le swipe ne renvoie que
  /// `matched: bool`, pas l'objet complet) pour pouvoir ouvrir directement la conversation.
  Future<void> _celebrateMatch(AppServices services, DiscoveryCandidate candidate) async {
    final matches = await services.discoveryApi.getMatches();
    MatchSummary? match;
    for (final m in matches) {
      if (m.otherUserId == candidate.userId) {
        match = m;
        break;
      }
    }
    if (!mounted || match == null) return;
    // P9.1 : vraie notification navigateur (en plus du dialogue déjà affiché ci-dessous, qui
    // reste le retour principal) — n'affiche rien si la préférence "Nouveau match" est
    // désactivée ou si la permission navigateur n'a jamais été accordée.
    if (await NotificationPrefs.isEnabled(NotificationPrefs.match, defaultValue: true)) {
      services.notificationsService.show(
        title: 'Braise commune !',
        body: 'Vous avez matché avec ${candidate.displayName}.',
      );
    }
    if (!mounted) return;
    final tokens = BraiseTokens.of(context);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Braise commune avec ${candidate.displayName} !'),
        content: const Text('Vous vous êtes braisés tous les deux. Lancez la conversation ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Continuer à découvrir'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: tokens.braiseInk,
              foregroundColor: tokens.braiseFillText,
            ),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              Navigator.of(context).push(braiseRoute(context, ConversationScreen(match: match!)));
            },
            child: const Text('Commencer à discuter'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _exitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = BraiseTokens.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Découvrir'),
        actions: [
          IconButton(
            tooltip: 'Qui vous a braisé',
            icon: Badge.count(
              count: _likesReceivedCount,
              isLabelVisible: _likesReceivedCount > 0,
              child: SignDiamond(color: tokens.inkSecondary, size: 22),
            ),
            onPressed: () async {
              await Navigator.of(context).push(braiseRoute(context, const LikesReceivedScreen()));
              unawaited(_refreshLikesReceivedBadge());
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Text(_error!, style: textTheme.bodyMedium?.copyWith(color: tokens.erreur)),
            )
          : _feed.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(BraiseSpacing.xxl),
                child: Text(
                  'Plus de profil à découvrir pour le moment. Revenez bientôt.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyLarge,
                ),
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(BraiseSpacing.xxl),
              child: Column(
                children: [
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      // AnimatedSwitcher clippe (hardEdge) sa pile interne par défaut : la carte
                      // active qui glisse hors de sa propre largeur se ferait couper des deux
                      // côtés au lieu de sortir de l'écran. On désactive le clip pour ce widget.
                      layoutBuilder: (currentChild, previousChildren) => Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [...previousChildren, ?currentChild],
                      ),
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.04),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      // La sortie "swipe" (glisser + pivoter + s'effacer) est pilotée à part par
                      // _exitController, pas par la transition d'AnimatedSwitcher : celle-ci ne se
                      // déclenche qu'une fois la carte suivante dévoilée (clé différente), donc son
                      // fondu d'entrée reste inchangé pendant que la carte active s'envole.
                      child: AnimatedBuilder(
                        key: ValueKey(_feed.first.userId),
                        animation: _exitController,
                        builder: (context, child) {
                          final t = Curves.easeInCubic.transform(_exitController.value);
                          final dx = _exitSign * t * 520;
                          final angle = _exitSign * t * 0.24;
                          return Transform.translate(
                            offset: Offset(dx, 0),
                            child: Transform.rotate(
                              angle: angle,
                              child: Opacity(opacity: 1 - t, child: child),
                            ),
                          );
                        },
                        child: _CandidateCard(candidate: _feed.first),
                      ),
                    ),
                  ),
                  const SizedBox(height: BraiseSpacing.lg),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isSwiping ? null : () => _swipe('pass'),
                          child: const Text('Passer'),
                        ),
                      ),
                      const SizedBox(width: BraiseSpacing.md),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: _isSwiping ? null : () => _swipe('like'),
                          icon: SignDiamond(color: tokens.braiseFillText, size: 16),
                          label: const Text('Braise'),
                        ),
                      ),
                    ],
                  ),
                  if (_feed.length > 1) ...[
                    const SizedBox(height: BraiseSpacing.lg),
                    _NextCandidatePreview(candidate: _feed[1]),
                  ],
                ],
              ),
            ),
    );
  }
}

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({required this.candidate});

  final DiscoveryCandidate candidate;

  @override
  Widget build(BuildContext context) {
    final tokens = BraiseTokens.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(BraiseSpacing.xxl),
      decoration: BoxDecoration(
        color: tokens.surface1,
        border: Border.all(color: tokens.borderHairline),
        borderRadius: BorderRadius.circular(BraiseRadii.keyCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AvatarSigil(spec: candidate.avatar, size: 56),
              const SizedBox(width: BraiseSpacing.md),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${candidate.displayName} · ${candidate.age}', style: textTheme.titleMedium),
                  if (candidate.isVerified || candidate.trustScore != null) ...[
                    const SizedBox(height: BraiseSpacing.xs),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (candidate.isVerified) ...[
                          SignSquareCore(color: tokens.foiInk, size: 14),
                          const SizedBox(width: BraiseSpacing.xs),
                        ],
                        Text(
                          [
                            if (candidate.isVerified) 'VÉRIFIÉ',
                            if (candidate.trustScore != null) 'CONFIANCE ${candidate.trustScore}',
                          ].join(' · '),
                          style: textTheme.labelSmall?.copyWith(
                            color: tokens.foiInk,
                            letterSpacing: 10 * 0.08,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: BraiseSpacing.xl),
          Expanded(
            child: Text(
              '« ${candidate.bio} »',
              style: textTheme.bodyLarge,
            ),
          ),
          const SizedBox(height: BraiseSpacing.lg),
          Wrap(
            spacing: BraiseSpacing.sm,
            runSpacing: BraiseSpacing.sm,
            children: [
              if (candidate.commonInterests.isNotEmpty)
                Chip(
                  label: Text('${candidate.commonInterests.length} intérêts en commun'),
                  backgroundColor: tokens.braiseTint,
                  side: BorderSide(color: tokens.braiseInk),
                ),
              for (final interest in candidate.interests)
                Chip(
                  label: Text(interest),
                  backgroundColor: tokens.surface2,
                  side: BorderSide(color: tokens.borderHairline),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Aperçu du prochain profil de la file — moins présent (opacité réduite), jamais la même
/// hiérarchie que la carte active : on garde "une carte à la fois" (cahier des charges A.7).
class _NextCandidatePreview extends StatelessWidget {
  const _NextCandidatePreview({required this.candidate});

  final DiscoveryCandidate candidate;

  @override
  Widget build(BuildContext context) {
    final tokens = BraiseTokens.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Opacity(
      opacity: 0.8,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(BraiseSpacing.lg),
        decoration: BoxDecoration(
          color: tokens.surface1,
          border: Border.all(color: tokens.borderHairline),
          borderRadius: BorderRadius.circular(BraiseRadii.card),
        ),
        child: Row(
          children: [
            AvatarSigil(spec: candidate.avatar, size: 44),
            const SizedBox(width: BraiseSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${candidate.displayName} · ${candidate.age}', style: textTheme.titleMedium),
                  const SizedBox(height: BraiseSpacing.xs),
                  Text(
                    '« ${candidate.bio} »',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
