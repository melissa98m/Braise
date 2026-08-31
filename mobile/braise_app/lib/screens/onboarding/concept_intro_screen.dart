import 'package:flutter/material.dart';

import '../../theme/braise_tokens.dart';
import '../../widgets/braise_page_route.dart';
import '../../widgets/sign_shapes.dart';
import '../root_shell.dart';

/// A.4.1, point 5 : "Explication pédagogique du concept (écran d'onboarding dédié) : pourquoi le
/// physique est différé, comment fonctionnent les flammes." N'existait pas avant ce palier —
/// l'onboarding sautait directement de la création du profil à la découverte, sans jamais
/// expliquer la mécanique centrale du produit. Affiché une seule fois, juste après la publication
/// du profil public (voir `isOnboarding` dans `ProfileSetupScreen`), avant d'entrer dans l'app.
class ConceptIntroScreen extends StatefulWidget {
  const ConceptIntroScreen({super.key});

  @override
  State<ConceptIntroScreen> createState() => _ConceptIntroScreenState();
}

class _ConceptIntroScreenState extends State<ConceptIntroScreen> {
  final _pageController = PageController();
  int _page = 0;

  static const _pageCount = 3;

  void _next() {
    if (_page == _pageCount - 1) {
      Navigator.of(context).pushReplacement(braiseRoute(context, const RootShell()));
      return;
    }
    _pageController.nextPage(duration: const Duration(milliseconds: 320), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = BraiseTokens.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                BraiseSpacing.xxl,
                BraiseSpacing.lg,
                BraiseSpacing.xxl,
                0,
              ),
              child: Row(
                children: [
                  for (var i = 0; i < _pageCount; i++)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: i == _pageCount - 1 ? 0 : BraiseSpacing.sm),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          height: 4,
                          decoration: BoxDecoration(
                            color: i <= _page ? tokens.braiseInk : tokens.borderHairline,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (page) => setState(() => _page = page),
                children: const [
                  _ConceptPage(
                    icon: _PersonalityIcon(),
                    eyebrow: 'LE CONCEPT',
                    title: 'Une personnalité avant un visage',
                    body:
                        'Ici, le physique n\'est pas un filtre d\'entrée. Vous découvrez d\'abord '
                        'les centres d\'intérêt et la personnalité de vos matchs — la photo vient '
                        'plus tard, quand une vraie connexion s\'est installée.',
                  ),
                  _ConceptPage(
                    icon: SignDiamond(color: Color(0xFFFF8C42), size: 40),
                    eyebrow: 'LE JEU DES FLAMMES',
                    title: 'Une question par jour, jamais une épreuve',
                    body:
                        'Chaque jour, une question sur votre match. Bonne réponse : +1 flamme, '
                        'pour vous deux. Mauvaise réponse : juste une relecture de son profil, '
                        'sans pénalité — la mécanique récompense l\'attention, elle ne punit pas.',
                  ),
                  _ConceptPage(
                    icon: SignHatchedCircle(color: Color(0xFF9E8CFF), size: 40),
                    eyebrow: 'LE VOILE SE LÈVE',
                    title: 'Le profil physique se dévoile ensemble',
                    body:
                        'Silhouette, puis flou léger, puis net : à mesure que les flammes '
                        's\'accumulent. Au seuil atteint, les photos se débloquent pour les deux '
                        'côtés en même temps — jamais un seul des deux en avance sur l\'autre.',
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(BraiseSpacing.xxl),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _next,
                  child: Text(_page == _pageCount - 1 ? 'Découvrir Braise' : 'Suivant'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }
}

class _ConceptPage extends StatelessWidget {
  const _ConceptPage({
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.body,
  });

  final Widget icon;
  final String eyebrow;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final tokens = BraiseTokens.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: BraiseSpacing.xxl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 88,
            height: 88,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tokens.surface1,
              border: Border.all(color: tokens.borderHairline),
              shape: BoxShape.circle,
            ),
            child: icon,
          ),
          const SizedBox(height: BraiseSpacing.xxl),
          Text(
            eyebrow,
            style: textTheme.labelSmall?.copyWith(color: tokens.braiseInk, letterSpacing: 12 * 0.16),
          ),
          const SizedBox(height: BraiseSpacing.sm),
          Text(title, style: textTheme.headlineMedium),
          const SizedBox(height: BraiseSpacing.md),
          Text(body, style: textTheme.bodyLarge?.copyWith(color: tokens.inkSecondary)),
        ],
      ),
    );
  }
}

class _PersonalityIcon extends StatelessWidget {
  const _PersonalityIcon();

  @override
  Widget build(BuildContext context) {
    final tokens = BraiseTokens.of(context);
    // Pas de primitive dédiée dans docs/DESIGN_TOKENS.md pour "personnalité/intérêts" (les 4
    // signes — braise, voile, confiance, vérifié — couvrent des concepts précis, pas celui-ci) :
    // une icône Material reste cohérente avec ce que fait déjà settings_screen.dart pour les
    // réglages, plutôt que de détourner un signe pour un sens qu'il ne porte pas.
    return Icon(Icons.chat_bubble_outline, color: tokens.foiInk, size: 40);
  }
}
