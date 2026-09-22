import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'location_exception.dart';

/// L'API `Geolocation` du navigateur (gratuite, locale, aucun service de géocodage tiers —
/// cohérent avec la contrainte du projet, voir CLAUDE.md) : une position ponctuelle, jamais un
/// suivi continu (`watchPosition` n'est pas utilisé), pour résoudre `city` une seule fois au
/// moment où l'utilisateur appuie sur "Utiliser ma position" (voir profile_setup_screen.dart).
/// Contrairement à `Notification.requestPermission` (une vraie Promise, voir
/// notification_platform_web.dart), `getCurrentPosition` est une API à callbacks — convertie ici
/// en `Future` via un `Completer`.
Future<({double lat, double lon})> getCurrentPosition() {
  final completer = Completer<({double lat, double lon})>();

  void onSuccess(web.GeolocationPosition position) {
    if (completer.isCompleted) return;
    completer.complete((lat: position.coords.latitude, lon: position.coords.longitude));
  }

  void onError(web.GeolocationPositionError error) {
    if (completer.isCompleted) return;
    final kind = error.code == web.GeolocationPositionError.PERMISSION_DENIED
        ? LocationPlatformError.permissionDenied
        : LocationPlatformError.unavailable;
    final message = kind == LocationPlatformError.permissionDenied
        ? "Vous n'avez pas autorisé l'accès à votre position."
        : 'Position indisponible pour le moment.';
    completer.completeError(LocationException(kind, message));
  }

  web.window.navigator.geolocation.getCurrentPosition(onSuccess.toJS, onError.toJS);
  return completer.future;
}
