// Raid progression data for a character's latest expansion.

/// A single raid encounter (boss) with per-difficulty kill counts.
class RaidEncounter {
  final String name;
  final int id;
  final Map<String, int> killCounts; // 'NORMAL' -> 12, 'HEROIC' -> 5
  final String? iconUrl;

  const RaidEncounter({
    required this.name,
    required this.id,
    required this.killCounts,
    this.iconUrl,
  });

  bool isKilledOn(String difficulty) => (killCounts[difficulty] ?? 0) > 0;
  int killsOn(String difficulty) => killCounts[difficulty] ?? 0;

  RaidEncounter copyWith({String? iconUrl}) => RaidEncounter(
        name: name,
        id: id,
        killCounts: killCounts,
        iconUrl: iconUrl ?? this.iconUrl,
      );

  factory RaidEncounter.fromJson(Map<String, dynamic> json) {
    final kills = <String, int>{};
    final killsJson = json['kill_counts'] as Map<String, dynamic>? ?? {};
    for (final entry in killsJson.entries) {
      kills[entry.key] = entry.value as int;
    }
    return RaidEncounter(
      name: json['name'] as String? ?? 'Unknown',
      id: json['id'] as int? ?? 0,
      killCounts: kills,
      iconUrl: json['icon_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'id': id,
        'kill_counts': killCounts,
        if (iconUrl != null) 'icon_url': iconUrl,
      };
}

/// Progress summary for a specific difficulty within a raid.
class RaidDifficultyProgress {
  final String type; // NORMAL, HEROIC, MYTHIC, LFR
  final String name; // Normal, Heroic, Mythic, Looking for Raid
  final int completedCount;
  final int totalCount;

  const RaidDifficultyProgress({
    required this.type,
    required this.name,
    required this.completedCount,
    required this.totalCount,
  });

  bool get isComplete => completedCount >= totalCount;
  double get progress => totalCount > 0 ? completedCount / totalCount : 0;

  factory RaidDifficultyProgress.fromJson(Map<String, dynamic> json) {
    return RaidDifficultyProgress(
      type: json['type'] as String? ?? '',
      name: json['name'] as String? ?? '',
      completedCount: json['completed_count'] as int? ?? 0,
      totalCount: json['total_count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        'name': name,
        'completed_count': completedCount,
        'total_count': totalCount,
      };
}

/// A single raid instance with encounters and difficulty progress.
class RaidInstance {
  final String name;
  final int id;
  final List<RaidEncounter> encounters;
  final List<RaidDifficultyProgress> difficulties;
  final String? iconUrl;

  const RaidInstance({
    required this.name,
    required this.id,
    required this.encounters,
    required this.difficulties,
    this.iconUrl,
  });

  int get totalBosses =>
      difficulties.isNotEmpty ? difficulties.first.totalCount : encounters.length;

  RaidInstance copyWith({String? iconUrl, List<RaidEncounter>? encounters}) =>
      RaidInstance(
        name: name,
        id: id,
        encounters: encounters ?? this.encounters,
        difficulties: difficulties,
        iconUrl: iconUrl ?? this.iconUrl,
      );

  factory RaidInstance.fromJson(Map<String, dynamic> json) {
    return RaidInstance(
      name: json['name'] as String? ?? 'Unknown',
      id: json['id'] as int? ?? 0,
      encounters: (json['encounters'] as List? ?? [])
          .map((e) => RaidEncounter.fromJson(e as Map<String, dynamic>))
          .toList(),
      difficulties: (json['difficulties'] as List? ?? [])
          .map((d) =>
              RaidDifficultyProgress.fromJson(d as Map<String, dynamic>))
          .toList(),
      iconUrl: json['icon_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'id': id,
        'encounters': encounters.map((e) => e.toJson()).toList(),
        'difficulties': difficulties.map((d) => d.toJson()).toList(),
        if (iconUrl != null) 'icon_url': iconUrl,
      };
}

/// Raid progression for the latest expansion.
class RaidProgression {
  final String expansionName;
  final int expansionId;
  final List<RaidInstance> instances;

  const RaidProgression({
    required this.expansionName,
    required this.expansionId,
    required this.instances,
  });

  RaidProgression copyWith({List<RaidInstance>? instances}) => RaidProgression(
        expansionName: expansionName,
        expansionId: expansionId,
        instances: instances ?? this.instances,
      );

  /// Canonical difficulty ordering.
  static const difficultyOrder = ['LFR', 'NORMAL', 'HEROIC', 'MYTHIC'];

  /// Parses the Blizzard API encounters/raids response.
  ///
  /// Finds the latest expansion by highest ID, then flattens the nested
  /// expansion → instance → mode → encounter structure into our model.
  factory RaidProgression.fromApiJson(Map<String, dynamic> json) {
    final expansions = json['expansions'] as List? ?? [];
    if (expansions.isEmpty) {
      return const RaidProgression(
          expansionName: '', expansionId: 0, instances: []);
    }

    // Find latest expansion by highest ID
    Map<String, dynamic>? latestExpansion;
    int maxExpId = 0;
    for (final exp in expansions) {
      final expData = exp['expansion'] as Map<String, dynamic>? ?? {};
      final id = expData['id'] as int? ?? 0;
      if (id > maxExpId) {
        maxExpId = id;
        latestExpansion = exp as Map<String, dynamic>;
      }
    }

    if (latestExpansion == null) {
      return const RaidProgression(
          expansionName: '', expansionId: 0, instances: []);
    }

    final expName =
        latestExpansion['expansion']?['name'] as String? ?? 'Unknown';
    final instances = <RaidInstance>[];
    final apiInstances = latestExpansion['instances'] as List? ?? [];

    for (final inst in apiInstances) {
      final instData = inst['instance'] as Map<String, dynamic>? ?? {};
      final instName = instData['name'] as String? ?? 'Unknown';
      final instId = instData['id'] as int? ?? 0;
      final modes = inst['modes'] as List? ?? [];

      // Merge encounters across difficulties
      final encounterMap = <int, Map<String, dynamic>>{};
      final encounterOrder = <int>[];
      final difficultyList = <RaidDifficultyProgress>[];

      for (final mode in modes) {
        final diffData = mode['difficulty'] as Map<String, dynamic>? ?? {};
        final diffType = diffData['type'] as String? ?? '';
        final diffName = diffData['name'] as String? ?? '';
        final progress = mode['progress'] as Map<String, dynamic>? ?? {};
        final completedCount = progress['completed_count'] as int? ?? 0;
        final totalCount = progress['total_count'] as int? ?? 0;

        difficultyList.add(RaidDifficultyProgress(
          type: diffType,
          name: diffName,
          completedCount: completedCount,
          totalCount: totalCount,
        ));

        final encounters = progress['encounters'] as List? ?? [];
        for (final enc in encounters) {
          final encData = enc['encounter'] as Map<String, dynamic>? ?? {};
          final encId = encData['id'] as int? ?? 0;
          final encName = encData['name'] as String? ?? 'Unknown';
          final killCount = enc['completed_count'] as int? ?? 0;

          if (!encounterMap.containsKey(encId)) {
            encounterMap[encId] = {
              'name': encName,
              'id': encId,
              'kill_counts': <String, int>{},
            };
            encounterOrder.add(encId);
          }
          (encounterMap[encId]!['kill_counts'] as Map<String, int>)[diffType] =
              killCount;
        }
      }

      // Sort difficulties by canonical order
      difficultyList.sort((a, b) {
        final ai = difficultyOrder.indexOf(a.type);
        final bi = difficultyOrder.indexOf(b.type);
        return (ai == -1 ? 99 : ai).compareTo(bi == -1 ? 99 : bi);
      });

      // Build encounters preserving API order
      final encounters = encounterOrder.map((id) {
        final data = encounterMap[id]!;
        return RaidEncounter(
          name: data['name'] as String,
          id: data['id'] as int,
          killCounts: Map<String, int>.from(data['kill_counts'] as Map),
        );
      }).toList();

      instances.add(RaidInstance(
        name: instName,
        id: instId,
        encounters: encounters,
        difficulties: difficultyList,
      ));
    }

    return RaidProgression(
      expansionName: expName,
      expansionId: maxExpId,
      instances: instances,
    );
  }

  /// Parses from cached JSON format.
  factory RaidProgression.fromJson(Map<String, dynamic> json) {
    return RaidProgression(
      expansionName: json['expansion_name'] as String? ?? '',
      expansionId: json['expansion_id'] as int? ?? 0,
      instances: (json['instances'] as List? ?? [])
          .map((i) => RaidInstance.fromJson(i as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'expansion_name': expansionName,
        'expansion_id': expansionId,
        'instances': instances.map((i) => i.toJson()).toList(),
      };

  /// Mock data for development/preview.
  static RaidProgression mock() {
    return const RaidProgression(
      expansionName: 'The War Within',
      expansionId: 505,
      instances: [
        RaidInstance(
          name: 'Liberation of Undermine',
          id: 1296,
          encounters: [
            RaidEncounter(name: 'Vexie and the Geargrinders', id: 2902, killCounts: {'NORMAL': 8, 'HEROIC': 6, 'MYTHIC': 2}),
            RaidEncounter(name: 'Cauldron of Carnage', id: 2903, killCounts: {'NORMAL': 7, 'HEROIC': 5, 'MYTHIC': 1}),
            RaidEncounter(name: 'Rik Reverb', id: 2904, killCounts: {'NORMAL': 6, 'HEROIC': 4}),
            RaidEncounter(name: 'Stix Bunkjunker', id: 2905, killCounts: {'NORMAL': 5, 'HEROIC': 3}),
            RaidEncounter(name: 'Sprocketmonger Lockenstock', id: 2906, killCounts: {'NORMAL': 5, 'HEROIC': 2, 'MYTHIC': 1}),
            RaidEncounter(name: 'The One-Armed Bandit', id: 2907, killCounts: {'NORMAL': 4, 'HEROIC': 1}),
            RaidEncounter(name: "Mug'Zee, Heads of Security", id: 2908, killCounts: {'NORMAL': 3}),
            RaidEncounter(name: 'Chrome King Gallywix', id: 2909, killCounts: {'NORMAL': 2}),
          ],
          difficulties: [
            RaidDifficultyProgress(type: 'NORMAL', name: 'Normal', completedCount: 8, totalCount: 8),
            RaidDifficultyProgress(type: 'HEROIC', name: 'Heroic', completedCount: 6, totalCount: 8),
            RaidDifficultyProgress(type: 'MYTHIC', name: 'Mythic', completedCount: 2, totalCount: 8),
          ],
        ),
        RaidInstance(
          name: 'Nerub-ar Palace',
          id: 1273,
          encounters: [
            RaidEncounter(name: 'Ulgrax the Devourer', id: 2820, killCounts: {'NORMAL': 15, 'HEROIC': 12, 'MYTHIC': 5}),
            RaidEncounter(name: 'The Bloodbound Horror', id: 2821, killCounts: {'NORMAL': 14, 'HEROIC': 11, 'MYTHIC': 4}),
            RaidEncounter(name: 'Sikran, Captain of the Sureki', id: 2822, killCounts: {'NORMAL': 13, 'HEROIC': 10, 'MYTHIC': 3}),
            RaidEncounter(name: "Rasha'nan", id: 2823, killCounts: {'NORMAL': 12, 'HEROIC': 9, 'MYTHIC': 2}),
            RaidEncounter(name: "Broodtwister Ovi'nax", id: 2824, killCounts: {'NORMAL': 11, 'HEROIC': 8, 'MYTHIC': 1}),
            RaidEncounter(name: "Nexus-Princess Ky'veza", id: 2825, killCounts: {'NORMAL': 10, 'HEROIC': 7, 'MYTHIC': 1}),
            RaidEncounter(name: 'The Silken Court', id: 2826, killCounts: {'NORMAL': 9, 'HEROIC': 6}),
            RaidEncounter(name: 'Queen Ansurek', id: 2827, killCounts: {'NORMAL': 8, 'HEROIC': 4}),
          ],
          difficulties: [
            RaidDifficultyProgress(type: 'NORMAL', name: 'Normal', completedCount: 8, totalCount: 8),
            RaidDifficultyProgress(type: 'HEROIC', name: 'Heroic', completedCount: 8, totalCount: 8),
            RaidDifficultyProgress(type: 'MYTHIC', name: 'Mythic', completedCount: 6, totalCount: 8),
          ],
        ),
      ],
    );
  }
}
