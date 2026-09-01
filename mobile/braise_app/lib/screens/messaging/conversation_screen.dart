import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_exception.dart';
import '../../api/messaging_api.dart';
import '../../models/discovery.dart';
import '../../models/messaging.dart';
import '../../notifications/notification_prefs.dart';
import '../../state/app_services.dart';
import '../../theme/braise_tokens.dart';
import '../../widgets/braise_page_route.dart';
import '../../widgets/flame_diamonds.dart';
import '../moderation/report_screen.dart';
import '../rating/rating_screen.dart';
import '../unlock/unlock_screen.dart';

/// Écran 04 — la progression reste lisible en permanence (diamants pleins/vides dans l'en-tête,
/// jamais une seule couleur) ; le quiz du jour redirige vers la relecture du profil en cas
/// d'erreur, jamais une pénalité (cahier des charges A.7).
class ConversationScreen extends StatefulWidget {
  const ConversationScreen({super.key, required this.match, this.chatSocketFactory});

  final MatchSummary match;

  /// Injectable (P10) : `null` en production (`ChatSocket.new`, vraie connexion), un factice
  /// dans les tests d'écran — même motif que `AppServices(httpClient: ...)`. `ChatSocket` lui-même
  /// accepte déjà un `channel` factice ; ce champ est ce qui permet à un test de fournir ce canal
  /// au moment précis où `_connect()` construit le socket, sans que `ConversationScreen` ait
  /// besoin de connaître `StreamChannelController` lui-même.
  final ChatSocket Function({required String matchId, required String token})? chatSocketFactory;

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

  String? _myId;
  bool _otherIsTyping = false;
  Timer? _typingClearTimer;
  DateTime _lastTypingSentAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _match = widget.match;
    _myId = context.read<AppServices>().authController.userId;
    _connect();
    _loadHistory();
    _loadDailyQuestion();
  }

  Future<void> _connect() async {
    final services = context.read<AppServices>();
    final token = services.authController.token;
    if (token == null) return;
    final factory = widget.chatSocketFactory ?? ChatSocket.new;
    final socket = factory(matchId: _match.matchId, token: token);
    socket.messages.listen((message) {
      if (!mounted) return;
      setState(() => _messages.add(message));
      _scrollToEnd();
      // On regarde activement l'écran quand ce message arrive : on marque tout de suite comme
      // lu plutôt que d'attendre une action explicite qui n'existe pas dans cette UI.
      if (message.senderId != _myId) {
        socket.markRead();
        unawaited(_maybeNotifyNewMessage(services, message));
      }
    });
    socket.typingEvents.listen((event) {
      if (!mounted || event.senderId == _myId) return;
      _typingClearTimer?.cancel();
      setState(() => _otherIsTyping = true);
      // Pas de "stopped typing" explicite dans le protocole : on efface simplement l'indicateur
      // si aucun nouvel événement n'arrive avant ce délai, ce qui reste imperceptible pour
      // quelqu'un qui écrit en continu (les navigateurs renvoient bien plus souvent que ça).
      _typingClearTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _otherIsTyping = false);
      });
    });
    socket.readEvents.listen((event) {
      if (!mounted || event.readerId == _myId) return;
      setState(() {
        for (var i = 0; i < _messages.length; i++) {
          final message = _messages[i];
          if (message.senderId == _myId && !message.createdAt.isAfter(event.readAt)) {
            _messages[i] = message.copyWith(read: true);
          }
        }
      });
    });
    setState(() => _socket = socket);
  }

  /// P9.1 : vraie notification navigateur pour un message reçu pendant que la conversation est
  /// ouverte — n'affiche rien si la préférence "Messages" est désactivée ou si la permission
  /// navigateur n'a jamais été accordée. `defaultValue: false` reprend celui de `SettingsScreen`
  /// (seule des 3 préférences désactivée par défaut).
  Future<void> _maybeNotifyNewMessage(AppServices services, ChatMessage message) async {
    if (!await NotificationPrefs.isEnabled(NotificationPrefs.messages, defaultValue: false)) {
      return;
    }
    if (!mounted) return;
    services.notificationsService.show(
      title: 'Nouveau message de ${_match.otherDisplayName}',
      body: message.body,
    );
  }

  Future<void> _loadHistory() async {
    final services = context.read<AppServices>();
    final history = await services.messagingApi.getMessages(_match.matchId);
    if (!mounted) return;
    setState(() => _messages.insertAll(0, history));
    _scrollToEnd();
    _socket?.markRead();
  }

  void _onComposerChanged(String _) {
    final now = DateTime.now();
    if (now.difference(_lastTypingSentAt) < const Duration(seconds: 2)) return;
    _lastTypingSentAt = now;
    _socket?.sendTyping();
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
        prompt: _dailyQuestion!.prompt,
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
              onTap: () => Navigator.of(
                context,
              ).push(braiseRoute(context, UnlockScreen(match: _match))),
            ),
          _Banner(
            text: 'Noter cet échange',
            color: tokens.voileInk,
            onTap: () => Navigator.of(
              context,
            ).push(braiseRoute(context, RatingScreen(match: _match))),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(BraiseSpacing.lg),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                final isMine = message.senderId == myId;
                // Coin "queue" resserré (6px) du côté de l'émetteur — même asymétrie que la
                // maquette, pas un simple rectangle arrondi uniforme.
                final radius = BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isMine ? 18 : 6),
                  bottomRight: Radius.circular(isMine ? 6 : 18),
                );
                // Le statut de lecture (cahier des charges A.5) ne s'affiche que sous le tout
                // dernier message qu'on a envoyé soi-même — un tick par bulle serait du bruit.
                final isLastOfMine =
                    isMine && !_messages.skip(index + 1).any((m) => m.senderId == myId);
                return Column(
                  crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: [
                    Align(
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
                          borderRadius: radius,
                        ),
                        child: Text(message.body, style: textTheme.bodyLarge),
                      ),
                    ),
                    if (isLastOfMine)
                      Padding(
                        padding: const EdgeInsets.only(right: BraiseSpacing.xs, bottom: BraiseSpacing.sm),
                        child: Text(
                          message.read ? 'Lu' : 'Envoyé',
                          style: textTheme.labelSmall?.copyWith(
                            color: message.read ? tokens.foiInk : tokens.inkFloor,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          if (_otherIsTyping)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: BraiseSpacing.lg),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${_match.otherDisplayName} est en train d\'écrire…',
                  style: textTheme.labelSmall?.copyWith(color: tokens.inkSecondary),
                ),
              ),
            ),
          if (!_loadingQuestion && _dailyQuestion != null) _DailyQuestionCard(
            question: _dailyQuestion!,
            onAnswer: _answer,
          ),
          Padding(
            padding: const EdgeInsets.only(top: BraiseSpacing.sm),
            child: Center(
              child: TextButton(
                onPressed: () => Navigator.of(
                  context,
                ).push(braiseRoute(context, ReportScreen(match: _match))),
                child: Text(
                  'Signaler ce profil',
                  style: textTheme.labelSmall?.copyWith(
                    color: tokens.inkSecondary,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(BraiseSpacing.lg),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _bodyController,
                    decoration: InputDecoration(hintText: 'Écrire à ${_match.otherDisplayName}…'),
                    onChanged: _onComposerChanged,
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
    _typingClearTimer?.cancel();
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
        boxShadow: [BoxShadow(color: tokens.braiseInk.withValues(alpha: 0.14), blurRadius: 40)],
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
                Text(question.prompt, style: textTheme.bodyLarge),
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
