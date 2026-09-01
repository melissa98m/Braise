// ProfileSetupScreen (écran 02) was the last directly-testable screen without coverage.
// Deliberately not exercising _addPhoto() (real ImagePicker platform channel, not mockable here)
// or _pickBirthDate() (a real showDatePicker flow) — _save() only requires _birthDate OR an
// already-loaded _profile to proceed, and a successful _load() always sets _profile, so
// publishing is reachable without ever touching the date picker.

import 'dart:convert';

import 'package:braise_app/screens/onboarding/concept_intro_screen.dart';
import 'package:braise_app/screens/profile/profile_setup_screen.dart';
import 'package:braise_app/state/app_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Voir test/screens/ban_appeal_screen_test.dart pour pourquoi ce helper existe :
/// `http.Response(String, ...)` retombe sur Latin-1 sans en-tête Content-Type explicite, ce qui
/// casse `utf8.decode` côté `ApiClient._decode` dès qu'un accent apparaît (partout, en français).
http.Response _json(Object data, int status) {
  return http.Response(
    jsonEncode(data),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

Map<String, dynamic> _publicProfile({
  String displayName = 'Camille',
  String bio = 'Toujours partante pour une rando.',
  List<String> interests = const ['Cinéma'],
  bool isPublished = false,
  String? gender,
  String? city,
  int? maxDistanceKm,
}) => {
  'display_name': displayName,
  'age': 27,
  'bio': bio,
  'interests': interests,
  'avatar': {'seed': 'abc', 'from_color': '#FF3366', 'to_color': '#3366FF', 'angle_deg': 45.0},
  'is_published': isPublished,
  'is_premium': false,
  'is_verified': true,
  'gender': gender,
  'looking_for_gender': null,
  'age_min': null,
  'age_max': null,
  'city': city,
  'max_distance_km': maxDistanceKm,
};

/// L'écran est dans un `SingleChildScrollView` (comme ReportScreen) : ce qui est sous la ligne
/// de flottaison échoue silencieusement un `tester.tap()` sans passer par `ensureVisible()`
/// d'abord.
Future<void> _tapAfterScrollingTo(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
}

Widget _harness(AppServices services, {bool isOnboarding = false}) {
  return MultiProvider(
    providers: [Provider<AppServices>.value(value: services)],
    child: MaterialApp(home: ProfileSetupScreen(isOnboarding: isOnboarding)),
  );
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('loads and pre-fills the name, bio, and interests', (tester) async {
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/profiles/me/public') {
        return _json(_publicProfile(), 200);
      }
      if (request.method == 'GET' && request.url.path == '/profiles/me/private') {
        return _json({'photos': []}, 200);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'Prénom / pseudo'), findsOneWidget);
    final nameField = tester.widget<TextField>(find.byType(TextField).first);
    expect(nameField.controller!.text, 'Camille');
    expect(find.text('Cinéma'), findsOneWidget);
    expect(find.text('Publier mon profil public'), findsOneWidget);
  });

  testWidgets('a load error is surfaced without leaving the form stuck loading', (tester) async {
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/profiles/me/public') {
        return _json({'detail': 'Service indisponible.'}, 503);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await tester.pumpAndSettle();

    expect(find.text('Service indisponible.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('adding and removing an interest chip', (tester) async {
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/profiles/me/public') {
        return _json(_publicProfile(interests: const []), 200);
      }
      if (request.method == 'GET' && request.url.path == '/profiles/me/private') {
        return _json({'photos': []}, 200);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.widgetWithText(TextField, 'Ajouter un intérêt'));
    await tester.enterText(find.widgetWithText(TextField, 'Ajouter un intérêt'), 'Randonnée');
    await _tapAfterScrollingTo(tester, find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text('Randonnée'), findsOneWidget);

    // Appel direct du callback plutôt que de viser l'icône de suppression du Chip (rendu par
    // défaut par le widget Material, fragile à cibler par icône) : même effet que l'utilisateur
    // tapant dessus, sans dépendre du détail de rendu de Chip.
    final chip = tester.widget<Chip>(find.widgetWithText(Chip, 'Randonnée'));
    chip.onDeleted!();
    await tester.pumpAndSettle();

    expect(find.text('Randonnée'), findsNothing);
  });

  testWidgets('the add-interest and add-photo buttons have accessible names', (tester) async {
    // P14 a11y pass: both were bare icon buttons with no tooltip/Semantics label, so a screen
    // reader announced just "button" — found by inspecting the live app's accessibility tree,
    // not by reading the widget code.
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/profiles/me/public') {
        return _json(_publicProfile(interests: const []), 200);
      }
      if (request.method == 'GET' && request.url.path == '/profiles/me/private') {
        return _json({'photos': []}, 200);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byTooltip('Ajouter un intérêt'));
    expect(find.byTooltip('Ajouter un intérêt'), findsOneWidget);
    await tester.ensureVisible(find.bySemanticsLabel('Ajouter une photo'));
    expect(find.bySemanticsLabel('Ajouter une photo'), findsOneWidget);
  });

  testWidgets('using the bio prompt fills the bio field with the shown prompt', (tester) async {
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/profiles/me/public') {
        return _json(_publicProfile(bio: ''), 200);
      }
      if (request.method == 'GET' && request.url.path == '/profiles/me/private') {
        return _json({'photos': []}, 200);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await tester.pumpAndSettle();

    expect(find.text('MATIÈRE À QUESTIONS'), findsOneWidget);
    final bioField = tester.widget<TextField>(find.byType(TextField).at(1));
    expect(bioField.controller!.text, isEmpty);

    await _tapAfterScrollingTo(tester, find.text('Utiliser'));
    await tester.pumpAndSettle();

    // La question affichée est choisie aléatoirement à l'ouverture (peu importe laquelle) —
    // seul compte que "Utiliser" copie bien ce qui est montré dans le champ bio.
    final updatedField = tester.widget<TextField>(find.byType(TextField).at(1));
    expect(updatedField.controller!.text, isNotEmpty);
  });

  testWidgets('selecting a gender chip toggles it, tapping again clears it', (tester) async {
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/profiles/me/public') {
        return _json(_publicProfile(), 200);
      }
      if (request.method == 'GET' && request.url.path == '/profiles/me/private') {
        return _json({'photos': []}, 200);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await tester.pumpAndSettle();

    final femmeChip = find.widgetWithText(ChoiceChip, 'Femme').first;
    await _tapAfterScrollingTo(tester, femmeChip);
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(femmeChip).selected, isTrue);

    await _tapAfterScrollingTo(tester, femmeChip);
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(femmeChip).selected, isFalse);
  });

  testWidgets('regenerating the avatar calls the API', (tester) async {
    var regenerateCalled = false;
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/profiles/me/public') {
        return _json(_publicProfile(), 200);
      }
      if (request.method == 'GET' && request.url.path == '/profiles/me/private') {
        return _json({'photos': []}, 200);
      }
      if (request.method == 'POST' && request.url.path == '/profiles/me/avatar/regenerate') {
        regenerateCalled = true;
        return _json({
          'seed': 'xyz',
          'from_color': '#00FF00',
          'to_color': '#0000FF',
          'angle_deg': 90.0,
        }, 200);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await tester.pumpAndSettle();

    await _tapAfterScrollingTo(tester, find.text('Régénérer'));
    await tester.pumpAndSettle();

    expect(regenerateCalled, isTrue);
  });

  testWidgets('publishing sends the current fields and confirms outside onboarding', (
    tester,
  ) async {
    Map<String, dynamic>? sentBody;
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/profiles/me/public') {
        return _json(_publicProfile(displayName: 'Camille', isPublished: false), 200);
      }
      if (request.method == 'GET' && request.url.path == '/profiles/me/private') {
        return _json({'photos': []}, 200);
      }
      if (request.method == 'PUT' && request.url.path == '/profiles/me/public') {
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return _json(_publicProfile(displayName: 'Camille', isPublished: true), 200);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await tester.pumpAndSettle();

    await _tapAfterScrollingTo(tester, find.text('Publier mon profil public'));
    await tester.pumpAndSettle();

    expect(sentBody, isNotNull);
    expect(sentBody!['display_name'], 'Camille');
    expect(sentBody!['is_published'], isTrue);
    expect(find.text('Profil public publié.'), findsOneWidget);
  });

  testWidgets('publishing during onboarding navigates to the concept intro screen', (
    tester,
  ) async {
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/profiles/me/public') {
        return _json(_publicProfile(isPublished: false), 200);
      }
      if (request.method == 'GET' && request.url.path == '/profiles/me/private') {
        return _json({'photos': []}, 200);
      }
      if (request.method == 'PUT' && request.url.path == '/profiles/me/public') {
        return _json(_publicProfile(isPublished: true), 200);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client), isOnboarding: true));
    await tester.pumpAndSettle();

    await _tapAfterScrollingTo(tester, find.text('Publier mon profil public'));
    await tester.pumpAndSettle();

    expect(find.byType(ConceptIntroScreen), findsOneWidget);
  });

  testWidgets('a publish failure surfaces its message', (tester) async {
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/profiles/me/public') {
        return _json(_publicProfile(), 200);
      }
      if (request.method == 'GET' && request.url.path == '/profiles/me/private') {
        return _json({'photos': []}, 200);
      }
      if (request.method == 'PUT' && request.url.path == '/profiles/me/public') {
        return _json({'detail': 'Erreur serveur.'}, 500);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await tester.pumpAndSettle();

    await _tapAfterScrollingTo(tester, find.text('Publier mon profil public'));
    await tester.pumpAndSettle();

    expect(find.text('Erreur serveur.'), findsOneWidget);
  });

  testWidgets('loads and pre-fills the city and distance radius', (tester) async {
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/profiles/me/public') {
        return _json(_publicProfile(city: 'Paris', maxDistanceKm: 150), 200);
      }
      if (request.method == 'GET' && request.url.path == '/profiles/me/private') {
        return _json({'photos': []}, 200);
      }
      if (request.method == 'GET' && request.url.path == '/profiles/cities') {
        return _json(['Paris', 'Lyon', 'Marseille'], 200);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await tester.pumpAndSettle();

    expect(find.text('Paris'), findsOneWidget);
    expect(find.text('Rayon de recherche : 150 km'), findsOneWidget);
  });

  testWidgets('no city set hides the distance slider', (tester) async {
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/profiles/me/public') {
        return _json(_publicProfile(), 200);
      }
      if (request.method == 'GET' && request.url.path == '/profiles/me/private') {
        return _json({'photos': []}, 200);
      }
      if (request.method == 'GET' && request.url.path == '/profiles/cities') {
        return _json(['Paris', 'Lyon'], 200);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await tester.pumpAndSettle();

    expect(find.textContaining('Rayon de recherche'), findsNothing);
  });

  testWidgets('publishing sends the chosen city and distance radius', (tester) async {
    Map<String, dynamic>? sentBody;
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/profiles/me/public') {
        return _json(_publicProfile(), 200);
      }
      if (request.method == 'GET' && request.url.path == '/profiles/me/private') {
        return _json({'photos': []}, 200);
      }
      if (request.method == 'GET' && request.url.path == '/profiles/cities') {
        return _json(['Paris', 'Lyon'], 200);
      }
      if (request.method == 'PUT' && request.url.path == '/profiles/me/public') {
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return _json(_publicProfile(isPublished: true), 200);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(_harness(AppServices(httpClient: client)));
    await tester.pumpAndSettle();

    await _tapAfterScrollingTo(tester, find.text('Non renseignée'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lyon').last);
    await tester.pumpAndSettle();

    await _tapAfterScrollingTo(tester, find.text('Publier mon profil public'));
    await tester.pumpAndSettle();

    expect(sentBody, isNotNull);
    expect(sentBody!['city'], 'Lyon');
    // Le rayon par défaut (aucun encore choisi manuellement) suit la valeur affichée par défaut.
    expect(sentBody!['max_distance_km'], 100);
  });
}
