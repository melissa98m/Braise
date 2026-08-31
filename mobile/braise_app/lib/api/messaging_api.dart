import 'dart:async';
import 'dart:convert';

import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/messaging.dart';
import 'api_client.dart';
import 'api_config.dart';

class MessagingApi {
  MessagingApi(this._client);
  final ApiClient _client;

  Future<List<ChatMessage>> getMessages(String matchId, {int limit = 50}) async {
    final json = await _client.get(
      '/messaging/matches/$matchId/messages',
      query: {'limit': '$limit'},
    );
    return (json as List).map((m) => ChatMessage.fromJson(m as Map<String, dynamic>)).toList();
  }

  Future<DailyQuestion> getDailyQuestion(String matchId) async {
    final json = await _client.get('/messaging/matches/$matchId/daily-question');
    return DailyQuestion.fromJson(json as Map<String, dynamic>);
  }

  Future<DailyQuestionResult> answerDailyQuestion(String matchId, String selected) async {
    final json = await _client.post(
      '/messaging/matches/$matchId/daily-question/answer',
      body: {'selected': selected},
    );
    return DailyQuestionResult.fromJson(json as Map<String, dynamic>);
  }
}

/// Notifie que `senderId` est en train d'écrire — éphémère, jamais stocké côté serveur (voir
/// api/v1/messaging.py::chat_ws).
class TypingEvent {
  const TypingEvent(this.senderId);
  final String senderId;
}

/// `readerId` a marqué la conversation comme lue jusqu'à `readAt` — sert à mettre à jour le
/// coche "lu" des messages qu'on a soi-même envoyés (voir ConversationScreen).
class ReadEvent {
  const ReadEvent(this.readerId, this.readAt);
  final String readerId;
  final DateTime readAt;
}

/// Connexion WebSocket au chat d'un match. Le token voyage en query string : un navigateur ne
/// peut pas poser de header Authorization sur une poignée de main WebSocket (voir
/// backend/CLAUDE.md, même contrainte des deux côtés).
///
/// `channel` optionnel (P10) : `null` en production (vraie connexion `WebSocketChannel.connect`),
/// un `StreamChannelController().local`/`.foreign` factice dans les tests d'écran — même motif
/// d'injection que `ApiClient(httpClient: ...)`. Typé `StreamChannel<dynamic>` plutôt que
/// `WebSocketChannel` (que `WebSocketChannel.connect` renvoie bien, `WebSocketChannel` en étant
/// un) précisément pour que ce champ accepte aussi le canal factice des tests, qui n'a pas de
/// vraie connexion WebSocket derrière lui.
class ChatSocket {
  ChatSocket({required String matchId, required String token, StreamChannel<dynamic>? channel})
    : _channel =
          channel ??
          WebSocketChannel.connect(
            Uri.parse('${ApiConfig.wsBaseUrl}/messaging/ws/$matchId?token=$token'),
          ) {
    // Un seul flux brut, démultiplexé en 3 par type — le serveur tague déjà chaque frame
    // ("message"/"typing"/"read", voir api/v1/messaging.py), donc pas besoin d'une classe
    // d'union scellée pour ça.
    final raw = _channel.stream
        .map((data) => jsonDecode(data as String) as Map<String, dynamic>)
        .asBroadcastStream();

    _messages = raw
        .where((json) => (json['type'] as String? ?? 'message') == 'message')
        .map(ChatMessage.fromJson);
    _typing = raw
        .where((json) => json['type'] == 'typing')
        .map((json) => TypingEvent(json['sender_id'] as String));
    _reads = raw
        .where((json) => json['type'] == 'read')
        .map(
          (json) => ReadEvent(json['reader_id'] as String, DateTime.parse(json['read_at'] as String)),
        );
  }

  final StreamChannel<dynamic> _channel;
  late final Stream<ChatMessage> _messages;
  late final Stream<TypingEvent> _typing;
  late final Stream<ReadEvent> _reads;

  Stream<ChatMessage> get messages => _messages;
  Stream<TypingEvent> get typingEvents => _typing;
  Stream<ReadEvent> get readEvents => _reads;

  void send(String body) {
    _channel.sink.add(jsonEncode({'type': 'message', 'body': body}));
  }

  void sendTyping() {
    _channel.sink.add(jsonEncode({'type': 'typing'}));
  }

  void markRead() {
    _channel.sink.add(jsonEncode({'type': 'read'}));
  }

  Future<void> close() => _channel.sink.close();
}
