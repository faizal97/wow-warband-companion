/// Represents a WoW character from the Battle.net API.
class WowCharacter {
  final int id;
  final String name;
  final String realm;
  final String realmSlug;
  final int level;
  final String characterClass;
  final String activeSpec;
  final String race;
  final String faction;
  final String? avatarUrl;
  final String? renderUrl;
  final int? equippedItemLevel;
  final String? gender;
  final int? lastLoginTimestamp;
  final int? achievementPoints;

  const WowCharacter({
    required this.id,
    required this.name,
    required this.realm,
    required this.realmSlug,
    required this.level,
    required this.characterClass,
    required this.activeSpec,
    required this.race,
    required this.faction,
    this.avatarUrl,
    this.renderUrl,
    this.equippedItemLevel,
    this.gender,
    this.lastLoginTimestamp,
    this.achievementPoints,
  });

  /// Creates a copy with the given fields replaced.
  WowCharacter copyWith({
    int? id,
    String? name,
    String? realm,
    String? realmSlug,
    int? level,
    String? characterClass,
    String? activeSpec,
    String? race,
    String? faction,
    String? avatarUrl,
    String? renderUrl,
    int? equippedItemLevel,
    String? gender,
    int? lastLoginTimestamp,
    int? achievementPoints,
  }) {
    return WowCharacter(
      id: id ?? this.id,
      name: name ?? this.name,
      realm: realm ?? this.realm,
      realmSlug: realmSlug ?? this.realmSlug,
      level: level ?? this.level,
      characterClass: characterClass ?? this.characterClass,
      activeSpec: activeSpec ?? this.activeSpec,
      race: race ?? this.race,
      faction: faction ?? this.faction,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      renderUrl: renderUrl ?? this.renderUrl,
      equippedItemLevel: equippedItemLevel ?? this.equippedItemLevel,
      gender: gender ?? this.gender,
      lastLoginTimestamp: lastLoginTimestamp ?? this.lastLoginTimestamp,
      achievementPoints: achievementPoints ?? this.achievementPoints,
    );
  }

  factory WowCharacter.fromJson(Map<String, dynamic> json) {
    return WowCharacter(
      id: json['id'] as int,
      name: json['name'] as String,
      realm: json['realm']?['name'] as String? ?? 'Unknown',
      realmSlug: json['realm']?['slug'] as String? ?? '',
      level: json['level'] as int? ?? 0,
      characterClass: json['playable_class']?['name'] as String? ?? 'Unknown',
      activeSpec: json['active_spec']?['name'] as String? ?? 'Unknown',
      race: json['playable_race']?['name'] as String? ?? 'Unknown',
      faction: json['faction']?['name'] as String? ?? 'Unknown',
      avatarUrl: json['avatar_url'] as String?,
      renderUrl: json['render_url'] as String?,
      equippedItemLevel: json['equipped_item_level'] as int?,
      gender: json['gender'] is String
          ? json['gender'] as String
          : json['gender']?['name'] as String?,
      lastLoginTimestamp: json['last_login_timestamp'] as int?,
      achievementPoints: json['achievement_points'] as int?,
    );
  }

  /// Serializes to JSON for caching.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'realm': {'name': realm, 'slug': realmSlug},
      'level': level,
      'playable_class': {'name': characterClass},
      'active_spec': {'name': activeSpec},
      'playable_race': {'name': race},
      'faction': {'name': faction},
      'avatar_url': avatarUrl,
      'render_url': renderUrl,
      'equipped_item_level': equippedItemLevel,
      'gender': gender,
      'last_login_timestamp': lastLoginTimestamp,
      'achievement_points': achievementPoints,
    };
  }

  /// Mock characters for development/preview.
  static List<WowCharacter> mockCharacters() {
    return [
      const WowCharacter(
        id: 1,
        name: 'Thrallzul',
        realm: 'Illidan',
        realmSlug: 'illidan',
        level: 80,
        characterClass: 'Death Knight',
        activeSpec: 'Frost',
        race: 'Orc',
        faction: 'Horde',
        equippedItemLevel: 623,
      ),
      const WowCharacter(
        id: 2,
        name: 'Luminos',
        realm: 'Stormrage',
        realmSlug: 'stormrage',
        level: 80,
        characterClass: 'Paladin',
        activeSpec: 'Holy',
        race: 'Human',
        faction: 'Alliance',
        equippedItemLevel: 618,
      ),
      const WowCharacter(
        id: 3,
        name: 'Sylvarion',
        realm: 'Area 52',
        realmSlug: 'area-52',
        level: 80,
        characterClass: 'Druid',
        activeSpec: 'Restoration',
        race: 'Night Elf',
        faction: 'Alliance',
        equippedItemLevel: 611,
      ),
      const WowCharacter(
        id: 4,
        name: 'Frostweave',
        realm: 'Tichondrius',
        realmSlug: 'tichondrius',
        level: 80,
        characterClass: 'Mage',
        activeSpec: 'Frost',
        race: 'Void Elf',
        faction: 'Alliance',
        equippedItemLevel: 615,
      ),
      const WowCharacter(
        id: 5,
        name: 'Shadowstep',
        realm: 'Illidan',
        realmSlug: 'illidan',
        level: 73,
        characterClass: 'Rogue',
        activeSpec: 'Subtlety',
        race: 'Blood Elf',
        faction: 'Horde',
        equippedItemLevel: 580,
      ),
    ];
  }
}
