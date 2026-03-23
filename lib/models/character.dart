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

  /// Legendary Warcraft heroes for Tower Defense mode.
  static List<WowCharacter> legendaryHeroes() {
    return [
      const WowCharacter(
        id: 9001,
        name: 'Varian Wrynn',
        realm: 'Azeroth',
        realmSlug: 'azeroth',
        level: 90,
        characterClass: 'Warrior',
        activeSpec: 'Arms',
        race: 'Human',
        faction: 'Alliance',
        avatarUrl: 'asset:assets/td/heroes/varian_wrynn.jpg',
        equippedItemLevel: 250,
      ),
      const WowCharacter(
        id: 9002,
        name: 'Illidan Stormrage',
        realm: 'Azeroth',
        realmSlug: 'azeroth',
        level: 90,
        characterClass: 'Demon Hunter',
        activeSpec: 'Havoc',
        race: 'Night Elf',
        faction: 'Alliance',
        avatarUrl: 'asset:assets/td/heroes/illidan_stormrage.jpg',
        equippedItemLevel: 250,
      ),
      const WowCharacter(
        id: 9003,
        name: 'Jaina Proudmoore',
        realm: 'Azeroth',
        realmSlug: 'azeroth',
        level: 90,
        characterClass: 'Mage',
        activeSpec: 'Frost',
        race: 'Human',
        faction: 'Alliance',
        avatarUrl: 'asset:assets/td/heroes/jaina_proudmoore.jpg',
        equippedItemLevel: 250,
      ),
      const WowCharacter(
        id: 9004,
        name: 'Sylvanas Windrunner',
        realm: 'Azeroth',
        realmSlug: 'azeroth',
        level: 90,
        characterClass: 'Hunter',
        activeSpec: 'Marksmanship',
        race: 'Undead',
        faction: 'Horde',
        avatarUrl: 'asset:assets/td/heroes/sylvanas_windrunner.jpg',
        equippedItemLevel: 250,
      ),
      const WowCharacter(
        id: 9005,
        name: 'Anduin Wrynn',
        realm: 'Azeroth',
        realmSlug: 'azeroth',
        level: 90,
        characterClass: 'Priest',
        activeSpec: 'Holy',
        race: 'Human',
        faction: 'Alliance',
        avatarUrl: 'asset:assets/td/heroes/anduin_wrynn.jpg',
        equippedItemLevel: 250,
      ),
      const WowCharacter(
        id: 9006,
        name: 'Malfurion Stormrage',
        realm: 'Azeroth',
        realmSlug: 'azeroth',
        level: 90,
        characterClass: 'Druid',
        activeSpec: 'Restoration',
        race: 'Night Elf',
        faction: 'Alliance',
        avatarUrl: 'asset:assets/td/heroes/malfurion_stormrage.jpg',
        equippedItemLevel: 250,
      ),
      const WowCharacter(
        id: 9007,
        name: 'Thrall',
        realm: 'Azeroth',
        realmSlug: 'azeroth',
        level: 90,
        characterClass: 'Shaman',
        activeSpec: 'Elemental',
        race: 'Orc',
        faction: 'Horde',
        avatarUrl: 'asset:assets/td/heroes/thrall.jpg',
        equippedItemLevel: 250,
      ),
      const WowCharacter(
        id: 9008,
        name: "Kael'thas Sunstrider",
        realm: 'Azeroth',
        realmSlug: 'azeroth',
        level: 90,
        characterClass: 'Mage',
        activeSpec: 'Fire',
        race: 'Blood Elf',
        faction: 'Horde',
        avatarUrl: 'asset:assets/td/heroes/kaelthas_sunstrider.jpg',
        equippedItemLevel: 250,
      ),
    ];
  }
}
