import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/character.dart';
import '../../theme/app_theme.dart';
import '../../theme/wow_class_colors.dart';
import '../data/effect_types.dart';
import '../data/td_class_registry.dart';
import 'td_class_guide_screen.dart';
import 'td_dungeon_briefing_screen.dart';

// ---------------------------------------------------------------------------
// TdCompSelectionScreen — pick your towers after seeing the dungeon
// ---------------------------------------------------------------------------

class TdCompSelectionScreen extends StatefulWidget {
  final List<WowCharacter> allCharacters;
  final TdDungeonDef dungeon;
  final int keystoneLevel;
  final int maxTowers;
  final TdClassRegistry classRegistry;

  const TdCompSelectionScreen({
    super.key,
    required this.allCharacters,
    required this.dungeon,
    required this.keystoneLevel,
    required this.maxTowers,
    required this.classRegistry,
  });

  @override
  State<TdCompSelectionScreen> createState() => _TdCompSelectionScreenState();
}

class _TdCompSelectionScreenState extends State<TdCompSelectionScreen> {
  final Set<int> _selectedIds = {};
  String? _archetypeFilter; // null = all, 'melee', 'ranged', 'support', 'aoe'

  bool get _canDeploy => _selectedIds.length >= 3;
  bool get _atMax => _selectedIds.length >= widget.maxTowers;

  List<WowCharacter> get _filteredCharacters {
    if (_archetypeFilter == null) return widget.allCharacters;
    return widget.allCharacters.where((c) {
      final def = widget.classRegistry.getClass(c.characterClass);
      return def.archetype.name == _archetypeFilter;
    }).toList();
  }

  void _toggle(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else if (!_atMax) {
        _selectedIds.add(id);
      }
    });
  }

  void _deploy() {
    final selected = widget.allCharacters
        .where((c) => _selectedIds.contains(c.id))
        .toList();
    Navigator.of(context).pop(selected);
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final dungeon = widget.dungeon;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Column(
        children: [
          // ── Header: dungeon info ──────────────────────────────────────
          Container(
            padding: EdgeInsets.fromLTRB(20, topPad + 12, 20, 14),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              border: Border(
                bottom: BorderSide(
                  color: dungeon.bossColor.withValues(alpha: 0.15),
                ),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: const Icon(Icons.arrow_back_rounded,
                          color: AppTheme.textSecondary, size: 22),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'SELECT TOWERS',
                      style: GoogleFonts.rajdhani(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                        letterSpacing: 3,
                      ),
                    ),
                    const Spacer(),
                    // Class guide button
                    GestureDetector(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const TdClassGuideScreen()),
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceElevated,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppTheme.surfaceBorder),
                        ),
                        child: const Icon(Icons.menu_book_rounded,
                            size: 16, color: AppTheme.textTertiary),
                      ),
                    ),
                    // Keystone level badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFA335EE).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color:
                              const Color(0xFFA335EE).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        '+${widget.keystoneLevel}',
                        style: GoogleFonts.rajdhani(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFA335EE),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Dungeon bar
                GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          TdDungeonBriefingScreen(dungeon: dungeon),
                    ),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: dungeon.bossColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: dungeon.bossColor.withValues(alpha: 0.15),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(TdIcons.getIcon(dungeon.bossIcon),
                            color: dungeon.bossColor, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                dungeon.name.toUpperCase(),
                                style: GoogleFonts.rajdhani(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: dungeon.bossColor,
                                  letterSpacing: 1,
                                ),
                              ),
                              Text(
                                dungeon.theme,
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  color: AppTheme.textTertiary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.info_outline_rounded,
                            color: dungeon.bossColor.withValues(alpha: 0.5),
                            size: 16),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Selection counter ─────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 14,
                  decoration: BoxDecoration(
                    color: _canDeploy
                        ? const Color(0xFF4CAF50)
                        : AppTheme.textTertiary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${_selectedIds.length}/${widget.maxTowers} TOWERS SELECTED',
                  style: GoogleFonts.rajdhani(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _canDeploy
                        ? const Color(0xFF4CAF50)
                        : AppTheme.textTertiary,
                    letterSpacing: 2,
                  ),
                ),
                if (widget.maxTowers == 6) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD4A017).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '6TH SLOT',
                      style: GoogleFonts.rajdhani(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFFD4A017),
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // ── Archetype filter tabs ────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip(null, 'ALL'),
                  _buildFilterChip('melee', 'MELEE'),
                  _buildFilterChip('ranged', 'RANGED'),
                  _buildFilterChip('support', 'SUPPORT'),
                  _buildFilterChip('aoe', 'AOE'),
                ],
              ),
            ),
          ),

          // ── Character list/grid (responsive) ──────────────────────────
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                // Wide screens (web/tablet): use compact horizontal cards
                if (width > 500) {
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    itemCount: _filteredCharacters.length,
                    itemBuilder: (context, index) {
                      return _buildCharacterRow(_filteredCharacters[index]);
                    },
                  );
                }
                // Mobile: grid with responsive column count
                final cols = width > 400 ? 4 : 3;
                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 0.75,
                  ),
                  itemCount: _filteredCharacters.length,
                  itemBuilder: (context, index) {
                    return _buildCharacterTile(_filteredCharacters[index]);
                  },
                );
              },
            ),
          ),

          // ── Deploy button ─────────────────────────────────────────────
          Container(
            padding: EdgeInsets.fromLTRB(20, 12, 20, bottomPad + 12),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              border: Border(
                top: BorderSide(color: AppTheme.surfaceBorder),
              ),
            ),
            child: SizedBox(
              width: double.infinity,
              child: GestureDetector(
                onTap: _canDeploy ? _deploy : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: _canDeploy
                        ? const Color(0xFFA335EE)
                        : AppTheme.surfaceBorder,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: _canDeploy
                        ? [
                            BoxShadow(
                              color: const Color(0xFFA335EE)
                                  .withValues(alpha: 0.25),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      _canDeploy
                          ? 'DEPLOY ${_selectedIds.length} TOWERS'
                          : 'SELECT AT LEAST 3 TOWERS',
                      style: GoogleFonts.rajdhani(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: _canDeploy
                            ? Colors.white
                            : AppTheme.textTertiary,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Filter chip
  // -----------------------------------------------------------------------

  Widget _buildFilterChip(String? archetype, String label) {
    final isActive = _archetypeFilter == archetype;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () => setState(() => _archetypeFilter = archetype),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: isActive
                ? const Color(0xFFA335EE).withValues(alpha: 0.15)
                : AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isActive
                  ? const Color(0xFFA335EE).withValues(alpha: 0.4)
                  : AppTheme.surfaceBorder,
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.rajdhani(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isActive
                  ? const Color(0xFFA335EE)
                  : AppTheme.textTertiary,
              letterSpacing: 1,
            ),
          ),
        ),
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Character row (wide screens — compact horizontal card)
  // -----------------------------------------------------------------------

  Widget _buildCharacterRow(WowCharacter character) {
    final isSelected = _selectedIds.contains(character.id);
    final classColor = WowClassColors.forClass(character.characterClass);
    final classDef = widget.classRegistry.getClass(character.characterClass);
    final isDisabled = _atMax && !isSelected;

    return GestureDetector(
      onTap: isDisabled ? null : () => _toggle(character.id),
      onLongPress: () => _showCharacterDetail(character),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? classColor.withValues(alpha: 0.1)
              : AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? classColor.withValues(alpha: 0.5)
                : isDisabled
                    ? AppTheme.surfaceBorder.withValues(alpha: 0.3)
                    : AppTheme.surfaceBorder,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Opacity(
          opacity: isDisabled ? 0.4 : 1.0,
          child: Row(
            children: [
              // Avatar
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? classColor
                        : classColor.withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                ),
                child: ClipOval(
                  child: character.avatarUrl != null
                      ? (character.avatarUrl!.startsWith('asset:')
                          ? Image.asset(
                              character.avatarUrl!.substring(6),
                              width: 36, height: 36, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                  color: classColor.withValues(alpha: 0.2),
                                  child: Icon(Icons.person, color: classColor, size: 18)),
                            )
                          : CachedNetworkImage(
                              imageUrl: character.avatarUrl!,
                              width: 36, height: 36, fit: BoxFit.cover,
                              placeholder: (_, __) => Container(
                                  color: classColor.withValues(alpha: 0.2),
                                  child: Icon(Icons.person, color: classColor, size: 18)),
                              errorWidget: (_, __, ___) => Container(
                                  color: classColor.withValues(alpha: 0.2),
                                  child: Icon(Icons.person, color: classColor, size: 18)),
                            ))
                      : Container(
                          color: classColor.withValues(alpha: 0.2),
                          child: Icon(Icons.person, color: classColor, size: 18)),
                ),
              ),
              const SizedBox(width: 10),
              // Name + class
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      character.name,
                      style: GoogleFonts.rajdhani(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isSelected ? classColor : AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      '${character.characterClass} \u00B7 ${classDef.archetype.name.toUpperCase()} \u00B7 ${classDef.passive.name}',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        color: AppTheme.textTertiary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // ilvl
              if (character.equippedItemLevel != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    '${character.equippedItemLevel}',
                    style: GoogleFonts.rajdhani(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              // Info button (visible on wide screens, easier than long-press)
              GestureDetector(
                onTap: () => _showCharacterDetail(character),
                child: Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(Icons.info_outline_rounded,
                      color: AppTheme.textTertiary.withValues(alpha: 0.5),
                      size: 18),
                ),
              ),
              // Check
              if (isSelected)
                Icon(Icons.check_circle_rounded, color: classColor, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Character tile (mobile grid)
  // -----------------------------------------------------------------------

  Widget _buildCharacterTile(WowCharacter character) {
    final isSelected = _selectedIds.contains(character.id);
    final classColor = WowClassColors.forClass(character.characterClass);
    final classDef = widget.classRegistry.getClass(character.characterClass);
    final isDisabled = _atMax && !isSelected;

    return GestureDetector(
      onTap: isDisabled ? null : () => _toggle(character.id),
      onLongPress: () => _showCharacterDetail(character),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: isSelected
              ? classColor.withValues(alpha: 0.1)
              : AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? classColor.withValues(alpha: 0.6)
                : isDisabled
                    ? AppTheme.surfaceBorder.withValues(alpha: 0.3)
                    : AppTheme.surfaceBorder,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Opacity(
          opacity: isDisabled ? 0.4 : 1.0,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Avatar
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? classColor
                        : classColor.withValues(alpha: 0.3),
                    width: isSelected ? 2.5 : 1.5,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: classColor.withValues(alpha: 0.3),
                            blurRadius: 12,
                          ),
                        ]
                      : null,
                ),
                child: ClipOval(
                  child: character.avatarUrl != null
                      ? (character.avatarUrl!.startsWith('asset:')
                          ? Image.asset(
                              character.avatarUrl!.substring(6),
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: classColor.withValues(alpha: 0.2),
                                child: Icon(Icons.person,
                                    color: classColor, size: 24),
                              ),
                            )
                          : CachedNetworkImage(
                              imageUrl: character.avatarUrl!,
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => Container(
                                color: classColor.withValues(alpha: 0.2),
                                child: Icon(Icons.person,
                                    color: classColor, size: 24),
                              ),
                              errorWidget: (_, __, ___) => Container(
                                color: classColor.withValues(alpha: 0.2),
                                child: Icon(Icons.person,
                                    color: classColor, size: 24),
                              ),
                            ))
                      : Container(
                          color: classColor.withValues(alpha: 0.2),
                          child: Icon(Icons.person,
                              color: classColor, size: 24),
                        ),
                ),
              ),
              const SizedBox(height: 6),
              // Name
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  character.name,
                  style: GoogleFonts.rajdhani(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? classColor : AppTheme.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
              // Class + archetype
              Text(
                classDef.archetype.name.toUpperCase(),
                style: GoogleFonts.inter(
                  fontSize: 9,
                  color: AppTheme.textTertiary,
                  letterSpacing: 0.5,
                ),
              ),
              // Selection indicator
              if (isSelected)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(Icons.check_circle_rounded,
                      color: classColor, size: 14),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Character detail bottom sheet
  // -----------------------------------------------------------------------

  void _showCharacterDetail(WowCharacter character) {
    final classDef = widget.classRegistry.getClass(character.characterClass);
    final classColor = WowClassColors.forClass(character.characterClass);
    final archInfo = widget.classRegistry.getArchetype(classDef.archetype);
    final isSelected = _selectedIds.contains(character.id);

    // Compute normalized damage (same formula as TdTower)
    final ilvl = character.equippedItemLevel ?? 100;
    final damage = ilvl > 300
        ? 40 + ((ilvl - 500).clamp(0, 200) / 200) * 30
        : 40 + ((ilvl - 60).clamp(0, 80) / 80) * 30;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceElevated,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(
            24, 16, 24, MediaQuery.of(context).padding.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Character header
            Row(
              children: [
                Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: classColor, width: 2.5),
                  ),
                  child: ClipOval(
                    child: character.avatarUrl != null
                        ? (character.avatarUrl!.startsWith('asset:')
                            ? Image.asset(
                                character.avatarUrl!.substring(6),
                                width: 52, height: 52, fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  color: classColor.withValues(alpha: 0.2),
                                  child: Icon(Icons.person, color: classColor, size: 26),
                                ),
                              )
                            : CachedNetworkImage(
                                imageUrl: character.avatarUrl!,
                                width: 52, height: 52, fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => Container(
                                  color: classColor.withValues(alpha: 0.2),
                                  child: Icon(Icons.person, color: classColor, size: 26),
                                ),
                              ))
                        : Container(
                            color: classColor.withValues(alpha: 0.2),
                            child: Icon(Icons.person, color: classColor, size: 26),
                          ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        character.name,
                        style: GoogleFonts.rajdhani(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: classColor,
                        ),
                      ),
                      Text(
                        '${character.characterClass} \u00B7 ${character.race} \u00B7 ${character.realm}',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Stats row
            Row(
              children: [
                _statBadge('ILVL', '${character.equippedItemLevel ?? '?'}', classColor),
                const SizedBox(width: 8),
                _statBadge('DAMAGE', damage.toStringAsFixed(0), classColor),
                const SizedBox(width: 8),
                _statBadge('ARCHETYPE', classDef.archetype.name.toUpperCase(), classColor),
              ],
            ),
            const SizedBox(height: 12),

            // Archetype info
            if (archInfo != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.surfaceBorder),
                ),
                child: Text(
                  archInfo.stats,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: AppTheme.textTertiary,
                  ),
                ),
              ),
            const SizedBox(height: 12),

            // Passive ability
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: classColor.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: classColor.withValues(alpha: 0.15)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_awesome_rounded,
                          color: classColor, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        'PASSIVE',
                        style: GoogleFonts.rajdhani(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: classColor.withValues(alpha: 0.7),
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    classDef.passive.name,
                    style: GoogleFonts.rajdhani(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: classColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    classDef.passive.description,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),

            // Empowered passive (if available)
            if (classDef.empoweredPassive != null) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFA335EE).withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: const Color(0xFFA335EE).withValues(alpha: 0.15)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.star_rounded,
                            color: Color(0xFFA335EE), size: 14),
                        const SizedBox(width: 6),
                        Text(
                          'EMPOWERED (2 VALOR)',
                          style: GoogleFonts.rajdhani(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFFA335EE).withValues(alpha: 0.7),
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      classDef.empoweredPassive!.name,
                      style: GoogleFonts.rajdhani(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFFA335EE),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      classDef.empoweredPassive!.description,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),

            // Select/deselect button
            GestureDetector(
              onTap: () {
                _toggle(character.id);
                Navigator.of(context).pop();
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.surfaceBorder
                      : classColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    isSelected ? 'REMOVE FROM COMP' : 'ADD TO COMP',
                    style: GoogleFonts.rajdhani(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isSelected
                          ? AppTheme.textSecondary
                          : Colors.white,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statBadge(String label, String value, Color accent) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.surfaceBorder),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: GoogleFonts.rajdhani(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 9,
                color: AppTheme.textTertiary,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
