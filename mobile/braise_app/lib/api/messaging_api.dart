import 'dart:async';
import 'dart:convert';

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

/// Connexion WebSocket au chat d'un match. Le token voyage en query string : un navigateur ne
/// peut pas poser de header Authorization sur une poignée de main WebSocket (voir
/// backend/CLAUDE.md, même contrainte des deux côtés).
class ChatSocket {
  ChatSocket({required String matchId, required String token})
    : _channel = WebSocketChannel.connect(
        Uri.parse('${ApiConfig.wsBaseUrl}/messaging/ws/$matchId?token=$token'),
      ) {
    _messages = _channel.stream
        .map((raw) => ChatMessage.fromJson(jsonDecode(raw as String) as Map<String, dynamic>))
        .asBroadcastStream();
  }

  final WebSocketChannel _channel;
  late final Stream<ChatMessage> _messages;

  Stream<ChatMessage> get messages => _messages;

  void send(String body) {
    _channel.sink.add(jsonEncode({'body': body}));
  }

  Future<void> close() => _channel.sink.close();
}
