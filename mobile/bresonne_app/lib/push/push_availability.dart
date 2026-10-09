/// Ce que l'appareil permet en matière de notifications push — indépendant de la plateforme, pour
/// que l'interface (carte d'activation, Paramètres) ne change pas le jour où une app native
/// (FCM/APNs) remplacera le Web Push : seule l'implémentation de `push_platform` changera.
enum PushAvailability {
  /// Aucun push possible sur ce navigateur/appareil.
  unsupported,

  /// iPhone/iPad dans Safari : le Web Push n'existe qu'une fois l'app ajoutée à l'écran d'accueil
  /// (iOS 16.4+). Il faut guider l'ajout, pas demander une permission impossible.
  needsInstall,

  /// Permission jamais demandée : on peut proposer l'activation (sur un geste explicite).
  canAsk,

  granted,

  /// Refusée : seuls les réglages du navigateur/système peuvent la rétablir, jamais une nouvelle
  /// invite (les navigateurs ne la réaffichent pas).
  denied,
}
