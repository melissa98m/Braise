import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../api/api_exception.dart';
import '../../location/location_exception.dart';
import '../../location/location_platform.dart';
import '../../models/public_profile.dart';
import '../../state/app_services.dart';
import '../../theme/braise_tokens.dart';
import '../../utils/validators.dart';
import '../../widgets/avatar_sigil.dart';
import '../../widgets/braise_page_route.dart';
import '../onboarding/concept_intro_screen.dart';

class _GenderChips extends StatelessWidget {
  const _GenderChips({required this.value, required this.onChanged});

  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = BraiseTokens.of(context);
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return Wrap(
      spacing: BraiseSpacing.sm,
      runSpacing: BraiseSpacing.sm,
      children: [
        for (final entry in genderOptions.entries)
          // Petit "pop" d'échelle à la sélection — retour tactile immédiat sur un choix qui,
          // sinon, ne change qu'une couleur de fond difficile à remarquer en un coup d'œil.
          AnimatedScale(
            scale: value == entry.key ? 1.06 : 1.0,
            duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 120),
            curve: Curves.easeOutCubic,
            child: ChoiceChip(
              label: Text(entry.value),
              selected: value == entry.key,
              // Retaper sur la puce déjà sélectionnée la désélectionne (retour à "non renseigné"),
              // plutôt que de forcer un choix — ces préférences sont facultatives (cahier des
              // charges A.5).
              onSelected: (selected) => onChanged(selected ? entry.key : null),
              selectedColor: tokens.braiseTint,
              side: BorderSide(color: value == entry.key ? tokens.braiseInk : tokens.borderHairline),
            ),
          ),
      ],
    );
  }
}

/// Multi-sélection pour "vous recherchez" (homme/femme/non binaire, plusieurs à la fois) —
/// contrairement à `_GenderChips` (son propre genre, un seul choix a du sens), ici chaque puce
/// bascule indépendamment son appartenance à la liste plutôt que de remplacer la sélection.
class _MultiGenderChips extends StatelessWidget {
  const _MultiGenderChips({required this.values, required this.onChanged});

  final List<String> values;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = BraiseTokens.of(context);
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return Wrap(
      spacing: BraiseSpacing.sm,
      runSpacing: BraiseSpacing.sm,
      children: [
        for (final entry in genderOptions.entries)
          AnimatedScale(
            scale: values.contains(entry.key) ? 1.06 : 1.0,
            duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 120),
            curve: Curves.easeOutCubic,
            child: ChoiceChip(
              label: Text(entry.value),
              selected: values.contains(entry.key),
              onSelected: (selected) => onChanged(
                selected ? [...values, entry.key] : values.where((v) => v != entry.key).toList(),
              ),
              selectedColor: tokens.braiseTint,
              side: BorderSide(
                color: values.contains(entry.key) ? tokens.braiseInk : tokens.borderHairline,
              ),
            ),
          ),
      ],
    );
  }
}

/// Écran 02 — le compteur d'indice (bio) et les intérêts guident vers du concret, pas une bio
/// vide type "demandez-moi" (cahier des charges Module 1).
class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key, this.isOnboarding = false});

  /// true juste après l'inscription (profil jamais publié) : la publication enchaîne directement
  /// sur la découverte plutôt que de laisser l'utilisateur sur cet écran (il n'y a rien "avant"
  /// vers quoi revenir avec Navigator.pop).
  final bool isOnboarding;

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  static const _bioMaxLength = 90;

  // Éditeur de bio guidé (cahier des charges A.5 Module 1) : de quoi éviter une bio vide type
  // « demandez-moi », sans dicter une formule figée — l'utilisateur reste libre de tout réécrire.
  static const _bioPrompts = [
    'Un bruit qui vous rassure instantanément.',
    'La dernière chose qui vous a fait rire aux éclats.',
    'Un talent inutile mais dont vous êtes fier·e.',
    'Le sujet sur lequel vous pourriez parler des heures.',
    'Une habitude que personne ne soupçonnerait chez vous.',
    'Le meilleur conseil qu\'on vous ait donné.',
    'Un lieu où vous vous sentez vraiment vous-même.',
    'Ce que vous faites quand vous ne devriez rien faire.',
  ];
  int _bioPromptIndex = 0;

  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  final _interestController = TextEditingController();
  final _interests = <String>[];

  DateTime? _birthDate;
  PublicProfile? _profile;
  List<PrivatePhoto> _photos = [];
  bool _isPublished = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  static const _fullAgeRange = RangeValues(18, 99);
  String? _gender;
  List<String> _lookingForGender = [];
  RangeValues _ageRange = _fullAgeRange;

  // Distance (P9.3) : liste fermée de villes plutôt qu'un champ libre — seuls ces noms résolvent
  // en coordonnées côté backend (services/geo.py), un texte libre n'y correspondrait jamais.
  List<String> _cities = [];
  String? _city;
  static const _defaultMaxDistanceKm = 100;
  int? _maxDistanceKm;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _bioPromptIndex = DateTime.now().millisecond % _bioPrompts.length;
    _load();
    unawaited(_loadCities());
  }

  Future<void> _loadCities() async {
    // Purement décoratif (peuple un sélecteur) : une erreur ici laisse juste la liste vide,
    // jamais une exception non gérée ni une erreur affichée à la place du reste de l'écran.
    try {
      final cities = await context.read<AppServices>().profilesApi.getCities();
      if (!mounted) return;
      setState(() => _cities = cities);
    } on ApiException {
      // Laisse `_cities` vide — le sélecteur de ville n'a alors aucune option, sans bloquer
      // le reste du formulaire.
    }
  }

  /// "Utiliser ma position" (géolocalisation navigateur, gratuite — voir lib/location/) : une
  /// position ponctuelle, résolue côté serveur vers la ville la plus proche de la liste fermée
  /// (`GET /profiles/cities/nearest`, services/geo.nearest_city), jamais stockée telle quelle —
  /// seul le nom de ville qui en résulte remplit `_city`, exactement comme un choix manuel dans
  /// le menu déroulant juste au-dessus.
  Future<void> _useMyLocation() async {
    // Un écran d'explication avant la vraie demande système, pas seulement pour la pédagogie :
    // un navigateur peut définitivement bloquer l'invite native pour l'origine si elle est
    // perçue comme "spam" (demandée hors contexte) — donner le contexte ici, dans une boîte
    // qu'on contrôle, avant de déclencher `getCurrentPosition()` (qui affiche l'invite native
    // du navigateur), plutôt que de la déclencher directement au clic du bouton.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Autoriser Bresonne à accéder à votre position ?'),
        content: const Text(
          'Nous utilisons votre position pour déterminer votre ville et permettre certaines '
          "fonctionnalités de rencontre. Votre position précise n'est pas affichée aux autres "
          'utilisateurs.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Autoriser'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _locating = true);
    try {
      final position = await getCurrentPosition();
      if (!mounted) return;
      final city = await context
          .read<AppServices>()
          .profilesApi
          .getNearestCity(position.lat, position.lon);
      if (!mounted) return;
      setState(() => _city = city);
    } on LocationException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _shuffleBioPrompt() {
    setState(() => _bioPromptIndex = (_bioPromptIndex + 1) % _bioPrompts.length);
  }

  void _useBioPrompt() {
    setState(() {
      _bioController.text = _bioPrompts[_bioPromptIndex];
      _bioController.selection = TextSelection.collapsed(offset: _bioController.text.length);
    });
  }

  Future<void> _load() async {
    final services = context.read<AppServices>();
    try {
      final profile = await services.profilesApi.getMyPublicProfile();
      final photos = await services.profilesApi.getMyPrivatePhotos();
      setState(() {
        _profile = profile;
        _photos = photos;
        _nameController.text = profile.displayName;
        _bioController.text = profile.bio;
        _interests.addAll(profile.interests);
        _isPublished = profile.isPublished;
        _gender = profile.gender;
        _lookingForGender = profile.lookingForGender ?? [];
        _ageRange = RangeValues(
          (profile.ageMin ?? _fullAgeRange.start.round()).toDouble(),
          (profile.ageMax ?? _fullAgeRange.end.round()).toDouble(),
        );
        _city = profile.city;
        _maxDistanceKm = profile.maxDistanceKm;
        _loading = false;
      });
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _addPhoto() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    final services = context.read<AppServices>();
    try {
      final photos = await services.profilesApi.uploadPrivatePhoto(
        bytes,
        picked.name,
        picked.mimeType ?? 'image/jpeg',
      );
      setState(() => _photos = photos);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    }
  }

  Future<void> _deletePhoto(String key) async {
    final services = context.read<AppServices>();
    final photos = await services.profilesApi.deletePrivatePhoto(key);
    setState(() => _photos = photos);
  }

  Future<void> _regenerateAvatar() async {
    final services = context.read<AppServices>();
    final spec = await services.profilesApi.regenerateAvatar();
    if (_profile != null) {
      setState(() {
        _profile = PublicProfile(
          displayName: _profile!.displayName,
          age: _profile!.age,
          bio: _profile!.bio,
          interests: _profile!.interests,
          avatar: spec,
          isPublished: _profile!.isPublished,
          isPremium: _profile!.isPremium,
          isVerified: _profile!.isVerified,
          gender: _profile!.gender,
          lookingForGender: _profile!.lookingForGender,
          ageMin: _profile!.ageMin,
          ageMax: _profile!.ageMax,
          city: _profile!.city,
          maxDistanceKm: _profile!.maxDistanceKm,
        );
      });
    }
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 25),
      firstDate: DateTime(now.year - 100),
      lastDate: DateTime(now.year - 18, now.month, now.day),
    );
    if (picked != null) setState(() => _birthDate = picked);
  }

  void _addInterest() {
    final value = _interestController.text.trim();
    if (value.isEmpty || _interests.contains(value) || _interests.length >= 10) return;
    setState(() {
      _interests.add(value);
      _interestController.clear();
    });
  }

  Future<void> _save({required bool publish}) async {
    if (_birthDate == null && _profile == null) return;
    final nameError = validateDisplayName(_nameController.text);
    if (nameError != null) {
      setState(() => _error = nameError);
      return;
    }
    final services = context.read<AppServices>();
    setState(() {
      _error = null;
      _saving = true;
    });
    try {
      final updated = await services.profilesApi.updateMyPublicProfile(
        displayName: _nameController.text.trim(),
        birthDate: _birthDate ?? DateTime(DateTime.now().year - 25),
        bio: _bioController.text.trim(),
        interests: _interests,
        isPublished: publish,
        gender: _gender,
        // Liste vide = "aucun filtre" côté backend, même sémantique que null : pas besoin de
        // distinguer les deux ici.
        lookingForGender: _lookingForGender.isEmpty ? null : _lookingForGender,
        // Tranche complète = pas de préférence : on ne transmet une borne que si elle a
        // effectivement été resserrée, pour matcher exactement la sémantique "null = pas de
        // filtre" du backend (services/discovery.get_feed).
        ageMin: _ageRange.start.round() == _fullAgeRange.start.round()
            ? null
            : _ageRange.start.round(),
        ageMax: _ageRange.end.round() == _fullAgeRange.end.round()
            ? null
            : _ageRange.end.round(),
        city: _city,
        // Sans ville choisie, un rayon n'a rien à mesurer depuis — le backend l'ignorerait de
        // toute façon (services/discovery.get_feed : `my_location is None` désactive le filtre),
        // mais autant ne jamais l'envoyer plutôt que de laisser une valeur orpheline en base.
        // `?? _defaultMaxDistanceKm` : si une ville vient d'être choisie mais que le curseur
        // n'a jamais été touché, `_maxDistanceKm` reste `null` alors que le curseur affiche déjà
        // "100 km" par défaut (voir le `Text` juste au-dessus dans `build()`) — sans ce repli,
        // le profil publié n'aurait en réalité *aucun* filtre de distance malgré ce qu'affichait
        // l'écran au moment de publier.
        maxDistanceKm: _city == null ? null : (_maxDistanceKm ?? _defaultMaxDistanceKm),
      );
      setState(() {
        _profile = updated;
        _isPublished = updated.isPublished;
      });
      if (!mounted || !publish) return;
      if (widget.isOnboarding) {
        // A.4.1.5 : explication pédagogique dédiée avant la première entrée dans l'app, jamais
        // vue par un utilisateur qui republie juste son profil plus tard (isOnboarding == false).
        Navigator.of(context).pushReplacement(braiseRoute(context, const ConceptIntroScreen()));
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profil public publié.')),
      );
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator(semanticsLabel: 'Chargement en cours.')));

    final tokens = BraiseTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return Scaffold(
      appBar: AppBar(title: const Text('Profil public')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(BraiseSpacing.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Votre signe, pas votre selfie', style: textTheme.headlineMedium),
            const SizedBox(height: BraiseSpacing.xl),
            Row(
              children: [
                if (_profile != null)
                  // Un fondu + léger zoom plutôt qu'un cut instantané : "Régénérer" échangeait la
                  // spec d'avatar d'un coup, sans aucun retour visuel que quelque chose venait de
                  // changer.
                  AnimatedSwitcher(
                    duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 320),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeOutCubic,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(
                        scale: Tween(begin: 0.85, end: 1.0).animate(animation),
                        child: child,
                      ),
                    ),
                    child: AvatarSigil(
                      key: ValueKey(_profile!.avatar.seed),
                      spec: _profile!.avatar,
                      size: 88,
                    ),
                  ),
                const SizedBox(width: BraiseSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Composez un avatar-sigil : matière, halo, trame. Aucune ressemblance '
                        'physique.',
                        style: textTheme.bodyMedium,
                      ),
                      const SizedBox(height: BraiseSpacing.sm),
                      OutlinedButton(
                        onPressed: _regenerateAvatar,
                        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                        child: const Text('Régénérer'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: BraiseSpacing.xxl),
            TextField(
              controller: _nameController,
              maxLength: displayNameMaxLength,
              decoration: const InputDecoration(labelText: 'Prénom / pseudo'),
            ),
            const SizedBox(height: BraiseSpacing.lg),
            OutlinedButton(
              onPressed: _pickBirthDate,
              child: Text(
                _birthDate == null
                    ? 'Date de naissance'
                    : '${_birthDate!.day}/${_birthDate!.month}/${_birthDate!.year}',
              ),
            ),
            const SizedBox(height: BraiseSpacing.lg),
            TextField(
              controller: _bioController,
              maxLength: _bioMaxLength,
              maxLines: 3,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: "Indice d'entrée",
                hintText: 'Je connais tous les bruits du métro ligne 2 les yeux fermés.',
              ),
            ),
            if (_bioController.text.trim().isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: BraiseSpacing.lg),
                child: Container(
                  padding: const EdgeInsets.all(BraiseSpacing.md),
                  decoration: BoxDecoration(
                    color: tokens.surface1,
                    border: Border.all(color: tokens.borderHairline),
                    borderRadius: BorderRadius.circular(BraiseRadii.card),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'MATIÈRE À QUESTIONS',
                              style: textTheme.labelSmall?.copyWith(
                                color: tokens.inkFloor,
                                letterSpacing: 11 * 0.14,
                              ),
                            ),
                            const SizedBox(height: BraiseSpacing.xs),
                            AnimatedSwitcher(
                              duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 220),
                              child: Text(
                                _bioPrompts[_bioPromptIndex],
                                key: ValueKey(_bioPromptIndex),
                                style: textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: _shuffleBioPrompt,
                        icon: const Icon(Icons.refresh),
                        tooltip: 'Une autre question',
                      ),
                      TextButton(onPressed: _useBioPrompt, child: const Text('Utiliser')),
                    ],
                  ),
                ),
              ),
            Text(
              "Centres d'intérêt",
              style: textTheme.labelSmall?.copyWith(letterSpacing: 13 * 0.14),
            ),
            const SizedBox(height: BraiseSpacing.sm),
            Wrap(
              spacing: BraiseSpacing.sm,
              runSpacing: BraiseSpacing.sm,
              children: [
                for (final interest in _interests)
                  // Pop d'entrée (échelle + fondu) à l'ajout — `ValueKey` garantit que Flutter
                  // réutilise l'instance déjà animée d'une puce existante au lieu de la rejouer à
                  // chaque rebuild ; seule une puce vraiment nouvelle est montée pour la première
                  // fois et anime donc depuis `begin`.
                  TweenAnimationBuilder<double>(
                    key: ValueKey(interest),
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    builder: (context, t, child) => Opacity(
                      opacity: t,
                      child: Transform.scale(scale: 0.7 + 0.3 * t, child: child),
                    ),
                    child: Chip(
                      label: Text(interest),
                      backgroundColor: tokens.braiseTint,
                      side: BorderSide(color: tokens.braiseInk, width: 1.75),
                      onDeleted: () => setState(() => _interests.remove(interest)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: BraiseSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _interestController,
                    decoration: const InputDecoration(labelText: 'Ajouter un intérêt'),
                    onSubmitted: (_) => _addInterest(),
                  ),
                ),
                const SizedBox(width: BraiseSpacing.sm),
                IconButton(
                  onPressed: _addInterest,
                  icon: const Icon(Icons.add),
                  tooltip: 'Ajouter un intérêt',
                ),
              ],
            ),
            const SizedBox(height: BraiseSpacing.xxl),
            Text(
              'PRÉFÉRENCES DE DÉCOUVERTE',
              style: textTheme.labelSmall?.copyWith(letterSpacing: 13 * 0.14),
            ),
            const SizedBox(height: BraiseSpacing.xs),
            Text(
              'Facultatif : laissez tout vide pour ne filtrer sur rien (cahier des charges A.5).',
              style: textTheme.bodyMedium?.copyWith(color: tokens.inkSecondary),
            ),
            const SizedBox(height: BraiseSpacing.md),
            Text('Votre genre', style: textTheme.bodyLarge),
            const SizedBox(height: BraiseSpacing.sm),
            _GenderChips(
              value: _gender,
              onChanged: (value) => setState(() => _gender = value),
            ),
            const SizedBox(height: BraiseSpacing.lg),
            Text('Vous recherchez', style: textTheme.bodyLarge),
            const SizedBox(height: BraiseSpacing.sm),
            _MultiGenderChips(
              values: _lookingForGender,
              onChanged: (values) => setState(() => _lookingForGender = values),
            ),
            const SizedBox(height: BraiseSpacing.lg),
            Text(
              _ageRange == _fullAgeRange
                  ? 'Tranche d\'âge : toutes'
                  : 'Tranche d\'âge : ${_ageRange.start.round()}–${_ageRange.end.round()} ans',
              style: textTheme.bodyLarge,
            ),
            RangeSlider(
              values: _ageRange,
              min: _fullAgeRange.start,
              max: _fullAgeRange.end,
              divisions: (_fullAgeRange.end - _fullAgeRange.start).round(),
              labels: RangeLabels(
                '${_ageRange.start.round()}',
                '${_ageRange.end.round()}',
              ),
              onChanged: (value) => setState(() => _ageRange = value),
            ),
            const SizedBox(height: BraiseSpacing.lg),
            // Wrap plutôt qu'un Row+Spacer : le bouton passe à la ligne suivante sur un écran
            // étroit au lieu de déborder (repéré via les tests d'écran, viewport 400px de large,
            // le même que celui utilisé partout ailleurs dans l'app pour simuler un vrai
            // téléphone).
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: BraiseSpacing.sm,
              children: [
                Text('Votre ville', style: textTheme.bodyLarge),
                const SizedBox(width: BraiseSpacing.md),
                TextButton.icon(
                  onPressed: _locating ? null : _useMyLocation,
                  icon: _locating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            semanticsLabel: 'Localisation en cours.',
                          ),
                        )
                      : const Icon(Icons.my_location, size: 18),
                  label: const Text('Utiliser ma position'),
                ),
              ],
            ),
            const SizedBox(height: BraiseSpacing.sm),
            DropdownButtonFormField<String?>(
              // `_cities` peut être vide un instant (chargement, ou échec silencieux — voir
              // _loadCities) : rien de bloquant, juste aucune option tant que ça ne résout pas.
              initialValue: _cities.contains(_city) ? _city : null,
              decoration: const InputDecoration(hintText: 'Non renseignée'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Non renseignée')),
                for (final city in _cities) DropdownMenuItem(value: city, child: Text(city)),
              ],
              onChanged: (value) => setState(() => _city = value),
            ),
            // AnimatedSize plutôt qu'une simple insertion conditionnelle : choisir une ville fait
            // apparaître le curseur de rayon avec une croissance de mise en page, pas un saut brut.
            AnimatedSize(
              duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _city == null
                  ? const SizedBox.shrink()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: BraiseSpacing.lg),
                        Text(
                          'Rayon de recherche : ${_maxDistanceKm ?? _defaultMaxDistanceKm} km',
                          style: textTheme.bodyLarge,
                        ),
                        Slider(
                          value: (_maxDistanceKm ?? _defaultMaxDistanceKm).toDouble(),
                          min: 1,
                          max: 1000,
                          divisions: 999,
                          label: '${_maxDistanceKm ?? _defaultMaxDistanceKm} km',
                          onChanged: (value) => setState(() => _maxDistanceKm = value.round()),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: BraiseSpacing.xxl),
            Container(
              padding: const EdgeInsets.all(BraiseSpacing.lg),
              decoration: BoxDecoration(
                color: tokens.surface1,
                border: Border.all(color: tokens.borderHairline),
                borderRadius: BorderRadius.circular(BraiseRadii.card),
              ),
              child: Text(
                'Vos vraies photos vivent dans le profil privé. Vous seul décidez quand.',
                style: textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: BraiseSpacing.lg),
            Wrap(
              spacing: BraiseSpacing.md,
              runSpacing: BraiseSpacing.md,
              children: [
                for (final photo in _photos)
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(BraiseRadii.media),
                        child: Image.network(photo.url, width: 96, height: 120, fit: BoxFit.cover),
                      ),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: Semantics(
                          button: true,
                          label: 'Supprimer cette photo',
                          child: GestureDetector(
                            onTap: () => _deletePhoto(photo.key),
                            behavior: HitTestBehavior.opaque,
                            // Rayon agrandi (12 -> 16) : la cible tactile d'origine (24px) était
                            // bien en dessous du minimum recommandé de 44px pour une action de
                            // suppression — trouvé en inspectant l'app réelle, pas en relisant le
                            // code. Reste modeste par rapport au plein 44px pour ne pas empiéter
                            // sur la vignette (96x120), mais une vraie amélioration tactile.
                            child: CircleAvatar(
                              radius: 16,
                              backgroundColor: tokens.erreur,
                              child: const Icon(Icons.close, size: 16, color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                if (_photos.length < 3)
                  Semantics(
                    button: true,
                    label: 'Ajouter une photo',
                    child: InkWell(
                      onTap: _addPhoto,
                      child: Container(
                        width: 96,
                        height: 120,
                        decoration: BoxDecoration(
                          border: Border.all(color: tokens.borderStrong, width: 1.75),
                          borderRadius: BorderRadius.circular(BraiseRadii.media),
                        ),
                        child: Icon(Icons.add_a_photo_outlined, color: tokens.inkSecondary),
                      ),
                    ),
                  ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: BraiseSpacing.lg),
                child: Text(_error!, style: textTheme.bodyMedium?.copyWith(color: tokens.erreur)),
              ),
            const SizedBox(height: BraiseSpacing.xxl),
            ElevatedButton(
              onPressed: _saving ? null : () => _save(publish: true),
              child: AnimatedSwitcher(
                duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 180),
                child: _saving
                    ? SizedBox(
                        key: const ValueKey('saving'),
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: tokens.braiseFillText,
                          semanticsLabel: 'Chargement en cours.',
                        ),
                      )
                    : Text(
                        _isPublished ? 'Mettre à jour mon profil public' : 'Publier mon profil public',
                        key: const ValueKey('label'),
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
    _nameController.dispose();
    _bioController.dispose();
    _interestController.dispose();
    super.dispose();
  }
}
