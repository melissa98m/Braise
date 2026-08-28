import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_exception.dart';
import '../../models/discovery.dart';
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
            ? const Center(child: CircularProgressIndicator())
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
            : ListView.separated(
                padding: const EdgeInsets.all(BraiseSpacing.lg),
                itemCount: _matches.length,
                separatorBuilder: (_, _) => const SizedBox(height: BraiseSpacing.sm),
                itemBuilder: (context, index) {
                  final match = _matches[index];
                  return ListTile(
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
                    trailing: FlameDiamonds(filled: match.flameCount, total: match.unlockThreshold),
                    onTap: () =>
                        Navigator.of(context).push(braiseRoute(context, ConversationScreen(match: match))),
                  );
                },
              ),
      ),
    );
  }
}
