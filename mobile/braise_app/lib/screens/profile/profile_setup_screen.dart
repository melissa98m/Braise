import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../api/api_exception.dart';
import '../../models/public_profile.dart';
import '../../state/app_services.dart';
import '../../theme/braise_tokens.dart';
import '../../widgets/avatar_sigil.dart';
import '../../widgets/braise_page_route.dart';
import '../root_shell.dart';

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

  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  final _interestController = TextEditingController();
  final _interests = <String>[];

  DateTime? _birthDate;
  PublicProfile? _profile;
  List<PrivatePhoto> _photos = [];
  bool _isPublished = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
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
    final services = context.read<AppServices>();
    setState(() => _error = null);
    try {
      final updated = await services.profilesApi.updateMyPublicProfile(
        displayName: _nameController.text.trim(),
        birthDate: _birthDate ?? DateTime(DateTime.now().year - 25),
        bio: _bioController.text.trim(),
        interests: _interests,
        isPublished: publish,
      );
      setState(() {
        _profile = updated;
        _isPublished = updated.isPublished;
      });
      if (!mounted || !publish) return;
      if (widget.isOnboarding) {
        Navigator.of(context).pushReplacement(braiseRoute(context, const RootShell()));
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profil public publié.')),
      );
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final tokens = BraiseTokens.of(context);
    final textTheme = Theme.of(context).textTheme;

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
                if (_profile != null) AvatarSigil(spec: _profile!.avatar, size: 88),
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
              decoration: const InputDecoration(
                labelText: "Indice d'entrée",
                hintText: 'Je connais tous les bruits du métro ligne 2 les yeux fermés.',
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
                  Chip(
                    label: Text(interest),
                    backgroundColor: tokens.braiseTint,
                    side: BorderSide(color: tokens.braiseInk, width: 1.75),
                    onDeleted: () => setState(() => _interests.remove(interest)),
                  ),
              ],
            ),
            const SizedBox(height: BraiseSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _interestController,
                    decoration: const InputDecoration(hintText: 'Ajouter un intérêt'),
                    onSubmitted: (_) => _addInterest(),
                  ),
                ),
                const SizedBox(width: BraiseSpacing.sm),
                IconButton(onPressed: _addInterest, icon: const Icon(Icons.add)),
              ],
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
                        top: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap: () => _deletePhoto(photo.key),
                          child: CircleAvatar(
                            radius: 12,
                            backgroundColor: tokens.erreur,
                            child: const Icon(Icons.close, size: 14, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                if (_photos.length < 3)
                  InkWell(
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
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: BraiseSpacing.lg),
                child: Text(_error!, style: textTheme.bodyMedium?.copyWith(color: tokens.erreur)),
              ),
            const SizedBox(height: BraiseSpacing.xxl),
            ElevatedButton(
              onPressed: () => _save(publish: true),
              child: Text(_isPublished ? 'Mettre à jour mon profil public' : 'Publier mon profil public'),
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
