import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../models/character.dart';
import '../../services/character_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/wow_class_colors.dart';
import '../data/effect_types.dart';
import '../data/td_balance_config.dart';
import '../data/td_class_registry.dart';
import '../data/td_dungeon_registry.dart';
import '../data/td_hero_registry.dart';
import '../data/td_rotation.dart';
import '../data/td_run_state.dart';
import 'td_class_guide_screen.dart';
import 'td_comp_selection_screen.dart';
import 'td_dungeon_roulette_screen.dart';
import 'td_game_screen.dart';
import 'td_upgrade_screen.dart';

class TdMenuScreen extends StatefulWidget {
  final List<WowCharacter>? heroes;
  const TdMenuScreen({super.key, this.heroes});

  @override
  State<TdMenuScreen> createState() => _TdMenuScreenState();
}

class _TdMenuScreenState extends State<TdMenuScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _glowController;

  TdClassRegistry? _classRegistry;
  TdHeroRegistry? _heroRegistry;
  TdRotation? _rotation;
  List<TdDungeonDef> _dungeons = [];
  bool _dataLoading = true;

  bool _useHeroes = false; // false = warband, true = legendary heroes
  bool _rosterLocked = false; // locked after INSERT KEYSTONE

  @override
  void initState() {
    super.initState();
    if (widget.heroes != null) {
      _useHeroes = true;
    }
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _loadData();
  }

  Future<void> _loadData() async {
    final classReg = TdClassRegistry();
    final dungeonReg = TdDungeonRegistry();
    final heroReg = TdHeroRegistry();
    final rotation = TdRotation();

    await Future.wait([
      classReg.load(),
      dungeonReg.load(),
      heroReg.load(),
      rotation.load(),
    ]);

    if (mounted) {
      setState(() {
        _classRegistry = classReg;
        _heroRegistry = heroReg;
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

  bool get _isGuestMode => widget.heroes != null;

  List<WowCharacter> _getActiveRoster(List<WowCharacter> warbandCharacters) {
    if (widget.heroes != null) {
      return _heroRegistry?.getHeroes() ?? widget.heroes!;
    }
    return _useHeroes
        ? (_heroRegistry?.getHeroes() ?? WowCharacter.legendaryHeroes())
        : warbandCharacters;
  }

  bool get _canStart => !_dataLoading;

  void _startRun(List<WowCharacter> allCharacters) {
    setState(() => _rosterLocked = true);
    final runState = TdRunState();
    _navigateToKey(allCharacters, runState).then((_) {
      if (mounted) setState(() => _rosterLocked = false);
    });
  }

  Future<void> _navigateToKey(
      List<WowCharacter> allCharacters, TdRunState runState) async {
    if (!mounted) return;
    const config = TdBalanceConfig.defaults;

    // 1. Roulette (if no current dungeon — i.e. not a depletion retry)
    TdDungeonDef dungeon;
    if (runState.currentDungeon != null) {
      dungeon = runState.currentDungeon!;
    } else {
      final selected = await Navigator.of(context).push<TdDungeonDef>(
        MaterialPageRoute(
          builder: (_) => TdDungeonRouletteScreen(
            dungeons: _dungeons,
            keystoneLevel: runState.keystoneLevel,
          ),
        ),
      );
      if (selected == null || !mounted) return;
      dungeon = selected;
      runState.currentDungeon = dungeon;
    }

    // 2. Comp selection
    if (!mounted) return;
    final comp = await Navigator.of(context).push<List<WowCharacter>>(
      MaterialPageRoute(
        builder: (_) => TdCompSelectionScreen(
          allCharacters: allCharacters,
          dungeon: dungeon,
          keystoneLevel: runState.keystoneLevel,
          maxTowers: runState.maxTowers(config),
          classRegistry: _classRegistry!,
          heroRegistry: _heroRegistry,
        ),
      ),
    );
    if (comp == null || !mounted) return;

    // 3. Upgrade screen (if valor available)
    if (runState.valor > 0 && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TdUpgradeScreen(
            runState: runState,
            selectedCharacters: comp,
            classRegistry: _classRegistry!,
            heroRegistry: _heroRegistry,
          ),
        ),
      );
    }

    // 4. Game
    if (!mounted) return;
    final result = await Navigator.of(context).push<
        ({bool cleared, int lives, int stars})>(
      MaterialPageRoute(
        builder: (_) => TdGameScreen(
          characters: comp,
          keystoneLevel: runState.keystoneLevel,
          dungeon: dungeon,
          classRegistry: _classRegistry!,
          heroRegistry: _heroRegistry,
          dungeons: _dungeons,
          runState: runState,
        ),
      ),
    );

    if (result == null || !mounted) return;

    // 5. Process result and loop
    if (result.cleared) {
      runState.onClear(result.lives, result.stars, config);
      _navigateToKey(allCharacters, runState);
    } else {
      runState.onDeplete(config);
      _navigateToKey(allCharacters, runState);
    }
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
          final characters = _getActiveRoster(provider.characters);
          return Stack(
            children: [
              // Main scrollable content
              CustomScrollView(
                slivers: [
                  // Dungeon header
                  SliverToBoxAdapter(child: _buildDungeonHeader()),

                  // Roster source tab (only when logged in)
                  SliverToBoxAdapter(child: _buildRosterTab()),

                  // Roster section header
                  SliverToBoxAdapter(child: _buildRosterSectionHeader(characters.length)),

                  // Character roster (read-only preview)
                  SliverPadding(
                    padding: const EdgeInsets.only(bottom: 100),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          return _CharacterPickerCard(
                            character: characters[index],
                            isSelected: false,
                            onTap: () {}, // read-only
                            classRegistry: _classRegistry,
                            heroRegistry: _heroRegistry,
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
          // Keystone gem
          AnimatedBuilder(
            animation: _glowController,
            builder: (context, child) {
              final glowIntensity = 0.15 + (_glowController.value * 0.15);
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
                      const Color(0xFFA335EE).withValues(alpha: glowIntensity),
                      const Color(0xFFA335EE).withValues(alpha: glowIntensity * 0.3),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFA335EE).withValues(alpha: glowIntensity),
                      blurRadius: 20,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(
                    Icons.diamond_rounded,
                    color: const Color(0xFFA335EE).withValues(alpha: 0.9),
                    size: 36,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          Text(
            'MYTHIC KEYSTONE',
            style: GoogleFonts.rajdhani(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
              letterSpacing: 3,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _rotation?.season ?? 'Loading...',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: AppTheme.textTertiary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Dungeon is randomly assigned',
            style: GoogleFonts.inter(
              fontSize: 11,
              color: AppTheme.textTertiary.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRosterSectionHeader(int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Row(
        children: [
          Text(
            _useHeroes ? 'LEGENDARY HEROES' : 'YOUR ROSTER',
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
              color: AppTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count characters',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: AppTheme.textTertiary,
              ),
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const TdClassGuideScreen()),
            ),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: AppTheme.surfaceElevated,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.menu_book_rounded, size: 16, color: AppTheme.textTertiary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRosterTab() {
    if (_isGuestMode) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.surfaceBorder),
        ),
        padding: const EdgeInsets.all(3),
        child: Row(
          children: [
            _buildTabButton('YOUR WARBAND', !_useHeroes),
            _buildTabButton('LEGENDARY HEROES', _useHeroes),
          ],
        ),
      ),
    );
  }

  Widget _buildTabButton(String label, bool isActive) {
    return Expanded(
      child: GestureDetector(
        onTap: _rosterLocked
            ? null
            : () => setState(() {
                  _useHeroes = label == 'LEGENDARY HEROES';
                }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive
                ? const Color(0xFFA335EE).withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: isActive
                ? Border.all(
                    color: const Color(0xFFA335EE).withValues(alpha: 0.4))
                : null,
          ),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isActive
                    ? const Color(0xFFA335EE)
                    : AppTheme.textTertiary,
                letterSpacing: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStartButton(List<WowCharacter> characters) {
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
                  ? 'INSERT KEYSTONE'
                  : 'LOADING...',
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
  final TdHeroRegistry? heroRegistry;

  const _CharacterPickerCard({
    required this.character,
    required this.isSelected,
    required this.onTap,
    this.classRegistry,
    this.heroRegistry,
  });

  @override
  Widget build(BuildContext context) {
    final classColor = WowClassColors.forClass(character.characterClass);
    final classDef = (classRegistry != null
            ? heroRegistry?.getHeroClassDef(character.name, classRegistry!)
            : null) ??
        classRegistry?.getClass(character.characterClass);
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

                      // Selection indicator (only in comp selection mode)
                      if (isSelected)
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: classColor,
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 14,
                          ),
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
            ? (character.avatarUrl!.startsWith('asset:')
                ? Image.asset(
                    character.avatarUrl!.substring(6),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _avatarFallback(classColor),
                  )
                : CachedNetworkImage(
                    imageUrl: character.avatarUrl!,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => _avatarFallback(classColor),
                    errorWidget: (_, __, ___) => _avatarFallback(classColor),
                  ))
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
