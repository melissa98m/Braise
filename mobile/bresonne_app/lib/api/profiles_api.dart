import '../models/avatar_spec.dart';
import '../models/public_profile.dart';
import 'api_client.dart';

class ProfilesApi {
  ProfilesApi(this._client);
  final ApiClient _client;

  Future<PublicProfile> getMyPublicProfile() async {
    final json = await _client.get('/profiles/me/public');
    return PublicProfile.fromJson(json as Map<String, dynamic>);
  }

  Future<PublicProfile> updateMyPublicProfile({
    required String displayName,
    required DateTime birthDate,
    required String bio,
    required List<String> interests,
    required bool isPublished,
    String? gender,
    List<String>? lookingForGender,
    int? ageMin,
    int? ageMax,
    String? city,
    int? maxDistanceKm,
  }) async {
    final json = await _client.put(
      '/profiles/me/public',
      body: {
        'display_name': displayName,
        'birth_date':
            '${birthDate.year.toString().padLeft(4, '0')}-${birthDate.month.toString().padLeft(2, '0')}-${birthDate.day.toString().padLeft(2, '0')}',
        'bio': bio,
        'interests': interests,
        'is_published': isPublished,
        'gender': gender,
        'looking_for_gender': lookingForGender,
        'age_min': ageMin,
        'age_max': ageMax,
        'city': city,
        'max_distance_km': maxDistanceKm,
      },
    );
    return PublicProfile.fromJson(json as Map<String, dynamic>);
  }

  Future<AvatarSpec> regenerateAvatar() async {
    final json = await _client.post('/profiles/me/avatar/regenerate');
    return AvatarSpec.fromJson(json as Map<String, dynamic>);
  }

  /// Liste fermée de villes (P9.3) — voir services/geo.py côté backend. Peuple le sélecteur de
  /// ville de `ProfileSetupScreen` : seuls ces noms résolvent en coordonnées pour le filtre de
  /// distance, saisir autre chose serait accepté (juste un nom d'affichage) mais ignoré comme
  /// filtre.
  Future<List<String>> getCities() async {
    final json = await _client.get('/profiles/cities');
    return (json as List).cast<String>();
  }

  /// Résout une position GPS (voir `lib/location/`) vers la ville la plus proche de la liste
  /// fermée — pas de géocodage payant, juste un plus-proche-voisin côté serveur sur les
  /// coordonnées déjà embarquées (services/geo.py). Le résultat alimente directement le champ
  /// `city` du formulaire, exactement comme s'il avait été choisi à la main dans la liste.
  Future<String> getNearestCity(double lat, double lon) async {
    final json = await _client.get(
      '/profiles/cities/nearest',
      query: {'lat': lat.toString(), 'lon': lon.toString()},
    );
    return json as String;
  }

  Future<List<PrivatePhoto>> getMyPrivatePhotos() async {
    final json = await _client.get('/profiles/me/private');
    final photos = (json as Map<String, dynamic>)['photos'] as List;
    return photos.map((p) => PrivatePhoto.fromJson(p as Map<String, dynamic>)).toList();
  }

  Future<List<PrivatePhoto>> uploadPrivatePhoto(
    List<int> bytes,
    String filename,
    String contentType,
  ) async {
    final json = await _client.postMultipart(
      '/profiles/me/private/photos',
      fieldName: 'file',
      bytes: bytes,
      filename: filename,
      contentType: contentType,
    );
    final photos = (json as Map<String, dynamic>)['photos'] as List;
    return photos.map((p) => PrivatePhoto.fromJson(p as Map<String, dynamic>)).toList();
  }

  Future<List<PrivatePhoto>> deletePrivatePhoto(String objectKey) async {
    final json = await _client.delete('/profiles/me/private/photos/$objectKey');
    final photos = (json as Map<String, dynamic>)['photos'] as List;
    return photos.map((p) => PrivatePhoto.fromJson(p as Map<String, dynamic>)).toList();
  }

  Future<List<PrivatePhoto>> getPartnerPhotos(String matchId) async {
    final json = await _client.get('/profiles/matches/$matchId/partner-photos');
    final photos = (json as Map<String, dynamic>)['photos'] as List;
    return photos.map((p) => PrivatePhoto.fromJson(p as Map<String, dynamic>)).toList();
  }

  Future<PartnerProfile> getPartnerProfile(String matchId) async {
    final json = await _client.get('/profiles/matches/$matchId/partner-profile');
    return PartnerProfile.fromJson(json as Map<String, dynamic>);
  }
}
