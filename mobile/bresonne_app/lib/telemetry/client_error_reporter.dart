import 'dart:async';

import 'package:flutter/foundation.dart';

/// Remonte au backend les erreurs non gérées de l'app (POST /client-errors), pour qu'un plantage
/// chez un·e testeur·se ne passe plus inaperçu — sans service tiers (pas de Sentry), cohérent
/// avec la politique « aucune ressource tierce » de l'app.
///
/// Branché dans `main()` sur `FlutterError.onError` (erreurs du framework : build, layout...) et
/// `PlatformDispatcher.onError` (exceptions asynchrones non rattrapées). Prudent par construction :
/// une même erreur n'est envoyée qu'une fois par session, au plus [maxReportsPerSession] en tout,
/// et un envoi qui échoue est abandonné en silence — un rapport d'erreur ne doit jamais devenir
/// lui-même une source d'erreurs ou de trafic en boucle. Le backend regroupe ensuite les
/// occurrences de toutes les sessions (services/client_errors.py).
class ClientErrorReporter {
  ClientErrorReporter({required this.send, this.maxReportsPerSession = 10});

  final Future<void> Function({
    required String message,
    String? stack,
    required String source,
    String? path,
  })
  send;
  final int maxReportsPerSession;

  final Set<String> _alreadySent = {};
  int _sent = 0;

  void report(Object error, StackTrace? stack, {required String source}) {
    final message = error.toString();
    if (_sent >= maxReportsPerSession || !_alreadySent.add('$source|$message')) return;
    _sent++;
    unawaited(
      send(
        message: message,
        stack: stack?.toString(),
        source: source,
        path: Uri.base.path,
      ).catchError((Object _) {}),
    );
  }

  /// Installe les deux points de capture, en gardant le comportement par défaut de Flutter
  /// (affichage console de l'erreur) : on ajoute un envoi, on ne masque rien.
  void install() {
    final previousFlutterHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      previousFlutterHandler?.call(details);
      report(details.exception, details.stack, source: 'flutter');
    };
    final previousPlatformHandler = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      report(error, stack, source: 'platform');
      return previousPlatformHandler?.call(error, stack) ?? false;
    };
  }
}
