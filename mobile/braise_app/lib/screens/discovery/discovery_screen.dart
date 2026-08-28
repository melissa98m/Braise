import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_exception.dart';
import '../../models/discovery.dart';
import '../../state/app_services.dart';
import '../../theme/braise_tokens.dart';
import '../../widgets/avatar_sigil.dart';

/// Écran 03 — pas de swipe façon catalogue : une carte à la fois, hiérarchie phrase > intérêts
/// > avatar (cahier des charges A.7 : refuse le tri purement visuel).
class DiscoveryScreen extends StatefulWidget {
  const DiscoveryScreen({super.key});

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen> {
  List<DiscoveryCandidate> _feed = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFeed();
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
    if (_feed.isEmpty) return;
    final candidate = _feed.first;
    final services = context.read<AppServices>();
    try {
      final matched = await services.discoveryApi.swipe(candidate.userId, decision);
      setState(() => _feed = _feed.sublist(1));
      if (matched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Vous avez matché avec ${candidate.displayName} !')),
        );
      }
    } on ApiException catch (e) {
      if (e.isPaymentRequired && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      } else {
        setState(() => _error = e.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = BraiseTokens.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Découvrir')),
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
                  Expanded(child: _CandidateCard(candidate: _feed.first)),
                  const SizedBox(height: BraiseSpacing.xl),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _swipe('pass'),
                          child: const Text('Passer'),
                        ),
                      ),
                      const SizedBox(width: BraiseSpacing.md),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: () => _swipe('like'),
                          child: Text('Répondre à ${_feed.first.displayName}'),
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
              Text('${candidate.displayName} · ${candidate.age}', style: textTheme.titleMedium),
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
