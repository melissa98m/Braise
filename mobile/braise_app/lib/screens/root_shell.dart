import 'package:flutter/material.dart';

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
  int _index = 0;

  static const _screens = [
    DiscoveryScreen(),
    MatchesListScreen(),
    ProfileTrustScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final tokens = BraiseTokens.of(context);
    // Chaque onglet garde une forme distincte (cercle / carré / cercle plein), jamais seulement
    // une couleur ou une icône Material interchangeable — même alphabet de signes que le reste
    // de l'app (docs/DESIGN_TOKENS.md).
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: [
          NavigationDestination(
            icon: SignCircleOutline(color: tokens.inkSecondary),
            selectedIcon: SignCircleOutline(color: tokens.braiseInk),
            label: 'Découvrir',
          ),
          NavigationDestination(
            icon: SignSquareOutline(color: tokens.inkSecondary),
            selectedIcon: SignSquareOutline(color: tokens.braiseInk),
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
