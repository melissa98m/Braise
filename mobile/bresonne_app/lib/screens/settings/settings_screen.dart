import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../api/api_exception.dart';
import '../../notifications/notification_prefs.dart';
import '../../state/app_services.dart';
import '../../state/theme_controller.dart';
import '../../theme/braise_tokens.dart';
import '../../widgets/braise_page_route.dart';
import '../legal/legal_screen.dart';
import '../onboarding/otp_screen.dart';

/// Écran Paramètres — regroupe compte, apparence, confidentialité RGPD et notifications, qui
/// n'avaient sinon aucun écran dédié : l'export/suppression de données vivait avant dans
/// ProfileTrustScreen (Phase 5), ce qui encombrait l'écran de confiance avec des réglages plutôt
/// que des informations de profil. Les 3 bascules de notifications pilotent désormais de vraies
/// notifications navigateur (P9.1, `notifications/`) — plus une préférence sans effet : basculer
/// une bascule sur "activé" demande la permission navigateur si elle n'a jamais été tranchée.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with SingleTickerProviderStateMixin {
  bool _notifMatch = true;
  bool _notifQuestion = true;
  bool _notifMessages = false;
  bool _loadingPrefs = true;

  // Pulsation brève de la ligne concernée après un export réussi — vient s'ajouter au SnackBar
  // (déjà l'unique retour, insuffisant seul pour un geste RGPD qu'on veut sentir "pris en compte"
  // immédiatement sous le doigt). Un `AnimationController` classique (joué une seule fois, jamais
  // en boucle) plutôt qu'un `Future.delayed` + `setState` : piloté par le ticker de test comme
  // toute animation de ce projet, il ne laisse jamais de minuteur en suspens une fois le widget
  // détruit — contrairement à un `Timer` brut, qui ferait échouer `pumpAndSettle()` dans les tests.
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _loadNotifPrefs();
  }

  void _pulseExportSuccess() {
    if (MediaQuery.of(context).disableAnimations) return;
    _pulseController.forward(from: 0);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadNotifPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _notifMatch = prefs.getBool(NotificationPrefs.match) ?? true;
      _notifQuestion = prefs.getBool(NotificationPrefs.question) ?? true;
      _notifMessages = prefs.getBool(NotificationPrefs.messages) ?? false;
      _loadingPrefs = false;
    });
  }

  Future<void> _setNotifPref(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
    // Demander la permission ici (activation explicite d'une bascule), pas au chargement de
    // l'écran ni au démarrage de l'app : les navigateurs traitent une demande de permission hors
    // d'un geste utilisateur explicite comme du spam et la rejettent souvent d'office.
    if (value && mounted) {
      await context.read<AppServices>().notificationsService.requestPermission();
    }
  }

  String _maskPhone(String phone) {
    if (phone.length <= 4) return phone;
    final visible = phone.substring(phone.length - 2);
    return '${'•' * (phone.length - 2)}$visible';
  }

  Future<void> _exportData() async {
    final services = context.read<AppServices>();
    try {
      await services.apiClient.get('/auth/me/export');
      if (!mounted) return;
      _pulseExportSuccess();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Export généré côté serveur (droit à la portabilité, RGPD).'),
        ),
      );
    } on ApiException catch (e) {
      // Sans ce catch, un échec réseau ici disparaissait sans aucun retour — contrairement à
      // toute autre action mutante de l'app, qui affiche toujours le message d'erreur.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer votre compte ?'),
        content: const Text(
          'Votre profil et vos photos privées seront effacés. Vos échanges avec vos matchs '
          'restent visibles pour eux, sans votre nom. Action irréversible.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final services = context.read<AppServices>();
    try {
      await services.apiClient.delete('/auth/me');
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    await services.authController.signOut();
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushAndRemoveUntil(braiseRoute(context, const OtpScreen()), (route) => false);
  }

  Future<void> _signOut() async {
    final services = context.read<AppServices>();
    await services.authController.signOut();
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushAndRemoveUntil(braiseRoute(context, const OtpScreen()), (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = BraiseTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    final phone = context.watch<AppServices>().authController.phone;
    final themeMode = context.watch<ThemeController>().mode;
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return Scaffold(
      appBar: AppBar(title: const Text('Paramètres')),
      body: _loadingPrefs
          ? const Center(child: CircularProgressIndicator(semanticsLabel: 'Chargement en cours.'))
          // Fondu léger à l'arrivée du contenu — ce sous-arbre n'est monté qu'une fois les
          // préférences chargées, donc l'animation ne rejoue jamais sur un simple `setState`
          // ultérieur (bascule d'un interrupteur, par ex.) qui ne recrée pas ce widget.
          : TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) => Opacity(opacity: value, child: child),
              child: ListView(
              padding: const EdgeInsets.all(BraiseSpacing.xxl),
              children: [
                _SectionLabel('COMPTE'),
                _SettingsCard(
                  children: [
                    _SettingsRow(label: 'Téléphone', value: phone == null ? '—' : _maskPhone(phone)),
                  ],
                ),
                const SizedBox(height: BraiseSpacing.xxl),
                _SectionLabel('APPARENCE'),
                _SettingsCard(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(BraiseSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Thème', style: textTheme.bodyLarge),
                          const SizedBox(height: BraiseSpacing.md),
                          SegmentedButton<ThemeMode>(
                            segments: const [
                              ButtonSegment(value: ThemeMode.system, label: Text('Système')),
                              ButtonSegment(value: ThemeMode.light, label: Text('Clair')),
                              ButtonSegment(value: ThemeMode.dark, label: Text('Sombre')),
                            ],
                            selected: {themeMode},
                            onSelectionChanged: (selection) =>
                                context.read<ThemeController>().setMode(selection.first),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: BraiseSpacing.xxl),
                _SectionLabel('CONFIDENTIALITÉ — RGPD'),
                _SettingsCard(
                  children: [
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        final raw = _pulseController.value;
                        // Enveloppe montée-descente (0 -> 1 -> 0) sur une seule passe du
                        // contrôleur, pas une boucle : un aller simple suffit pour un "pulse".
                        final t = raw <= 0.5
                            ? Curves.easeOutCubic.transform(raw * 2)
                            : 1 - Curves.easeOutCubic.transform((raw - 0.5) * 2);
                        return ColoredBox(
                          color: Color.lerp(
                            Colors.transparent,
                            tokens.foiInk.withValues(alpha: 0.16),
                            t,
                          )!,
                          child: child,
                        );
                      },
                      child: _SettingsActionRow(label: 'Exporter mes données', onTap: _exportData),
                    ),
                    Divider(height: 1, color: tokens.borderHairline),
                    _SettingsActionRow(
                      label: 'Informations légales',
                      onTap: () =>
                          Navigator.of(context).push(braiseRoute(context, const LegalScreen())),
                    ),
                    Divider(height: 1, color: tokens.borderHairline),
                    _SettingsActionRow(
                      label: 'Supprimer mon compte',
                      color: tokens.erreur,
                      onTap: _deleteAccount,
                    ),
                  ],
                ),
                const SizedBox(height: BraiseSpacing.xxl),
                _SectionLabel('NOTIFICATIONS'),
                Text(
                  // Notifications navigateur réelles (P9.1) uniquement quand l'app est ouverte —
                  // pas de vraies notifications push (Service Worker), voir docs/V2_FEATURES.md.
                  'Fonctionnent tant que l\'application est ouverte dans un onglet.',
                  style: textTheme.bodyMedium,
                ),
                const SizedBox(height: BraiseSpacing.sm),
                _SettingsCard(
                  children: [
                    _NotifRow(
                      label: 'Nouveau match',
                      desc: 'Un like réciproque',
                      value: _notifMatch,
                      onChanged: (v) {
                        setState(() => _notifMatch = v);
                        _setNotifPref(NotificationPrefs.match, v);
                      },
                    ),
                    Divider(height: 1, color: tokens.borderHairline),
                    _NotifRow(
                      label: 'Question du jour',
                      desc: 'Rappel quotidien',
                      value: _notifQuestion,
                      onChanged: (v) {
                        setState(() => _notifQuestion = v);
                        _setNotifPref(NotificationPrefs.question, v);
                      },
                    ),
                    Divider(height: 1, color: tokens.borderHairline),
                    _NotifRow(
                      label: 'Messages',
                      desc: 'Nouveaux messages reçus',
                      value: _notifMessages,
                      onChanged: (v) {
                        setState(() => _notifMessages = v);
                        _setNotifPref(NotificationPrefs.messages, v);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: BraiseSpacing.xxl),
                OutlinedButton(onPressed: _signOut, child: const Text('Se déconnecter')),
              ],
              ),
            ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = BraiseTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: BraiseSpacing.sm),
      child: Text(
        text,
        style: textTheme.labelSmall?.copyWith(color: tokens.inkFloor, letterSpacing: 11 * 0.14),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final tokens = BraiseTokens.of(context);
    return Container(
      decoration: BoxDecoration(
        color: tokens.surface1,
        border: Border.all(color: tokens.borderHairline),
        borderRadius: BorderRadius.circular(BraiseRadii.card),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final tokens = BraiseTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: BraiseSpacing.lg, vertical: BraiseSpacing.md),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: textTheme.bodyLarge),
          Text(value, style: textTheme.labelSmall?.copyWith(color: tokens.inkSecondary)),
        ],
      ),
    );
  }
}

class _SettingsActionRow extends StatelessWidget {
  const _SettingsActionRow({required this.label, required this.onTap, this.color});
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final tokens = BraiseTokens.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: BraiseSpacing.lg, vertical: BraiseSpacing.md),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: textTheme.bodyLarge?.copyWith(color: color)),
            Icon(Icons.chevron_right, color: color ?? tokens.inkFloor),
          ],
        ),
      ),
    );
  }
}

class _NotifRow extends StatelessWidget {
  const _NotifRow({
    required this.label,
    required this.desc,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String desc;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = BraiseTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Focus(
      // `excludeSemantics` ci-dessous (nécessaire pour la sémantique, voir plus bas) supprime
      // aussi le focus clavier natif du `Switch` sous-jacent : au clavier seul (sans lecteur
      // d'écran), les 3 lignes devenaient totalement inatteignables par Tab — trouvé en
      // parcourant l'ordre de tabulation réel de l'app, pas en supposant que le premier correctif
      // suffisait. `Focus` redonne un arrêt de tabulation réel à la ligne, `onKeyEvent` reproduit
      // l'activation Entrée/Espace qu'un vrai `Switch` gère normalement lui-même.
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          onChanged(!value);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Semantics(
        // Sans frontière propre à chaque ligne, les 3 réglages de notification se lisaient comme
        // un seul bloc côté lecteur d'écran ("Nouveau match Un like réciproque Question du jour
        // Rappel quotidien Messages Nouveaux messages reçus"), impossible de savoir quel
        // interrupteur correspond à quoi en y naviguant — trouvé en inspectant l'arbre
        // d'accessibilité réel, pas en relisant le code. `excludeSemantics` remplace la lecture
        // des `Text`/`Switch` descendants (qui dupliquerait le label ci-dessous) par ce seul
        // nœud ; `toggled`/`onTap` reportent explicitement l'état et l'action du `Switch` exclu,
        // sinon un lecteur d'écran ne saurait plus si le réglage est activé ni comment le changer.
        container: true,
        label: '$label. $desc',
        toggled: value,
        onTap: () => onChanged(!value),
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: BraiseSpacing.lg, vertical: BraiseSpacing.sm),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: textTheme.bodyLarge),
                    const SizedBox(height: 2),
                    Text(desc, style: textTheme.labelSmall?.copyWith(color: tokens.inkFloor)),
                  ],
                ),
              ),
              Switch(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}
