import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'screens/moderation/ban_appeal_screen.dart';
import 'screens/onboarding/welcome_screen.dart';
import 'screens/root_shell.dart';
import 'state/app_services.dart';
import 'state/auth_controller.dart';
import 'state/theme_controller.dart';
import 'theme/braise_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Le `SemanticsHandle` renvoyé n'est jamais conservé ni disposé — Flutter web ne construit son
  // arbre sémantique qu'à la demande (première interaction, ou détection d'une techno
  // d'assistance) — sans cet appel, une personne utilisant un lecteur d'écran n'entend rien
  // d'autre que le bouton caché "Enable accessibility" au premier chargement, sans aucun indice
  // que l'app contient autre chose. Ne jamais appeler `.dispose()` dessus : ce serait redésactiver
  // l'arbre (trouvé en inspectant l'arbre réel via Playwright, pas en lisant le code).
  SemanticsBinding.instance.ensureSemantics();
  runApp(const BraiseApp());
}

class BraiseApp extends StatelessWidget {
  const BraiseApp({super.key});

  @override
  Widget build(BuildContext context) {
    final services = AppServices();
    final themeController = ThemeController()..restore();

    return MultiProvider(
      providers: [
        Provider<AppServices>.value(value: services),
        ChangeNotifierProvider<AuthController>.value(value: services.authController),
        ChangeNotifierProvider<ThemeController>.value(value: themeController),
      ],
      // Builder : le MaterialApp a besoin de lire ThemeController via context.watch, donc son
      // context doit être un descendant de MultiProvider, pas celui de BraiseApp lui-même.
      child: Builder(
        builder: (context) {
          final mode = context.watch<ThemeController>().mode;
          return MaterialApp(
            title: 'Braise',
            debugShowCheckedModeBanner: false,
            // App entièrement en français, sans version localisée alternative : on fixe la
            // locale plutôt que de suivre celle de l'appareil/du navigateur, pour que le
            // sélecteur de date Material (texte + format de saisie JJ/MM/AAAA) reste cohérent
            // avec le reste de l'app quel que soit le réglage régional du visiteur.
            locale: const Locale('fr'),
            supportedLocales: const [Locale('fr')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: buildBraiseTheme(Brightness.light),
            darkTheme: buildBraiseTheme(Brightness.dark),
            // Sombre reste le réglage par défaut à l'installation (docs/DESIGN_TOKENS.md) ;
            // l'utilisateur peut désormais changer ce choix depuis Paramètres (ThemeController).
            themeMode: mode,
            home: const _AuthGate(),
          );
        },
      ),
    );
  }
}

class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  @override
  void initState() {
    super.initState();
    context.read<AuthController>().restoreSession();
  }

  @override
  Widget build(BuildContext context) {
    final status = context.watch<AuthController>().status;
    return switch (status) {
      AuthStatus.unknown => const Scaffold(body: Center(child: CircularProgressIndicator(semanticsLabel: 'Chargement en cours.'))),
      // Écran d'accueil (CTA "Créer un compte"/"J'ai déjà un compte"), pas directement OtpScreen :
      // WelcomeScreen pousse vers OtpScreen via un vrai `Navigator.push`, donc après vérification
      // réussie le `pushReplacement` d'OtpScreen (voir otp_screen.dart) remplace cette route-là,
      // pas la route racine — WelcomeScreen reste dans l'historique mais n'est plus jamais
      // atteignable une fois connecté, ce qui est le comportement voulu (pas de retour arrière
      // vers l'accueil/l'OTP depuis l'app une fois dans RootShell).
      AuthStatus.signedOut => const WelcomeScreen(),
      AuthStatus.signedIn => const RootShell(),
      AuthStatus.banned => const BanAppealScreen(),
    };
  }
}
