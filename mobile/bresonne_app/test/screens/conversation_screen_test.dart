// ConversationScreen was the one screen this project's HTTP-mock infra couldn't reach: it talks
// over a real WebSocket (ChatSocket), with no injectable channel. P10 gave ChatSocket an
// injectable `channel` (StreamChannel<dynamic>, defaults to a real WebSocketChannel.connect) and
// ConversationScreen an injectable `chatSocketFactory`, the same pattern as
// AppServices(httpClient: ...). Tests here use package:stream_channel's StreamChannelController
// to get two connected fake ends: ChatSocket holds `.local`, so writing to `.foreign.sink`
// simulates a frame from the server, and listening to `.foreign.stream` captures whatever
// ChatSocket actually sends.

import 'dart:convert';

import 'package:bresonne_app/api/messaging_api.dart';
import 'package:bresonne_app/models/discovery.dart';
import 'package:bresonne_app/screens/messaging/conversation_screen.dart';
import 'package:bresonne_app/state/app_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stream_channel/stream_channel.dart';

/// Voir test/screens/ban_appeal_screen_test.dart pour pourquoi ce helper existe :
/// `http.Response(String, ...)` retombe sur Latin-1 sans en-tête Content-Type explicite, ce qui
/// casse `utf8.decode` côté `ApiClient._decode` dès qu'un accent apparaît (partout, en français).
http.Response _json(Object data, int status) {
  return http.Response(
    jsonEncode(data),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

final _match = MatchSummary(
  matchId: 'match-1',
  otherUserId: 'user-2',
  otherDisplayName: 'Camille',
  flameCount: 2,
  unlockThreshold: 5,
  unlockPct: 40,
  blurStage: 'flou_leger',
  matchedAt: DateTime(2026, 1, 1),
);

Map<String, dynamic> _message({
  required String id,
  required String senderId,
  required String body,
  bool read = false,
  DateTime? createdAt,
}) => {
  'id': id,
  'match_id': _match.matchId,
  'sender_id': senderId,
  'body': body,
  'created_at': (createdAt ?? DateTime(2026, 1, 1, 12)).toIso8601String(),
  'read': read,
};

/// Construit l'écran avec un `ChatSocket` branché sur un canal factice — jamais de vraie
/// connexion réseau. Renvoie aussi le contrôleur pour que le test puisse simuler des frames
/// serveur (`controller.foreign.sink.add(...)`) et observer ce que l'écran envoie
/// (`controller.foreign.stream`).
({Widget widget, StreamChannelController<dynamic> controller}) _harness(
  AppServices services,
) {
  final controller = StreamChannelController<dynamic>();
  final widget = MultiProvider(
    providers: [Provider<AppServices>.value(value: services)],
    child: MaterialApp(
      home: ConversationScreen(
        match: _match,
        chatSocketFactory: ({required matchId, required token}) =>
            ChatSocket(matchId: matchId, token: token, channel: controller.local),
      ),
    ),
  );
  return (widget: widget, controller: controller);
}

Future<AppServices> _signedInServices(http.Client client) async {
  SharedPreferences.setMockInitialValues({'braise_token': 'token-1'});
  final services = AppServices(httpClient: client);
  await services.authController.restoreSession();
  return services;
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('loads and shows the message history', (tester) async {
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/auth/me') {
        return _json({'id': 'me', 'phone': '+33600000000'}, 200);
      }
      if (request.method == 'GET' &&
          request.url.path == '/messaging/matches/${_match.matchId}/messages') {
        return _json([
          _message(id: 'm1', senderId: 'user-2', body: 'Salut !'),
          _message(id: 'm2', senderId: 'me', body: 'Hello.'),
        ], 200);
      }
      if (request.method == 'GET' &&
          request.url.path == '/messaging/matches/${_match.matchId}/daily-question') {
        return _json({'detail': 'Pas de question aujourd\'hui.'}, 404);
      }
      return http.Response('not found', 404);
    });

    final services = await _signedInServices(client);
    final harness = _harness(services);
    await tester.pumpWidget(harness.widget);
    await tester.pumpAndSettle();

    expect(find.text('Salut !'), findsOneWidget);
    expect(find.text('Hello.'), findsOneWidget);
  });

  testWidgets('a message received over the socket appears and gets marked read', (
    tester,
  ) async {
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/auth/me') {
        return _json({'id': 'me', 'phone': '+33600000000'}, 200);
      }
      if (request.method == 'GET' &&
          request.url.path == '/messaging/matches/${_match.matchId}/messages') {
        return _json([], 200);
      }
      if (request.method == 'GET' &&
          request.url.path == '/messaging/matches/${_match.matchId}/daily-question') {
        return _json({'detail': 'Pas de question aujourd\'hui.'}, 404);
      }
      return http.Response('not found', 404);
    });

    final services = await _signedInServices(client);
    final harness = _harness(services);
    await tester.pumpWidget(harness.widget);
    await tester.pumpAndSettle();

    // `expectLater`/`emitsThrough` plutôt qu'un `.listen()` manuel sur `foreign.stream` : ce
    // dernier fait planter le test sous la zone FakeAsync de flutter_test (le simple fait
    // d'attacher un écouteur bloque indéfiniment `pumpAndSettle`, sans rapport avec ce que fait
    // réellement ChatSocket) — `expectLater` sait s'intégrer correctement avec le contrôle du
    // temps du test. `emitsThrough` plutôt que `emits` : `_loadHistory()` envoie déjà un "read"
    // à l'ouverture (avant même le message injecté ci-dessous), donc le tout premier événement
    // du flux n'est pas forcément celui qu'on veut vérifier — seul compte qu'un "read" apparaisse
    // à un moment ou un autre après réception du message.
    final readSent = expectLater(
      harness.controller.foreign.stream,
      emitsThrough(predicate<String>((raw) => (jsonDecode(raw) as Map)['type'] == 'read')),
    );

    harness.controller.foreign.sink.add(
      jsonEncode(_message(id: 'm3', senderId: 'user-2', body: 'Tu es là ?')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tu es là ?'), findsOneWidget);
    await readSent;
  });

  testWidgets('sending a message clears the composer and sends it over the socket', (
    tester,
  ) async {
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/auth/me') {
        return _json({'id': 'me', 'phone': '+33600000000'}, 200);
      }
      if (request.method == 'GET' &&
          request.url.path == '/messaging/matches/${_match.matchId}/messages') {
        return _json([], 200);
      }
      if (request.method == 'GET' &&
          request.url.path == '/messaging/matches/${_match.matchId}/daily-question') {
        return _json({'detail': 'Pas de question aujourd\'hui.'}, 404);
      }
      return http.Response('not found', 404);
    });

    final services = await _signedInServices(client);
    final harness = _harness(services);
    await tester.pumpWidget(harness.widget);
    await tester.pumpAndSettle();

    // `emitsThrough` : le composeur envoie aussi un "typing" avant le "message" (voir
    // _onComposerChanged), donc le "message" n'est pas forcément le tout premier événement.
    final messageSent = expectLater(
      harness.controller.foreign.stream,
      emitsThrough(
        predicate<String>((raw) {
          final frame = jsonDecode(raw) as Map;
          return frame['type'] == 'message' && frame['body'] == 'Bien et toi ?';
        }),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Bien et toi ?');
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    await messageSent;
  });

  testWidgets('the daily question renders and answering shows the result', (tester) async {
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/auth/me') {
        return _json({'id': 'me', 'phone': '+33600000000'}, 200);
      }
      if (request.method == 'GET' &&
          request.url.path == '/messaging/matches/${_match.matchId}/messages') {
        return _json([], 200);
      }
      if (request.method == 'GET' &&
          request.url.path == '/messaging/matches/${_match.matchId}/daily-question') {
        return _json({
          'prompt': 'Lequel de ces centres d\'intérêt appartient vraiment à Alix ?',
          'options': ['Cinéma', 'Randonnée'],
          'answered': false,
          'is_correct': null,
        }, 200);
      }
      if (request.method == 'POST' &&
          request.url.path == '/messaging/matches/${_match.matchId}/daily-question/answer') {
        return _json({'correct': true, 'correct_answer': 'Cinéma', 'flame_count': 3}, 200);
      }
      return http.Response('not found', 404);
    });

    final services = await _signedInServices(client);
    final harness = _harness(services);
    await tester.pumpWidget(harness.widget);
    await tester.pumpAndSettle();

    expect(find.text('QUESTION DU JOUR'), findsOneWidget);
    expect(find.text('Lequel de ces centres d\'intérêt appartient vraiment à Alix ?'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Cinéma'));
    await tester.pumpAndSettle();

    expect(find.text('Bonne réponse ! +1 flamme pour vous deux.'), findsOneWidget);
  });

  testWidgets('a typing event from the other side shows and then clears the indicator', (
    tester,
  ) async {
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/auth/me') {
        return _json({'id': 'me', 'phone': '+33600000000'}, 200);
      }
      if (request.method == 'GET' &&
          request.url.path == '/messaging/matches/${_match.matchId}/messages') {
        return _json([], 200);
      }
      if (request.method == 'GET' &&
          request.url.path == '/messaging/matches/${_match.matchId}/daily-question') {
        return _json({'detail': 'Pas de question aujourd\'hui.'}, 404);
      }
      return http.Response('not found', 404);
    });

    final services = await _signedInServices(client);
    final harness = _harness(services);
    await tester.pumpWidget(harness.widget);
    await tester.pumpAndSettle();

    harness.controller.foreign.sink.add(jsonEncode({'type': 'typing', 'sender_id': 'user-2'}));
    await tester.pumpAndSettle();
    expect(find.textContaining('est en train d\'écrire'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    expect(find.textContaining('est en train d\'écrire'), findsNothing);
  });

  testWidgets('a delivered event then a read event flip "Envoyé" -> "Reçu" -> "Lu à HH:mm"', (
    tester,
  ) async {
    final sentAt = DateTime(2026, 1, 1, 12);
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/auth/me') {
        return _json({'id': 'me', 'phone': '+33600000000'}, 200);
      }
      if (request.method == 'GET' &&
          request.url.path == '/messaging/matches/${_match.matchId}/messages') {
        return _json([
          _message(id: 'm1', senderId: 'me', body: 'Salut, ça va ?', createdAt: sentAt),
        ], 200);
      }
      if (request.method == 'GET' &&
          request.url.path == '/messaging/matches/${_match.matchId}/daily-question') {
        return _json({'detail': 'Pas de question aujourd\'hui.'}, 404);
      }
      return http.Response('not found', 404);
    });

    final services = await _signedInServices(client);
    final harness = _harness(services);
    await tester.pumpWidget(harness.widget);
    await tester.pumpAndSettle();

    expect(find.text('Envoyé'), findsOneWidget);
    expect(find.text('Reçu'), findsNothing);

    harness.controller.foreign.sink.add(
      jsonEncode({
        'type': 'delivered',
        'match_id': _match.matchId,
        'deliverer_id': 'user-2',
        'delivered_at': sentAt.add(const Duration(seconds: 30)).toIso8601String(),
      }),
    );
    await tester.pumpAndSettle();

    expect(find.text('Reçu'), findsOneWidget);
    expect(find.text('Envoyé'), findsNothing);

    final readAt = sentAt.add(const Duration(minutes: 1));
    harness.controller.foreign.sink.add(
      jsonEncode({'type': 'read', 'reader_id': 'user-2', 'read_at': readAt.toIso8601String()}),
    );
    await tester.pumpAndSettle();

    final hour = readAt.toLocal().hour.toString().padLeft(2, '0');
    final minute = readAt.toLocal().minute.toString().padLeft(2, '0');
    expect(find.text('Lu à $hour:$minute'), findsOneWidget);
    expect(find.text('Reçu'), findsNothing);
  });
}
