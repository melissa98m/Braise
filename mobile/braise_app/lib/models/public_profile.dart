import 'avatar_spec.dart';

class PublicProfile {
  const PublicProfile({
    required this.displayName,
    required this.age,
    required this.bio,
    required this.interests,
    required this.avatar,
    required this.isPublished,
    required this.isPremium,
    required this.isVerified,
    required this.gender,
    required this.lookingForGender,
    required this.ageMin,
    required this.ageMax,
  });

  factory PublicProfile.fromJson(Map<String, dynamic> json) {
    return PublicProfile(
      displayName: json['display_name'] as String,
      age: json['age'] as int,
      bio: json['bio'] as String,
      interests: (json['interests'] as List).cast<String>(),
      avatar: AvatarSpec.fromJson(json['avatar'] as Map<String, dynamic>),
      isPublished: json['is_published'] as bool,
      isPremium: json['is_premium'] as bool,
      isVerified: json['is_verified'] as bool,
      gender: json['gender'] as String?,
      lookingForGender: json['looking_for_gender'] as String?,
      ageMin: json['age_min'] as int?,
      ageMax: json['age_max'] as int?,
    );
  }

  final String displayName;
  final int age;
  final String bio;
  final List<String> interests;
  final AvatarSpec avatar;
  final bool isPublished;
  final bool isPremium;
  final bool isVerified;
  final String? gender;
  final String? lookingForGender;
  final int? ageMin;
  final int? ageMax;
}

/// "homme" / "femme" / "non_binaire" — doit rester en phase avec Gender côté backend
/// (schemas/profile.py). Pas de "tous" ici : null porte déjà ce sens (voir looking_for_gender).
const genderOptions = <String, String>{
  'homme': 'Homme',
  'femme': 'Femme',
  'non_binaire': 'Non binaire',
};

class PrivatePhoto {
  const PrivatePhoto({required this.key, required this.url});

  factory PrivatePhoto.fromJson(Map<String, dynamic> json) {
    return PrivatePhoto(key: json['key'] as String, url: json['url'] as String);
  }

  final String key;
  final String url;
}
