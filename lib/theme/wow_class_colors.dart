import 'package:flutter/material.dart';

/// Official WoW class colors — these are the exact hex values used by
/// Blizzard and recognized by the entire WoW community.
class WowClassColors {
  WowClassColors._();

  static const Color deathKnight = Color(0xFFC41E3A);
  static const Color demonHunter = Color(0xFFA330C9);
  static const Color druid = Color(0xFFFF7C0A);
  static const Color evoker = Color(0xFF33937F);
  static const Color hunter = Color(0xFFAAD372);
  static const Color mage = Color(0xFF3FC7EB);
  static const Color monk = Color(0xFF00FF98);
  static const Color paladin = Color(0xFFF48CBA);
  static const Color priest = Color(0xFFE0E0E0);
  static const Color rogue = Color(0xFFFFF468);
  static const Color shaman = Color(0xFF0070DD);
  static const Color warlock = Color(0xFF8788EE);
  static const Color warrior = Color(0xFFC69B6D);

  static Color forClass(String className) {
    switch (className.toLowerCase()) {
      case 'death knight':
        return deathKnight;
      case 'demon hunter':
        return demonHunter;
      case 'druid':
        return druid;
      case 'evoker':
        return evoker;
      case 'hunter':
        return hunter;
      case 'mage':
        return mage;
      case 'monk':
        return monk;
      case 'paladin':
        return paladin;
      case 'priest':
        return priest;
      case 'rogue':
        return rogue;
      case 'shaman':
        return shaman;
      case 'warlock':
        return warlock;
      case 'warrior':
        return warrior;
      default:
        return const Color(0xFF8899AA);
    }
  }

  /// Returns a darker shade for backgrounds/gradients.
  static Color forClassDark(String className) {
    return Color.lerp(forClass(className), Colors.black, 0.7)!;
  }

  /// Returns a subtle version for surface tints.
  static Color forClassSurface(String className) {
    return forClass(className).withValues(alpha: 0.08);
  }
}
