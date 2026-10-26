import 'package:flutter/material.dart';

/// A selectable AI assistant "character". Rendered as a stylized gradient
/// orb + glyph (see `_AiAvatarOrb` in the assistant screen) rather than a
/// photorealistic image, so the set stays clearly non-realistic/stylized
/// per the design brief and never assumes the user's own gender.
class AiAvatarOption {
  final String id;
  final String name;
  final String tagline;
  final IconData icon;
  final List<Color> gradient;

  const AiAvatarOption({
    required this.id,
    required this.name,
    required this.tagline,
    required this.icon,
    required this.gradient,
  });
}

class AiAvatars {
  static const List<AiAvatarOption> all = [
    AiAvatarOption(
      id: 'aria',
      name: 'Aria',
      tagline: 'Female futuristic AI',
      icon: Icons.auto_awesome_rounded,
      gradient: [Color(0xFFEC4899), Color(0xFF7C3AED)],
    ),
    AiAvatarOption(
      id: 'zayn',
      name: 'Zayn',
      tagline: 'Male futuristic AI',
      icon: Icons.bolt_rounded,
      gradient: [Color(0xFF3B82F6), Color(0xFF2DD4BF)],
    ),
    AiAvatarOption(
      id: 'nova',
      name: 'Nova',
      tagline: 'Neutral futuristic AI',
      icon: Icons.blur_on_rounded,
      gradient: [Color(0xFF8B5CF6), Color(0xFF2DD4BF)],
    ),
    AiAvatarOption(
      id: 'buddy',
      name: 'Buddy',
      tagline: 'Cute friendly robot',
      icon: Icons.smart_toy_rounded,
      gradient: [Color(0xFF22C55E), Color(0xFF2DD4BF)],
    ),
    AiAvatarOption(
      id: 'finn',
      name: 'Finn',
      tagline: 'Professional finance assistant',
      icon: Icons.account_balance_rounded,
      gradient: [Color(0xFF7C3AED), Color(0xFFF59E0B)],
    ),
  ];

  static AiAvatarOption byId(String? id) {
    return all.firstWhere((a) => a.id == id, orElse: () => all[2]);
  }
}
