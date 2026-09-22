import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_exception.dart';
import '../../state/app_services.dart';
import '../../state/auth_controller.dart';
import '../../theme/braise_tokens.dart';
import '../../widgets/braise_page_route.dart';
import '../../widgets/sign_shapes.dart';
import '../legal/legal_screen.dart';
import '../profile/profile_setup_screen.dart';
import '../root_shell.dart';

/// Recueil de consentement RGPD, juste après l'OTP (voir `_AuthGate` dans main.dart : un compte
/// `signedIn` sans les 4 consentements est routé ici avant tout le reste, y compris un compte
/// déjà existant qui datait d'avant cette fonctionnalité). 4 cases distinctes plutôt qu'une seule
/// case globale "j'accepte tout" : la CNIL exige, pour une donnée sensible (ici l'orientation,
/// révélée par la combinaison genre/genre recherché — voir schemas/profile.py), un consentement
/// "libre, spécifique, éclairé et univoque" recueilli séparément de l'acceptation des CGU —
/// jamais pré-cochée, jamais groupée avec le reste.
class ConsentScreen extends StatefulWidget {
  const ConsentScreen({super.key});

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  bool _ageConfirmed = false;
  bool _cguAccepted = false;
  bool _privacyAcknowledged = false;
  bool _sensitiveDataConsented = false;
  bool _loading = false;
  String? _error;

  bool get _allChecked =>
      _ageConfirmed && _cguAccepted && _privacyAcknowledged && _sensitiveDataConsented;

  Future<void> _continue() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await context.read<AuthController>().submitFullConsent();
      if (!mounted) return;
      final services = context.read<AppServices>();
      final profile = await services.profilesApi.getMyPublicProfile();
      if (!mounted) return;
      final destination =
          profile.isPublished ? const RootShell() : const ProfileSetupScreen(isOnboarding: true);
      // pushAndRemoveUntil systématique (jamais pushReplacement) : cet écran peut être atteint
      // aussi bien en root reactif (_AuthGate) qu'en route poussée depuis OtpScreen — un
      // pushReplacement laisserait dans le premier cas un RootShell fantôme empilé dessous, même
      // bug de fond que celui documenté sur OtpScreen.
      Navigator.of(context).pushAndRemoveUntil(braiseRoute(context, destination), (_) => false);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = BraiseTokens.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(BraiseSpacing.xxl),
          children: [
            SignHatchedCircle(color: tokens.voileInk, size: 40),
            const SizedBox(height: BraiseSpacing.lg),
            Text('Avant de continuer', style: textTheme.displayLarge?.copyWith(fontSize: 28)),
            const SizedBox(height: BraiseSpacing.sm),
            Text(
              'Quelques confirmations nécessaires pour créer votre compte.',
              style: textTheme.bodyLarge?.copyWith(color: tokens.inkSecondary),
            ),
            const SizedBox(height: BraiseSpacing.xl),
            CheckboxListTile(
              value: _ageConfirmed,
              onChanged: (v) => setState(() => _ageConfirmed = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: const Text('Je confirme avoir 18 ans ou plus.'),
            ),
            CheckboxListTile(
              value: _cguAccepted,
              onChanged: (v) => setState(() => _cguAccepted = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: _LinkedConsentLabel(
                prefix: "J'ai lu et j'accepte les ",
                linkText: "Conditions Générales d'Utilisation",
                suffix: ' de Bresonne.',
                onTapLink: () => Navigator.of(context)
                    .push(braiseRoute(context, const LegalScreen())),
              ),
            ),
            CheckboxListTile(
              value: _privacyAcknowledged,
              onChanged: (v) => setState(() => _privacyAcknowledged = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: _LinkedConsentLabel(
                prefix: "J'ai pris connaissance de la ",
                linkText: 'Politique de confidentialité',
                suffix: ' de Bresonne.',
                onTapLink: () => Navigator.of(context)
                    .push(braiseRoute(context, const LegalScreen(initialTab: 1))),
              ),
            ),
            const SizedBox(height: BraiseSpacing.lg),
            // Case 4, isolée dans son propre cadre : c'est la seule donnée sensible au sens RGPD
            // art. 9 de tout cet écran (orientation, déduite du genre et des préférences de
            // rencontre) — elle ne doit jamais se fondre visuellement avec les 3 cases
            // précédentes, ni être cochée par un même geste global.
            Container(
              padding: const EdgeInsets.all(BraiseSpacing.md),
              decoration: BoxDecoration(
                color: tokens.surface1,
                borderRadius: BorderRadius.circular(BraiseRadii.card),
                border: Border.all(color: tokens.borderHairline),
              ),
              // Material(transparency) : CheckboxListTile est un ListTile, qui peint son fond et
              // ses ondes d'encre sur le Material ancêtre le plus proche — sans ce Material
              // intermédiaire, c'est le Container coloré ci-dessus qui les recevrait à la place,
              // les rendant invisibles (assertion levée par Flutter en debug/test).
              child: Material(
                type: MaterialType.transparency,
                child: CheckboxListTile(
                  value: _sensitiveDataConsented,
                  onChanged: (v) => setState(() => _sensitiveDataConsented = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Je consens expressément au traitement de mon orientation — déduite de mon '
                    'genre et du genre que je recherche — par Bresonne, afin de permettre les '
                    'fonctionnalités de rencontre et de matching.',
                  ),
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: BraiseSpacing.lg),
                child: Text(_error!, style: textTheme.bodyMedium?.copyWith(color: tokens.erreur)),
              ),
            const SizedBox(height: BraiseSpacing.xl),
            ElevatedButton(
              onPressed: _allChecked && !_loading ? _continue : null,
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        semanticsLabel: 'Chargement en cours.',
                      ),
                    )
                  : const Text('Continuer'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Une case avec un segment de texte cliquable au milieu (le nom du document légal) — un
/// `RichText`/`TextSpan` avec `TapGestureRecognizer`, pas 3 widgets côte à côte, pour que le
/// texte continue de s'enrouler naturellement sur plusieurs lignes comme n'importe quel `Text`.
class _LinkedConsentLabel extends StatelessWidget {
  const _LinkedConsentLabel({
    required this.prefix,
    required this.linkText,
    required this.suffix,
    required this.onTapLink,
  });

  final String prefix;
  final String linkText;
  final String suffix;
  final VoidCallback onTapLink;

  @override
  Widget build(BuildContext context) {
    final tokens = BraiseTokens.of(context);
    final base = Theme.of(context).textTheme.bodyMedium;
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(text: prefix),
          TextSpan(
            text: linkText,
            style: base?.copyWith(color: tokens.braiseInk, decoration: TextDecoration.underline),
            recognizer: TapGestureRecognizer()..onTap = onTapLink,
          ),
          TextSpan(text: suffix),
        ],
      ),
    );
  }
}
