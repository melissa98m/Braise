import 'package:flutter/material.dart';

import '../../theme/braise_tokens.dart';
import '../../widgets/braise_page_route.dart';
import '../../widgets/sign_shapes.dart';
import '../legal/legal_screen.dart';
import 'otp_screen.dart';

/// Écran d'accueil — premier écran vu à l'installation, avant toute authentification. L'OTP
/// téléphone ne distingue pas techniquement "créer un compte" et "se connecter" (le même
/// `POST /auth/verify-otp` crée le compte au premier succès et connecte ensuite — voir
/// `services/otp.py`) : les deux CTA ci-dessous mènent donc tous les deux à `OtpScreen`, sans
/// paramètre de mode à lui passer. Les distinguer visuellement reste la bonne UX (attente
/// habituelle d'un écran d'accueil) même si le parcours réel est unifié derrière.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = BraiseTokens.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(BraiseSpacing.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(flex: 2),
              SignDiamond(color: tokens.braiseInk, size: 56),
              const SizedBox(height: BraiseSpacing.xl),
              Text('Braise', style: textTheme.displayLarge?.copyWith(fontSize: 40)),
              const SizedBox(height: BraiseSpacing.sm),
              Text(
                "L'affinité avant le physique. Découvrez qui vous matche, "
                'pas seulement à quoi iel ressemble.',
                style: textTheme.bodyLarge?.copyWith(color: tokens.inkSecondary),
              ),
              const Spacer(flex: 3),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(braiseRoute(context, const OtpScreen())),
                  child: const Text('Créer un compte'),
                ),
              ),
              const SizedBox(height: BraiseSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).push(braiseRoute(context, const OtpScreen())),
                  child: const Text('J\'ai déjà un compte'),
                ),
              ),
              const SizedBox(height: BraiseSpacing.sm),
              Center(
                child: TextButton(
                  onPressed: () =>
                      Navigator.of(context).push(braiseRoute(context, const LegalScreen())),
                  child: Text(
                    'En continuant, vous acceptez nos CGU et notre politique de confidentialité',
                    textAlign: TextAlign.center,
                    style: textTheme.labelSmall?.copyWith(
                      color: tokens.inkSecondary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: BraiseSpacing.md),
            ],
          ),
        ),
      ),
    );
  }
}
