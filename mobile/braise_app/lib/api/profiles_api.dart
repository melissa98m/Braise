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
      },
    );
    return PublicProfile.fromJson(json as Map<String, dynamic>);
  }

  Future<AvatarSpec> regenerateAvatar() async {
    final json = await _client.post('/profiles/me/avatar/regenerate');
    return AvatarSpec.fromJson(json as Map<String, dynamic>);
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
}
