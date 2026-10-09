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
import '../../utils/validators.dart';
import '../../widgets/braise_page_route.dart';
import '../../widgets/flame_diamonds.dart';
import '../moderation/report_screen.dart';
import '../profile/partner_profile_screen.dart';
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

  // Petit retour tactile sur l'envoi (scale du bouton + fondu bref du composeur) — jamais
  // déclenché si `disableAnimations` (voir `_send()`), donc `_sendPulse` reste toujours `false`
  // dans ce cas et les deux widgets animés qui le lisent restent immobiles.
  bool _sendPulse = false;

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
      // reçu (immédiatement, avant même le "read" ci-dessous) puis lu plutôt que d'attendre une
      // action explicite qui n'existe pas dans cette UI.
      if (message.senderId != _myId) {
        socket.markDelivered();
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
    socket.deliveredEvents.listen((event) {
      if (!mounted || event.delivererId == _myId) return;
      setState(() {
        for (var i = 0; i < _messages.length; i++) {
          final message = _messages[i];
          if (message.senderId == _myId &&
              !message.delivered &&
              !message.createdAt.isAfter(event.deliveredAt)) {
            _messages[i] = message.copyWith(delivered: true, deliveredAt: event.deliveredAt);
          }
        }
      });
    });
    socket.readEvents.listen((event) {
      if (!mounted || event.readerId == _myId) return;
      setState(() {
        for (var i = 0; i < _messages.length; i++) {
          final message = _messages[i];
          if (message.senderId == _myId && !message.createdAt.isAfter(event.readAt)) {
            // Lire implique avoir reçu : si aucun "delivered" explicite n'est encore arrivé
            // (ex. les deux frames se doublent en pratique, voir markDelivered() ci-dessus), le
            // "read" fait quand même progresser l'accusé de réception plutôt que de le laisser
            // en retard sur la lecture (même règle que services/matches.mark_read côté serveur).
            _messages[i] = message.copyWith(
              read: true,
              readAt: event.readAt,
              delivered: true,
              deliveredAt: message.deliveredAt ?? event.readAt,
            );
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
    if (!await NotificationPrefs.isEnabled(
      NotificationPrefs.messages,
      defaultValue: NotificationPrefs.defaultFor(NotificationPrefs.messages),
    )) {
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
    // Déclenche le pop du bouton + le bref fondu du composeur (voir build()) ; jamais déclenché
    // sous mouvement réduit, plutôt que de compter uniquement sur une durée à zéro — même
    // convention "guard the trigger" que le reste de l'app (ex. FlameDiamonds).
    if (!MediaQuery.of(context).disableAnimations) {
      setState(() => _sendPulse = true);
    }
  }

  // Trois états, jamais quatre : "Envoyé" (le serveur l'a persisté, personne d'autre ne l'a
  // encore reçu), "Reçu" (l'autre l'a effectivement reçu mais pas encore lu) et "Lu à HH:mm"
  // (l'heure exacte à laquelle le destinataire a marqué la conversation comme lue — voir
  // backend/CLAUDE.md, services/matches.message_read_at).
  String _statusLabel(ChatMessage message) {
    if (message.read) return 'Lu à ${_formatTime(message.readAt ?? message.createdAt)}';
    if (message.delivered) return 'Reçu';
    return 'Envoyé';
  }

  String _formatTime(DateTime dateTime) {
    final local = dateTime.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        final duration = MediaQuery.of(context).disableAnimations
            ? Duration.zero
            : const Duration(milliseconds: 200);
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: duration,
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
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final pulseDuration = reduceMotion ? Duration.zero : const Duration(milliseconds: 130);

    return Scaffold(
      appBar: AppBar(
        // Titre tappable vers PartnerProfileScreen — même geste que les icon-only tappables
        // ailleurs dans l'app (P15) : Semantics(button: true, label: ...) explicite plutôt que
        // de compter sur le seul InkWell, qui ne porte aucune sémantique de bouton par défaut.
        title: InkWell(
          onTap: () => Navigator.of(
            context,
          ).push(braiseRoute(context, PartnerProfileScreen(match: _match))),
          child: Semantics(
            button: true,
            label: '${_match.otherDisplayName}, voir le profil',
            excludeSemantics: true,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: Text(_match.otherDisplayName, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: BraiseSpacing.xs),
                const Icon(Icons.chevron_right, size: 18),
              ],
            ),
          ),
        ),
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
                // Clé stable par message : garantit que l'animation d'entrée ne rejoue jamais sur
                // un simple rebuild (ex. flip "Envoyé" -> "Lu"), et que l'insertion en tête lors
                // de `_loadHistory` (insertAll(0, ...)) ne mélange pas l'état de widgets voisins.
                return _AnimatedMessageBubble(
                  key: ValueKey(message.id),
                  reduceMotion: reduceMotion,
                  isMine: isMine,
                  child: Column(
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
                          padding: const EdgeInsets.only(
                            right: BraiseSpacing.xs,
                            bottom: BraiseSpacing.sm,
                          ),
                          // Le statut passe de "Envoyé" à "Reçu" puis "Lu à HH:mm" en fondu plutôt
                          // qu'en changement de texte instantané — borné (AnimatedSwitcher fait un
                          // seul crossfade fini), donc sans risque pour pumpAndSettle même hors
                          // mouvement réduit.
                          child: AnimatedSwitcher(
                            duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 220),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeOutCubic,
                            child: Text(
                              _statusLabel(message),
                              key: ValueKey('${message.delivered}-${message.read}'),
                              style: textTheme.labelSmall?.copyWith(
                                color: message.read ? tokens.foiInk : tokens.inkFloor,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          if (_otherIsTyping)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: BraiseSpacing.lg,
                vertical: BraiseSpacing.xs,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${_match.otherDisplayName} est en train d\'écrire',
                      style: textTheme.labelSmall?.copyWith(color: tokens.inkSecondary),
                    ),
                    const SizedBox(width: BraiseSpacing.xs),
                    _TypingDots(reduceMotion: reduceMotion, color: tokens.inkSecondary),
                  ],
                ),
              ),
            ),
          if (!_loadingQuestion && _dailyQuestion != null) _DailyQuestionCard(
            question: _dailyQuestion!,
            onAnswer: _answer,
            reduceMotion: reduceMotion,
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
                  // Bref fondu au moment de l'envoi plutôt qu'un effacement sec du composeur —
                  // `onEnd` (borné, un seul aller-retour) ramène `_sendPulse` à `false`, ce qui
                  // fait redescendre à la fois ce fondu et le pop du bouton ci-dessous ensemble.
                  child: AnimatedOpacity(
                    opacity: _sendPulse ? 0.55 : 1,
                    duration: pulseDuration,
                    curve: Curves.easeOutCubic,
                    onEnd: () {
                      if (_sendPulse) setState(() => _sendPulse = false);
                    },
                    child: TextField(
                      controller: _bodyController,
                      maxLength: messageMaxLength,
                      decoration: InputDecoration(
                        hintText: 'Écrire à ${_match.otherDisplayName}…',
                        counterText: '',
                      ),
                      onChanged: _onComposerChanged,
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                ),
                const SizedBox(width: BraiseSpacing.sm),
                AnimatedScale(
                  scale: _sendPulse ? 1.18 : 1,
                  duration: pulseDuration,
                  curve: Curves.easeOutCubic,
                  child: IconButton.filled(onPressed: _send, icon: const Icon(Icons.arrow_upward)),
                ),
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
  const _DailyQuestionCard({
    required this.question,
    required this.onAnswer,
    required this.reduceMotion,
  });

  final DailyQuestion question;
  final ValueChanged<String> onAnswer;
  final bool reduceMotion;

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
          // Transition en fondu entre "question ouverte" et "réponse envoyée" plutôt qu'un
          // remplacement instantané — un seul crossfade borné (AnimatedSwitcher), sans risque
          // pour pumpAndSettle.
          AnimatedSwitcher(
            duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 280),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeOutCubic,
            child: question.answered
                ? Text(
                    key: const ValueKey('answered'),
                    question.isCorrect == true
                        ? 'Bonne réponse envoyée aujourd\'hui.'
                        : 'Réponse envoyée aujourd\'hui — revenez demain.',
                    style: textTheme.bodyLarge,
                  )
                : Column(
                    key: const ValueKey('unanswered'),
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
          ),
        ],
      ),
    );
  }
}

/// Entrée d'une bulle de message : léger fondu + glissement latéral (depuis la droite pour les
/// messages envoyés, depuis la gauche pour les reçus) — ne rejoue jamais sur un simple rebuild
/// grâce à la `key` stable posée par l'appelant (`ValueKey(message.id)`), qui préserve l'état de
/// ce widget d'un build à l'autre. Toujours désactivé sous mouvement réduit.
class _AnimatedMessageBubble extends StatelessWidget {
  const _AnimatedMessageBubble({
    super.key,
    required this.reduceMotion,
    required this.isMine,
    required this.child,
  });

  final bool reduceMotion;
  final bool isMine;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (reduceMotion) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) {
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset((1 - t) * (isMine ? 14 : -14), 0),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// Trois points en "vague" à l'apparition de l'indicateur de frappe — un seul aller borné
/// (`TweenAnimationBuilder` non bouclé), jamais une boucle infinie : un `AnimationController.
/// repeat()` casserait `pumpAndSettle()` dans les tests (même piège que documenté pour
/// `PaywallScreen._PulsingDiamond`, voir CLAUDE.md), et ce widget se démonte/remonte à chaque
/// apparition de l'indicateur (il est sous un `if` dans build()) donc rejoue naturellement à
/// chaque fois sans avoir besoin d'une clé dédiée.
class _TypingDots extends StatelessWidget {
  const _TypingDots({required this.reduceMotion, required this.color});

  final bool reduceMotion;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (reduceMotion) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Dot(color: color, opacity: 1),
          _Dot(color: color, opacity: 1),
          _Dot(color: color, opacity: 1),
        ],
      );
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 640),
      curve: Curves.linear,
      builder: (context, t, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final localT = ((t - i * 0.16) / 0.62).clamp(0.0, 1.0);
            final eased = Curves.easeOutCubic.transform(localT);
            return _Dot(color: color, opacity: eased, scale: 0.5 + 0.5 * eased);
          }),
        );
      },
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.opacity, this.scale = 1});

  final Color color;
  final double opacity;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Transform.scale(
        scale: scale,
        child: Container(
          width: 5,
          height: 5,
          margin: const EdgeInsets.symmetric(horizontal: 1.5),
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}
