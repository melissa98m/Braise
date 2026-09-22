import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_exception.dart';
import '../notifications/notification_prefs.dart';
import '../state/app_services.dart';
import '../theme/braise_tokens.dart';
import '../widgets/sign_shapes.dart';
import 'discovery/discovery_screen.dart';
import 'matches/matches_list_screen.dart';
import 'profile/profile_trust_screen.dart';

/// Barre d'onglets à 3 entrées : Découvrir / Échanges / Moi. La maquette montre 4 onglets
/// (avec "Braises" séparé), mais rien côté backend ne justifie un écran dédié aux flammes en
/// dehors du profil ("Moi") et des échanges — pas d'onglet sans contenu propre à lui.
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  // P9.1 : au plus une fois par jour calendaire — évite de renotifier à chaque fois que
  // RootShell est reconstruit dans la même session (ce n'est pas juste un montage unique : voir
  // les allers-retours possibles depuis _AuthGate).
  static const _questionLastShownKey = 'braise_notif_question_last_shown';

  int _index = 0;
  int _totalUnread = 0;

  static const _screens = [
    DiscoveryScreen(),
    MatchesListScreen(),
    ProfileTrustScreen(),
  ];

  @override
  void initState() {
    super.initState();
    unawaited(_maybeNotifyDailyQuestion());
    unawaited(_refreshUnreadBadge());
  }

  /// P9.2 : badge global sur l'onglet "Échanges" — `MatchesListScreen`/`ProfileTrustScreen`
  /// appellent déjà `getMatches()` chacun de leur côté pour leurs propres besoins (liste,
  /// total de flammes) ; un troisième appel ici pour le badge suit le même principe pragmatique
  /// plutôt que d'inventer un état partagé pour 3 écrans. Pas de rafraîchissement en direct
  /// pendant qu'une conversation est ouverte (pas de flux global de lecture inter-écrans) :
  /// seulement au montage et en quittant l'onglet Échanges, qui couvre le cas réel (le badge se
  /// vide quand on revient de la messagerie).
  Future<void> _refreshUnreadBadge() async {
    try {
      final matches = await context.read<AppServices>().discoveryApi.getMatches();
      if (!mounted) return;
      setState(() {
        _totalUnread = matches.fold(0, (sum, m) => sum + m.unreadCount);
      });
    } on ApiException {
      // Purement décoratif (un badge) : une erreur ici ne doit jamais faire échouer RootShell
      // ni s'afficher — MatchesListScreen affiche déjà sa propre erreur si le problème persiste.
    }
  }

  Future<void> _maybeNotifyDailyQuestion() async {
    if (!await NotificationPrefs.isEnabled(NotificationPrefs.question, defaultValue: true)) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    if (prefs.getString(_questionLastShownKey) == today) return;
    await prefs.setString(_questionLastShownKey, today);
    if (!mounted) return;
    context.read<AppServices>().notificationsService.show(
      title: 'Question du jour disponible',
      body: 'Répondez pour gagner une flamme avec vos matchs.',
    );
  }

  /// Le badge de messages non lus passait d'un chiffre à l'autre instantanément — un fondu +
  /// léger scale rend chaque nouvelle valeur perceptible comme un événement plutôt qu'un simple
  /// changement de texte. `AnimatedSwitcher` cross-fade la carte `Badge.count` entière (icône
  /// incluse) : sans effet visible sur l'icône elle-même puisqu'elle est strictement identique
  /// avant/après, seul le badge change réellement de contenu.
  Widget _unreadBadge(Color iconColor, Duration duration) {
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeOutCubic,
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: ScaleTransition(scale: animation, child: child)),
      child: Badge.count(
        key: ValueKey(_totalUnread),
        count: _totalUnread,
        isLabelVisible: _totalUnread > 0,
        child: SignSquareOutline(color: iconColor),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = BraiseTokens.of(context);
    final badgeDuration = MediaQuery.of(context).disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 220);
    // Chaque onglet garde une forme distincte (cercle / carré / cercle plein), jamais seulement
    // une couleur ou une icône Material interchangeable — même alphabet de signes que le reste
    // de l'app (docs/DESIGN_TOKENS.md).
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) {
          // On quitte l'onglet Échanges : c'est le moment le plus probable où des messages
          // viennent d'être lus, donc où le badge doit se vider.
          final leavingMatches = _index == 1 && value != 1;
          setState(() => _index = value);
          if (leavingMatches) unawaited(_refreshUnreadBadge());
        },
        destinations: [
          NavigationDestination(
            icon: SignCircleOutline(color: tokens.inkSecondary),
            selectedIcon: SignCircleOutline(color: tokens.braiseInk),
            label: 'Découvrir',
          ),
          NavigationDestination(
            icon: _unreadBadge(tokens.inkSecondary, badgeDuration),
            selectedIcon: _unreadBadge(tokens.braiseInk, badgeDuration),
            label: 'Échanges',
          ),
          NavigationDestination(
            icon: SignFilledCircle(color: tokens.inkSecondary),
            selectedIcon: SignFilledCircle(color: tokens.braiseInk),
            label: 'Moi',
          ),
        ],
      ),
    );
  }
}
