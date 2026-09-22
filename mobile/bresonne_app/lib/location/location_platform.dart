// Sélection conditionnelle à la compilation : même motif que
// `notifications/notification_platform.dart` — la vraie API `Geolocation` du navigateur (via
// `dart:js_interop`) sur le web, un stub qui échoue proprement partout ailleurs (notamment la VM
// utilisée par `flutter test`/`flutter analyze`, qui ne peut pas compiler un fichier import-ant
// `dart:js_interop`).
export 'location_platform_stub.dart'
    if (dart.library.js_interop) 'location_platform_web.dart';
