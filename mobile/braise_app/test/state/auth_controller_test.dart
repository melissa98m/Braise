import 'dart:convert';

import 'package:braise_app/api/api_client.dart';
import 'package:braise_app/api/auth_api.dart';
import 'package:braise_app/state/auth_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sert /auth/verify-otp et /auth/me contre un MockClient plutôt que le backend réel — le point
/// de ce fichier est justement l'infrastructure de mock HTTP qui manquait jusqu'ici (voir
/// docs/ROADMAP.md, Phase 6 : "Pas de tests HTTP mockés en Dart pour cette passe"). meResponse
/// contrôle ce que renvoie /auth/me après verify-otp/restoreSession, pour simuler
/// signedIn/banned/signedOut sans jamais toucher un vrai réseau.
AuthController buildController({required http.Response Function() meResponse}) {
  final client = MockClient((request) async {
    if (request.method == 'POST' && request.url.path == '/auth/verify-otp') {
      return _json({'access_token': 'tok-123'}, 200);
    }
    if (request.method == 'GET' && request.url.path == '/auth/me') {
      return meResponse();
    }
    return http.Response('not found', 404);
  });

  late final AuthController controller;
  final apiClient = ApiClient(tokenProvider: () => controller.token, httpClient: client);
  controller = AuthController(AuthApi(apiClient));
  return controller;
}

/// `http.Response(String, ...)` choisit l'encodage du corps depuis l'en-tête Content-Type ; sans
/// lui, il retombe sur Latin-1, ce qui casse `utf8.decode` côté `ApiClient._decode` dès qu'un
/// accent apparaît dans le JSON — "Compte supprimé." en contient un, "Compte suspendu." non, ce
/// qui a fait passer une première version de ce fichier sans ce helper sans qu'aucun test ne
/// s'en aperçoive (le message d'erreur retombait sur un texte générique, indétectable par ce
/// fichier tant qu'il ne comparait que le statut final, pas le message).
http.Response _json(Object data, int status) {
  return http.Response(
    jsonEncode(data),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

http.Response _mePayload({String id = 'user-1', String phone = '+33600000000'}) {
  return _json({'id': id, 'phone': phone}, 200);
}

http.Response _forbidden(String detail) {
  return _json({'detail': detail}, 403);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('restoreSession', () {
    test('no stored token -> signedOut, without calling the network', () async {
      final controller = buildController(meResponse: () => _mePayload());
      await controller.restoreSession();
      expect(controller.status, AuthStatus.signedOut);
      expect(controller.token, isNull);
    });

    test('stored token + /auth/me 200 -> signedIn with profile populated', () async {
      SharedPreferences.setMockInitialValues({'braise_token': 'stored-token'});
      final controller = buildController(
        meResponse: () => _mePayload(id: 'abc', phone: '+33611111111'),
      );
      await controller.restoreSession();
      expect(controller.status, AuthStatus.signedIn);
      expect(controller.userId, 'abc');
      expect(controller.phone, '+33611111111');
    });

    test('stored token + 403 "Compte suspendu." -> banned, token kept', () async {
      SharedPreferences.setMockInitialValues({'braise_token': 'stored-token'});
      final controller = buildController(
        meResponse: () => _forbidden('Compte suspendu.'),
      );
      await controller.restoreSession();
      expect(controller.status, AuthStatus.banned);
      // Le seul cas où le token doit survivre à un échec de /auth/me — nécessaire pour que
      // BanAppealScreen puisse encore appeler /moderation/ban-appeal.
      expect(controller.token, 'stored-token');
    });

    test('stored token + 403 "Compte supprimé." -> signedOut, token cleared', () async {
      SharedPreferences.setMockInitialValues({'braise_token': 'stored-token'});
      final controller = buildController(
        meResponse: () => _forbidden('Compte supprimé.'),
      );
      await controller.restoreSession();
      expect(controller.status, AuthStatus.signedOut);
      expect(controller.token, isNull);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('braise_token'), isNull);
    });

    test('stored token + 401 (expired) -> signedOut like any other invalid token', () async {
      SharedPreferences.setMockInitialValues({'braise_token': 'stale-token'});
      final controller = buildController(
        meResponse: () => _json({'detail': 'Identifiants invalides ou expirés.'}, 401),
      );
      await controller.restoreSession();
      expect(controller.status, AuthStatus.signedOut);
      expect(controller.token, isNull);
    });
  });

  group('verifyOtp', () {
    test('happy path -> signedIn, token persisted', () async {
      final controller = buildController(meResponse: () => _mePayload());
      await controller.verifyOtp('+33600000000', '123456');
      expect(controller.status, AuthStatus.signedIn);
      expect(controller.token, 'tok-123');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('braise_token'), 'tok-123');
    });

    test('banned account: OTP succeeds but /auth/me 403s -> banned, not a crash', () async {
      // services/otp.py ne vérifie pas is_banned : verify-otp réussit toujours, seul le
      // /auth/me qui suit peut révéler que le compte est banni (voir AuthController).
      final controller = buildController(
        meResponse: () => _forbidden('Compte suspendu.'),
      );
      await controller.verifyOtp('+33600000000', '123456');
      expect(controller.status, AuthStatus.banned);
      expect(controller.token, 'tok-123');
    });

    test('any other /auth/me failure after verify-otp rethrows', () async {
      final controller = buildController(
        meResponse: () => _json({'detail': 'Erreur serveur.'}, 500),
      );
      await expectLater(
        () => controller.verifyOtp('+33600000000', '123456'),
        throwsA(anything),
      );
    });
  });
}
