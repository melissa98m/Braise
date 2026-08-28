import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_exception.dart';
import '../../state/auth_controller.dart';
import '../../theme/braise_tokens.dart';
import '../../widgets/braise_page_route.dart';
import '../../widgets/sign_shapes.dart';
import '../root_shell.dart';

/// Écran 01 — adapté à ce qui existe réellement côté backend (OTP téléphone), pas le scan de
/// pièce d'identité de la maquette : il n'y a pas de KYC fort dans ce MVP (cahier des charges
/// D.6, stub gratuit/local — voir CLAUDE.md).
class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  bool _codeSent = false;
  bool _loading = false;
  String? _error;
  String? _debugCode;

  Future<void> _requestOtp() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auth = context.read<AuthController>();
      final debugCode = await auth.requestOtp(_phoneController.text.trim());
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

  Future<void> _verifyOtp() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auth = context.read<AuthController>();
      await auth.verifyOtp(_phoneController.text.trim(), _codeController.text.trim());
      if (mounted) {
        Navigator.of(context).pushReplacement(braiseRoute(context, const RootShell()));
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      setState(() => _loading = false);
    }
  }

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
              const SizedBox(height: BraiseSpacing.lg),
              // 2 étapes (numéro, code) — mêmes segments pleins/vides que la maquette 3 étapes,
              // jamais seulement une couleur pour indiquer la progression.
              Row(
                children: [
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
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
                      duration: const Duration(milliseconds: 250),
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
                "Un code est envoyé par SMS pour confirmer votre numéro. Aucune pièce d'identité "
                "n'est demandée à ce stade.",
                style: textTheme.bodyLarge?.copyWith(color: tokens.inkSecondary),
              ),
              const SizedBox(height: BraiseSpacing.xxl),
              TextField(
                controller: _phoneController,
                enabled: !_codeSent,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(hintText: '+33 6 12 34 56 78'),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: !_codeSent
                    ? const SizedBox(width: double.infinity)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: BraiseSpacing.lg),
                          TextField(
                            controller: _codeController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(hintText: 'Code reçu par SMS'),
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
              const Spacer(),
              ElevatedButton(
                onPressed: _loading
                    ? null
                    : (_codeSent ? _verifyOtp : _requestOtp),
                child: Text(_codeSent ? 'Vérifier le code' : 'Recevoir mon code'),
              ),
              const SizedBox(height: BraiseSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: Text(
                  'Sans vérification : découverte limitée.',
                  textAlign: TextAlign.center,
                  style: textTheme.labelSmall?.copyWith(color: tokens.inkSecondary),
                ),
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
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }
}
