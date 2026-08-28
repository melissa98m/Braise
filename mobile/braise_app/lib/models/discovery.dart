import 'avatar_spec.dart';

class DiscoveryCandidate {
  const DiscoveryCandidate({
    required this.userId,
    required this.displayName,
    required this.age,
    required this.bio,
    required this.interests,
    required this.avatar,
    required this.commonInterests,
    required this.compatibilityScore,
  });

  factory DiscoveryCandidate.fromJson(Map<String, dynamic> json) {
    return DiscoveryCandidate(
      userId: json['user_id'] as String,
      displayName: json['display_name'] as String,
      age: json['age'] as int,
      bio: json['bio'] as String,
      interests: (json['interests'] as List).cast<String>(),
      avatar: AvatarSpec.fromJson(json['avatar'] as Map<String, dynamic>),
      commonInterests: (json['common_interests'] as List).cast<String>(),
      compatibilityScore: (json['compatibility_score'] as num).toDouble(),
    );
  }

  final String userId;
  final String displayName;
  final int age;
  final String bio;
  final List<String> interests;
  final AvatarSpec avatar;
  final List<String> commonInterests;
  final double compatibilityScore;
}

class MatchSummary {
  const MatchSummary({
    required this.matchId,
    required this.otherUserId,
    required this.otherDisplayName,
    required this.flameCount,
    required this.unlockThreshold,
    required this.unlockPct,
    required this.blurStage,
    required this.matchedAt,
  });

  factory MatchSummary.fromJson(Map<String, dynamic> json) {
    return MatchSummary(
      matchId: json['match_id'] as String,
      otherUserId: json['other_user_id'] as String,
      otherDisplayName: json['other_display_name'] as String,
      flameCount: json['flame_count'] as int,
      unlockThreshold: json['unlock_threshold'] as int,
      unlockPct: json['unlock_pct'] as int,
      blurStage: json['blur_stage'] as String,
      matchedAt: DateTime.parse(json['matched_at'] as String),
    );
  }

  final String matchId;
  final String otherUserId;
  final String otherDisplayName;
  final int flameCount;
  final int unlockThreshold;
  final int unlockPct;
  final String blurStage; // "silhouette" | "flou_leger" | "net"
  final DateTime matchedAt;

  bool get isUnlocked => blurStage == 'net';
}
