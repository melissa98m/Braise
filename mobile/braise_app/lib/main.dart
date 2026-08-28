import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/onboarding/otp_screen.dart';
import 'screens/root_shell.dart';
import 'state/app_services.dart';
import 'state/auth_controller.dart';
import 'theme/braise_theme.dart';

void main() {
  runApp(const BraiseApp());
}

class BraiseApp extends StatelessWidget {
  const BraiseApp({super.key});

  @override
  Widget build(BuildContext context) {
    final services = AppServices();

    return MultiProvider(
      providers: [
        Provider<AppServices>.value(value: services),
        ChangeNotifierProvider<AuthController>.value(value: services.authController),
      ],
      child: MaterialApp(
        title: 'Braise',
        debugShowCheckedModeBanner: false,
        theme: buildBraiseTheme(Brightness.light),
        darkTheme: buildBraiseTheme(Brightness.dark),
        // Sombre reste le défaut à l'installation (docs/DESIGN_TOKENS.md) ; un vrai bouton
        // clair/sombre/auto est laissé pour une prochaine passe, pas essentiel à la fidélité
        // fonctionnelle de ce MVP.
        themeMode: ThemeMode.dark,
        home: const _AuthGate(),
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
      AuthStatus.unknown => const Scaffold(body: Center(child: CircularProgressIndicator())),
      AuthStatus.signedOut => const OtpScreen(),
      AuthStatus.signedIn => const RootShell(),
    };
  }
}
