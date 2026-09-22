import 'location_exception.dart';

/// Cible non-web (en pratique : uniquement la VM `flutter test`/`flutter analyze`, cette app
/// n'étant jamais réellement servie ailleurs qu'en web — voir CLAUDE.md). N'est jamais appelé en
/// usage réel ; existe uniquement pour que ce fichier compile sur la VM.
Future<({double lat, double lon})> getCurrentPosition() {
  return Future.error(
    const LocationException(LocationPlatformError.unavailable, 'Géolocalisation indisponible.'),
  );
}
