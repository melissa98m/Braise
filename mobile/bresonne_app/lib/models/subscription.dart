class SubscriptionStatus {
  const SubscriptionStatus({
    required this.isPremium,
    required this.expiresAt,
    required this.cancelAtPeriodEnd,
  });

  factory SubscriptionStatus.fromJson(Map<String, dynamic> json) {
    return SubscriptionStatus(
      isPremium: json['is_premium'] as bool,
      expiresAt: json['expires_at'] == null
          ? null
          : DateTime.parse(json['expires_at'] as String),
      cancelAtPeriodEnd: json['cancel_at_period_end'] as bool,
    );
  }

  final bool isPremium;
  final DateTime? expiresAt;
  final bool cancelAtPeriodEnd;
}
