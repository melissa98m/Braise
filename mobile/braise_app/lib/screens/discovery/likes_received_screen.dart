import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_exception.dart';
import '../../models/discovery.dart';
import '../../state/app_services.dart';
import '../../theme/braise_tokens.dart';
import '../../widgets/avatar_sigil.dart';
import '../../widgets/braise_page_route.dart';
import '../../widgets/sign_shapes.dart';
import '../messaging/conversation_screen.dart';
import '../paywall/paywall_screen.dart';

/// « Qui vous a déjà braisé » — les profils qui ont liké l'utilisateur avant qu'il/elle ne les
/// swipe (`GET /discovery/likes-received`). Gratuit : uniquement le nombre, incitation à
/// Braise+. Premium : le détail complet, avec les mêmes actions "Braiser en retour"/"Passer"
/// que l'écran de découverte principal — `POST /discovery/swipe` reste le seul chemin de
/// décision, pas de logique dupliquée côté backend.
class LikesReceivedScreen extends StatefulWidget {
  const LikesReceivedScreen({super.key});

  @override
  State<LikesReceivedScreen> createState() => _LikesReceivedScreenState();
}

class _LikesReceivedScreenState extends State<LikesReceivedScreen> {
  LikesReceived? _data;
  bool _loading = true;
  String? _error;
  final Set<String> _acting = {};

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
      final data = await context.read<AppServices>().discoveryApi.getLikesReceived();
      if (!mounted) return;
      setState(() {
        _data = data;
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

  Future<void> _respond(DiscoveryCandidate candidate, String decision) async {
    final services = context.read<AppServices>();
    setState(() => _acting.add(candidate.userId));
    try {
      final matched = await services.discoveryApi.swipe(candidate.userId, decision);
      if (!mounted) return;
      setState(() {
        _acting.remove(candidate.userId);
        final current = _data!;
        _data = LikesReceived(
          count: current.count - 1,
          isPremium: current.isPremium,
          candidates: current.candidates.where((c) => c.userId != candidate.userId).toList(),
        );
      });
      if (matched) await _celebrateMatch(services, candidate);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _acting.remove(candidate.userId));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

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
    final tokens = BraiseTokens.of(context);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Braise commune avec ${candidate.displayName} !'),
        content: const Text('Vous vous êtes braisés tous les deux. Lancez la conversation ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Continuer'),
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
  Widget build(BuildContext context) {
    final tokens = BraiseTokens.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Qui vous a braisé')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(BraiseSpacing.xxl),
                child: Text(_error!, style: textTheme.bodyMedium?.copyWith(color: tokens.erreur)),
              ),
            )
          : RefreshIndicator(onRefresh: _load, child: _buildContent(context)),
    );
  }

  Widget _buildContent(BuildContext context) {
    final tokens = BraiseTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    final data = _data!;

    if (!data.isPremium) {
      return ListView(
        padding: const EdgeInsets.all(BraiseSpacing.xxl),
        children: [
          const SizedBox(height: BraiseSpacing.xxl),
          Center(child: SignDiamond(color: tokens.alerte, size: 40)),
          const SizedBox(height: BraiseSpacing.lg),
          Text(
            data.count == 0
                ? "Personne ne vous a encore braisé·e. Continuez à découvrir des profils."
                : '${data.count} personne${data.count > 1 ? 's' : ''} vous ${data.count > 1 ? 'ont' : 'a'} déjà braisé·e.',
            textAlign: TextAlign.center,
            style: textTheme.displayLarge,
          ),
          if (data.count > 0) ...[
            const SizedBox(height: BraiseSpacing.md),
            Text(
              'Passez à Braise+ pour découvrir qui, et leur répondre directement.',
              textAlign: TextAlign.center,
              style: textTheme.bodyLarge?.copyWith(color: tokens.inkSecondary),
            ),
            const SizedBox(height: BraiseSpacing.xl),
            ElevatedButton(
              onPressed: () => Navigator.of(context).push(braiseRoute(context, const PaywallScreen())),
              style: ElevatedButton.styleFrom(
                backgroundColor: tokens.alerte,
                foregroundColor: tokens.surfaceRoot,
              ),
              child: const Text('Débloquer avec Braise+'),
            ),
          ],
        ],
      );
    }

    if (data.candidates.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(BraiseSpacing.xxl),
        children: [
          const SizedBox(height: BraiseSpacing.xxl),
          Center(
            child: Text(
              "Personne ne vous a encore braisé·e. Continuez à découvrir des profils.",
              textAlign: TextAlign.center,
              style: textTheme.bodyLarge,
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(BraiseSpacing.xxl),
      itemCount: data.candidates.length,
      separatorBuilder: (_, _) => const SizedBox(height: BraiseSpacing.lg),
      itemBuilder: (context, index) => _LikerCard(
        candidate: data.candidates[index],
        busy: _acting.contains(data.candidates[index].userId),
        onLikeBack: () => _respond(data.candidates[index], 'like'),
        onPass: () => _respond(data.candidates[index], 'pass'),
      ),
    );
  }
}

class _LikerCard extends StatelessWidget {
  const _LikerCard({
    required this.candidate,
    required this.busy,
    required this.onLikeBack,
    required this.onPass,
  });

  final DiscoveryCandidate candidate;
  final bool busy;
  final VoidCallback onLikeBack;
  final VoidCallback onPass;

  @override
  Widget build(BuildContext context) {
    final tokens = BraiseTokens.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(BraiseSpacing.lg),
      decoration: BoxDecoration(
        color: tokens.surface1,
        border: Border.all(color: tokens.borderHairline),
        borderRadius: BorderRadius.circular(BraiseRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AvatarSigil(spec: candidate.avatar, size: 48),
              const SizedBox(width: BraiseSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${candidate.displayName} · ${candidate.age}', style: textTheme.titleMedium),
                    if (candidate.commonInterests.isNotEmpty)
                      Text(
                        '${candidate.commonInterests.length} intérêts en commun',
                        style: textTheme.bodySmall?.copyWith(color: tokens.inkSecondary),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: BraiseSpacing.md),
          Text(
            candidate.bio.isEmpty ? 'Pas encore de bio.' : '« ${candidate.bio} »',
            style: textTheme.bodyMedium,
          ),
          const SizedBox(height: BraiseSpacing.lg),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : onPass,
                  child: const Text('Passer'),
                ),
              ),
              const SizedBox(width: BraiseSpacing.md),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: busy ? null : onLikeBack,
                  icon: SignDiamond(color: tokens.braiseFillText, size: 16),
                  label: const Text('Braiser en retour'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
