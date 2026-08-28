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
    );
  }

  final String displayName;
  final int age;
  final String bio;
  final List<String> interests;
  final AvatarSpec avatar;
  final bool isPublished;
  final bool isPremium;
}

class PrivatePhoto {
  const PrivatePhoto({required this.key, required this.url});

  factory PrivatePhoto.fromJson(Map<String, dynamic> json) {
    return PrivatePhoto(key: json['key'] as String, url: json['url'] as String);
  }

  final String key;
  final String url;
}
