import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../api/api_exception.dart';
import '../../notifications/notification_prefs.dart';
import '../../state/app_services.dart';
import '../../state/theme_controller.dart';
import '../../theme/braise_tokens.dart';
import '../../widgets/braise_page_route.dart';
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

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notifMatch = true;
  bool _notifQuestion = true;
  bool _notifMessages = false;
  bool _loadingPrefs = true;

  @override
  void initState() {
    super.initState();
    _loadNotifPrefs();
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

    return Scaffold(
      appBar: AppBar(title: const Text('Paramètres')),
      body: _loadingPrefs
          ? const Center(child: CircularProgressIndicator())
          : ListView(
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
                    _SettingsActionRow(label: 'Exporter mes données', onTap: _exportData),
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
                  'Préférences locales uniquement — les notifications push arrivent dans une '
                  'prochaine version.',
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
    return Padding(
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
    );
  }
}
