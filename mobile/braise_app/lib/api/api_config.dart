/// L'API tourne sur l'hôte, pas dans le réseau Docker interne, car ce code s'exécute dans le
/// navigateur (cible web) et doit résoudre une adresse réelle.
///
/// `_host` est dérivé de `Uri.base` (l'URL de la page elle-même) plutôt que codé en dur sur
/// "localhost" : pour un bêta-test entre proches sur le même réseau local (pas de VPS, pas de
/// domaine — voir docs/V2_FEATURES.md), l'app est servie via l'IP LAN de la machine hôte
/// (`http://192.168.1.x:5000`), pas `localhost`, qui sur l'appareil d'un·e testeur·se ne
/// désignerait que lui-même. En dérivant l'hôte de la page courante, la même build fonctionne
/// aussi bien en local (`localhost`) que depuis un autre appareil du réseau (l'IP LAN), sans
/// reconfiguration. Sous la VM de test (`flutter test`), `Uri.base.host` est vide — replié sur
/// "localhost", sans incidence puisque les tests d'écran ne touchent jamais le réseau (voir
/// test/screens/, `AppServices(httpClient: ...)`).
class ApiConfig {
  static String get _host => Uri.base.host.isEmpty ? 'localhost' : Uri.base.host;

  static String get httpBaseUrl => 'http://$_host:8010';
  static String get wsBaseUrl => 'ws://$_host:8010';
}
