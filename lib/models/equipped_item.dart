/// Canonical WoW character sheet slot ordering.
const List<String> slotOrder = [
  'HEAD',
  'NECK',
  'SHOULDER',
  'BACK',
  'CHEST',
  'WRIST',
  'HANDS',
  'WAIST',
  'LEGS',
  'FEET',
  'FINGER_1',
  'FINGER_2',
  'TRINKET_1',
  'TRINKET_2',
  'MAIN_HAND',
  'OFF_HAND',
];

/// A single equipped item on a WoW character.
class EquippedItem {
  final String slot;
  final String slotDisplayName;
  final int itemId;
  final String itemName;
  final int itemLevel;
  final String quality;
  final List<String> enchantments;
  final List<String> sockets;
  final String? setName;
  final String? iconUrl;
  final String? mediaHref;

  const EquippedItem({
    required this.slot,
    required this.slotDisplayName,
    required this.itemId,
    required this.itemName,
    required this.itemLevel,
    required this.quality,
    this.enchantments = const [],
    this.sockets = const [],
    this.setName,
    this.iconUrl,
    this.mediaHref,
  });

  EquippedItem copyWith({String? iconUrl}) {
    return EquippedItem(
      slot: slot,
      slotDisplayName: slotDisplayName,
      itemId: itemId,
      itemName: itemName,
      itemLevel: itemLevel,
      quality: quality,
      enchantments: enchantments,
      sockets: sockets,
      setName: setName,
      iconUrl: iconUrl ?? this.iconUrl,
      mediaHref: mediaHref,
    );
  }

  factory EquippedItem.fromJson(Map<String, dynamic> json) {
    final enchantmentsList = <String>[];
    final enchantments = json['enchantments'] as List?;
    if (enchantments != null) {
      for (final e in enchantments) {
        final display = e['display_string'] as String?;
        if (display != null) enchantmentsList.add(display);
      }
    }

    final socketsList = <String>[];
    final sockets = json['sockets'] as List?;
    if (sockets != null) {
      for (final s in sockets) {
        final name = s['item']?['name'] as String?;
        if (name != null) socketsList.add(name);
      }
    }

    return EquippedItem(
      slot: json['slot']?['type'] as String? ?? 'UNKNOWN',
      slotDisplayName: json['slot']?['name'] as String? ?? 'Unknown',
      itemId: json['item']?['id'] as int? ?? 0,
      itemName: json['name'] as String? ?? 'Unknown Item',
      itemLevel: json['level']?['value'] as int? ?? 0,
      quality: json['quality']?['type'] as String? ?? 'COMMON',
      enchantments: enchantmentsList,
      sockets: socketsList,
      setName: json['set']?['item_set']?['name'] as String?,
      iconUrl: json['icon_url'] as String?,
      mediaHref: json['media']?['key']?['href'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'slot': {'type': slot, 'name': slotDisplayName},
      'item': {'id': itemId},
      'name': itemName,
      'level': {'value': itemLevel},
      'quality': {'type': quality},
      'enchantments':
          enchantments.map((e) => {'display_string': e}).toList(),
      'sockets': sockets.map((s) => {'item': {'name': s}}).toList(),
      if (setName != null) 'set': {'item_set': {'name': setName}},
      if (iconUrl != null) 'icon_url': iconUrl,
      if (mediaHref != null) 'media': {'key': {'href': mediaHref}},
    };
  }
}

/// All equipped items on a character.
class CharacterEquipment {
  final List<EquippedItem> equippedItems;

  const CharacterEquipment({required this.equippedItems});

  factory CharacterEquipment.fromJson(Map<String, dynamic> json) {
    final items = json['equipped_items'] as List? ?? [];
    return CharacterEquipment(
      equippedItems: items
          .map((item) =>
              EquippedItem.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'equipped_items': equippedItems.map((item) => item.toJson()).toList(),
    };
  }

  /// Mock data for development/preview.
  static CharacterEquipment mock() {
    return const CharacterEquipment(
      equippedItems: [
        EquippedItem(
          slot: 'HEAD',
          slotDisplayName: 'Head',
          itemId: 212056,
          itemName: 'Helm of Writhing Darkness',
          itemLevel: 623,
          quality: 'EPIC',
          sockets: ['Quick Ruby'],
        ),
        EquippedItem(
          slot: 'SHOULDER',
          slotDisplayName: 'Shoulder',
          itemId: 212058,
          itemName: 'Mantle of the Void',
          itemLevel: 619,
          quality: 'EPIC',
        ),
        EquippedItem(
          slot: 'CHEST',
          slotDisplayName: 'Chest',
          itemId: 212060,
          itemName: 'Robes of Smoldering Devastation',
          itemLevel: 626,
          quality: 'EPIC',
          enchantments: ['Enchanted: +Haste'],
          setName: 'Regalia of the Cinderwolf',
        ),
        EquippedItem(
          slot: 'MAIN_HAND',
          slotDisplayName: 'Main Hand',
          itemId: 212400,
          itemName: 'Edict of the Eternals',
          itemLevel: 626,
          quality: 'LEGENDARY',
          enchantments: ['Enchanted: Authority of Fiery Resolve'],
        ),
        EquippedItem(
          slot: 'TRINKET_1',
          slotDisplayName: 'Trinket 1',
          itemId: 212456,
          itemName: 'Spymaster\'s Web',
          itemLevel: 623,
          quality: 'EPIC',
        ),
        EquippedItem(
          slot: 'LEGS',
          slotDisplayName: 'Legs',
          itemId: 212062,
          itemName: 'Leggings of the Void',
          itemLevel: 619,
          quality: 'RARE',
          sockets: ['Masterful Emerald'],
        ),
      ],
    );
  }
}
