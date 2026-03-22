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
  final TdDungeon? dungeon;

  const TdGameScreen({
    super.key,
    required this.characters,
    required this.keystoneLevel,
    this.dungeon,
  });

  @override
  State<TdGameScreen> createState() => _TdGameScreenState();
}

class _TdGameScreenState extends State<TdGameScreen>
    with SingleTickerProviderStateMixin {
  late final TdGameState _game;
  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;

  // Track which lane is being hovered during a drag.
  int? _dragHoverLane;

  @override
  void initState() {
    super.initState();
    _game = TdGameState();
    _game.startRun(widget.characters, widget.keystoneLevel, dungeon: widget.dungeon);
    _game.addListener(_onGameStateChanged);
    // Don't auto-start — let the player position towers first
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
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
          // Dungeon name + key level
          Expanded(
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
                return GestureDetector(
                  onTap: () => _showAffixInfo(a),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFFFA500), width: 1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          a.name.toUpperCase(),
                          style: GoogleFonts.rajdhani(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFFFFA500),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.info_outline, size: 10,
                            color: const Color(0xFFFFA500).withValues(alpha: 0.6)),
                      ],
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
        // Overlays (only for end states that don't need interaction)
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

                  // Hit particles (projectiles + damage numbers)
                  ..._game.hitEvents
                      .where((h) => h.enemyLane == laneIndex)
                      .map((hit) => _buildHitParticle(hit, laneWidth, laneHeight)),

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
    final size = enemy.isBoss ? 36.0 : 24.0;
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

    return Positioned(
      left: left,
      top: top - 6,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // HP bar
          SizedBox(
            width: size + 4,
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
              boxShadow: isBeingHit
                  ? [
                      BoxShadow(
                        color: const Color(0xFFFFD700).withValues(alpha: 0.5),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: Icon(
                enemy.isBoss ? dungeon.bossIcon : dungeon.enemyIcon,
                color: Colors.white,
                size: enemy.isBoss ? 18 : 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------
  // 4b. Hit particles
  // -----------------------------------------------------------------------

  Widget _buildHitParticle(TdHitEvent hit, double laneWidth, double laneHeight) {
    final progress = hit.progress;

    // Projectile travels from tower position toward enemy position
    final towerVisualX = (1.0 - hit.towerX) * laneWidth;
    final enemyVisualX = (1.0 - hit.enemyX) * laneWidth;

    // Projectile dot position (lerp from tower to enemy)
    final dotX = towerVisualX + (enemyVisualX - towerVisualX) * progress;
    final dotY = laneHeight / 2;

    // Damage number (floats up from enemy position, fades out)
    final dmgOpacity = (1.0 - progress).clamp(0.0, 1.0);
    final dmgY = dotY - 20 * progress; // float upward

    return Positioned(
      left: 0,
      top: 0,
      right: 0,
      bottom: 0,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Projectile dot (only show in first 60% of animation)
          if (progress < 0.6)
            Positioned(
              left: dotX - 3,
              top: dotY - 3,
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hit.isAoe
                      ? const Color(0xFF0070DD) // blue for AoE
                      : const Color(0xFFFFD700), // gold for single target
                  boxShadow: [
                    BoxShadow(
                      color: (hit.isAoe
                              ? const Color(0xFF0070DD)
                              : const Color(0xFFFFD700))
                          .withValues(alpha: 0.6),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ),

          // Damage number (shows during last 70% of animation)
          if (progress > 0.3)
            Positioned(
              left: enemyVisualX - 12,
              top: dmgY - 8,
              child: Opacity(
                opacity: dmgOpacity,
                child: Text(
                  '-${hit.damage.round()}',
                  style: GoogleFonts.rajdhani(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFFFD700),
                  ),
                ),
              ),
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
            child: GestureDetector(
              onTap: () => _showTowerInfo(tower),
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

  Widget _buildSetupBanner() {
    return Container(
      color: AppTheme.surfaceElevated,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.swap_vert_rounded, color: AppTheme.textSecondary, size: 18),
          const SizedBox(width: 8),
          Text(
            'DRAG CHARACTERS TO POSITION IN LANES',
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
    final isBossWave = nextWave == TdGameState.totalWaves;

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
          Expanded(
            child: Text(
              isBossWave
                  ? 'Next: BOSS WAVE${_game.keystone.hasTyrannical ? " (Tyrannical!)" : ""}'
                  : 'Next: 5–8 enemies${_game.keystone.hasFortified ? " (Fortified)" : ""}',
              style: GoogleFonts.inter(
                fontSize: 11, color: AppTheme.textSecondary,
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
              final towerColor = tower.isDebuffed ? const Color(0xFFFF5E5B) : tower.color;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: towerColor.withValues(alpha: 0.5), width: 1.5),
                    ),
                    child: ClipOval(
                      child: tower.character.avatarUrl != null
                          ? CachedNetworkImage(
                              imageUrl: tower.character.avatarUrl!,
                              fit: BoxFit.cover, width: 28, height: 28,
                              placeholder: (_, __) => _infoBarFallback(tower, towerColor),
                              errorWidget: (_, __, ___) => _infoBarFallback(tower, towerColor),
                            )
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
                '+${widget.keystoneLevel} \u2022 ${_game.enemiesKilled} kills \u2022 ${_game.lives} lives left',
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
                            dungeon: widget.dungeon,
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

  // -----------------------------------------------------------------------
  // Info sheets
  // -----------------------------------------------------------------------

  void _showTowerInfo(TdTower tower) {
    final classColor = tower.color;
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
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: classColor, width: 2),
                  ),
                  child: ClipOval(
                    child: tower.character.avatarUrl != null
                        ? CachedNetworkImage(
                            imageUrl: tower.character.avatarUrl!,
                            fit: BoxFit.cover, width: 48, height: 48,
                          )
                        : Container(
                            color: classColor.withValues(alpha: 0.15),
                            child: Center(
                              child: Text(
                                tower.character.name[0].toUpperCase(),
                                style: GoogleFonts.rajdhani(
                                  fontSize: 22, fontWeight: FontWeight.w700, color: classColor,
                                ),
                              ),
                            ),
                          ),
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
            _infoRow('ITEM LEVEL', '${tower.character.equippedItemLevel ?? "?"}', null),
            const SizedBox(height: 10),
            _infoRow('BASE DAMAGE', '${tower.baseDamage.toStringAsFixed(1)} / hit', null),
            const SizedBox(height: 10),
            _infoRow('ATTACK SPEED', 'Every ${tower.attackInterval}s', null),
            const SizedBox(height: 10),
            _infoRow('LANE', tower.laneIndex >= 0 ? 'Lane ${tower.laneIndex + 1}' : 'Unassigned', null),
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
        return 'Moderate damage (0.8x), hits the furthest enemy in lane';
      case TowerArchetype.healer:
        return 'Does not attack. Buffs adjacent lane towers +30% damage';
      case TowerArchetype.aoe:
        return 'Low damage (0.4x), hits ALL enemies in lane simultaneously';
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
}
