import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_exception.dart';
import '../../state/auth_controller.dart';
import '../../theme/braise_tokens.dart';
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
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const RootShell()),
        );
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
              const SizedBox(height: BraiseSpacing.xxl),
              Text('On vérifie que vous êtes bien vous.', style: textTheme.displayLarge),
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
              if (_codeSent) ...[
                const SizedBox(height: BraiseSpacing.lg),
                TextField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(hintText: 'Code reçu par SMS'),
                ),
                if (_debugCode != null)
                  Padding(
                    padding: const EdgeInsets.only(top: BraiseSpacing.sm),
                    child: Text(
                      'Mode debug local : code pré-rempli ($_debugCode).',
                      style: textTheme.labelSmall?.copyWith(color: tokens.foiInk),
                    ),
                  ),
              ],
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
