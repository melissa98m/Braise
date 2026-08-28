import 'package:flutter/material.dart';

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
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.explore_outlined), label: 'Découvrir'),
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), label: 'Échanges'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Moi'),
        ],
      ),
    );
  }
}
