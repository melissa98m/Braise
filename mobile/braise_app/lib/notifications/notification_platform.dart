// Sélection conditionnelle à la compilation : `notification_platform_web.dart` (vraie API
// `Notification` du navigateur, via `dart:js_interop`) sur le web, `notification_platform_stub.dart`
// (no-op) partout ailleurs — notamment la VM utilisée par `flutter test`/`flutter analyze`, qui
// ne peut tout simplement pas compiler un fichier import-ant `dart:js_interop` (cette librairie
// n'existe pas hors des cibles web). `dart.library.js_interop` est la condition standard pour ce
// choix depuis la nouvelle interop JS de Dart 3.3+ (remplace l'ancien `dart.library.html`).
export 'notification_platform_stub.dart'
    if (dart.library.js_interop) 'notification_platform_web.dart';
