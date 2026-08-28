/// Ports documentés dans CLAUDE.md — l'API tourne sur l'hôte, pas dans le réseau Docker interne,
/// car ce code s'exécute dans le navigateur (cible web) et doit résoudre une adresse réelle.
class ApiConfig {
  static const String httpBaseUrl = 'http://localhost:8010';
  static const String wsBaseUrl = 'ws://localhost:8010';
}
