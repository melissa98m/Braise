// WelcomeScreen is the very first screen a signed-out user sees (main.dart's _AuthGate) — a
// presentation screen with two CTAs before the OTP flow. The OTP backend doesn't actually
// distinguish signup from login (POST /auth/verify-otp creates the account on first success,
// signs in afterward — see services/otp.py), so both CTAs push the same OtpScreen; this test
// only checks that both are present and reachable, not that they differ in destination.

import 'package:bresonne_app/screens/legal/legal_screen.dart';
import 'package:bresonne_app/screens/onboarding/otp_screen.dart';
import 'package:bresonne_app/screens/onboarding/welcome_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

Widget _harness() {
  return MaterialApp(theme: ThemeData.dark(), home: const WelcomeScreen());
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('shows the app name and both call-to-actions', (tester) async {
    await tester.pumpWidget(_harness());

    expect(find.text('Bresonne'), findsOneWidget);
    expect(find.text('Créer un compte'), findsOneWidget);
    expect(find.text('J\'ai déjà un compte'), findsOneWidget);
  });

  testWidgets('"Créer un compte" opens the OTP screen', (tester) async {
    await tester.pumpWidget(_harness());

    await tester.tap(find.text('Créer un compte'));
    await tester.pumpAndSettle();

    expect(find.byType(OtpScreen), findsOneWidget);
  });

  testWidgets('"J\'ai déjà un compte" opens the OTP screen', (tester) async {
    await tester.pumpWidget(_harness());

    await tester.tap(find.text('J\'ai déjà un compte'));
    await tester.pumpAndSettle();

    expect(find.byType(OtpScreen), findsOneWidget);
  });

  testWidgets('the legal notice opens the CGU/privacy screen', (tester) async {
    await tester.pumpWidget(_harness());

    await tester.tap(
      find.text('En continuant, vous acceptez nos CGU et notre politique de confidentialité'),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LegalScreen), findsOneWidget);
  });
}
