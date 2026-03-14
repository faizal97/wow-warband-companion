import 'package:flutter/material.dart';

/// A single Mythic+ best run for a season.
class MythicPlusBestRun {
  final String dungeonName;
  final int dungeonId;
  final int keystoneLevel;
  final int completedTimestamp;
  final int durationMs;
  final int keystoneUpgrades;
  final bool isTimedCompletion;
  final List<String> affixes;
  final double rating;
  final String? iconUrl;

  const MythicPlusBestRun({
    required this.dungeonName,
    this.dungeonId = 0,
    required this.keystoneLevel,
    required this.completedTimestamp,
    required this.durationMs,
    required this.keystoneUpgrades,
    required this.isTimedCompletion,
    required this.affixes,
    required this.rating,
    this.iconUrl,
  });

  MythicPlusBestRun copyWith({String? iconUrl}) {
    return MythicPlusBestRun(
      dungeonName: dungeonName,
      dungeonId: dungeonId,
      keystoneLevel: keystoneLevel,
      completedTimestamp: completedTimestamp,
      durationMs: durationMs,
      keystoneUpgrades: keystoneUpgrades,
      isTimedCompletion: isTimedCompletion,
      affixes: affixes,
      rating: rating,
      iconUrl: iconUrl ?? this.iconUrl,
    );
  }

  factory MythicPlusBestRun.fromJson(Map<String, dynamic> json) {
    final affixList = <String>[];
    final affixes = json['keystone_affixes'] as List? ?? [];
    for (final a in affixes) {
      final name = a['name'] as String?;
      if (name != null) affixList.add(name);
    }

    return MythicPlusBestRun(
      dungeonName: json['dungeon']?['name'] as String? ?? 'Unknown',
      dungeonId: json['dungeon']?['id'] as int? ?? 0,
      keystoneLevel: json['keystone_level'] as int? ?? 0,
      completedTimestamp: json['completed_timestamp'] as int? ?? 0,
      durationMs: json['duration'] as int? ?? 0,
      keystoneUpgrades: json['keystone_upgrades'] as int? ?? 0,
      isTimedCompletion: json['is_completed_within_time'] as bool? ?? false,
      affixes: affixList,
      rating: (json['mythic_rating']?['rating'] as num?)?.toDouble() ?? 0.0,
      iconUrl: json['icon_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'dungeon': {'name': dungeonName, 'id': dungeonId},
      'keystone_level': keystoneLevel,
      'completed_timestamp': completedTimestamp,
      'duration': durationMs,
      'keystone_upgrades': keystoneUpgrades,
      'is_completed_within_time': isTimedCompletion,
      'keystone_affixes': affixes.map((a) => {'name': a}).toList(),
      'mythic_rating': {'rating': rating},
      if (iconUrl != null) 'icon_url': iconUrl,
    };
  }
}

/// Mythic+ profile for a character, including rating and best runs.
class MythicPlusProfile {
  final double currentRating;
  final double ratingColorR;
  final double ratingColorG;
  final double ratingColorB;
  final int? latestSeasonId;
  final List<MythicPlusBestRun> bestRuns;

  const MythicPlusProfile({
    required this.currentRating,
    required this.ratingColorR,
    required this.ratingColorG,
    required this.ratingColorB,
    this.latestSeasonId,
    this.bestRuns = const [],
  });

  /// Creates a copy with the given fields replaced.
  MythicPlusProfile copyWith({
    double? currentRating,
    double? ratingColorR,
    double? ratingColorG,
    double? ratingColorB,
    int? latestSeasonId,
    List<MythicPlusBestRun>? bestRuns,
  }) {
    return MythicPlusProfile(
      currentRating: currentRating ?? this.currentRating,
      ratingColorR: ratingColorR ?? this.ratingColorR,
      ratingColorG: ratingColorG ?? this.ratingColorG,
      ratingColorB: ratingColorB ?? this.ratingColorB,
      latestSeasonId: latestSeasonId ?? this.latestSeasonId,
      bestRuns: bestRuns ?? this.bestRuns,
    );
  }

  /// Returns a Flutter [Color] from the API's RGB values.
  Color get ratingColor => Color.fromARGB(
        255,
        ratingColorR.round().clamp(0, 255),
        ratingColorG.round().clamp(0, 255),
        ratingColorB.round().clamp(0, 255),
      );

  factory MythicPlusProfile.fromJson(Map<String, dynamic> json) {
    final ratingData =
        json['current_mythic_rating'] as Map<String, dynamic>? ?? {};
    final colorData = ratingData['color'] as Map<String, dynamic>? ?? {};

    // Parse seasons to find the highest ID (most recent)
    int? latestSeasonId;
    final seasons = json['seasons'] as List?;
    if (seasons != null && seasons.isNotEmpty) {
      int maxId = 0;
      for (final s in seasons) {
        final id = s['id'] as int? ?? 0;
        if (id > maxId) maxId = id;
      }
      latestSeasonId = maxId > 0 ? maxId : null;
    }

    // Parse best runs (present when fetching season data)
    final bestRunsList = <MythicPlusBestRun>[];
    final bestRuns = json['best_runs'] as List?;
    if (bestRuns != null) {
      for (final run in bestRuns) {
        bestRunsList
            .add(MythicPlusBestRun.fromJson(run as Map<String, dynamic>));
      }
    }

    return MythicPlusProfile(
      currentRating:
          (ratingData['rating'] as num?)?.toDouble() ?? 0.0,
      ratingColorR: (colorData['r'] as num?)?.toDouble() ?? 255.0,
      ratingColorG: (colorData['g'] as num?)?.toDouble() ?? 255.0,
      ratingColorB: (colorData['b'] as num?)?.toDouble() ?? 255.0,
      latestSeasonId: latestSeasonId,
      bestRuns: bestRunsList,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'current_mythic_rating': {
        'rating': currentRating,
        'color': {
          'r': ratingColorR,
          'g': ratingColorG,
          'b': ratingColorB,
        },
      },
      if (latestSeasonId != null)
        'seasons': [
          {'id': latestSeasonId}
        ],
      'best_runs': bestRuns.map((run) => run.toJson()).toList(),
    };
  }

  /// Mock data for development/preview.
  static MythicPlusProfile mock() {
    return const MythicPlusProfile(
      currentRating: 2547.3,
      ratingColorR: 255,
      ratingColorG: 128,
      ratingColorB: 0,
      latestSeasonId: 13,
      bestRuns: [
        MythicPlusBestRun(
          dungeonName: 'Stonevault',
          keystoneLevel: 15,
          completedTimestamp: 1710000000000,
          durationMs: 1680000,
          keystoneUpgrades: 2,
          isTimedCompletion: true,
          affixes: ['Tyrannical', 'Bolstering'],
          rating: 285.5,
        ),
        MythicPlusBestRun(
          dungeonName: 'City of Threads',
          keystoneLevel: 14,
          completedTimestamp: 1709900000000,
          durationMs: 1920000,
          keystoneUpgrades: 1,
          isTimedCompletion: true,
          affixes: ['Fortified', 'Raging'],
          rating: 265.2,
        ),
        MythicPlusBestRun(
          dungeonName: 'The Dawnbreaker',
          keystoneLevel: 13,
          completedTimestamp: 1709800000000,
          durationMs: 2100000,
          keystoneUpgrades: 0,
          isTimedCompletion: false,
          affixes: ['Tyrannical'],
          rating: 220.0,
        ),
        MythicPlusBestRun(
          dungeonName: 'Ara-Kara, City of Echoes',
          keystoneLevel: 14,
          completedTimestamp: 1709700000000,
          durationMs: 1750000,
          keystoneUpgrades: 3,
          isTimedCompletion: true,
          affixes: ['Fortified', 'Sanguine'],
          rating: 275.8,
        ),
      ],
    );
  }
}
