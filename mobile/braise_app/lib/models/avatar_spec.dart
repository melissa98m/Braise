import 'package:flutter/material.dart';

/// Dégradé déterministe (jamais une photo) — miroir de services/avatar.py côté backend.
class AvatarSpec {
  const AvatarSpec({
    required this.seed,
    required this.fromColor,
    required this.toColor,
    required this.angleDeg,
  });

  factory AvatarSpec.fromJson(Map<String, dynamic> json) {
    return AvatarSpec(
      seed: json['seed'] as String,
      fromColor: _colorFromHex(json['from_color'] as String),
      toColor: _colorFromHex(json['to_color'] as String),
      angleDeg: (json['angle_deg'] as num).toDouble(),
    );
  }

  final String seed;
  final Color fromColor;
  final Color toColor;
  final double angleDeg;

  static Color _colorFromHex(String hex) {
    final clean = hex.replaceFirst('#', '');
    return Color(int.parse('FF$clean', radix: 16));
  }
}
