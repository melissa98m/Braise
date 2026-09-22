import 'package:flutter/material.dart';

import '../../theme/braise_tokens.dart';
import '../../widgets/braise_page_route.dart';
import '../legal/legal_screen.dart';
import 'otp_screen.dart';

/// Écran d'accueil — premier écran vu à l'installation, avant toute authentification. L'OTP
/// téléphone ne distingue pas techniquement "créer un compte" et "se connecter" (le même
/// `POST /auth/verify-otp` crée le compte au premier succès et connecte ensuite — voir
/// `services/otp.py`) : les deux CTA ci-dessous mènent donc tous les deux à `OtpScreen`, sans
/// paramètre de mode à lui passer. Les distinguer visuellement reste la bonne UX (attente
/// habituelle d'un écran d'accueil) même si le parcours réel est unifié derrière.
///
/// Premier écran de l'app : mérite le seul "hero moment" d'entrée de toute l'app — logo, titre,
/// sous-titre et CTA se révèlent en cascade (fondu + léger glissement vers le haut) plutôt que
/// d'apparaître d'un coup. `MediaQuery.disableAnimations` saute directement à l'état final, même
/// motif que `braise_page_route.dart`/`paywall_screen.dart`'s `_PulsingDiamond`.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.of(context).disableAnimations) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Une étape de la cascade : fondu + léger glissement vers le haut sur un segment `[start, end]`
  /// de `_controller`, jamais un simple `Curves.easeOutCubic` global — c'est l'échelonnement qui
  /// fait la cascade, pas la courbe seule.
  Widget _reveal(double start, double end, Widget child) {
    final t = Interval(start, end, curve: Curves.easeOutCubic).transform(_controller.value);
    return Opacity(
      opacity: t.clamp(0.0, 1.0),
      child: Transform.translate(offset: Offset(0, (1 - t) * 18), child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = BraiseTokens.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(BraiseSpacing.xxl),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Spacer(flex: 2),
                  _reveal(
                    0.0,
                    0.5,
                    Image.asset('assets/branding/bresonne_mark.png', width: 64, height: 64),
                  ),
                  const SizedBox(height: BraiseSpacing.xl),
                  _reveal(
                    0.1,
                    0.6,
                    Text('Bresonne', style: textTheme.displayLarge?.copyWith(fontSize: 40)),
                  ),
                  const SizedBox(height: BraiseSpacing.sm),
                  _reveal(
                    0.2,
                    0.7,
                    Text(
                      "L'affinité avant le physique. Découvrez qui vous matche, "
                      'pas seulement à quoi iel ressemble.',
                      style: textTheme.bodyLarge?.copyWith(color: tokens.inkSecondary),
                    ),
                  ),
                  const Spacer(flex: 3),
                  _reveal(
                    0.4,
                    0.9,
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () =>
                            Navigator.of(context).push(braiseRoute(context, const OtpScreen())),
                        child: const Text('Créer un compte'),
                      ),
                    ),
                  ),
                  const SizedBox(height: BraiseSpacing.sm),
                  _reveal(
                    0.45,
                    0.95,
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () =>
                            Navigator.of(context).push(braiseRoute(context, const OtpScreen())),
                        child: const Text('J\'ai déjà un compte'),
                      ),
                    ),
                  ),
                  const SizedBox(height: BraiseSpacing.sm),
                  _reveal(
                    0.5,
                    1.0,
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
                  ),
                  const SizedBox(height: BraiseSpacing.md),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
