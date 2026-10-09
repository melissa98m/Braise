import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_exception.dart';
import '../../state/app_services.dart';
import '../../state/auth_controller.dart';
import '../../theme/braise_tokens.dart';
import '../../utils/validators.dart';
import '../../widgets/braise_page_route.dart';
import '../../widgets/sign_shapes.dart';
import '../profile/profile_setup_screen.dart';
import '../root_shell.dart';
import 'consent_screen.dart';

/// Écran 01 — adapté à ce qui existe réellement côté backend (OTP par email), pas le scan de
/// pièce d'identité de la maquette : il n'y a pas de KYC fort dans ce MVP (cahier des charges
/// D.6, stub gratuit/local — voir CLAUDE.md).
class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> with SingleTickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  bool _codeSent = false;
  bool _loading = false;
  String? _error;
  String? _debugCode;

  // Secousse du champ code sur un code refusé — un usage classique et volontaire du mouvement
  // pour un retour d'erreur (cf. `animate` skill), jamais déclenchée sur une erreur de demande de
  // code (étape 1), seulement sur un code vérifié et refusé (étape 2).
  late final AnimationController _shakeController;
  late final Animation<double> _shakeOffset;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _shakeOffset =
        TweenSequence<double>([
          TweenSequenceItem(
            tween: Tween(begin: 0.0, end: -8.0).chain(CurveTween(curve: Curves.easeOut)),
            weight: 1,
          ),
          TweenSequenceItem(
            tween: Tween(begin: -8.0, end: 8.0).chain(CurveTween(curve: Curves.easeInOut)),
            weight: 1,
          ),
          TweenSequenceItem(
            tween: Tween(begin: 8.0, end: -5.0).chain(CurveTween(curve: Curves.easeInOut)),
            weight: 1,
          ),
          TweenSequenceItem(
            tween: Tween(begin: -5.0, end: 0.0).chain(CurveTween(curve: Curves.easeOut)),
            weight: 1,
          ),
        ]).animate(
          _shakeController,
        );
  }

  Future<void> _requestOtp() async {
    final emailError = validateEmail(_emailController.text);
    if (emailError != null) {
      setState(() => _error = emailError);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auth = context.read<AuthController>();
      final debugCode = await auth.requestOtp(_emailController.text.trim());
      setState(() {
        _codeSent = true;
        _debugCode = debugCode;
        if (debugCode != null) _codeController.text = debugCode;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      setState(() => _loading = false);
    }
  }

  void _changeEmail() {
    setState(() {
      _codeSent = false;
      _debugCode = null;
      _error = null;
      _codeController.clear();
    });
  }

  Future<void> _verifyOtp() async {
    final codeError = validateOtpCode(_codeController.text);
    if (codeError != null) {
      setState(() => _error = codeError);
      if (mounted && !MediaQuery.of(context).disableAnimations) {
        _shakeController.forward(from: 0);
      }
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auth = context.read<AuthController>();
      await auth.verifyOtp(_emailController.text.trim(), _codeController.text.trim());
      if (!mounted) return;
      // Consentement RGPD (ConsentScreen) avant absolument tout le reste, y compris pour un
      // compte banni (BanAppealScreen reste atteignable ensuite via _AuthGate, ce chemin-ci ne
      // s'exécute que pour un compte signedIn) : sans ça, l'appel suivant à
      // getMyPublicProfile() n'aurait de toute façon aucune importance puisque
      // PUT /profiles/me/public restera 403 tant que le consentement n'est pas donné.
      if (auth.status == AuthStatus.signedIn && !auth.consentsGiven) {
        Navigator.of(context)
            .pushAndRemoveUntil(braiseRoute(context, const ConsentScreen()), (_) => false);
        return;
      }
      // Un profil public jamais publié (nouvelle inscription) passe d'abord par sa création —
      // pas de découverte tant qu'il n'y a rien à montrer aux autres.
      final services = context.read<AppServices>();
      final profile = await services.profilesApi.getMyPublicProfile();
      if (!mounted) return;
      // pushAndRemoveUntil pour un profil déjà publié (retour) : WelcomeScreen a poussé cet
      // écran par-dessus la route racine, qui affiche déjà RootShell de façon réactive une fois
      // connecté (_AuthGate) — un simple pushReplacement laissait donc RootShell empilé deux
      // fois, avec une flèche "retour" fantôme qui ne menait nulle part de nouveau. Pour la
      // création de profil (isOnboarding), pushReplacement reste correct : ce n'est pas encore
      // la destination finale.
      final destination = profile.isPublished
          ? const RootShell()
          : const ProfileSetupScreen(isOnboarding: true);
      if (profile.isPublished) {
        Navigator.of(context).pushAndRemoveUntil(braiseRoute(context, destination), (_) => false);
        return;
      }
      Navigator.of(context).pushReplacement(
        braiseRoute(context, destination),
      );
    } on ApiException catch (e) {
      setState(() => _error = e.message);
      if (mounted && !MediaQuery.of(context).disableAnimations) {
        _shakeController.forward(from: 0);
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = BraiseTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    final animDuration = MediaQuery.of(context).disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 250);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(BraiseSpacing.xxl),
          // Contenu défilant au-dessus d'un bouton toujours visible en bas : l'étape 2 (champ
          // code, aide « courriers indésirables », « Modifier l'adresse », bannière debug)
          // dépasse la hauteur d'un petit téléphone — et de n'importe lequel clavier ouvert. Une
          // Column fixe avec Spacer débordait alors simplement, bouton compris.
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: BraiseSpacing.lg),
                      // 2 étapes (numéro, code) — mêmes segments pleins/vides que la maquette 3 étapes,
                      // jamais seulement une couleur pour indiquer la progression.
                      Row(
                        children: [
                          Expanded(
                            child: AnimatedContainer(
                              duration: animDuration,
                              height: 4,
                              decoration: BoxDecoration(
                                color: tokens.braiseInk,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          const SizedBox(width: BraiseSpacing.sm),
                          Expanded(
                            child: AnimatedContainer(
                              duration: animDuration,
                              height: 4,
                              decoration: BoxDecoration(
                                color: _codeSent ? tokens.braiseInk : tokens.borderHairline,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          const SizedBox(width: BraiseSpacing.sm),
                          Text(
                            _codeSent ? '2/2' : '1/2',
                            style: textTheme.labelSmall?.copyWith(color: tokens.inkSecondary),
                          ),
                        ],
                      ),
                      const SizedBox(height: BraiseSpacing.xxl),
                      Text(
                        'On vérifie que vous êtes bien vous.',
                        style: textTheme.displayLarge?.copyWith(fontSize: 30, height: 34 / 30),
                      ),
                      const SizedBox(height: BraiseSpacing.lg),
                      Text(
                        "Un code est envoyé par email pour confirmer votre adresse. Aucune pièce "
                        "d'identité n'est demandée à ce stade.",
                        style: textTheme.bodyLarge?.copyWith(color: tokens.inkSecondary),
                      ),
                      const SizedBox(height: BraiseSpacing.xxl),
                      TextField(
                        controller: _emailController,
                        enabled: !_codeSent,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        textCapitalization: TextCapitalization.none,
                        autofillHints: const [AutofillHints.email],
                        // `labelText` distinct du `hintText` (l'exemple de format) : sans lui, le repère
                        // visuel du champ disparaissait dès la première frappe — repéré en revoyant les
                        // 9 champs de texte de l'app, un seul motif partout, jamais un oubli isolé.
                        decoration: const InputDecoration(
                          labelText: 'Adresse email',
                          hintText: 'prenom@exemple.fr',
                        ),
                      ),
                      AnimatedSize(
                        duration: animDuration,
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.topCenter,
                        child: !_codeSent
                            ? const SizedBox(width: double.infinity)
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: BraiseSpacing.lg),
                                  AnimatedBuilder(
                                    animation: _shakeOffset,
                                    builder: (context, child) => Transform.translate(
                                      offset: Offset(_shakeOffset.value, 0),
                                      child: child,
                                    ),
                                    child: TextField(
                                      controller: _codeController,
                                      keyboardType: TextInputType.number,
                                      autofillHints: const [AutofillHints.oneTimeCode],
                                      decoration: const InputDecoration(labelText: 'Code reçu par email'),
                                    ),
                                  ),
                                  const SizedBox(height: BraiseSpacing.sm),
                                  Text(
                                    'Rien reçu ? Vérifiez vos courriers indésirables.',
                                    style: textTheme.bodyMedium?.copyWith(color: tokens.inkSecondary),
                                  ),
                                  // Le champ adresse est verrouillé une fois le code demandé : sans ce
                                  // retour à l'étape 1, une faute de frappe dans l'adresse (fréquente,
                                  // contrairement à un numéro) laissait la personne bloquée sur un code
                                  // qui n'arrivera jamais. Redemander un code passe par la même étape.
                                  TextButton(
                                    onPressed: _loading ? null : _changeEmail,
                                    child: const Text("Modifier l'adresse ou renvoyer un code"),
                                  ),
                                  if (_debugCode != null)
                                    Container(
                                      margin: const EdgeInsets.only(top: BraiseSpacing.md),
                                      padding: const EdgeInsets.all(BraiseSpacing.md),
                                      decoration: BoxDecoration(
                                        color: tokens.surface1,
                                        border: Border.all(color: tokens.borderHairline),
                                        borderRadius: BorderRadius.circular(BraiseRadii.card),
                                      ),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          SignSquareCore(color: tokens.foiInk, size: 26),
                                          const SizedBox(width: BraiseSpacing.md),
                                          Expanded(
                                            child: Text(
                                              'Mode debug local : code pré-rempli ($_debugCode).',
                                              style: textTheme.bodyMedium?.copyWith(color: tokens.inkPrimary),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: BraiseSpacing.lg),
                          child: Text(_error!, style: textTheme.bodyMedium?.copyWith(color: tokens.erreur)),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: BraiseSpacing.lg),
              ElevatedButton(
                onPressed: _loading
                    ? null
                    : (_codeSent ? _verifyOtp : _requestOtp),
                child: Text(_codeSent ? 'Vérifier le code' : 'Recevoir mon code'),
              ),
              const SizedBox(height: BraiseSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _shakeController.dispose();
    super.dispose();
  }
}
