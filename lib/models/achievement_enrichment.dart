/// Enrichment data from Wago DB2 for a single achievement.
/// Provides criteria type info, quest line details, creature/faction/currency
/// names, and reward info that the Battle.net API lacks.
library;

class QuestEntry {
  final int id;
  final String? name;

  const QuestEntry({required this.id, this.name});

  factory QuestEntry.fromJson(Map<String, dynamic> json) {
    return QuestEntry(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String?,
    );
  }
}

class QuestLineInfo {
  final int id;
  final String name;
  final int questCount;
  final List<QuestEntry> quests;

  const QuestLineInfo({
    required this.id,
    required this.name,
    required this.questCount,
    this.quests = const [],
  });

  factory QuestLineInfo.fromJson(Map<String, dynamic> json) {
    final questsJson = json['quests'] as List? ?? [];
    return QuestLineInfo(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      questCount: json['questCount'] as int? ?? 0,
      quests: questsJson
          .map((q) => QuestEntry.fromJson(q as Map<String, dynamic>))
          .toList(),
    );
  }
}

class EnrichedCriterion {
  /// Criteria type label: quest, kill, achievement, currency, reputation, etc.
  final String type;

  /// Raw criteria type int from Wago Criteria table.
  final int? criteriaType;

  /// Asset ID (quest ID, creature ID, etc.) from Criteria table.
  final int? asset;

  /// Resolved asset name (creature name, faction name, currency name).
  final String? assetName;

  /// Target amount for progress criteria (e.g., "kill 500", "collect 10").
  final int? amount;

  /// Quest line info, populated for quest-type criteria.
  final QuestLineInfo? questLine;

  /// For group/container criteria: sub-criteria map.
  final Map<int, EnrichedCriterion>? children;

  /// Description from CriteriaTree (for group nodes).
  final String? description;

  const EnrichedCriterion({
    required this.type,
    this.criteriaType,
    this.asset,
    this.assetName,
    this.amount,
    this.questLine,
    this.children,
    this.description,
  });

  bool get isQuest =>
      type == 'quest' ||
      type == 'questline' ||
      type == 'daily_quest' ||
      type == 'world_quest';
  bool get isGroup => type == 'group';

  factory EnrichedCriterion.fromJson(Map<String, dynamic> json) {
    final questLineJson = json['questLine'] as Map<String, dynamic>?;
    final childrenJson = json['children'] as Map<String, dynamic>?;

    Map<int, EnrichedCriterion>? children;
    if (childrenJson != null) {
      children = childrenJson.map(
        (k, v) => MapEntry(
            int.parse(k), EnrichedCriterion.fromJson(v as Map<String, dynamic>)),
      );
    }

    return EnrichedCriterion(
      type: json['type'] as String? ?? 'other',
      criteriaType: json['criteriaType'] as int?,
      asset: json['asset'] as int?,
      assetName: json['assetName'] as String?,
      amount: json['amount'] as int?,
      questLine:
          questLineJson != null ? QuestLineInfo.fromJson(questLineJson) : null,
      children: children,
      description: json['description'] as String?,
    );
  }
}

class AchievementEnrichment {
  final int achievementId;
  final int faction;
  final int rewardItemId;
  final int supercedesId;

  /// Map of CriteriaTree ID → enriched data.
  final Map<int, EnrichedCriterion> criteria;

  /// Human-readable reward text (e.g., "Reward: Title - the Insane").
  final String? rewardText;

  /// Instance/dungeon/raid name this achievement belongs to.
  final String? instanceName;

  /// Resolved name for the reward item.
  final String? rewardItemName;

  const AchievementEnrichment({
    required this.achievementId,
    this.faction = -1,
    this.rewardItemId = 0,
    this.supercedesId = 0,
    this.criteria = const {},
    this.rewardText,
    this.instanceName,
    this.rewardItemName,
  });

  factory AchievementEnrichment.fromJson(Map<String, dynamic> json) {
    final criteriaJson = json['criteria'] as Map<String, dynamic>? ?? {};
    final criteria = criteriaJson.map(
      (k, v) => MapEntry(
          int.parse(k), EnrichedCriterion.fromJson(v as Map<String, dynamic>)),
    );

    return AchievementEnrichment(
      achievementId: json['achievementId'] as int? ?? 0,
      faction: json['faction'] as int? ?? -1,
      rewardItemId: json['rewardItemId'] as int? ?? 0,
      supercedesId: json['supercedesId'] as int? ?? 0,
      criteria: criteria,
      rewardText: json['rewardText'] as String?,
      instanceName: json['instanceName'] as String?,
      rewardItemName: json['rewardItemName'] as String?,
    );
  }

  /// Looks up enrichment for a criterion, checking both top-level and group children.
  EnrichedCriterion? findCriterion(int criteriaId) {
    if (criteria.containsKey(criteriaId)) return criteria[criteriaId];
    for (final entry in criteria.values) {
      if (entry.children != null && entry.children!.containsKey(criteriaId)) {
        return entry.children![criteriaId];
      }
    }
    return null;
  }
}
