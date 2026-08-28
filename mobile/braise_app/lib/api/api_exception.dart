/// Enveloppe une erreur HTTP de l'API avec le message renvoyé par FastAPI (`detail`), pour que
/// l'UI puisse afficher le vrai message métier ("Le courant n'est pas passé...") plutôt qu'un
/// "Une erreur est survenue" générique.
class ApiException implements Exception {
  ApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isPaymentRequired => statusCode == 402;

  @override
  String toString() => message;
}
