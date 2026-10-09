import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_exception.dart';
import '../../models/discovery.dart';
import '../../push/push_opt_in_card.dart';
import '../../state/app_services.dart';
import '../../theme/braise_tokens.dart';
import '../../widgets/braise_page_route.dart';
import '../../widgets/flame_diamonds.dart';
import '../messaging/conversation_screen.dart';

class MatchesListScreen extends StatefulWidget {
  const MatchesListScreen({super.key});

  @override
  State<MatchesListScreen> createState() => _MatchesListScreenState();
}

class _MatchesListScreenState extends State<MatchesListScreen> {
  List<MatchSummary> _matches = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final matches = await context.read<AppServices>().discoveryApi.getMatches();
      setState(() {
        _matches = matches;
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
      appBar: AppBar(title: const Text('Échanges')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator(semanticsLabel: 'Chargement en cours.'))
            : _error != null
            ? Center(child: Text(_error!, style: TextStyle(color: tokens.erreur)))
            : _matches.isEmpty
            ? ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(BraiseSpacing.xxl),
                    child: Text('Pas encore de match. Direction Découvrir !', style: textTheme.bodyLarge),
                  ),
                ],
              )
            : ListView.builder(
                padding: const EdgeInsets.all(BraiseSpacing.lg),
                // +1 : la carte d'activation des notifications en tête de liste (elle se masque
                // d'elle-même une fois activées, refusées ou reportées).
                itemCount: _matches.length + 1,
                itemBuilder: (context, position) {
                  if (position == 0) return const PushOptInCard();
                  final index = position - 1;
                  final match = _matches[index];
                  return _StaggeredEntrance(
                    index: index,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: BraiseSpacing.sm),
                      child: ListTile(
                        tileColor: tokens.surface1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(BraiseRadii.card),
                          side: BorderSide(color: tokens.borderHairline),
                        ),
                        title: Text(match.otherDisplayName, style: textTheme.titleMedium),
                        subtitle: Text(
                          match.isUnlocked ? 'Profil privé débloqué' : 'Profil privé · ${match.unlockPct}%',
                          style: textTheme.bodyMedium,
                        ),
                        trailing: _UnreadBadgePop(
                          count: match.unreadCount,
                          child: Badge.count(
                            count: match.unreadCount,
                            isLabelVisible: match.unreadCount > 0,
                            alignment: AlignmentDirectional.topStart,
                            offset: const Offset(-4, -4),
                            child: FlameDiamonds(filled: match.flameCount, total: match.unlockThreshold),
                          ),
                        ),
                        onTap: () => Navigator.of(
                          context,
                        ).push(braiseRoute(context, ConversationScreen(match: match))),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

/// Entrée échelonnée des lignes de la liste : fondu + léger glissement, décalé de ~55ms par
/// élément et plafonné aux ~10 premières pour qu'une longue liste de matches n'étire pas
/// indéfiniment la chorégraphie (au-delà, tout le monde apparaît avec le même délai plafond).
class _StaggeredEntrance extends StatefulWidget {
  const _StaggeredEntrance({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_StaggeredEntrance> createState() => _StaggeredEntranceState();
}

class _StaggeredEntranceState extends State<_StaggeredEntrance> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    // Pas `MediaQuery.of(context)` ici : cet écran monte cette entrée depuis un `ListView`, où
    // établir une dépendance InheritedWidget en plein `initState()` lève "dependOnInherited...
    // was called before initState() completed" (constaté en lançant les tests, pas en relisant
    // le code) — `platformDispatcher.accessibilityFeatures` lit le même réglage sans passer par
    // le système de dépendances du BuildContext.
    final reduceMotion = WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    if (reduceMotion) {
      _visible = true;
      return;
    }
    final delay = Duration(milliseconds: widget.index.clamp(0, 10) * 55);
    Future.delayed(delay, () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final duration = reduceMotion ? Duration.zero : const Duration(milliseconds: 320);
    return AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: duration,
      curve: Curves.easeOutCubic,
      child: AnimatedSlide(
        offset: _visible ? Offset.zero : const Offset(0, 0.05),
        duration: duration,
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

/// Petit "pop" d'échelle quand le badge de messages non lus apparaît/évolue — même esprit que le
/// pop de FlameDiamonds quand un diamant se remplit (widgets/flame_diamonds.dart) : on retient la
/// valeur précédente pour ne déclencher l'animation que sur un changement réel, jamais en boucle.
class _UnreadBadgePop extends StatefulWidget {
  const _UnreadBadgePop({required this.count, required this.child});

  final int count;
  final Widget child;

  @override
  State<_UnreadBadgePop> createState() => _UnreadBadgePopState();
}

class _UnreadBadgePopState extends State<_UnreadBadgePop> {
  int _previousCount = 0;

  @override
  void didUpdateWidget(covariant _UnreadBadgePop oldWidget) {
    super.didUpdateWidget(oldWidget);
    _previousCount = oldWidget.count;
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final justAppeared = !reduceMotion && widget.count > 0 && widget.count != _previousCount;
    return TweenAnimationBuilder<double>(
      key: ValueKey(widget.count),
      tween: Tween(begin: justAppeared ? 0.5 : 1, end: 1),
      duration: justAppeared ? const Duration(milliseconds: 320) : Duration.zero,
      curve: Curves.easeOutQuint,
      builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
      child: widget.child,
    );
  }
}
