import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../models/character.dart';
import '../../services/character_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/wow_class_colors.dart';
import '../data/effect_types.dart';
import '../data/td_class_registry.dart';
import '../data/td_dungeon_registry.dart';
import '../data/td_rotation.dart';
import 'td_game_screen.dart';

class TdMenuScreen extends StatefulWidget {
  const TdMenuScreen({super.key});

  @override
  State<TdMenuScreen> createState() => _TdMenuScreenState();
}

class _TdMenuScreenState extends State<TdMenuScreen>
    with SingleTickerProviderStateMixin {
  int _keystoneLevel = 2;
  int _selectedDungeonIndex = 0;
  final Set<int> _selectedCharacterIds = {};
  late AnimationController _glowController;

  TdClassRegistry? _classRegistry;
  TdRotation? _rotation;
  List<TdDungeonDef> _dungeons = [];
  bool _dataLoading = true;

  TdDungeonDef get _selectedDungeon =>
      _dungeons[_selectedDungeonIndex % _dungeons.length];

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _loadData();
  }

  Future<void> _loadData() async {
    final classReg = TdClassRegistry();
    final dungeonReg = TdDungeonRegistry();
    final rotation = TdRotation();

    await Future.wait([
      classReg.load(),
      dungeonReg.load(),
      rotation.load(),
    ]);

    if (mounted) {
      setState(() {
        _classRegistry = classReg;
        _rotation = rotation;
        _dungeons = rotation.getDungeons(dungeonReg);
        _dataLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  void _toggleCharacter(int id) {
    setState(() {
      if (_selectedCharacterIds.contains(id)) {
        _selectedCharacterIds.remove(id);
      } else if (_selectedCharacterIds.length < 5) {
        _selectedCharacterIds.add(id);
      }
    });
  }

  bool get _canStart => _selectedCharacterIds.length >= 3 && !_dataLoading;

  void _startRun(List<WowCharacter> allCharacters) {
    final selected = allCharacters
        .where((c) => _selectedCharacterIds.contains(c.id))
        .toList();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TdGameScreen(
          characters: selected,
          keystoneLevel: _keystoneLevel,
          dungeon: _selectedDungeon,
          classRegistry: _classRegistry!,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_dataLoading) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(
                color: Color(0xFFA335EE),
                strokeWidth: 2,
              ),
              const SizedBox(height: 16),
              Text(
                'Loading dungeon data...',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppTheme.textTertiary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Consumer<CharacterProvider>(
        builder: (context, provider, _) {
          final characters = provider.characters;
          return Stack(
            children: [
              // Main scrollable content
              CustomScrollView(
                slivers: [
                  // Dungeon header
                  SliverToBoxAdapter(child: _buildDungeonHeader()),

                  // Keystone selector
                  SliverToBoxAdapter(child: _buildKeystoneSelector()),

                  // Party section header
                  SliverToBoxAdapter(child: _buildPartySectionHeader()),

                  // Character cards
                  SliverPadding(
                    padding: const EdgeInsets.only(bottom: 100),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final character = characters[index];
                          final isSelected =
                              _selectedCharacterIds.contains(character.id);
                          return _CharacterPickerCard(
                            character: character,
                            isSelected: isSelected,
                            onTap: () => _toggleCharacter(character.id),
                            classRegistry: _classRegistry,
                          );
                        },
                        childCount: characters.length,
                      ),
                    ),
                  ),
                ],
              ),

              // Close button — top left
              Positioned(
                top: MediaQuery.of(context).padding.top + 12,
                left: 16,
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppTheme.surface.withValues(alpha: 0.8),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppTheme.surfaceBorder,
                        width: 1,
                      ),
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      color: AppTheme.textSecondary,
                      size: 20,
                    ),
                  ),
                ),
              ),

              // Start button — pinned at bottom
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildStartButton(characters),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDungeonHeader() {
    final dungeon = _selectedDungeon;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 56,
        bottom: 28,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF1A0E2E),
            Color(0xFF130B20),
            AppTheme.background,
          ],
          stops: [0.0, 0.6, 1.0],
        ),
      ),
      child: Column(
        children: [
          // Dungeon icon
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: dungeon.bossColor.withValues(alpha: 0.4),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: dungeon.bossColor.withValues(alpha: 0.15),
                  blurRadius: 24,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Icon(
              TdIcons.getIcon(dungeon.bossIcon),
              color: dungeon.bossColor.withValues(alpha: 0.9),
              size: 30,
            ),
          ),
          const SizedBox(height: 16),
          // Tappable dungeon name with arrows
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: () => setState(() {
                  _selectedDungeonIndex =
                      (_selectedDungeonIndex - 1 + _dungeons.length) %
                          _dungeons.length;
                }),
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.chevron_left_rounded,
                      color: AppTheme.textTertiary, size: 28),
                ),
              ),
              Text(
                dungeon.name.toUpperCase(),
                style: GoogleFonts.rajdhani(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                  letterSpacing: 3,
                  height: 1.0,
                ),
              ),
              GestureDetector(
                onTap: () => setState(() {
                  _selectedDungeonIndex =
                      (_selectedDungeonIndex + 1) % _dungeons.length;
                }),
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.chevron_right_rounded,
                      color: AppTheme.textTertiary, size: 28),
                ),
              ),
            ],
          ),
          if (dungeon.theme.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              dungeon.theme,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: dungeon.bossColor.withValues(alpha: 0.6),
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            '${_rotation?.season ?? 'Loading...'} \u00B7 ${_selectedDungeonIndex + 1}/${_dungeons.length}',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: AppTheme.textTertiary,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeystoneSelector() {
    final bool showAffixWarning = _keystoneLevel >= 7;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.surfaceBorder),
        ),
        child: Column(
          children: [
            Text(
              'KEYSTONE LEVEL',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppTheme.textTertiary,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Minus button
                GestureDetector(
                  onTap: _keystoneLevel > 2
                      ? () => setState(() => _keystoneLevel--)
                      : null,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _keystoneLevel > 2
                          ? AppTheme.surfaceElevated
                          : AppTheme.surface,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _keystoneLevel > 2
                            ? AppTheme.surfaceBorder
                            : AppTheme.surfaceBorder.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Icon(
                      Icons.remove_rounded,
                      color: _keystoneLevel > 2
                          ? AppTheme.textSecondary
                          : AppTheme.textTertiary.withValues(alpha: 0.5),
                      size: 20,
                    ),
                  ),
                ),

                const SizedBox(width: 24),

                // Keystone gem
                AnimatedBuilder(
                  animation: _glowController,
                  builder: (context, child) {
                    final glowIntensity =
                        0.15 + (_glowController.value * 0.15);
                    return Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFFA335EE).withValues(alpha: 0.6),
                          width: 2,
                        ),
                        gradient: RadialGradient(
                          colors: [
                            const Color(0xFFA335EE)
                                .withValues(alpha: glowIntensity),
                            const Color(0xFFA335EE)
                                .withValues(alpha: glowIntensity * 0.3),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.5, 1.0],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFA335EE)
                                .withValues(alpha: glowIntensity),
                            blurRadius: 20,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          '+$_keystoneLevel',
                          style: GoogleFonts.rajdhani(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                            height: 1.0,
                          ),
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(width: 24),

                // Plus button
                GestureDetector(
                  onTap: () => setState(() => _keystoneLevel++),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceElevated,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.surfaceBorder),
                    ),
                    child: const Icon(
                      Icons.add_rounded,
                      color: AppTheme.textSecondary,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),

            // Affix warning at +7
            if (showAffixWarning) ...[
              const SizedBox(height: 14),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF8000).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFFFF8000).withValues(alpha: 0.25),
                  ),
                ),
                child: Text(
                  '2 AFFIXES',
                  style: GoogleFonts.rajdhani(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFFF8000),
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPartySectionHeader() {
    final selected = _selectedCharacterIds.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Row(
        children: [
          Text(
            'SELECT YOUR PARTY',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppTheme.textTertiary,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: selected >= 3
                  ? const Color(0xFFA335EE).withValues(alpha: 0.12)
                  : AppTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$selected / 5',
              style: GoogleFonts.rajdhani(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: selected >= 3
                    ? const Color(0xFFA335EE)
                    : AppTheme.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStartButton(List<WowCharacter> characters) {
    final remaining = 3 - _selectedCharacterIds.length;

    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.of(context).padding.bottom + 16,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppTheme.background.withValues(alpha: 0.0),
            AppTheme.background.withValues(alpha: 0.9),
            AppTheme.background,
          ],
          stops: const [0.0, 0.3, 0.5],
        ),
      ),
      child: GestureDetector(
        onTap: _canStart ? () => _startRun(characters) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: double.infinity,
          height: 56,
          decoration: BoxDecoration(
            color: _canStart
                ? const Color(0xFFA335EE)
                : AppTheme.surfaceElevated,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _canStart
                  ? const Color(0xFFA335EE).withValues(alpha: 0.6)
                  : AppTheme.surfaceBorder,
            ),
            boxShadow: _canStart
                ? [
                    BoxShadow(
                      color:
                          const Color(0xFFA335EE).withValues(alpha: 0.3),
                      blurRadius: 16,
                      spreadRadius: 0,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              _canStart
                  ? 'START +$_keystoneLevel KEYSTONE'
                  : 'SELECT $remaining MORE',
              style: GoogleFonts.rajdhani(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _canStart
                    ? Colors.white
                    : AppTheme.textTertiary,
                letterSpacing: 2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Character Picker Card
// ---------------------------------------------------------------------------

class _CharacterPickerCard extends StatelessWidget {
  final WowCharacter character;
  final bool isSelected;
  final VoidCallback onTap;
  final TdClassRegistry? classRegistry;

  const _CharacterPickerCard({
    required this.character,
    required this.isSelected,
    required this.onTap,
    this.classRegistry,
  });

  @override
  Widget build(BuildContext context) {
    final classColor = WowClassColors.forClass(character.characterClass);
    final classDef = classRegistry?.getClass(character.characterClass);
    final archetype = classDef?.archetype ?? TowerArchetype.melee;
    final archetypeLabel = archetype.name.toUpperCase();

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? classColor.withValues(alpha: 0.1)
              : AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? classColor.withValues(alpha: 0.5)
                : AppTheme.surfaceBorder,
            width: 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Row(
            children: [
              // Left class color bar
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 3,
                height: 64,
                color: isSelected
                    ? classColor
                    : classColor.withValues(alpha: 0.3),
              ),

              // Avatar
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 8, bottom: 8),
                child: _buildAvatar(classColor),
              ),

              // Content
              Expanded(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  child: Row(
                    children: [
                      // Name and class info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              character.name,
                              style: GoogleFonts.rajdhani(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: isSelected
                                    ? classColor
                                    : AppTheme.textPrimary,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Text(
                                  character.characterClass,
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w400,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6),
                                  child: Text(
                                    '\u00B7',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: AppTheme.textTertiary,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: classColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    archetypeLabel,
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color:
                                          classColor.withValues(alpha: 0.8),
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                                if (classDef != null) ...[
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6),
                                    child: Text(
                                      '\u00B7',
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        color: AppTheme.textTertiary,
                                      ),
                                    ),
                                  ),
                                  Flexible(
                                    child: Text(
                                      classDef.passive.name,
                                      style: GoogleFonts.inter(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w400,
                                        color: AppTheme.textTertiary,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Item level
                      if (character.equippedItemLevel != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: Text(
                            '${character.equippedItemLevel}',
                            style: GoogleFonts.rajdhani(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ),

                      // Selection indicator
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected
                              ? classColor
                              : Colors.transparent,
                          border: Border.all(
                            color: isSelected
                                ? classColor
                                : AppTheme.surfaceBorder,
                            width: 2,
                          ),
                        ),
                        child: isSelected
                            ? const Icon(
                                Icons.check_rounded,
                                color: Colors.white,
                                size: 14,
                              )
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(Color classColor) {
    return SizedBox(
      width: 42,
      height: 42,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: character.avatarUrl != null
            ? CachedNetworkImage(
                imageUrl: character.avatarUrl!,
                fit: BoxFit.cover,
                placeholder: (_, __) => _avatarFallback(classColor),
                errorWidget: (_, __, ___) => _avatarFallback(classColor),
              )
            : _avatarFallback(classColor),
      ),
    );
  }

  Widget _avatarFallback(Color classColor) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: classColor.withValues(alpha: 0.15),
        border: Border.all(
          color: classColor.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Center(
        child: Text(
          character.name.isNotEmpty ? character.name[0].toUpperCase() : '?',
          style: GoogleFonts.rajdhani(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: classColor,
          ),
        ),
      ),
    );
  }
}
