// Choix conditionnel identique à `notifications/notification_platform.dart` : la cible web a
// besoin de `dart:js_interop` (Service Worker + Push API), que la VM utilisée par `flutter
// test`/`flutter analyze` ne peut pas compiler.
export 'push_platform_stub.dart' if (dart.library.js_interop) 'push_platform_web.dart';
