/// L'API tourne sur l'hôte, pas dans le réseau Docker interne, car ce code s'exécute soit dans le
/// navigateur (cible web), soit sur un appareil natif (APK Android), et doit résoudre une adresse
/// réelle dans les deux cas.
///
/// Sur web, `_host` est dérivé de `Uri.base` (l'URL de la page elle-même) plutôt que codé en dur
/// sur "localhost" : pour un bêta-test entre proches sur le même réseau local (pas de VPS, pas de
/// domaine — voir docs/V2_FEATURES.md), l'app est servie via l'IP LAN de la machine hôte
/// (`http://192.168.1.x:5000`), pas `localhost`, qui sur l'appareil d'un·e testeur·se ne
/// désignerait que lui-même. En dérivant l'hôte de la page courante, la même build fonctionne
/// aussi bien en local (`localhost`) que depuis un autre appareil du réseau (l'IP LAN), sans
/// reconfiguration. Sous la VM de test (`flutter test`), `Uri.base.host` est vide — replié sur
/// "localhost", sans incidence puisque les tests d'écran ne touchent jamais le réseau (voir
/// test/screens/, `AppServices(httpClient: ...)`).
///
/// Un APK natif n'a pas de "page" dont dériver `Uri.base.host` (Android/iOS n'ont pas cette
/// notion) : l'hôte y est fourni à la compilation via `--dart-define=API_HOST=<ip-lan>`
/// (`flutter build apk --dart-define=API_HOST=192.168.1.39`), lu par `String.fromEnvironment`, qui
/// prend le pas sur la dérivation web quand il est fourni.
///
/// `API_HOST` suppose que l'API est joignable au même hôte que la page, juste sur le port 8010 —
/// vrai pour une IP LAN, faux pour un tunnel (devtunnels, ngrok...) où chaque port forwardé a son
/// propre nom d'hôte et où la page est servie en https (donc un appel http:// est aussi bloqué en
/// mixed content, pas seulement mal routé). `API_BASE_URL` prend le dessus sur tout le reste pour
/// ce cas : une origine complète (`--dart-define=API_BASE_URL=https://dw8461v4-8010.uks1.devtunnels.ms`,
/// le tunnel forwardé pour le port 8010 du backend, pas celui de la page elle-même) ; le WS en est
/// dérivé en substituant juste le schéma (http→ws, https→wss).
///
/// `API_BASE_URL` peut aussi être un simple chemin (`/api`) : l'API est alors sur la même origine
/// que la page, derrière le reverse proxy de bêta/prod (infra/deploy/Caddyfile, une seule origine
/// pour l'app, l'API et les photos — plus de CORS, un seul certificat). C'est ce que fait
/// infra/deploy/build_web.sh ; l'origine (et donc http/https, ws/wss) vient de la page elle-même.
class ApiConfig {
  static const String _dartDefineHost = String.fromEnvironment('API_HOST');
  static const String _dartDefineBaseUrl = String.fromEnvironment('API_BASE_URL');

  static String get _host {
    if (_dartDefineHost.isNotEmpty) return _dartDefineHost;
    return Uri.base.host.isEmpty ? 'localhost' : Uri.base.host;
  }

  static String get _baseUrl {
    final override = _dartDefineBaseUrl;
    if (override.isEmpty) return 'http://$_host:8010';
    final trimmed = override.endsWith('/') ? override.substring(0, override.length - 1) : override;
    if (trimmed.startsWith('/')) return '${Uri.base.origin}$trimmed';
    return trimmed;
  }

  static String get httpBaseUrl => _baseUrl;
  static String get wsBaseUrl => _baseUrl.replaceFirst(RegExp(r'^http'), 'ws');
}
