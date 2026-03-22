import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/character.dart';
import '../../theme/app_theme.dart';
import '../models/td_models.dart';
import '../td_game_state.dart';

// ---------------------------------------------------------------------------
// TdGameScreen — main gameplay UI
// ---------------------------------------------------------------------------

class TdGameScreen extends StatefulWidget {
  final List<WowCharacter> characters;
  final int keystoneLevel;

  const TdGameScreen({
    super.key,
    required this.characters,
    required this.keystoneLevel,
  });

  @override
  State<TdGameScreen> createState() => _TdGameScreenState();
}

class _TdGameScreenState extends State<TdGameScreen>
    with SingleTickerProviderStateMixin {
  late final TdGameState _game;
  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;
  Timer? _autoResumeTimer;

  // Track which lane is being hovered during a drag.
  int? _dragHoverLane;

  @override
  void initState() {
    super.initState();
    _game = TdGameState();
    _game.startRun(widget.characters, widget.keystoneLevel);
    _game.addListener(_onGameStateChanged);
    // Don't auto-start — let the player position towers first
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _autoResumeTimer?.cancel();
    _ticker.dispose();
    _game.removeListener(_onGameStateChanged);
    _game.dispose();
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
    setState(() {}); // repaint
  }

  void _onGameStateChanged() {
    switch (_game.phase) {
      case TdGamePhase.betweenWaves:
        _ticker.stop();
        _autoResumeTimer?.cancel();
        _autoResumeTimer = Timer(const Duration(seconds: 3), () {
          if (mounted && _game.phase == TdGamePhase.betweenWaves) {
            _startNextWave();
          }
        });
        break;
      case TdGamePhase.victory:
      case TdGamePhase.defeat:
        _ticker.stop();
        break;
      default:
        break;
    }
    if (mounted) setState(() {});
  }

  void _startNextWave() {
    _autoResumeTimer?.cancel();
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
        child: Column(
          children: [
            _buildHeaderBar(),
            _buildAffixBar(),
            Expanded(child: _buildLanes()),
            _buildTowerInfoBar(),
            // Overlay (between waves / victory / defeat)
            // rendered via Stack in the lanes section instead
          ],
        ),
      ),
    );
  }

  // -----------------------------------------------------------------------
  // 1. Header bar
  // -----------------------------------------------------------------------

  Widget _buildHeaderBar() {
    final timerColor = _game.timer > 30
        ? AppTheme.textPrimary
        : _game.timer > 15
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
          // Dungeon name + key level
          Expanded(
            child: Text(
              '${_game.keystone.dungeonName.toUpperCase()} +${_game.keystone.level}',
              style: GoogleFonts.rajdhani(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: const Color(0xFFA335EE), // epic purple
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Wave indicator
          Text(
            'WAVE ${_game.currentWave}/${TdGameState.totalWaves}',
            style: GoogleFonts.rajdhani(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(width: 12),
          // Timer
          Icon(Icons.timer_outlined, color: timerColor, size: 16),
          const SizedBox(width: 4),
          Text(
            '${_game.timer.ceil()}s',
            style: GoogleFonts.rajdhani(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: timerColor,
            ),
          ),
        ],
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
          // Affix chips
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: _game.keystone.affixes.map((a) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFFFA500), width: 1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    a.name.toUpperCase(),
                    style: GoogleFonts.rajdhani(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFFFA500),
                    ),
                  ),
                );
              }).toList(),
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
    return Stack(
      children: [
        Column(
          children: List.generate(3, (lane) {
            return Expanded(
              child: _buildLane(lane),
            );
          }),
        ),
        // Overlays on top of everything
        if (_game.phase == TdGamePhase.setup) _buildSetupOverlay(),
        if (_game.phase == TdGamePhase.betweenWaves) _buildBetweenWavesOverlay(),
        if (_game.phase == TdGamePhase.victory) _buildVictoryOverlay(),
        if (_game.phase == TdGamePhase.defeat) _buildDefeatOverlay(),
      ],
    );
  }

  Widget _buildLane(int laneIndex) {
    final isHovered = _dragHoverLane == laneIndex;

    return DragTarget<int>(
      onWillAcceptWithDetails: (details) {
        setState(() => _dragHoverLane = laneIndex);
        return true;
      },
      onLeave: (_) {
        setState(() {
          if (_dragHoverLane == laneIndex) _dragHoverLane = null;
        });
      },
      onAcceptWithDetails: (details) {
        _game.moveTower(details.data, laneIndex);
        setState(() => _dragHoverLane = null);
      },
      builder: (context, candidateData, rejectedData) {
        return Container(
          decoration: BoxDecoration(
            color: isHovered
                ? const Color(0xFFA335EE).withValues(alpha: 0.08)
                : Colors.transparent,
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

              return Stack(
                clipBehavior: Clip.none,
                children: [
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

                  // Sanguine pools
                  ..._game.sanguinePools
                      .where((p) => p.laneIndex == laneIndex)
                      .map((pool) {
                    final poolLeft = (1.0 - pool.position) * (laneWidth - 60);
                    return Positioned(
                      left: poolLeft.clamp(0, laneWidth - 60),
                      top: laneHeight * 0.25,
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
                    );
                  }),

                  // Enemies
                  ..._game.enemies
                      .where((e) => e.laneIndex == laneIndex && e.position >= 0 && !e.isDead)
                      .map((enemy) => _buildEnemy(enemy, laneWidth, laneHeight)),

                  // Towers placed in this lane
                  ..._buildLaneTowers(laneIndex, laneWidth, laneHeight),
                ],
              );
            },
          ),
        );
      },
    );
  }

  // -----------------------------------------------------------------------
  // 4. Enemies
  // -----------------------------------------------------------------------

  Widget _buildEnemy(TdEnemy enemy, double laneWidth, double laneHeight) {
    // Enemies spawn RIGHT (position ~0), move LEFT (position -> 1.0).
    // Visual left = (1.0 - position) * available width.
    final size = enemy.isBoss ? 36.0 : 24.0;
    final left = ((1.0 - enemy.position) * (laneWidth - size)).clamp(0.0, laneWidth - size);
    final top = (laneHeight - size) / 2;

    final hpBarColor = enemy.isBoss ? const Color(0xFFFF8000) : const Color(0xFFFF5E5B);
    final enemyFill = enemy.isBoss
        ? const Color(0xFFFF8000).withValues(alpha: 0.70)
        : const Color(0xFFFF5E5B).withValues(alpha: 0.70);
    final enemyBorder = enemy.isBoss ? const Color(0xFFFF8000) : const Color(0xFFFF5E5B);

    return Positioned(
      left: left,
      top: top - 6, // offset up a bit for the HP bar
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // HP bar
          SizedBox(
            width: size,
            height: 3,
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
              color: enemyFill,
              shape: enemy.isBoss ? BoxShape.rectangle : BoxShape.circle,
              borderRadius: enemy.isBoss ? BorderRadius.circular(6) : null,
              border: Border.all(color: enemyBorder, width: 1.5),
            ),
            child: enemy.isBoss
                ? const Center(
                    child: Icon(Icons.local_fire_department, color: Colors.white, size: 18),
                  )
                : null,
          ),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------
  // 5. Towers (in lanes)
  // -----------------------------------------------------------------------

  List<Widget> _buildLaneTowers(int laneIndex, double laneWidth, double laneHeight) {
    final laneTowers = <Widget>[];
    for (var i = 0; i < _game.towers.length; i++) {
      final tower = _game.towers[i];
      if (tower.laneIndex != laneIndex) continue;

      // Towers sit on the left-ish area (just right of the goal line), stacked.
      final towerIndex = laneTowers.length;
      final left = 12.0 + towerIndex * 50.0;
      final top = (laneHeight - 40) / 2;

      final towerColor = tower.isDebuffed ? const Color(0xFFFF5E5B) : tower.color;

      laneTowers.add(
        Positioned(
          left: left,
          top: top - 6, // offset up to center avatar+name in lane
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
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: towerColor.withValues(alpha: isDragging ? 0.90 : 0.50),
          width: 2,
        ),
        boxShadow: isDragging
            ? [
                BoxShadow(
                  color: towerColor.withValues(alpha: 0.40),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: ClipOval(
        child: tower.character.avatarUrl != null
            ? CachedNetworkImage(
                imageUrl: tower.character.avatarUrl!,
                fit: BoxFit.cover,
                width: 40,
                height: 40,
                placeholder: (_, __) => _towerFallback(tower, towerColor),
                errorWidget: (_, __, ___) => _towerFallback(tower, towerColor),
              )
            : _towerFallback(tower, towerColor),
      ),
    );
  }

  Widget _towerFallback(TdTower tower, Color towerColor) {
    return Container(
      width: 40,
      height: 40,
      color: towerColor.withValues(alpha: 0.15),
      child: Center(
        child: Text(
          tower.character.name.isNotEmpty ? tower.character.name[0].toUpperCase() : '?',
          style: GoogleFonts.rajdhani(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: towerColor,
          ),
        ),
      ),
    );
  }

  Widget _buildTowerWithName(TdTower tower, Color towerColor, {bool isDragging = false}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildTowerCircle(tower, towerColor, isDragging: isDragging),
        const SizedBox(height: 2),
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

  Widget _buildTowerInfoBar() {
    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: _game.towers.map((tower) {
          final towerColor = tower.isDebuffed ? const Color(0xFFFF5E5B) : tower.color;
          return Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: towerColor.withValues(alpha: 0.50),
                      width: 1.5,
                    ),
                  ),
                  child: ClipOval(
                    child: tower.character.avatarUrl != null
                        ? CachedNetworkImage(
                            imageUrl: tower.character.avatarUrl!,
                            fit: BoxFit.cover,
                            width: 28,
                            height: 28,
                            placeholder: (_, __) => _infoBarFallback(tower, towerColor),
                            errorWidget: (_, __, ___) => _infoBarFallback(tower, towerColor),
                          )
                        : _infoBarFallback(tower, towerColor),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  tower.character.name.length > 8
                      ? '${tower.character.name.substring(0, 7)}...'
                      : tower.character.name,
                  style: GoogleFonts.rajdhani(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'L${tower.laneIndex + 1} \u00b7 ${tower.archetype.name}',
                  style: GoogleFonts.rajdhani(
                    fontSize: 9,
                    color: AppTheme.textTertiary,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _infoBarFallback(TdTower tower, Color towerColor) {
    return Container(
      width: 28,
      height: 28,
      color: towerColor.withValues(alpha: 0.15),
      child: Center(
        child: Text(
          tower.character.name.isNotEmpty ? tower.character.name[0].toUpperCase() : '?',
          style: GoogleFonts.rajdhani(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: towerColor,
          ),
        ),
      ),
    );
  }

  // -----------------------------------------------------------------------
  // 8. Overlays
  // -----------------------------------------------------------------------

  Widget _buildSetupOverlay() {
    return Positioned.fill(
      child: Container(
        color: AppTheme.background.withValues(alpha: 0.70),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.swap_vert_rounded,
                color: AppTheme.textSecondary,
                size: 36,
              ),
              const SizedBox(height: 12),
              Text(
                'DEPLOY YOUR PARTY',
                style: GoogleFonts.rajdhani(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Drag characters to reposition across lanes',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 28),
              _buildPurpleButton(
                'BEGIN WAVE 1',
                onTap: () {
                  _game.beginGame();
                  _lastElapsed = Duration.zero;
                  _ticker.start();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBetweenWavesOverlay() {
    return Positioned.fill(
      child: Container(
        color: AppTheme.background.withValues(alpha: 0.80),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'WAVE ${_game.currentWave} CLEAR',
                style: GoogleFonts.rajdhani(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF00FF98),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Reposition towers',
                style: GoogleFonts.rajdhani(
                  fontSize: 16,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 24),
              _buildPurpleButton(
                'START WAVE ${_game.currentWave + 1}',
                onTap: _startNextWave,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVictoryOverlay() {
    return Positioned.fill(
      child: Container(
        color: AppTheme.background.withValues(alpha: 0.85),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.emoji_events, color: Color(0xFFFFD700), size: 48),
              const SizedBox(height: 12),
              Text(
                'KEYSTONE COMPLETE',
                style: GoogleFonts.rajdhani(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFFFD700),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '+${widget.keystoneLevel} \u2022 ${_game.enemiesKilled} kills \u2022 ${_game.timer.ceil()}s left',
                style: GoogleFonts.rajdhani(
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildOutlinedButton('BACK', onTap: () => Navigator.of(context).pop()),
                  const SizedBox(width: 16),
                  _buildPurpleButton(
                    'NEXT: +${widget.keystoneLevel + 1}',
                    onTap: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TdGameScreen(
                            characters: widget.characters,
                            keystoneLevel: widget.keystoneLevel + 1,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDefeatOverlay() {
    return Positioned.fill(
      child: Container(
        color: AppTheme.background.withValues(alpha: 0.85),
        child: Center(
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
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${_game.enemiesKilled} kills',
                style: GoogleFonts.rajdhani(
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 28),
              _buildOutlinedButton('BACK', onTap: () => Navigator.of(context).pop()),
            ],
          ),
        ),
      ),
    );
  }

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
}
