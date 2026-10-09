// ClientErrorReporter : remontée des erreurs non gérées vers POST /client-errors. Vérifie qu'il
// ne devient jamais lui-même une source de trafic en boucle (dédoublonnage, plafond par session)
// ni d'erreurs (un envoi qui échoue est avalé).

import 'package:bresonne_app/telemetry/client_error_reporter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the same error is sent only once per session', () async {
    final sent = <String>[];
    final reporter = ClientErrorReporter(
      send: ({required message, stack, required source, path}) async => sent.add('$source|$message'),
    );

    reporter.report(StateError('boom'), StackTrace.current, source: 'flutter');
    reporter.report(StateError('boom'), StackTrace.current, source: 'flutter');
    reporter.report(StateError('other'), null, source: 'platform');
    await Future<void>.delayed(Duration.zero);

    expect(sent, ['flutter|Bad state: boom', 'platform|Bad state: other']);
  });

  test('stops after maxReportsPerSession distinct errors', () async {
    var calls = 0;
    final reporter = ClientErrorReporter(
      maxReportsPerSession: 3,
      send: ({required message, stack, required source, path}) async => calls++,
    );

    for (var i = 0; i < 10; i++) {
      reporter.report(Exception('error $i'), null, source: 'flutter');
    }
    await Future<void>.delayed(Duration.zero);

    expect(calls, 3);
  });

  test('a failing send is swallowed, never rethrown', () async {
    final reporter = ClientErrorReporter(
      send: ({required message, stack, required source, path}) async => throw Exception('offline'),
    );

    reporter.report(Exception('boom'), null, source: 'flutter');
    await Future<void>.delayed(Duration.zero);
    // Atteindre cette ligne sans exception non rattrapée dans la zone de test suffit.
  });
}
