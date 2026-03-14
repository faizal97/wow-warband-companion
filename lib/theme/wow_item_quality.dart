import 'package:flutter/material.dart';

/// Official WoW item quality (rarity) colors.
class WowItemQuality {
  WowItemQuality._();

  static const Color poor = Color(0xFF9D9D9D);
  static const Color common = Color(0xFFFFFFFF);
  static const Color uncommon = Color(0xFF1EFF00);
  static const Color rare = Color(0xFF0070DD);
  static const Color epic = Color(0xFFA335EE);
  static const Color legendary = Color(0xFFFF8000);
  static const Color artifact = Color(0xFFE6CC80);
  static const Color heirloom = Color(0xFF00CCFF);

  /// Returns the color for a given quality type string from the API.
  static Color forQuality(String qualityType) {
    switch (qualityType.toUpperCase()) {
      case 'POOR':
        return poor;
      case 'COMMON':
        return common;
      case 'UNCOMMON':
        return uncommon;
      case 'RARE':
        return rare;
      case 'EPIC':
        return epic;
      case 'LEGENDARY':
        return legendary;
      case 'ARTIFACT':
        return artifact;
      case 'HEIRLOOM':
        return heirloom;
      default:
        return common;
    }
  }
}
