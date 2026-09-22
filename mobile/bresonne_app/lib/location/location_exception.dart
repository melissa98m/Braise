/// Erreur de géolocalisation, indépendante de la plateforme — [LocationPlatformError] distingue
/// une permission refusée (le cas le plus courant, mérite un message dédié) du reste (position
/// indisponible, délai dépassé).
enum LocationPlatformError { permissionDenied, unavailable }

class LocationException implements Exception {
  const LocationException(this.kind, this.message);
  final LocationPlatformError kind;
  final String message;

  @override
  String toString() => message;
}
