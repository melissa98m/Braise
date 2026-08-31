import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'api_config.dart';
import 'api_exception.dart';

/// Client HTTP fin : injecte le token JWT courant, décode le JSON, transforme toute réponse
/// non-2xx en [ApiException] avec le `detail` de FastAPI. Pas de dio/retry/intercepteurs — pas
/// nécessaire pour 8 écrans MVP (voir pubspec.yaml).
class ApiClient {
  ApiClient({required this.tokenProvider, http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  /// Callback plutôt que dépendance directe à AuthController : garde api/ indépendant de state/.
  final String? Function() tokenProvider;

  /// Injectable pour les tests (`package:http/testing.dart`'s `MockClient`, déjà fourni par la
  /// dépendance `http` existante — pas besoin de mockito). En dehors des tests, `httpClient` est
  /// toujours omis et ce client réel unique sert tous les appels de l'app.
  final http.Client _http;

  Map<String, String> _headers({bool json = true}) {
    final headers = <String, String>{};
    if (json) headers['Content-Type'] = 'application/json';
    final token = tokenProvider();
    if (token != null) headers['Authorization'] = 'Bearer $token';
    return headers;
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    return Uri.parse('${ApiConfig.httpBaseUrl}$path').replace(queryParameters: query);
  }

  dynamic _decode(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      return jsonDecode(utf8.decode(response.bodyBytes));
    }
    String message = 'Erreur ${response.statusCode}';
    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is Map && body['detail'] != null) {
        message = body['detail'].toString();
      }
    } catch (_) {
      // Corps non-JSON (ex. erreur réseau côté proxy) : on garde le message générique.
    }
    throw ApiException(response.statusCode, message);
  }

  Future<dynamic> get(String path, {Map<String, String>? query}) async {
    final response = await _http.get(_uri(path, query), headers: _headers(json: false));
    return _decode(response);
  }

  Future<dynamic> post(String path, {Object? body}) async {
    final response = await _http.post(
      _uri(path),
      headers: _headers(),
      body: body == null ? null : jsonEncode(body),
    );
    return _decode(response);
  }

  Future<dynamic> put(String path, {Object? body}) async {
    final response = await _http.put(
      _uri(path),
      headers: _headers(),
      body: body == null ? null : jsonEncode(body),
    );
    return _decode(response);
  }

  Future<dynamic> delete(String path) async {
    final response = await _http.delete(_uri(path), headers: _headers(json: false));
    return _decode(response);
  }

  Future<dynamic> postMultipart(
    String path, {
    required String fieldName,
    required List<int> bytes,
    required String filename,
    required String contentType,
  }) async {
    final request = http.MultipartRequest('POST', _uri(path));
    final token = tokenProvider();
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    request.files.add(
      http.MultipartFile.fromBytes(
        fieldName,
        bytes,
        filename: filename,
        contentType: MediaType.parse(contentType),
      ),
    );
    final streamed = await _http.send(request);
    final response = await http.Response.fromStream(streamed);
    return _decode(response);
  }
}
