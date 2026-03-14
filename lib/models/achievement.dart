/// Achievement data models for the Blizzard WoW Achievement API.

class AchievementCategoryRef {
  final int id;
  final String name;

  const AchievementCategoryRef({required this.id, required this.name});

  factory AchievementCategoryRef.fromJson(Map<String, dynamic> json) {
    return AchievementCategoryRef(
      id: json['id'] as int,
      name: json['name'] as String? ?? 'Unknown',
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}

class AchievementRef {
  final int id;
  final String name;

  const AchievementRef({required this.id, required this.name});

  factory AchievementRef.fromJson(Map<String, dynamic> json) {
    return AchievementRef(
      id: json['id'] as int,
      name: json['name'] as String? ?? 'Unknown',
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}

class AchievementCategory {
  final int id;
  final String name;
  final List<AchievementCategoryRef> subcategories;
  final List<AchievementRef> achievementRefs;

  const AchievementCategory({
    required this.id,
    required this.name,
    this.subcategories = const [],
    this.achievementRefs = const [],
  });

  factory AchievementCategory.fromJson(Map<String, dynamic> json) {
    final subs = (json['subcategories'] as List?)
            ?.map((e) => AchievementCategoryRef.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    final achs = (json['achievements'] as List?)
            ?.map((e) => AchievementRef.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    return AchievementCategory(
      id: json['id'] as int,
      name: json['name'] as String? ?? 'Unknown',
      subcategories: subs,
      achievementRefs: achs,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'subcategories': subcategories.map((s) => s.toJson()).toList(),
        'achievements': achievementRefs.map((a) => a.toJson()).toList(),
      };
}

class AchievementCriteria {
  final int id;
  final String description;
  final int? amount;
  final List<AchievementCriteria> childCriteria;

  const AchievementCriteria({
    required this.id,
    this.description = '',
    this.amount,
    this.childCriteria = const [],
  });

  factory AchievementCriteria.fromJson(Map<String, dynamic> json) {
    final children = (json['child_criteria'] as List?)
            ?.map((e) => AchievementCriteria.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    return AchievementCriteria(
      id: json['id'] as int,
      description: json['description'] as String? ?? '',
      amount: json['amount'] as int?,
      childCriteria: children,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'description': description,
        if (amount != null) 'amount': amount,
        if (childCriteria.isNotEmpty)
          'child_criteria': childCriteria.map((c) => c.toJson()).toList(),
      };
}

class Achievement {
  final int id;
  final String name;
  final String description;
  final int points;
  final bool isAccountWide;
  final AchievementCriteria? criteria;
  final String? iconUrl;
  final String? mediaHref;

  const Achievement({
    required this.id,
    required this.name,
    required this.description,
    required this.points,
    this.isAccountWide = false,
    this.criteria,
    this.iconUrl,
    this.mediaHref,
  });

  Achievement copyWith({String? iconUrl}) => Achievement(
        id: id,
        name: name,
        description: description,
        points: points,
        isAccountWide: isAccountWide,
        criteria: criteria,
        iconUrl: iconUrl ?? this.iconUrl,
        mediaHref: mediaHref,
      );

  factory Achievement.fromJson(Map<String, dynamic> json) {
    final criteriaJson = json['criteria'] as Map<String, dynamic>?;
    return Achievement(
      id: json['id'] as int,
      name: json['name'] as String? ?? 'Unknown',
      description: json['description'] as String? ?? '',
      points: json['points'] as int? ?? 0,
      isAccountWide: json['is_account_wide'] as bool? ?? false,
      criteria: criteriaJson != null ? AchievementCriteria.fromJson(criteriaJson) : null,
      iconUrl: json['icon_url'] as String?,
      mediaHref: json['media']?['key']?['href'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'points': points,
        'is_account_wide': isAccountWide,
        if (criteria != null) 'criteria': criteria!.toJson(),
        if (iconUrl != null) 'icon_url': iconUrl,
        if (mediaHref != null) 'media': {'key': {'href': mediaHref}},
      };
}

class AchievementProgressEntry {
  final int achievementId;
  final bool isCompleted;
  final int? completedTimestamp;
  final Map<int, bool> criteriaProgress;

  const AchievementProgressEntry({
    required this.achievementId,
    required this.isCompleted,
    this.completedTimestamp,
    this.criteriaProgress = const {},
  });
}

class AccountAchievementProgress {
  final int totalQuantity;
  final int totalPoints;
  final Map<int, AchievementProgressEntry> achievements;

  const AccountAchievementProgress({
    required this.totalQuantity,
    required this.totalPoints,
    required this.achievements,
  });

  factory AccountAchievementProgress.fromJson(Map<String, dynamic> json) {
    final totalQuantity = json['total_quantity'] as int? ?? 0;
    final totalPoints = json['total_points'] as int? ?? 0;
    final achievementsList = json['achievements'] as List? ?? [];
    final map = <int, AchievementProgressEntry>{};

    for (final entry in achievementsList) {
      final e = entry as Map<String, dynamic>;
      final achId = e['achievement']?['id'] as int? ?? e['id'] as int;
      final completedTimestamp = e['completed_timestamp'] as int?;
      final isCompleted = completedTimestamp != null && completedTimestamp > 0;

      final criteriaProgress = <int, bool>{};
      _parseCriteriaProgress(e['criteria'] as Map<String, dynamic>?, criteriaProgress);

      map[achId] = AchievementProgressEntry(
        achievementId: achId,
        isCompleted: isCompleted,
        completedTimestamp: isCompleted ? completedTimestamp : null,
        criteriaProgress: criteriaProgress,
      );
    }

    return AccountAchievementProgress(
      totalQuantity: totalQuantity,
      totalPoints: totalPoints,
      achievements: map,
    );
  }

  static void _parseCriteriaProgress(
      Map<String, dynamic>? json, Map<int, bool> result) {
    if (json == null) return;
    final id = json['id'] as int?;
    final isCompleted = json['is_completed'] as bool? ?? false;
    if (id != null) {
      result[id] = isCompleted;
    }
    final children = json['child_criteria'] as List?;
    if (children != null) {
      for (final child in children) {
        _parseCriteriaProgress(child as Map<String, dynamic>, result);
      }
    }
  }
}
