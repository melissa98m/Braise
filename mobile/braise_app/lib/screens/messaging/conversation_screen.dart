import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_exception.dart';
import '../../api/messaging_api.dart';
import '../../models/discovery.dart';
import '../../models/messaging.dart';
import '../../state/app_services.dart';
import '../../theme/braise_tokens.dart';
import '../../widgets/flame_diamonds.dart';
import '../rating/rating_screen.dart';
import '../unlock/unlock_screen.dart';

/// Écran 04 — la progression reste lisible en permanence (diamants pleins/vides dans l'en-tête,
/// jamais une seule couleur) ; le quiz du jour redirige vers la relecture du profil en cas
/// d'erreur, jamais une pénalité (cahier des charges A.7).
class ConversationScreen extends StatefulWidget {
  const ConversationScreen({super.key, required this.match});

  final MatchSummary match;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final _bodyController = TextEditingController();
  final _scrollController = ScrollController();

  late MatchSummary _match;
  ChatSocket? _socket;
  final List<ChatMessage> _messages = [];
  DailyQuestion? _dailyQuestion;
  bool _loadingQuestion = true;

  @override
  void initState() {
    super.initState();
    _match = widget.match;
    _connect();
    _loadHistory();
    _loadDailyQuestion();
  }

  Future<void> _connect() async {
    final services = context.read<AppServices>();
    final token = services.authController.token;
    if (token == null) return;
    final socket = ChatSocket(matchId: _match.matchId, token: token);
    socket.messages.listen((message) {
      if (!mounted) return;
      setState(() => _messages.add(message));
      _scrollToEnd();
    });
    setState(() => _socket = socket);
  }

  Future<void> _loadHistory() async {
    final services = context.read<AppServices>();
    final history = await services.messagingApi.getMessages(_match.matchId);
    if (!mounted) return;
    setState(() => _messages.insertAll(0, history));
    _scrollToEnd();
  }

  Future<void> _loadDailyQuestion() async {
    final services = context.read<AppServices>();
    try {
      final question = await services.messagingApi.getDailyQuestion(_match.matchId);
      setState(() {
        _dailyQuestion = question;
        _loadingQuestion = false;
      });
    } on ApiException {
      // Pas de question dispensable aujourd'hui (ex. l'autre n'a pas encore d'intérêts déclarés) :
      // on masque simplement la carte plutôt que d'afficher une erreur.
      setState(() => _loadingQuestion = false);
    }
  }

  Future<void> _answer(String selected) async {
    final services = context.read<AppServices>();
    final result = await services.messagingApi.answerDailyQuestion(_match.matchId, selected);
    setState(() {
      _dailyQuestion = DailyQuestion(
        options: _dailyQuestion!.options,
        answered: true,
        isCorrect: result.correct,
      );
      _match = MatchSummary(
        matchId: _match.matchId,
        otherUserId: _match.otherUserId,
        otherDisplayName: _match.otherDisplayName,
        flameCount: result.flameCount,
        unlockThreshold: _match.unlockThreshold,
        unlockPct: (result.flameCount / _match.unlockThreshold * 100).clamp(0, 100).round(),
        blurStage: result.flameCount >= _match.unlockThreshold ? 'net' : _match.blurStage,
        matchedAt: _match.matchedAt,
      );
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.correct
              ? 'Bonne réponse ! +1 flamme pour vous deux.'
              : "Ce n'était pas ça — réponse : ${result.correctAnswer}. Pas de pénalité, juste une relecture.",
        ),
      ),
    );
  }

  void _send() {
    final body = _bodyController.text.trim();
    if (body.isEmpty || _socket == null) return;
    _socket!.send(body);
    _bodyController.clear();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = BraiseTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    final myId = context.read<AppServices>().authController.userId;

    return Scaffold(
      appBar: AppBar(
        title: Text(_match.otherDisplayName),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: BraiseSpacing.lg),
            child: Center(
              child: FlameDiamonds(filled: _match.flameCount, total: _match.unlockThreshold),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_match.isUnlocked)
            _Banner(
              text: 'Profil privé débloqué — voir les photos',
              color: tokens.foiInk,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => UnlockScreen(match: _match)),
              ),
            ),
          _Banner(
            text: 'Noter cet échange',
            color: tokens.voileInk,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => RatingScreen(match: _match)),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(BraiseSpacing.lg),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                final isMine = message.senderId == myId;
                return Align(
                  alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: BraiseSpacing.xs),
                    padding: const EdgeInsets.all(BraiseSpacing.md),
                    constraints: const BoxConstraints(maxWidth: 280),
                    decoration: BoxDecoration(
                      color: isMine ? tokens.braiseTint : tokens.surface2,
                      border: Border.all(
                        color: isMine ? tokens.braiseInk : tokens.borderHairline,
                      ),
                      borderRadius: BorderRadius.circular(BraiseRadii.card),
                    ),
                    child: Text(message.body, style: textTheme.bodyLarge),
                  ),
                );
              },
            ),
          ),
          if (!_loadingQuestion && _dailyQuestion != null) _DailyQuestionCard(
            question: _dailyQuestion!,
            onAnswer: _answer,
          ),
          Padding(
            padding: const EdgeInsets.all(BraiseSpacing.lg),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _bodyController,
                    decoration: InputDecoration(hintText: 'Écrire à ${_match.otherDisplayName}…'),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: BraiseSpacing.sm),
                IconButton.filled(onPressed: _send, icon: const Icon(Icons.arrow_upward)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _socket?.close();
    _bodyController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.color, required this.onTap});

  final String text;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(BraiseSpacing.md),
        color: color.withValues(alpha: 0.14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color)),
            const SizedBox(width: BraiseSpacing.xs),
            Icon(Icons.chevron_right, color: color, size: 18),
          ],
        ),
      ),
    );
  }
}

class _DailyQuestionCard extends StatelessWidget {
  const _DailyQuestionCard({required this.question, required this.onAnswer});

  final DailyQuestion question;
  final ValueChanged<String> onAnswer;

  @override
  Widget build(BuildContext context) {
    final tokens = BraiseTokens.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: BraiseSpacing.lg),
      padding: const EdgeInsets.all(BraiseSpacing.lg),
      decoration: BoxDecoration(
        color: tokens.surface1,
        border: Border.all(color: tokens.braiseInk, width: 1.75),
        borderRadius: BorderRadius.circular(BraiseRadii.keyCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'QUESTION DU JOUR',
            style: textTheme.labelSmall?.copyWith(color: tokens.braiseInk),
          ),
          const SizedBox(height: BraiseSpacing.sm),
          if (question.answered)
            Text(
              question.isCorrect == true
                  ? 'Bonne réponse envoyée aujourd\'hui.'
                  : 'Réponse envoyée aujourd\'hui — revenez demain.',
              style: textTheme.bodyLarge,
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final option in question.options)
                  Padding(
                    padding: const EdgeInsets.only(top: BraiseSpacing.sm),
                    child: OutlinedButton(
                      onPressed: () => onAnswer(option),
                      style: OutlinedButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        minimumSize: const Size.fromHeight(52),
                      ),
                      child: Text(option),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
