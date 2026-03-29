import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/character.dart';
import '../../theme/app_theme.dart';
import '../data/effect_types.dart';
import '../data/td_class_registry.dart';
import '../data/td_hero_registry.dart';
import '../data/td_run_state.dart';
import '../data/td_sfx_registry.dart';
import '../models/td_models.dart';
import '../services/td_audio_service.dart';
import '../td_game_state.dart';
import '../widgets/td_combat_log_overlay.dart';
import 'td_dungeon_briefing_screen.dart';

// ---------------------------------------------------------------------------
// TdGameScreen — main gameplay UI
// ---------------------------------------------------------------------------

class TdGameScreen extends StatefulWidget {
  final List<WowCharacter> characters;
  final int keystoneLevel;
  final TdDungeonDef dungeon;
  final TdClassRegistry classRegistry;
  final TdHeroRegistry? heroRegistry;
  final List<TdDungeonDef> dungeons; // rotation pool for roulette on victory
  final TdRunState? runState;
  final TdSfxRegistry? sfxRegistry;

  const TdGameScreen({
    super.key,
    required this.characters,
    required this.keystoneLevel,
    required this.dungeon,
    required this.classRegistry,
    this.heroRegistry,
    required this.dungeons,
    this.runState,
    this.sfxRegistry,
  });

  @override
  State<TdGameScreen> createState() => _TdGameScreenState();
}

class _TdGameScreenState extends State<TdGameScreen>
    with SingleTickerProviderStateMixin {
  late final TdGameState _game;
  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;
  TdAudioService? _audio;
  bool _showVolumeSlider = false;

  // Track which lane+slot is being hovered during a drag.
  int? _dragHoverLane;
  int? _dragHoverSlot;

  /// Scale factor for game elements based on screen width.
  /// Mobile (~375px) = 1.0x, Tablet (~768px) = 1.3x, Desktop (~1200px+) = 1.6x
  double get _uiScale {
    final width = MediaQuery.of(context).size.width;
    if (width > 1000) return 1.6;
    if (width > 700) return 1.3;
    return 1.0;
  }

  @override
  void initState() {
    super.initState();
    _game = TdGameState();
    _game.autocastAbilities = false; // Player controls abilities via UI
    _game.startRun(widget.characters, widget.keystoneLevel,
        dungeon: widget.dungeon, classRegistry: widget.classRegistry,
        heroRegistry: widget.heroRegistry, runState: widget.runState);
    _game.addListener(_onGameStateChanged);
    // Don't auto-start — let the player position towers first
    _ticker = createTicker(_onTick);
    _initAudio();
  }

  Future<void> _initAudio() async {
    if (widget.sfxRegistry != null) {
      _audio = TdAudioService(widget.sfxRegistry!);
      await _audio!.init();
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _game.removeListener(_onGameStateChanged);
    _game.dispose();
    _audio?.dispose();
    super.dispose();
  }

  // -----------------------------------------------------------------------
  // Ticker / game loop
  // -----------------------------------------------------------------------

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    // Cap dt to avoid huge jumps after a pause.
    _game.tick(dt.clamp(0, 0.5));
    // Play accumulated SFX events
    if (_audio != null && _game.sfxEvents.isNotEmpty) {
      _audio!.playEvents(_game.sfxEvents);
    }
    setState(() {}); // repaint
  }

  void _onGameStateChanged() {
    switch (_game.phase) {
      case TdGamePhase.betweenWaves:
      case TdGamePhase.victory:
      case TdGamePhase.defeat:
        _ticker.stop();
        // Play any remaining SFX from the final tick
        if (_audio != null && _game.sfxEvents.isNotEmpty) {
          _audio!.playEvents(_game.sfxEvents);
        }
        break;
      default:
        break;
    }
    if (mounted) setState(() {});
  }

  void _startNextWave() {
    _game.nextWave();
    _lastElapsed = Duration.zero;
    _ticker.stop();
    _ticker.start();
  }

  // -----------------------------------------------------------------------
  // Exit confirmation
  // -----------------------------------------------------------------------

  Future<void> _confirmExit() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.surfaceBorder),
        ),
        title: Text(
          'Leave Keystone?',
          style: GoogleFonts.rajdhani(
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        content: Text(
          'Your progress will be lost.',
          style: GoogleFonts.rajdhani(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('STAY', style: GoogleFonts.rajdhani(fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'LEAVE',
              style: GoogleFonts.rajdhani(
                fontWeight: FontWeight.w600,
                color: const Color(0xFFFF5E5B),
              ),
            ),
          ),
        ],
      ),
    );
    if (leave == true && mounted) {
      Navigator.of(context).pop();
    }
  }

  // -----------------------------------------------------------------------
  // Build
  // -----------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _buildHeaderBar(),
                if (_game.phase == TdGamePhase.setup) _buildSetupBanner(),
                if (_game.phase == TdGamePhase.betweenWaves) _buildWaveClearBanner(),
                if (_game.phase != TdGamePhase.setup && _game.phase != TdGamePhase.betweenWaves) _buildAffixBar(),
                Expanded(child: _buildLanes()),
                if (_game.phase == TdGamePhase.setup)
                  _buildSetupBottomBar()
                else if (_game.phase == TdGamePhase.betweenWaves)
                  _buildBetweenWavesBottomBar()
                else
                  _buildTowerInfoBar(),
              ],
            ),
            if (_showVolumeSlider) _buildVolumeSliderOverlay(),
          ],
        ),
      ),
    );
  }

  // -----------------------------------------------------------------------
  // 1. Header bar
  // -----------------------------------------------------------------------

  Widget _buildHeaderBar() {
    final livesColor = _game.lives > 10
        ? AppTheme.textPrimary
        : _game.lives > 5
            ? const Color(0xFFFFA500)
            : const Color(0xFFFF5E5B);

    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          // Close button
          GestureDetector(
            onTap: _confirmExit,
            child: const Icon(Icons.close, color: AppTheme.textSecondary, size: 20),
          ),
          const SizedBox(width: 10),
          // Dungeon name + key level (tap for dungeon info)
          Expanded(
            child: GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => TdDungeonBriefingScreen(dungeon: _game.keystone.dungeon),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      '${_game.keystone.dungeonName.toUpperCase()} +${_game.keystone.level}',
                      style: GoogleFonts.rajdhani(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFFA335EE),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.info_outline, size: 14,
                      color: const Color(0xFFA335EE).withValues(alpha: 0.5)),
                ],
              ),
            ),
          ),
          // Wave indicator
          Text(
            'WAVE ${_game.currentWave}/${_game.totalWaves}',
            style: GoogleFonts.rajdhani(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(width: 12),
          // Lives
          Icon(Icons.favorite, color: livesColor, size: 16),
          const SizedBox(width: 4),
          Text(
            '${_game.lives}',
            style: GoogleFonts.rajdhani(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: livesColor,
            ),
          ),
          if (_audio != null) ...[
            const SizedBox(width: 8),
            _buildVolumeControl(),
          ],
        ],
      ),
    );
  }

  Widget _buildVolumeControl() {
    final vol = _audio?.volume ?? 0.7;
    final icon = vol <= 0
        ? Icons.volume_off_rounded
        : vol < 0.5
            ? Icons.volume_down_rounded
            : Icons.volume_up_rounded;

    return GestureDetector(
      onTap: () => setState(() => _showVolumeSlider = !_showVolumeSlider),
      child: Icon(icon, color: AppTheme.textSecondary, size: 18),
    );
  }

  Widget _buildVolumeSliderOverlay() {
    return Positioned(
      top: 44,
      right: 8,
      child: GestureDetector(
        onTap: () {}, // absorb taps on the overlay itself
        child: Container(
          width: 180,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.surfaceElevated,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.surfaceBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              GestureDetector(
                onTap: () {
                  final newVol = (_audio?.volume ?? 0) > 0 ? 0.0 : 0.7;
                  _audio?.setVolume(newVol);
                  setState(() {});
                },
                child: Icon(
                  (_audio?.volume ?? 0) <= 0
                      ? Icons.volume_off_rounded
                      : Icons.volume_up_rounded,
                  color: AppTheme.textSecondary,
                  size: 18,
                ),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: const Color(0xFFA335EE),
                    inactiveTrackColor: AppTheme.surfaceBorder,
                    thumbColor: const Color(0xFFA335EE),
                    overlayColor: const Color(0xFFA335EE).withValues(alpha: 0.2),
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  ),
                  child: Slider(
                    value: _audio?.volume ?? 0.7,
                    min: 0,
                    max: 1,
                    onChanged: (v) {
                      _audio?.setVolume(v);
                      setState(() {});
                    },
                  ),
                ),
              ),
              Text(
                '${((_audio?.volume ?? 0.7) * 100).round()}',
                style: GoogleFonts.rajdhani(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -----------------------------------------------------------------------
  // 2. Affix bar
  // -----------------------------------------------------------------------

  Widget _buildAffixBar() {
    return Container(
      color: AppTheme.surfaceElevated,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          // Affix + dungeon modifier chips
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                // M+ affixes (orange)
                ..._game.keystone.affixes.map((a) {
                  return GestureDetector(
                    onTap: () => _showAffixInfo(a),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFFFA500), width: 1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset(
                            'assets/td/icons/affixes/${a.name}.png',
                            width: 14,
                            height: 14,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.bolt, size: 12, color: Color(0xFFFFA500),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            a.name.toUpperCase(),
                            style: GoogleFonts.rajdhani(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFFFFA500),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                // Dungeon enemy modifiers (dungeon-colored)
                ..._game.keystone.dungeon.enemyModifiers.map((mod) {
                  final dungeonColor = _game.keystone.dungeon.enemyColor;
                  return GestureDetector(
                    onTap: () => _showModifierInfo(mod),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        border: Border.all(color: dungeonColor.withValues(alpha: 0.6), width: 1),
                        borderRadius: BorderRadius.circular(4),
                        color: dungeonColor.withValues(alpha: 0.1),
                      ),
                      child: Text(
                        _modifierDisplayName(mod.type),
                        style: GoogleFonts.rajdhani(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: dungeonColor,
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
          // Kill count
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.dangerous_outlined, color: Color(0xFFFF5E5B), size: 14),
              const SizedBox(width: 4),
              Text(
                '${_game.enemiesKilled}',
                style: GoogleFonts.rajdhani(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------
  // 3. Lanes (main gameplay area)
  // -----------------------------------------------------------------------

  Widget _buildLanes() {
    final dungeon = _game.keystone.dungeon;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Dungeon background image (subtle, atmospheric)
        if (dungeon.backgroundImage != null) ...[
          Positioned.fill(
            child: Opacity(
              opacity: 0.15,
              child: Image.asset(
                dungeon.backgroundImage!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),
          // Dark overlay for readability
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.3),
            ),
          ),
        ],
        // Particle overlay (above background, behind lanes)
        if (dungeon.particles != null)
          Positioned.fill(
            child: IgnorePointer(
              child: _TdParticleOverlay(config: dungeon.particles!),
            ),
          ),
        Column(
          children: List.generate(3, (lane) {
            return Expanded(
              child: _buildLane(lane),
            );
          }),
        ),
        // Combat log overlay (above lanes, below targeting/end overlays)
        if (_game.combatLog.isNotEmpty && !_isTargeting &&
            _game.phase != TdGamePhase.victory &&
            _game.phase != TdGamePhase.defeat &&
            _game.phase != TdGamePhase.setup)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: TdCombatLogOverlay(
              entries: _game.combatLog,
              uiScale: _uiScale,
            ),
          ),
        // Targeting overlay — rendered inside lanes so positions align
        if (_isTargeting) ...[
          // Targeting content (enemy/lane/tower selection)
          Positioned.fill(
            child: _targetingType == 'lane'
                ? _buildLaneTargeting(_targetingTower.color)
                : _targetingType == 'enemy'
                    ? _buildEnemyTargeting(_targetingTower.color)
                    : _buildTowerTargeting(_targetingTower.color),
          ),
          // Targeting header (floating at top of lanes)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: _buildTargetingHeader(),
          ),
        ],
        // Overlays (only for end states that don't need interaction)
        if (_game.phase == TdGamePhase.victory) _buildVictoryOverlay(),
        if (_game.phase == TdGamePhase.defeat) _buildDefeatOverlay(),
      ],
    );
  }

  // Helper to access the targeting tower from _buildLanes
  TdTower get _targetingTower => _game.towers[_targetingTowerIndex];

  Widget _buildLane(int laneIndex) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: laneIndex < 2
              ? const BorderSide(color: AppTheme.surfaceBorder, width: 1)
              : BorderSide.none,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final laneWidth = constraints.maxWidth;
          final laneHeight = constraints.maxHeight;

          // Slot labels for display
          const slotLabels = ['FRONT', 'MID', 'BACK'];

          return SizedBox(
            width: laneWidth,
            height: laneHeight,
            child: Stack(
              children: [
                // Slot drop zones (3 per lane)
                ...List.generate(3, (slot) {
                  // Slot zones divide the lane into 3 equal drop areas
                  final zoneWidth = laneWidth / 3;
                  // Slots visually: slot 2 (back) is left (near goal), slot 0 (front) is right (near spawn)
                  final zoneLeft = (2 - slot) * zoneWidth;
                  final isHovered = _dragHoverLane == laneIndex && _dragHoverSlot == slot;

                  return Positioned(
                    left: zoneLeft,
                    top: 0,
                    width: zoneWidth,
                    height: laneHeight,
                    child: DragTarget<int>(
                      onWillAcceptWithDetails: (details) {
                        setState(() {
                          _dragHoverLane = laneIndex;
                          _dragHoverSlot = slot;
                        });
                        return true;
                      },
                      onLeave: (_) {
                        setState(() {
                          if (_dragHoverLane == laneIndex && _dragHoverSlot == slot) {
                            _dragHoverLane = null;
                            _dragHoverSlot = null;
                          }
                        });
                      },
                      onAcceptWithDetails: (details) {
                        _game.moveTower(details.data, laneIndex, slot: slot);
                        setState(() {
                          _dragHoverLane = null;
                          _dragHoverSlot = null;
                        });
                      },
                      builder: (context, candidateData, rejectedData) {
                        return Container(
                          decoration: BoxDecoration(
                            color: isHovered
                                ? const Color(0xFFA335EE).withValues(alpha: 0.08)
                                : Colors.transparent,
                            border: slot < 2
                                ? const Border(
                                    left: BorderSide(
                                      color: Color(0x15FFFFFF),
                                      width: 1,
                                    ),
                                  )
                                : null,
                          ),
                          // Show slot label when dragging
                          child: isHovered
                              ? Center(
                                  child: Text(
                                    slotLabels[slot],
                                    style: const TextStyle(
                                      color: Color(0x40FFFFFF),
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                )
                              : null,
                        );
                      },
                    ),
                  );
                }),

                // Goal line on the LEFT edge
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 3,
                  child: Container(
                    color: const Color(0xFFFF0000).withValues(alpha: 0.30),
                  ),
                ),

                // Fire zones (boss mechanic)
                ..._game.fireZones
                    .where((z) => z.laneIndex == laneIndex)
                    .map((zone) => Positioned.fill(
                          child: IgnorePointer(
                            child: Container(
                              color: const Color(0xFFFF4500).withValues(alpha: 0.1),
                              child: Center(
                                child: Icon(
                                  Icons.whatshot_rounded,
                                  color: const Color(0xFFFF4500).withValues(alpha: 0.3),
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                        )),

                // Sanguine pools
                ..._game.sanguinePools
                    .where((p) => p.laneIndex == laneIndex)
                    .map((pool) {
                  final poolLeft = (1.0 - pool.position) * (laneWidth - 60);
                  return Positioned(
                    left: poolLeft.clamp(0, laneWidth - 60),
                    top: laneHeight * 0.25,
                    child: IgnorePointer(
                      child: Container(
                        width: 60,
                        height: laneHeight * 0.5,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF0000).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(0xFFFF0000).withValues(alpha: 0.25),
                          ),
                        ),
                      ),
                    ),
                  );
                }),

                // Enemies
                ..._game.enemies
                    .where((e) => e.laneIndex == laneIndex && e.position >= 0 && !e.isDead)
                    .map((enemy) => _buildEnemy(enemy, laneWidth, laneHeight)),

                // Hit particles (projectiles + damage numbers)
                ..._game.hitEvents
                    .where((h) => h.enemyLane == laneIndex)
                    .map((hit) => _buildHitParticle(hit, laneWidth, laneHeight)),

                // Towers placed in this lane (at slot positions)
                ..._buildLaneTowers(laneIndex, laneWidth, laneHeight),

                // Lane preview badge (setup/between waves only)
                if (_game.phase == TdGamePhase.setup || _game.phase == TdGamePhase.betweenWaves)
                  _buildLanePreviewBadge(laneIndex),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildLanePreviewBadge(int laneIndex) {
    final counts = _game.nextWaveLaneCounts;
    final count = laneIndex < counts.length ? counts[laneIndex] : 0;
    if (count <= 0) return const SizedBox.shrink();

    Color badgeColor;
    if (count < 4) {
      badgeColor = const Color(0xFF00C853); // green — light
    } else if (count <= 6) {
      badgeColor = const Color(0xFFFFA500); // orange — moderate
    } else {
      badgeColor = const Color(0xFFFF5E5B); // red — heavy
    }

    return Positioned(
      right: 8,
      top: 4,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: badgeColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: badgeColor.withValues(alpha: 0.4), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.pest_control_rounded, size: 10, color: badgeColor),
            const SizedBox(width: 3),
            Text(
              '$count',
              style: GoogleFonts.rajdhani(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: badgeColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -----------------------------------------------------------------------
  // 4. Enemies
  // -----------------------------------------------------------------------

  Widget _buildEnemy(TdEnemy enemy, double laneWidth, double laneHeight) {
    final size = (enemy.isBoss ? 36.0 : 24.0) * _uiScale;
    final left = ((1.0 - enemy.position) * (laneWidth - size)).clamp(0.0, laneWidth - size);
    final top = (laneHeight - size) / 2;

    final dungeon = _game.keystone.dungeon;
    final isBeingHit = _game.hitEvents.any(
      (h) => h.enemyId == enemy.id && h.progress > 0.5 && h.progress < 0.9,
    );

    final baseColor = enemy.isBoss ? dungeon.bossColor : dungeon.enemyColor;
    final hpBarColor = baseColor;
    final enemyFill = isBeingHit
        ? Colors.white.withValues(alpha: 0.9)
        : baseColor.withValues(alpha: 0.70);
    final enemyBorder = baseColor;

    // Shield modifier: blue border
    final hasShield = enemy.shieldHits > 0;
    final shieldBorder = hasShield
        ? Border.all(color: const Color(0xFF4FC3F7), width: 2.5)
        : Border.all(color: enemyBorder, width: 1.5);

    // Phase/spectral invulnerability: reduce opacity
    final enemyOpacity = enemy.isInvulnerable ? 0.4 : 1.0;

    return Positioned(
      left: left,
      top: top - 6,
      child: Opacity(
        opacity: enemyOpacity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // HP bar
            SizedBox(
              width: size + 4,
              height: 3 * _uiScale,
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF330000),
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: enemy.hpFraction.clamp(0, 1),
                    child: Container(
                      decoration: BoxDecoration(
                        color: hpBarColor,
                        borderRadius: BorderRadius.circular(1.5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 3),
            // Enemy body
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: _enemyImagePath(enemy, dungeon) != null
                    ? Colors.transparent
                    : enemyFill,
                shape: enemy.isBoss ? BoxShape.rectangle : BoxShape.circle,
                borderRadius: enemy.isBoss ? BorderRadius.circular(6) : null,
                border: shieldBorder,
                boxShadow: [
                  if (isBeingHit)
                    BoxShadow(
                      color: const Color(0xFFFFD700).withValues(alpha: 0.5),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  if (hasShield)
                    BoxShadow(
                      color: const Color(0xFF4FC3F7).withValues(alpha: 0.3),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                ],
              ),
              child: ClipRRect(
                borderRadius: enemy.isBoss
                    ? BorderRadius.circular(6)
                    : BorderRadius.circular(size / 2),
                child: _buildEnemyContent(enemy, dungeon, isBeingHit, size),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Get enemy image asset path from dungeon definition, or null if not set.
  String? _enemyImagePath(TdEnemy enemy, TdDungeonDef dungeon) {
    return enemy.isBoss ? dungeon.bossImage : dungeon.enemyImage;
  }

  /// Build enemy visual content — image asset if available, icon fallback.
  Widget _buildEnemyContent(
      TdEnemy enemy, TdDungeonDef dungeon, bool isBeingHit, double size) {
    final imagePath = _enemyImagePath(enemy, dungeon);
    if (imagePath != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            imagePath,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _enemyIconFallback(enemy, dungeon),
          ),
          // Hit flash overlay
          if (isBeingHit)
            Container(color: Colors.white.withValues(alpha: 0.6)),
        ],
      );
    }
    return _enemyIconFallback(enemy, dungeon);
  }

  /// Fallback: original icon-based enemy rendering.
  Widget _enemyIconFallback(TdEnemy enemy, TdDungeonDef dungeon) {
    return Center(
      child: Icon(
        TdIcons.getIcon(enemy.isBoss ? dungeon.bossIcon : dungeon.enemyIcon),
        color: Colors.white,
        size: (enemy.isBoss ? 18 : 14) * _uiScale,
      ),
    );
  }

  // -----------------------------------------------------------------------
  // 4b. Hit particles
  // -----------------------------------------------------------------------

  Widget _buildHitParticle(TdHitEvent hit, double laneWidth, double laneHeight) {
    switch (hit.archetype) {
      case TowerArchetype.melee:
        return _buildMeleeHit(hit, laneWidth, laneHeight);
      case TowerArchetype.ranged:
        return _buildRangedHit(hit, laneWidth, laneHeight);
      case TowerArchetype.aoe:
        return _buildAoeHit(hit, laneWidth, laneHeight);
      case TowerArchetype.support:
        return const SizedBox.shrink(); // supports don't generate hits
    }
  }

  /// Melee: a slash arc at the enemy position — quick strike then fades.
  Widget _buildMeleeHit(TdHitEvent hit, double laneWidth, double laneHeight) {
    final progress = hit.progress;
    final enemyVisualX = (1.0 - hit.enemyX) * laneWidth;
    final centerY = laneHeight / 2;

    // Quick flash: full opacity for first 40%, then rapid fade
    final opacity = progress < 0.4 ? 1.0 : (1.0 - ((progress - 0.4) / 0.6)).clamp(0.0, 1.0);
    // Slash swings from small to full size quickly
    final scale = progress < 0.3 ? (0.4 + progress * 2.0) : 1.0;
    // Slight rotation for a "swing" feel
    final angle = -0.3 + progress * 0.6;

    return Positioned(
      left: 0, top: 0, right: 0, bottom: 0,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Slash mark at enemy position
          if (progress < 0.7)
            Positioned(
              left: enemyVisualX - 10,
              top: centerY - 10,
              child: Opacity(
                opacity: opacity,
                child: Transform.scale(
                  scale: scale,
                  child: Transform.rotate(
                    angle: angle,
                    child: Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: hit.attackColor,
                    ),
                  ),
                ),
              ),
            ),
          // Damage number
          ..._buildDamageNumber(hit, enemyVisualX, centerY),
        ],
      ),
    );
  }

  /// Ranged: projectile dot traveling from tower to enemy.
  Widget _buildRangedHit(TdHitEvent hit, double laneWidth, double laneHeight) {
    final progress = hit.progress;
    final towerVisualX = (1.0 - hit.towerX) * laneWidth;
    final enemyVisualX = (1.0 - hit.enemyX) * laneWidth;
    final dotX = towerVisualX + (enemyVisualX - towerVisualX) * progress;
    final centerY = laneHeight / 2;

    final dotSize = hit.isCrit ? 10.0 : 6.0;
    final glowAlpha = hit.isCrit ? 0.8 : 0.6;

    return Positioned(
      left: 0, top: 0, right: 0, bottom: 0,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Projectile dot (first 60% of animation)
          if (progress < 0.6)
            Positioned(
              left: dotX - dotSize / 2,
              top: centerY - dotSize / 2,
              child: Container(
                width: dotSize,
                height: dotSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hit.attackColor,
                  boxShadow: [
                    BoxShadow(
                      color: hit.attackColor.withValues(alpha: glowAlpha),
                      blurRadius: hit.isCrit ? 10 : 6,
                      spreadRadius: hit.isCrit ? 2 : 1,
                    ),
                  ],
                ),
              ),
            ),
          // Damage number
          ..._buildDamageNumber(hit, enemyVisualX, centerY),
        ],
      ),
    );
  }

  /// AoE: horizontal wave ripple across the lane at enemy Y position.
  Widget _buildAoeHit(TdHitEvent hit, double laneWidth, double laneHeight) {
    final progress = hit.progress;
    final enemyVisualX = (1.0 - hit.enemyX) * laneWidth;
    final centerY = laneHeight / 2;
    final opacity = (1.0 - progress).clamp(0.0, 1.0);
    final waveWidth = laneWidth * 0.4 * (0.3 + progress * 0.7); // expands

    return Positioned(
      left: 0, top: 0, right: 0, bottom: 0,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Horizontal wave line
          if (progress < 0.7)
            Positioned(
              left: enemyVisualX - waveWidth / 2,
              top: centerY - 1,
              child: Opacity(
                opacity: opacity * 0.7,
                child: Container(
                  width: waveWidth,
                  height: 2,
                  decoration: BoxDecoration(
                    color: hit.attackColor,
                    borderRadius: BorderRadius.circular(1),
                    boxShadow: [
                      BoxShadow(
                        color: hit.attackColor.withValues(alpha: 0.4),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // Damage number
          ..._buildDamageNumber(hit, enemyVisualX, centerY),
        ],
      ),
    );
  }

  /// Shared damage number widgets (float up, fade out, colored by attackColor).
  List<Widget> _buildDamageNumber(TdHitEvent hit, double enemyVisualX, double centerY) {
    final progress = hit.progress;
    final dmgOpacity = (1.0 - progress).clamp(0.0, 1.0);
    final dmgY = centerY - 20 * progress;

    if (progress <= 0.3) return const [];

    return [
      Positioned(
        left: enemyVisualX - 16,
        top: dmgY - 8,
        child: Opacity(
          opacity: dmgOpacity,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hit.isCrit)
                Text(
                  'CRIT!',
                  style: GoogleFonts.rajdhani(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: hit.attackColor,
                  ),
                ),
              Text(
                '-${hit.damage.round()}',
                style: GoogleFonts.rajdhani(
                  fontSize: hit.isCrit ? 14 : 12,
                  fontWeight: FontWeight.w700,
                  color: hit.attackColor,
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  // -----------------------------------------------------------------------
  // 5. Towers (in lanes)
  // -----------------------------------------------------------------------

  List<Widget> _buildLaneTowers(int laneIndex, double laneWidth, double laneHeight) {
    final laneTowers = <Widget>[];

    // Count how many towers are at each slot for vertical stacking
    final slotCounts = <int, int>{};
    final slotIndexMap = <int, int>{}; // towerIndex -> nth tower in that slot
    for (var i = 0; i < _game.towers.length; i++) {
      final tower = _game.towers[i];
      if (tower.laneIndex != laneIndex) continue;
      final slot = tower.slotIndex;
      slotIndexMap[i] = slotCounts[slot] ?? 0;
      slotCounts[slot] = (slotCounts[slot] ?? 0) + 1;
    }

    for (var i = 0; i < _game.towers.length; i++) {
      final tower = _game.towers[i];
      if (tower.laneIndex != laneIndex) continue;

      final nInSlot = slotCounts[tower.slotIndex] ?? 1;
      final indexInSlot = slotIndexMap[i] ?? 0;

      // Position tower at its slot: slotPosition maps 0.0-1.0 where
      // 0.0=spawn (right), 1.0=goal (left). Visual left = (1 - pos) * width.
      final scale = _uiScale;
      final towerSize = 44 * scale;
      final visualLeft = (1.0 - tower.slotPosition) * laneWidth - (20 * scale); // center the tower

      // Vertical stacking: spread towers evenly within the lane height
      double top;
      if (nInSlot == 1) {
        top = (laneHeight - 40 * scale) / 2 - 6;
      } else {
        // Distribute vertically with some padding
        final totalHeight = nInSlot * (46.0 * scale);
        final startY = (laneHeight - totalHeight) / 2;
        top = startY + indexInSlot * (46.0 * scale);
      }

      final towerColor = tower.color;

      laneTowers.add(
        Positioned(
          left: visualLeft.clamp(4, laneWidth - towerSize),
          top: top.clamp(0, laneHeight - (50 * scale)),
          child: Draggable<int>(
            data: i,
            feedback: Material(
              color: Colors.transparent,
              child: _buildTowerWithName(tower, towerColor, isDragging: true),
            ),
            childWhenDragging: Opacity(
              opacity: 0.3,
              child: _buildTowerWithName(tower, towerColor),
            ),
            child: _buildTowerWithName(tower, towerColor),
          ),
        ),
      );
    }
    return laneTowers;
  }

  Widget _buildTowerCircle(TdTower tower, Color towerColor, {bool isDragging = false}) {
    final isSupport = tower.archetype == TowerArchetype.support;
    final glowColor = isSupport ? tower.attackColor : towerColor;
    final isDebuffed = tower.isDebuffed;
    final hasActiveAbility = tower.activeAbilityActive;
    final hasUltimate = tower.ultimateActive;
    final isStealthed = tower.isStealthed;

    final scale = _uiScale;
    return SizedBox(
      width: 44 * scale,
      height: 44 * scale,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Ultimate active — golden pulsing glow ring (outermost)
          if (hasUltimate)
            Container(
              width: 44 * scale,
              height: 44 * scale,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFFFFD700).withValues(alpha: 0.9),
                  width: 2.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFFD700).withValues(alpha: 0.5),
                    blurRadius: 14,
                    spreadRadius: 4,
                  ),
                  BoxShadow(
                    color: towerColor.withValues(alpha: 0.3),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          // Active ability running — class-colored bright glow
          if (hasActiveAbility && !hasUltimate)
            Container(
              width: 44 * scale,
              height: 44 * scale,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: towerColor.withValues(alpha: 0.9),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: towerColor.withValues(alpha: 0.45),
                    blurRadius: 10,
                    spreadRadius: 3,
                  ),
                ],
              ),
            ),
          // Stealth — semi-transparent appearance
          if (isStealthed)
            Container(
              width: 44 * scale,
              height: 44 * scale,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.purple.withValues(alpha: 0.3),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          // Debuff red ring (behind the tower)
          if (isDebuffed)
            Container(
              width: 44 * scale,
              height: 44 * scale,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFFFF5E5B).withValues(alpha: 0.7),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF5E5B).withValues(alpha: 0.25),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          // Tower circle (always class-colored)
          Container(
            width: 40 * scale,
            height: 40 * scale,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: hasUltimate
                    ? const Color(0xFFFFD700).withValues(alpha: 0.9)
                    : hasActiveAbility
                        ? towerColor.withValues(alpha: 0.9)
                        : towerColor.withValues(alpha: isDragging ? 0.90 : 0.50),
                width: (hasUltimate || hasActiveAbility) ? 2.5 : 2,
              ),
              boxShadow: [
                if (isDragging)
                  BoxShadow(
                    color: towerColor.withValues(alpha: 0.40),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                if (isSupport && !isDragging && !hasUltimate && !hasActiveAbility)
                  BoxShadow(
                    color: glowColor.withValues(alpha: 0.35),
                    blurRadius: 10,
                    spreadRadius: 3,
                  ),
              ],
            ),
            child: ClipOval(
              child: tower.character.avatarUrl != null
                  ? (tower.character.avatarUrl!.startsWith('asset:')
                      ? Image.asset(
                          tower.character.avatarUrl!.substring(6),
                          fit: BoxFit.cover,
                          width: 40 * scale,
                          height: 40 * scale,
                          errorBuilder: (_, __, ___) => _towerFallback(tower, towerColor),
                        )
                      : CachedNetworkImage(
                          imageUrl: tower.character.avatarUrl!,
                          fit: BoxFit.cover,
                          width: 40 * scale,
                          height: 40 * scale,
                          placeholder: (_, __) => _towerFallback(tower, towerColor),
                          errorWidget: (_, __, ___) => _towerFallback(tower, towerColor),
                        ))
                  : _towerFallback(tower, towerColor),
            ),
          ),
          // Small debuff icon overlay (bottom-right)
          if (isDebuffed)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF5E5B),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.background, width: 1.5),
                ),
                child: const Icon(
                  Icons.arrow_downward_rounded,
                  size: 8,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _towerFallback(TdTower tower, Color towerColor) {
    final classIcon = TdClassIcons.assetPath(tower.character.characterClass);
    final scale = _uiScale;
    return Container(
      width: 40 * scale,
      height: 40 * scale,
      color: towerColor.withValues(alpha: 0.15),
      child: classIcon != null
          ? Image.asset(
              classIcon,
              width: 28 * scale, height: 28 * scale, fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Center(
                child: Text(
                  tower.character.name.isNotEmpty ? tower.character.name[0].toUpperCase() : '?',
                  style: GoogleFonts.rajdhani(
                    fontSize: 18, fontWeight: FontWeight.w700, color: towerColor,
                  ),
                ),
              ),
            )
          : Center(
              child: Text(
                tower.character.name.isNotEmpty ? tower.character.name[0].toUpperCase() : '?',
                style: GoogleFonts.rajdhani(
                  fontSize: 18, fontWeight: FontWeight.w700, color: towerColor,
                ),
              ),
            ),
    );
  }

  Widget _buildTowerWithName(TdTower tower, Color towerColor, {bool isDragging = false}) {
    // Determine ability status label
    String? abilityLabel;
    Color? abilityLabelColor;
    if (tower.ultimateActive && tower.ultimateAbility != null) {
      abilityLabel = tower.ultimateAbility!.name;
      abilityLabelColor = const Color(0xFFFFD700);
    } else if (tower.activeAbilityActive && tower.activeAbility != null) {
      abilityLabel = tower.activeAbility!.name;
      abilityLabelColor = towerColor;
    } else if (tower.isStealthed) {
      abilityLabel = 'Stealth';
      abilityLabelColor = Colors.purple;
    } else if (tower.currentForm != null) {
      abilityLabel = '${tower.currentForm![0].toUpperCase()}${tower.currentForm!.substring(1)} Form';
      abilityLabelColor = towerColor;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildTowerCircle(tower, towerColor, isDragging: isDragging),
        const SizedBox(height: 2),
        if (abilityLabel != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: abilityLabelColor!.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: abilityLabelColor.withValues(alpha: 0.5),
                width: 0.5,
              ),
            ),
            child: Text(
              abilityLabel.length > 10
                  ? '${abilityLabel.substring(0, 9)}..'
                  : abilityLabel,
              style: GoogleFonts.rajdhani(
                fontSize: 8,
                fontWeight: FontWeight.w700,
                color: abilityLabelColor,
                letterSpacing: 0.5,
              ),
            ),
          )
        else
          Text(
            tower.character.name.length > 7
                ? '${tower.character.name.substring(0, 6)}..'
                : tower.character.name,
            style: GoogleFonts.rajdhani(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: towerColor.withValues(alpha: 0.8),
            ),
          ),
      ],
    );
  }

  // -----------------------------------------------------------------------
  // 6. Tower info bar
  // -----------------------------------------------------------------------

  // ---- Targeting mode state ----
  bool _isTargeting = false;
  int _targetingTowerIndex = -1;
  bool _targetingIsUltimate = false;
  String _targetingType = ''; // "enemy", "lane", "tower"

  void _enterTargetingMode(int towerIndex, bool isUltimate) {
    final tower = _game.towers[towerIndex];
    final ability = isUltimate ? tower.ultimateAbility : tower.activeAbility;
    if (ability == null || ability.isInstant) return;

    // Pause the game
    _ticker.stop();

    setState(() {
      _isTargeting = true;
      _targetingTowerIndex = towerIndex;
      _targetingIsUltimate = isUltimate;
      _targetingType = ability.targeting;
    });
  }

  void _cancelTargeting() {
    setState(() {
      _isTargeting = false;
      _targetingTowerIndex = -1;
      _targetingType = '';
    });
    // Resume the game
    _lastElapsed = Duration.zero;
    _ticker.stop();
    _ticker.start();
  }

  void _confirmTarget({String? enemyId, int? lane, int? towerIdx}) {
    if (_targetingIsUltimate) {
      _game.castUltimate(_targetingTowerIndex,
          targetEnemyId: enemyId, targetLane: lane, targetTowerIndex: towerIdx);
    } else {
      _game.castActiveAbility(_targetingTowerIndex,
          targetEnemyId: enemyId, targetLane: lane, targetTowerIndex: towerIdx);
    }
    _cancelTargeting();
  }

  /// Cast an ability — enters targeting mode for targeted abilities,
  /// auto-casts for instant abilities.
  void _castWithAutoTarget(int towerIndex, bool isUltimate) {
    final tower = _game.towers[towerIndex];
    final ability = isUltimate ? tower.ultimateAbility : tower.activeAbility;
    if (ability == null) return;

    if (ability.isInstant) {
      if (isUltimate) {
        _game.castUltimate(towerIndex);
      } else {
        _game.castActiveAbility(towerIndex);
      }
    } else {
      // Targeted ability → enter targeting mode (pauses game)
      _enterTargetingMode(towerIndex, isUltimate);
    }
  }

  // -----------------------------------------------------------------------
  // Targeting overlay — pauses game, shows valid targets
  // -----------------------------------------------------------------------

  /// Floating header shown during targeting mode (ability name, description, cancel).
  Widget _buildTargetingHeader() {
    final tower = _game.towers[_targetingTowerIndex];
    final ability = _targetingIsUltimate
        ? tower.ultimateAbility
        : tower.activeAbility;
    final towerColor = tower.color;
    final scale = _uiScale;

    return Container(
      color: Colors.black87,
      padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 6 * scale),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Ability indicator dot
              Container(
                width: 10 * scale,
                height: 10 * scale,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _targetingIsUltimate
                      ? const Color(0xFFFFD700)
                      : towerColor,
                  boxShadow: [
                    BoxShadow(
                      color: (_targetingIsUltimate
                              ? const Color(0xFFFFD700)
                              : towerColor)
                          .withValues(alpha: 0.5),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8 * scale),
              // Ability name + targeting instruction
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ability?.name ?? '',
                      style: GoogleFonts.rajdhani(
                        fontSize: 16 * scale,
                        fontWeight: FontWeight.w700,
                        color: _targetingIsUltimate
                            ? const Color(0xFFFFD700)
                            : towerColor,
                      ),
                    ),
                    Text(
                      'Tap ${_targetingType == 'enemy' ? 'an enemy' : _targetingType == 'lane' ? 'a lane' : 'a tower'} to cast',
                      style: GoogleFonts.rajdhani(
                        fontSize: 11 * scale,
                        color: Colors.white60,
                      ),
                    ),
                  ],
                ),
              ),
              // Cancel button
              GestureDetector(
                onTap: _cancelTargeting,
                child: Container(
                  padding: EdgeInsets.symmetric(
                      horizontal: 12 * scale, vertical: 6 * scale),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.6),
                    ),
                  ),
                  child: Text(
                    'CANCEL',
                    style: GoogleFonts.rajdhani(
                      fontSize: 12 * scale,
                      fontWeight: FontWeight.w700,
                      color: Colors.red.shade300,
                    ),
                  ),
                ),
              ),
            ],
          ),
          // Ability description
          if (ability != null && ability.description.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: 4 * scale, left: 18 * scale),
              child: Text(
                ability.description,
                style: GoogleFonts.inter(
                  fontSize: 11 * scale,
                  color: Colors.white54,
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }

  /// Lane targeting: 3 tappable lane strips with dim overlay.
  Widget _buildLaneTargeting(Color towerColor) {
    return Column(
      children: List.generate(3, (lane) {
        final enemyCount =
            _game.enemies.where((e) => !e.isDead && e.laneIndex == lane).length;
        return Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _confirmTarget(lane: lane),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                border: Border(
                  bottom: lane < 2
                      ? BorderSide(
                          color: towerColor.withValues(alpha: 0.3), width: 1)
                      : BorderSide.none,
                ),
              ),
              child: Center(
                child: Container(
                  padding: EdgeInsets.symmetric(
                      horizontal: 20 * _uiScale, vertical: 10 * _uiScale),
                  decoration: BoxDecoration(
                    color: towerColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: towerColor.withValues(alpha: 0.6),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'LANE ${lane + 1}',
                        style: GoogleFonts.rajdhani(
                          fontSize: 18 * _uiScale,
                          fontWeight: FontWeight.w700,
                          color: towerColor,
                          letterSpacing: 2,
                        ),
                      ),
                      if (enemyCount > 0)
                        Text(
                          '$enemyCount ${enemyCount == 1 ? 'enemy' : 'enemies'}',
                          style: GoogleFonts.rajdhani(
                            fontSize: 12 * _uiScale,
                            color: Colors.white70,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  /// Enemy targeting: tappable enemies over a dimmed game field.
  Widget _buildEnemyTargeting(Color towerColor) {
    final liveEnemies =
        _game.enemies.where((e) => !e.isDead && e.position >= 0).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalHeight = constraints.maxHeight;
        final laneHeight = totalHeight / 3;
        final laneWidth = constraints.maxWidth;
        final scale = _uiScale;

        // ── Pass 1: compute raw positions for all enemies ──
        final n = liveEnemies.length;
        final outerSizes = List<double>.generate(
            n, (i) => (liveEnemies[i].isBoss ? 52.0 : 36.0) * scale);
        final lefts = List<double>.generate(
            n,
            (i) => ((1.0 - liveEnemies[i].position) *
                    (laneWidth - outerSizes[i]))
                .clamp(0.0, laneWidth - outerSizes[i]));
        final originalTops = List<double>.generate(
            n,
            (i) =>
                liveEnemies[i].laneIndex * laneHeight +
                (laneHeight - outerSizes[i]) / 2);
        final adjustedTops = List<double>.from(originalTops);

        // ── Pass 2: resolve overlaps per lane ──
        for (var lane = 0; lane < 3; lane++) {
          final indices = <int>[];
          for (var i = 0; i < n; i++) {
            if (liveEnemies[i].laneIndex == lane) indices.add(i);
          }
          if (indices.length <= 1) continue;

          indices.sort((a, b) => lefts[a].compareTo(lefts[b]));

          // Cluster enemies whose selector circles overlap horizontally
          final clusters = <List<int>>[
            [indices.first]
          ];
          for (var j = 1; j < indices.length; j++) {
            final prev = clusters.last.last;
            final curr = indices[j];
            final centerDist = (lefts[curr] + outerSizes[curr] / 2) -
                (lefts[prev] + outerSizes[prev] / 2);
            final overlapThresh =
                (outerSizes[curr] + outerSizes[prev]) / 2;
            if (centerDist.abs() < overlapThresh) {
              clusters.last.add(curr);
            } else {
              clusters.add([curr]);
            }
          }

          // Fan out each overlapping cluster vertically within the lane
          for (final cluster in clusters) {
            if (cluster.length <= 1) continue;
            final maxSize =
                cluster.map((i) => outerSizes[i]).reduce(max);
            final spacing = maxSize + 4.0 * scale;
            final totalSpread = cluster.length * spacing;
            final laneTop = lane * laneHeight;
            final startY = laneTop + (laneHeight - totalSpread) / 2;

            for (var k = 0; k < cluster.length; k++) {
              final idx = cluster[k];
              adjustedTops[idx] = (startY + k * spacing).clamp(
                  laneTop, laneTop + laneHeight - outerSizes[idx]);
            }
          }
        }

        // ── Connector lines from offset selectors to actual positions ──
        final connectorFrom = <Offset>[];
        final connectorTo = <Offset>[];
        for (var i = 0; i < n; i++) {
          if ((adjustedTops[i] - originalTops[i]).abs() > 1.0) {
            connectorFrom.add(Offset(
              lefts[i] + outerSizes[i] / 2,
              adjustedTops[i] + outerSizes[i] / 2,
            ));
            connectorTo.add(Offset(
              lefts[i] + outerSizes[i] / 2,
              originalTops[i] + outerSizes[i] / 2,
            ));
          }
        }

        return Stack(
          children: [
            // Dim background
            Positioned.fill(
              child: Container(color: Colors.black.withValues(alpha: 0.5)),
            ),
            // Connector lines (rendered behind selectors)
            if (connectorFrom.isNotEmpty)
              Positioned.fill(
                child: CustomPaint(
                  painter: _TargetConnectorPainter(
                    fromPoints: connectorFrom,
                    toPoints: connectorTo,
                    color: towerColor,
                  ),
                ),
              ),
            // Tappable enemies at adjusted positions
            for (var i = 0; i < n; i++)
              Builder(builder: (_) {
                final enemy = liveEnemies[i];
                final outerSize = outerSizes[i];
                final innerSize =
                    (enemy.isBoss ? 44.0 : 28.0) * scale;
                final baseColor = enemy.isBoss
                    ? _game.keystone.dungeon.bossColor
                    : _game.keystone.dungeon.enemyColor;

                return Positioned(
                  left: lefts[i],
                  top: adjustedTops[i],
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _confirmTarget(enemyId: enemy.id),
                    child: Container(
                      width: outerSize,
                      height: outerSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: towerColor.withValues(alpha: 0.9),
                          width: 2.5 * scale,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: towerColor.withValues(alpha: 0.4),
                            blurRadius: 10 * scale,
                            spreadRadius: 2 * scale,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Container(
                          width: innerSize,
                          height: innerSize,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: baseColor.withValues(alpha: 0.8),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (enemy.isBoss)
                                Icon(Icons.dangerous_rounded,
                                    size: 16 * scale,
                                    color: Colors.white),
                              Text(
                                '${(enemy.hpFraction * 100).round()}%',
                                style: GoogleFonts.rajdhani(
                                  fontSize:
                                      (enemy.isBoss ? 13 : 11) * scale,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            // Lane dividers
            for (var i = 0; i < 2; i++)
              Positioned(
                left: 0,
                right: 0,
                top: (i + 1) * laneHeight,
                child: Container(
                  height: 1,
                  color: Colors.white12,
                ),
              ),
          ],
        );
      },
    );
  }

  /// Tower targeting: tappable allied towers over a dimmed game field.
  Widget _buildTowerTargeting(Color casterColor) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalHeight = constraints.maxHeight;
        final laneHeight = totalHeight / 3;
        final laneWidth = constraints.maxWidth;
        final size = 48.0 * _uiScale;

        // Count towers per (lane, slot) for vertical stacking
        final slotCounts = <String, int>{};
        final slotIndexMap = <int, int>{};
        for (var i = 0; i < _game.towers.length; i++) {
          final t = _game.towers[i];
          if (t.laneIndex < 0) continue;
          final key = '${t.laneIndex}_${t.slotIndex}';
          slotIndexMap[i] = slotCounts[key] ?? 0;
          slotCounts[key] = (slotCounts[key] ?? 0) + 1;
        }

        return Stack(
          children: [
            // Dim background
            Positioned.fill(
              child: Container(color: Colors.black.withValues(alpha: 0.5)),
            ),
            // Tappable towers with vertical stacking for same-slot overlap
            for (var i = 0; i < _game.towers.length; i++)
              if (_game.towers[i].laneIndex >= 0)
                Builder(builder: (_) {
                  final t = _game.towers[i];
                  final slotX = (1.0 - t.slotPosition) * laneWidth;
                  final left = (slotX - size / 2).clamp(0.0, laneWidth - size);

                  // Vertical stacking when multiple towers share a slot
                  final key = '${t.laneIndex}_${t.slotIndex}';
                  final nInSlot = slotCounts[key] ?? 1;
                  final indexInSlot = slotIndexMap[i] ?? 0;
                  double top;
                  if (nInSlot == 1) {
                    top = t.laneIndex * laneHeight + (laneHeight - size) / 2;
                  } else {
                    final spacing = size + 4.0;
                    final totalSpread = nInSlot * spacing;
                    final laneTop = t.laneIndex * laneHeight;
                    final startY = laneTop + (laneHeight - totalSpread) / 2;
                    top = (startY + indexInSlot * spacing)
                        .clamp(laneTop, laneTop + laneHeight - size);
                  }

                  final tColor = t.color;
                  final idx = i;

                  return Positioned(
                    left: left,
                    top: top,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _confirmTarget(towerIdx: idx),
                      child: Container(
                        width: size,
                        height: size,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: tColor.withValues(alpha: 0.2),
                          border: Border.all(
                            color: casterColor.withValues(alpha: 0.9),
                            width: 2.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: casterColor.withValues(alpha: 0.4),
                              blurRadius: 10,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                t.character.name.length > 5
                                    ? t.character.name.substring(0, 4)
                                    : t.character.name,
                                style: GoogleFonts.rajdhani(
                                  fontSize: 11 * _uiScale,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                t.isDebuffed ? 'DEBUFFED' : t.archetype.name.toUpperCase(),
                                style: GoogleFonts.rajdhani(
                                  fontSize: 8 * _uiScale,
                                  color: t.isDebuffed
                                      ? Colors.red.shade300
                                      : Colors.white54,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
            // Lane dividers
            for (var i = 0; i < 2; i++)
              Positioned(
                left: 0,
                right: 0,
                top: (i + 1) * laneHeight,
                child: Container(
                  height: 1,
                  color: Colors.white12,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildTowerInfoBar() {
    final scale = _uiScale;
    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(_game.towers.length, (i) {
          final tower = _game.towers[i];
          final towerColor = tower.color;
          return Expanded(
            child: _buildAbilityCell(tower, i, towerColor, scale),
          );
        }),
      ),
    );
  }

  Widget _buildAbilityCell(TdTower tower, int index, Color towerColor, double scale) {
    final active = tower.activeAbility;
    final ultimate = tower.ultimateAbility;
    final cellWidth = 52.0 * scale;

    return SizedBox(
      width: cellWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Active ability button (separate tap zone) ──
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (active == null || !tower.canUseActive) return;
              _castWithAutoTarget(index, false);
            },
            child: SizedBox(
              width: 36 * scale,
              height: 36 * scale,
              child: Stack(
                children: [
                  // Background circle
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: tower.canUseActive
                          ? towerColor.withValues(alpha: 0.15)
                          : AppTheme.surface,
                      border: Border.all(
                        color: tower.canUseActive
                            ? towerColor.withValues(alpha: 0.9)
                            : AppTheme.textTertiary.withValues(alpha: 0.3),
                        width: tower.canUseActive ? 2.0 : 1.0,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        active?.name.substring(0, 1) ?? '?',
                        style: GoogleFonts.rajdhani(
                          fontSize: 14 * scale,
                          fontWeight: FontWeight.w700,
                          color: tower.canUseActive
                              ? Colors.white
                              : AppTheme.textTertiary,
                        ),
                      ),
                    ),
                  ),
                  // Cooldown sweep overlay
                  if (active != null && tower.activeCooldownRemaining > 0)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _CooldownSweepPainter(
                          progress: tower.activeCooldownRemaining / active.cooldown,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                  // Cooldown text
                  if (active != null && tower.activeCooldownRemaining > 0)
                    Center(
                      child: Text(
                        tower.activeCooldownRemaining.ceil().toString(),
                        style: GoogleFonts.rajdhani(
                          fontSize: 11 * scale,
                          fontWeight: FontWeight.w700,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Divider in class color
          Container(
            width: 30 * scale,
            height: 1,
            margin: const EdgeInsets.symmetric(vertical: 2),
            color: towerColor.withValues(alpha: 0.4),
          ),
          // ── Ultimate button (separate tap zone) ──
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (ultimate == null || !tower.canUseUltimate) return;
              _castWithAutoTarget(index, true);
            },
            child: SizedBox(
              width: 28 * scale,
              height: 28 * scale,
              child: Stack(
                children: [
                  // Charge ring
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _ChargeRingPainter(
                        progress: tower.ultimateChargeProgress,
                        color: towerColor,
                        isReady: tower.canUseUltimate,
                      ),
                    ),
                  ),
                  // Ultimate icon
                  Center(
                    child: Text(
                      ultimate?.name.substring(0, 1) ?? '?',
                      style: GoogleFonts.rajdhani(
                        fontSize: 10 * scale,
                        fontWeight: FontWeight.w700,
                        color: tower.canUseUltimate
                            ? const Color(0xFFFFD700)
                            : AppTheme.textTertiary.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Tower name
          Text(
            tower.character.name.length > 6
                ? tower.character.name.substring(0, 5)
                : tower.character.name,
            style: GoogleFonts.rajdhani(
              fontSize: 8,
              fontWeight: FontWeight.w600,
              color: AppTheme.textTertiary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _infoBarFallback(TdTower tower, Color towerColor) {
    final classIcon = TdClassIcons.assetPath(tower.character.characterClass);
    final scale = _uiScale;
    return Container(
      width: 28 * scale,
      height: 28 * scale,
      color: towerColor.withValues(alpha: 0.15),
      child: classIcon != null
          ? Image.asset(
              classIcon,
              width: 20 * scale, height: 20 * scale, fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Center(
                child: Text(
                  tower.character.name.isNotEmpty ? tower.character.name[0].toUpperCase() : '?',
                  style: GoogleFonts.rajdhani(
                    fontSize: 13, fontWeight: FontWeight.w700, color: towerColor,
                  ),
                ),
              ),
            )
          : Center(
              child: Text(
                tower.character.name.isNotEmpty ? tower.character.name[0].toUpperCase() : '?',
                style: GoogleFonts.rajdhani(
                  fontSize: 13, fontWeight: FontWeight.w700, color: towerColor,
                ),
              ),
            ),
    );
  }

  Widget _dialogAvatarFallback(WowCharacter character, Color classColor, double size) {
    final classIcon = TdClassIcons.assetPath(character.characterClass);
    return Container(
      width: size,
      height: size,
      color: classColor.withValues(alpha: 0.15),
      child: classIcon != null
          ? Center(
              child: Image.asset(
                classIcon,
                width: size * 0.6, height: size * 0.6, fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Text(
                  character.name.isNotEmpty ? character.name[0].toUpperCase() : '?',
                  style: GoogleFonts.rajdhani(
                    fontSize: size * 0.45, fontWeight: FontWeight.w700, color: classColor,
                  ),
                ),
              ),
            )
          : Center(
              child: Text(
                character.name.isNotEmpty ? character.name[0].toUpperCase() : '?',
                style: GoogleFonts.rajdhani(
                  fontSize: size * 0.45, fontWeight: FontWeight.w700, color: classColor,
                ),
              ),
            ),
    );
  }

  // -----------------------------------------------------------------------
  // 8. Overlays
  // -----------------------------------------------------------------------

  Widget _buildSetupBanner() {
    return Container(
      color: AppTheme.surfaceElevated,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.swap_vert_rounded, color: AppTheme.textSecondary, size: 18),
          const SizedBox(width: 8),
          Text(
            'DRAG TO FRONT / MID / BACK SLOTS IN LANES',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSetupBottomBar() {
    final unassigned = _game.towers.where((t) => t.laneIndex < 0).toList();
    final allDeployed = unassigned.isEmpty;

    return Container(
      color: AppTheme.surface,
      padding: EdgeInsets.fromLTRB(
        16, 12, 16,
        MediaQuery.of(context).padding.bottom + 12,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Unassigned tower dock
          if (unassigned.isNotEmpty) ...[
            Text(
              'DRAG TO A LANE',
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppTheme.textTertiary,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: unassigned.map((tower) {
                final towerIndex = _game.towers.indexOf(tower);
                final towerColor = tower.color;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Draggable<int>(
                    data: towerIndex,
                    feedback: Material(
                      color: Colors.transparent,
                      child: _buildTowerWithName(tower, towerColor, isDragging: true),
                    ),
                    childWhenDragging: Opacity(
                      opacity: 0.3,
                      child: _buildTowerWithName(tower, towerColor),
                    ),
                    child: _buildTowerWithName(tower, towerColor),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
          ],
          // Begin button
          GestureDetector(
            onTap: allDeployed
                ? () {
                    _game.beginGame();
                    if (_audio != null && _game.sfxEvents.isNotEmpty) {
                      _audio!.playEvents(_game.sfxEvents);
                    }
                    _lastElapsed = Duration.zero;
                    _ticker.start();
                  }
                : null,
            child: Container(
              width: double.infinity,
              height: 48,
              decoration: BoxDecoration(
                color: allDeployed
                    ? const Color(0xFFA335EE)
                    : AppTheme.surfaceElevated,
                borderRadius: BorderRadius.circular(10),
                border: allDeployed
                    ? null
                    : Border.all(color: AppTheme.surfaceBorder),
                boxShadow: allDeployed
                    ? [
                        BoxShadow(
                          color: const Color(0xFFA335EE).withValues(alpha: 0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: Text(
                  allDeployed
                      ? 'BEGIN WAVE 1'
                      : 'DEPLOY ${unassigned.length} MORE',
                  style: GoogleFonts.rajdhani(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: allDeployed ? Colors.white : AppTheme.textTertiary,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWaveClearBanner() {
    final nextWave = _game.currentWave + 1;
    final isBossWave = nextWave == _game.totalWaves;

    return Container(
      color: AppTheme.surfaceElevated,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF00FF98).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'WAVE ${_game.currentWave} CLEAR',
              style: GoogleFonts.rajdhani(
                fontSize: 12, fontWeight: FontWeight.w700,
                color: const Color(0xFF00FF98),
              ),
            ),
          ),
          const SizedBox(width: 10),
          if (isBossWave && _game.keystone.dungeon.bossImage != null) ...[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _game.keystone.dungeon.bossColor.withValues(alpha: 0.5),
                  width: 1.5,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: Image.asset(
                  _game.keystone.dungeon.bossImage!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              isBossWave
                  ? 'Next: BOSS WAVE${_game.keystone.hasTyrannical ? " (Tyrannical!)" : ""}'
                  : 'Next: 5–8 enemies${_game.keystone.hasFortified ? " (Fortified)" : ""}',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: isBossWave
                    ? _game.keystone.dungeon.bossColor
                    : AppTheme.textSecondary,
                fontWeight: isBossWave ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          const Icon(Icons.swap_vert_rounded, color: AppTheme.textTertiary, size: 16),
        ],
      ),
    );
  }

  Widget _buildBetweenWavesBottomBar() {
    final nextWave = _game.currentWave + 1;

    return Container(
      color: AppTheme.surface,
      padding: EdgeInsets.fromLTRB(
        16, 12, 16,
        MediaQuery.of(context).padding.bottom + 12,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Tower roster with current lanes
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: _game.towers.map((tower) {
              final towerColor = tower.color;
              final scale = _uiScale;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 28 * scale, height: 28 * scale,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: towerColor.withValues(alpha: 0.5), width: 1.5),
                    ),
                    child: ClipOval(
                      child: tower.character.avatarUrl != null
                          ? (tower.character.avatarUrl!.startsWith('asset:')
                              ? Image.asset(
                                  tower.character.avatarUrl!.substring(6),
                                  fit: BoxFit.cover, width: 28 * scale, height: 28 * scale,
                                  errorBuilder: (_, __, ___) => _infoBarFallback(tower, towerColor),
                                )
                              : CachedNetworkImage(
                                  imageUrl: tower.character.avatarUrl!,
                                  fit: BoxFit.cover, width: 28 * scale, height: 28 * scale,
                                  placeholder: (_, __) => _infoBarFallback(tower, towerColor),
                                  errorWidget: (_, __, ___) => _infoBarFallback(tower, towerColor),
                                ))
                          : _infoBarFallback(tower, towerColor),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'L${tower.laneIndex + 1}',
                    style: GoogleFonts.rajdhani(fontSize: 9, color: towerColor),
                  ),
                ],
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _startNextWave,
            child: Container(
              width: double.infinity,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFFA335EE),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFA335EE).withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  'START WAVE $nextWave',
                  style: GoogleFonts.rajdhani(
                    fontSize: 16, fontWeight: FontWeight.w700,
                    color: Colors.white, letterSpacing: 2,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVictoryOverlay() {
    final stars = _game.starRating;
    final nextLevel = (widget.keystoneLevel + _game.keystoneLevelChange).clamp(2, 999);
    final starColor = stars == 3
        ? const Color(0xFFFFD700) // gold
        : stars == 2
            ? const Color(0xFFC0C0C0) // silver-ish
            : const Color(0xFFCD7F32); // bronze

    return Positioned.fill(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Boss art background
          if (_game.keystone.dungeon.bossImage != null)
            Positioned.fill(
              child: Opacity(
                opacity: 0.30,
                child: Image.asset(
                  _game.keystone.dungeon.bossImage!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
          // Golden vignette overlay
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    AppTheme.background.withValues(alpha: 0.6),
                    AppTheme.background.withValues(alpha: 0.85),
                    AppTheme.background.withValues(alpha: 0.95),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),
          // Golden glow vignette
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFFFD700).withValues(alpha: 0.08),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.7],
                ),
              ),
            ),
          ),
          // Content
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Star rating
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(3, (i) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      i < stars ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: i < stars ? starColor : AppTheme.textTertiary,
                      size: 36,
                    ),
                  )),
                ),
                const SizedBox(height: 12),
                Text(
                  stars == 3 ? 'FLAWLESS' : stars == 2 ? 'CLEAN RUN' : 'KEYSTONE COMPLETE',
                  style: GoogleFonts.rajdhani(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: starColor,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '+${widget.keystoneLevel} \u2022 ${_game.enemiesKilled} kills \u2022 ${_game.lives}/${_game.maxLives} lives',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                // Keystone change
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00FF98).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'KEYSTONE +$stars \u2192 Level $nextLevel',
                    style: GoogleFonts.rajdhani(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF00FF98),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildOutlinedButton('BACK', onTap: () => Navigator.of(context).pop()),
                    const SizedBox(width: 16),
                    _buildPurpleButton(
                      'NEXT: +$nextLevel',
                      onTap: () => Navigator.of(context).pop((
                        cleared: true,
                        lives: _game.lives,
                        stars: _game.starRating,
                      )),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDefeatOverlay() {
    final nextLevel = (widget.keystoneLevel - 1).clamp(2, 999);
    final depleted = widget.keystoneLevel > 2;

    return Positioned.fill(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Boss art background
          if (_game.keystone.dungeon.bossImage != null)
            Positioned.fill(
              child: Opacity(
                opacity: 0.20,
                child: Image.asset(
                  _game.keystone.dungeon.bossImage!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
          // Red-tinted vignette overlay
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    AppTheme.background.withValues(alpha: 0.6),
                    AppTheme.background.withValues(alpha: 0.85),
                    AppTheme.background.withValues(alpha: 0.95),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),
          // Red glow vignette
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    Colors.transparent,
                    const Color(0xFFFF5E5B).withValues(alpha: 0.06),
                  ],
                  stops: const [0.3, 1.0],
                ),
              ),
            ),
          ),
          // Content
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.close, color: Color(0xFFFF5E5B), size: 48),
                const SizedBox(height: 12),
                Text(
                  'DEPLETED',
                  style: GoogleFonts.rajdhani(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFFF5E5B),
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${_game.enemiesKilled} kills \u2022 Wave ${_game.currentWave}/${_game.totalWaves}',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
                if (depleted) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF5E5B).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'KEYSTONE -1 \u2192 Level $nextLevel',
                      style: GoogleFonts.rajdhani(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFFFF5E5B),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildOutlinedButton('BACK', onTap: () => Navigator.of(context).pop()),
                    const SizedBox(width: 16),
                    _buildPurpleButton(
                      'RETRY +$nextLevel',
                      onTap: () => Navigator.of(context).pop((
                        cleared: false,
                        lives: 0,
                        stars: 0,
                      )),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Navigation helpers
  // -----------------------------------------------------------------------

  // Victory/defeat now pop with result — the menu screen drives the loop.

  // -----------------------------------------------------------------------
  // Shared button helpers
  // -----------------------------------------------------------------------

  Widget _buildPurpleButton(String label, {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFA335EE),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: GoogleFonts.rajdhani(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildOutlinedButton(String label, {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: AppTheme.surfaceBorder, width: 1.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: GoogleFonts.rajdhani(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Info sheets
  // -----------------------------------------------------------------------

  void _showTowerInfo(TdTower tower) {
    final classColor = tower.color;
    final avatarSize = 48 * _uiScale;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: AppTheme.surfaceBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            // Avatar + name
            Row(
              children: [
                Container(
                  width: avatarSize, height: avatarSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: classColor, width: 2),
                  ),
                  child: ClipOval(
                    child: tower.character.avatarUrl != null
                        ? (tower.character.avatarUrl!.startsWith('asset:')
                            ? Image.asset(
                                tower.character.avatarUrl!.substring(6),
                                fit: BoxFit.cover, width: avatarSize, height: avatarSize,
                                errorBuilder: (_, __, ___) => _dialogAvatarFallback(tower.character, classColor, avatarSize),
                              )
                            : CachedNetworkImage(
                                imageUrl: tower.character.avatarUrl!,
                                fit: BoxFit.cover, width: avatarSize, height: avatarSize,
                                errorWidget: (_, __, ___) => _dialogAvatarFallback(tower.character, classColor, avatarSize),
                              ))
                        : _dialogAvatarFallback(tower.character, classColor, avatarSize),
                  ),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tower.character.name,
                      style: GoogleFonts.rajdhani(
                        fontSize: 22, fontWeight: FontWeight.w700, color: classColor,
                      ),
                    ),
                    Text(
                      '${tower.character.characterClass} · ${tower.character.activeSpec}',
                      style: GoogleFonts.inter(
                        fontSize: 13, color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Stats
            _infoRow('ARCHETYPE', tower.archetype.name.toUpperCase(), _archetypeDescription(tower.archetype)),
            const SizedBox(height: 10),
            // Attack color swatch
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 110,
                  child: Text(
                    'ATTACK COLOR',
                    style: GoogleFonts.inter(
                      fontSize: 10, fontWeight: FontWeight.w600,
                      color: AppTheme.textTertiary, letterSpacing: 1,
                    ),
                  ),
                ),
                Container(
                  width: 16, height: 16,
                  decoration: BoxDecoration(
                    color: tower.attackColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: tower.attackColor.withValues(alpha: 0.5)),
                    boxShadow: [
                      BoxShadow(color: tower.attackColor.withValues(alpha: 0.4), blurRadius: 4),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _infoRow('ITEM LEVEL', '${tower.character.equippedItemLevel ?? "?"}', null),
            const SizedBox(height: 10),
            _infoRow('BASE DAMAGE', '${tower.baseDamage.toStringAsFixed(1)} / hit', null),
            const SizedBox(height: 10),
            _infoRow('ATTACK SPEED', 'Every ${tower.attackInterval}s', null),
            const SizedBox(height: 10),
            _infoRow('POSITION', tower.laneIndex >= 0
                ? 'Lane ${tower.laneIndex + 1} \u00b7 ${const ['Front', 'Mid', 'Back'][tower.slotIndex.clamp(0, 2)]}'
                : 'Unassigned', null),
            if (tower.passiveName.isNotEmpty && tower.passiveName != 'None') ...[
              const SizedBox(height: 10),
              _infoRow('PASSIVE', tower.passiveName, tower.passiveDescription),
            ],
            if (tower.isDebuffed) ...[
              const SizedBox(height: 10),
              _infoRow('STATUS', 'DEBUFFED', 'Damage reduced by 50%'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value, String? description) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 10, fontWeight: FontWeight.w600,
              color: AppTheme.textTertiary, letterSpacing: 1,
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: GoogleFonts.rajdhani(
                  fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.textPrimary,
                ),
              ),
              if (description != null)
                Text(
                  description,
                  style: GoogleFonts.inter(
                    fontSize: 11, color: AppTheme.textTertiary,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _archetypeDescription(TowerArchetype archetype) {
    switch (archetype) {
      case TowerArchetype.melee:
        return 'High damage, hits the closest enemy in lane';
      case TowerArchetype.ranged:
        return 'Full damage (1.0x), hits the furthest enemy in lane';
      case TowerArchetype.support:
        return 'Does not attack. Buffs adjacent lane towers';
      case TowerArchetype.aoe:
        return 'Reduced damage (0.5x), hits ALL enemies in lane simultaneously';
    }
  }

  static const Map<TdAffix, ({String name, String description, String effect})> _affixInfo = {
    TdAffix.fortified: (
      name: 'Fortified',
      description: 'Non-boss enemies are tougher',
      effect: '+30% HP on regular enemies',
    ),
    TdAffix.tyrannical: (
      name: 'Tyrannical',
      description: 'Boss enemies are significantly stronger',
      effect: '+50% HP on bosses',
    ),
    TdAffix.bolstering: (
      name: 'Bolstering',
      description: 'Killing an enemy empowers its allies',
      effect: 'When an enemy dies, others in that lane gain +10% speed',
    ),
    TdAffix.bursting: (
      name: 'Bursting',
      description: 'Dying enemies lash out at your towers',
      effect: 'Dead enemies debuff towers in their lane for 2s (50% damage reduction)',
    ),
    TdAffix.sanguine: (
      name: 'Sanguine',
      description: 'Fallen enemies leave healing pools',
      effect: 'Dead enemies leave a zone that heals enemies passing through (15% HP/s for 4s)',
    ),
  };

  void _showAffixInfo(TdAffix affix) {
    final info = _affixInfo[affix]!;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFFFA500), width: 1.5),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    info.name.toUpperCase(),
                    style: GoogleFonts.rajdhani(
                      fontSize: 16, fontWeight: FontWeight.w700,
                      color: const Color(0xFFFFA500), letterSpacing: 1,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              info.description,
              style: GoogleFonts.rajdhani(
                fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFFA500).withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.bolt, color: Color(0xFFFFA500), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      info.effect,
                      style: GoogleFonts.inter(
                        fontSize: 13, color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Dungeon modifier info
  // -----------------------------------------------------------------------

  String _modifierDisplayName(String type) {
    const names = {
      'spectral': 'SPECTRAL',
      'shield': 'SHIELDS',
      'resurrect': 'RESURRECT',
      'phase': 'VOID PHASE',
      'frost_aura': 'FROST AURA',
      'lane_switch': 'EVASIVE',
      'ranged_attack': 'RANGED',
      'accelerate': 'ACCELERATE',
    };
    return names[type] ?? type.replaceAll('_', ' ').toUpperCase();
  }

  String _modifierDescription(EffectDef mod) {
    switch (mod.type) {
      case 'spectral':
        final reduction = ((mod.params['damageReduction'] as num? ?? mod.params['dmgReduction'] as num?)?.toDouble() ?? 0.5) * 100;
        final until = ((mod.params['untilPosition'] as num?)?.toDouble() ?? 0.5) * 100;
        return 'Enemies take ${reduction.round()}% less damage until ${until.round()}% through the lane';
      case 'shield':
        final hits = (mod.params['hits'] as num?)?.toInt() ?? 2;
        final chance = ((mod.params['chance'] as num?)?.toDouble() ?? 1.0) * 100;
        return '${chance.round()}% of enemies spawn with a shield absorbing $hits hits';
      case 'resurrect':
        final chance = ((mod.params['chance'] as num?)?.toDouble() ?? 0.3) * 100;
        final hp = ((mod.params['hpFraction'] as num?)?.toDouble() ?? 0.4) * 100;
        return '${chance.round()}% chance to resurrect with ${hp.round()}% HP on death';
      case 'phase':
        final dur = (mod.params['invulnDuration'] as num?)?.toDouble() ?? 0.5;
        final interval = (mod.params['interval'] as num?)?.toDouble() ?? 3.0;
        return 'Enemies phase out for ${dur}s every ${interval}s, becoming invulnerable';
      case 'frost_aura':
        final slow = ((mod.params['slowPercent'] as num?)?.toDouble() ?? 0.05) * 100;
        return 'Enemies slow nearby tower attack speed by ${slow.round()}% (stacks)';
      case 'lane_switch':
        final chance = ((mod.params['chance'] as num?)?.toDouble() ?? 0.4) * 100;
        return '${chance.round()}% chance for enemies to switch lanes mid-path';
      case 'ranged_attack':
        final dmg = (mod.params['damage'] as num?)?.toDouble() ?? 5.0;
        final interval = (mod.params['interval'] as num?)?.toDouble() ?? 3.0;
        return 'Enemies attack towers for ${dmg.round()} damage every ${interval}s';
      case 'accelerate':
        final start = (mod.params['startSpeedMult'] as num?)?.toDouble() ?? 0.5;
        final end = (mod.params['endSpeedMult'] as num?)?.toDouble() ?? 1.5;
        return 'Enemies start at ${start}x speed, accelerate to ${end}x';
      default:
        return mod.type.replaceAll('_', ' ');
    }
  }

  void _showModifierInfo(EffectDef mod) {
    final dungeonColor = _game.keystone.dungeon.enemyColor;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: dungeonColor.withValues(alpha: 0.15),
                border: Border.all(color: dungeonColor.withValues(alpha: 0.4), width: 1.5),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _modifierDisplayName(mod.type),
                style: GoogleFonts.rajdhani(
                  fontSize: 16, fontWeight: FontWeight.w700,
                  color: dungeonColor, letterSpacing: 1,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              _modifierDescription(mod),
              style: GoogleFonts.inter(
                fontSize: 14,
                color: AppTheme.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Dungeon: ${_game.keystone.dungeonName}',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppTheme.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Particle overlay widget — atmospheric particles driven by ParticleDef
// ---------------------------------------------------------------------------

class _Particle {
  double x, y, dx, dy, size, opacity, life, maxLife;
  _Particle({
    required this.x, required this.y,
    required this.dx, required this.dy,
    required this.size, required this.opacity,
    this.life = 0, this.maxLife = 0,
  });
}

class _TdParticleOverlay extends StatefulWidget {
  final ParticleDef config;
  const _TdParticleOverlay({required this.config});

  @override
  State<_TdParticleOverlay> createState() => _TdParticleOverlayState();
}

class _TdParticleOverlayState extends State<_TdParticleOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<_Particle> _particles = [];
  final Random _rng = Random();
  Duration _lastElapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
    _controller.addListener(_onTick);
  }

  void _initParticles(Size size) {
    _particles.clear();
    for (var i = 0; i < widget.config.count; i++) {
      _particles.add(_spawnParticle(size, randomY: true));
    }
  }

  _Particle _spawnParticle(Size size, {bool randomY = true}) {
    final cfg = widget.config;
    final type = cfg.type;
    double x = _rng.nextDouble() * size.width;
    double y = randomY ? _rng.nextDouble() * size.height : -cfg.size;
    double dx = 0, dy = 0;
    double pSize = cfg.size * (0.5 + _rng.nextDouble());
    double pOpacity = cfg.opacity * (0.5 + _rng.nextDouble() * 0.5);
    double maxLife = 0;

    switch (type) {
      case 'wisps':
        dx = (_rng.nextDouble() - 0.5) * cfg.speed * 30;
        dy = -cfg.speed * 20 * (0.5 + _rng.nextDouble() * 0.5);
      case 'snow':
        dx = (_rng.nextDouble() - 0.5) * cfg.speed * 15;
        dy = cfg.speed * 40 * (0.5 + _rng.nextDouble() * 0.5);
        if (!randomY) y = -cfg.size;
      case 'embers':
        dx = (_rng.nextDouble() - 0.5) * cfg.speed * 20;
        dy = -cfg.speed * 60 * (0.5 + _rng.nextDouble() * 0.5);
      case 'void':
        dx = (_rng.nextDouble() - 0.5) * cfg.speed * 5;
        dy = (_rng.nextDouble() - 0.5) * cfg.speed * 5;
      case 'wind':
        dx = cfg.speed * 100 * (0.7 + _rng.nextDouble() * 0.3);
        dy = (_rng.nextDouble() - 0.5) * cfg.speed * 10;
        pSize = cfg.size * (0.3 + _rng.nextDouble() * 0.3);
        if (!randomY) x = -cfg.size * 3;
      case 'leaves':
        dx = cfg.speed * 30 * (0.5 + _rng.nextDouble() * 0.5);
        dy = cfg.speed * 30 * (0.5 + _rng.nextDouble() * 0.5);
        if (!randomY) { x = -cfg.size; y = _rng.nextDouble() * size.height * 0.3; }
      case 'sparks':
        dx = (_rng.nextDouble() - 0.5) * cfg.speed * 80;
        dy = (_rng.nextDouble() - 0.5) * cfg.speed * 80;
        maxLife = 0.5 + _rng.nextDouble() * 0.5;
      default:
        dx = (_rng.nextDouble() - 0.5) * cfg.speed * 20;
        dy = -cfg.speed * 20;
    }

    return _Particle(
      x: x, y: y, dx: dx, dy: dy,
      size: pSize, opacity: pOpacity,
      life: 0, maxLife: maxLife,
    );
  }

  void _onTick() {
    if (!mounted) return;
    final now = _controller.lastElapsedDuration ?? Duration.zero;
    final dt = (now - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = now;
    if (dt <= 0 || dt > 0.5) return;

    final ctx = context;
    final renderBox = ctx.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;
    final size = renderBox.size;

    if (_particles.isEmpty) {
      _initParticles(size);
      return;
    }

    final type = widget.config.type;
    for (var i = 0; i < _particles.length; i++) {
      final p = _particles[i];
      p.x += p.dx * dt;
      p.y += p.dy * dt;
      p.life += dt;

      // Type-specific behaviors
      switch (type) {
        case 'wisps':
          p.dx += ((_rng.nextDouble() - 0.5) * 10) * dt;
          p.opacity = widget.config.opacity * (0.3 + 0.7 * (0.5 + 0.5 * sin(p.life * 2)));
        case 'snow':
          p.dx = sin(p.life * 1.5 + i.toDouble()) * widget.config.speed * 15;
        case 'embers':
          p.opacity = widget.config.opacity * (0.3 + 0.7 * (0.5 + 0.5 * sin(p.life * 5)));
        case 'void':
          p.size = widget.config.size * (0.5 + 0.5 * sin(p.life * 2 + i.toDouble()));
        case 'leaves':
          p.dx += sin(p.life * 2) * widget.config.speed * 5 * dt;
        default:
          break;
      }

      // Wrap or respawn
      bool needsRespawn = false;
      if (type == 'sparks' && p.maxLife > 0 && p.life >= p.maxLife) {
        needsRespawn = true;
      } else if (p.x < -20 || p.x > size.width + 20 ||
          p.y < -20 || p.y > size.height + 20) {
        needsRespawn = true;
      }

      if (needsRespawn) {
        _particles[i] = _spawnParticle(size, randomY: false);
      }
    }

    setState(() {});
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ParticlePainter(
        particles: _particles,
        color: widget.config.color,
      ),
    );
  }
}

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final Color color;

  _ParticlePainter({required this.particles, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final paint = Paint()
        ..color = color.withValues(alpha: p.opacity.clamp(0.0, 1.0))
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(p.x, p.y), p.size, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter oldDelegate) => true;
}

// ---------------------------------------------------------------------------
// Ability Dock painters
// ---------------------------------------------------------------------------

/// Radial clockwise sweep painter for active ability cooldowns.
class _CooldownSweepPainter extends CustomPainter {
  final double progress; // 0.0 = ready, 1.0 = full cooldown
  final Color color;

  _CooldownSweepPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    // Sweep from top (12 o'clock) clockwise
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      2 * pi * progress,
      true,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _CooldownSweepPainter old) =>
      old.progress != progress;
}

/// Ring painter showing ultimate charge progress.
class _ChargeRingPainter extends CustomPainter {
  final double progress; // 0.0 to 1.0
  final Color color;
  final bool isReady;

  _ChargeRingPainter({
    required this.progress,
    required this.color,
    required this.isReady,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 2;

    // Background ring
    final bgPaint = Paint()
      ..color = Colors.white12
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawCircle(center, radius, bgPaint);

    if (progress <= 0) return;

    // Charge progress arc
    final fgPaint = Paint()
      ..color = isReady ? const Color(0xFFFFD700) : color.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      2 * pi * progress,
      false,
      fgPaint,
    );

    // Glow when ready
    if (isReady) {
      final glowPaint = Paint()
        ..color = const Color(0xFFFFD700).withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawCircle(center, radius, glowPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ChargeRingPainter old) =>
      old.progress != progress || old.isReady != isReady;
}

/// Draws thin connector lines from offset target selectors to actual positions.
class _TargetConnectorPainter extends CustomPainter {
  final List<Offset> fromPoints;
  final List<Offset> toPoints;
  final Color color;

  _TargetConnectorPainter({
    required this.fromPoints,
    required this.toPoints,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final dotPaint = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;

    for (var i = 0; i < fromPoints.length; i++) {
      canvas.drawLine(fromPoints[i], toPoints[i], linePaint);
      // Small dot at actual position
      canvas.drawCircle(toPoints[i], 3.0, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TargetConnectorPainter old) => true;
}
