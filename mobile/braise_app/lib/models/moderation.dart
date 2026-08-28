class TrustScore {
  const TrustScore({
    required this.score,
    required this.label,
    required this.ratingCount,
    required this.flaggedCount,
  });

  factory TrustScore.fromJson(Map<String, dynamic> json) {
    return TrustScore(
      score: json['score'] as int?,
      label: json['label'] as String?,
      ratingCount: json['rating_count'] as int,
      flaggedCount: json['flagged_count'] as int,
    );
  }

  final int? score;
  final String? label;
  final int ratingCount;
  final int flaggedCount;
}

class RatingResult {
  const RatingResult({required this.suspectedRancor, required this.trustScore});

  factory RatingResult.fromJson(Map<String, dynamic> json) {
    return RatingResult(
      suspectedRancor: json['suspected_rancor'] as bool,
      trustScore: json['trust_score'] as int?,
    );
  }

  final bool suspectedRancor;
  final int? trustScore;
}

const reportReasons = <String, String>{
  'harcelement': 'Harcèlement',
  'faux_profil': 'Faux profil',
  'contenu_inapproprie': 'Contenu inapproprié',
  'comportement_suspect': 'Comportement suspect',
  'autre': 'Autre',
};
