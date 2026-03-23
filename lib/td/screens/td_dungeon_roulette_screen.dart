import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_theme.dart';
import '../data/effect_types.dart';
import 'td_dungeon_briefing_screen.dart';

// ---------------------------------------------------------------------------
// TdDungeonRouletteScreen — dramatic dungeon selection animation
// ---------------------------------------------------------------------------

/// Shows a dramatic roulette animation cycling through dungeons before landing
/// on a randomly selected one. Returns the selected [TdDungeonDef] via
/// Navigator.pop().
class TdDungeonRouletteScreen extends StatefulWidget {
  final List<TdDungeonDef> dungeons;
  final int keystoneLevel;

  const TdDungeonRouletteScreen({
    super.key,
    required this.dungeons,
    required this.keystoneLevel,
  });

  @override
  State<TdDungeonRouletteScreen> createState() =>
      _TdDungeonRouletteScreenState();
}

class _TdDungeonRouletteScreenState extends State<TdDungeonRouletteScreen>
    with TickerProviderStateMixin {
  late final AnimationController _spinController;
  late final AnimationController _revealController;
  late final int _targetIndex;
  late final List<int> _sequence; // indices cycling through

  bool _landed = false;
  int _displayIndex = 0;

  static const int _totalCycles = 28; // total dungeon "frames" to show

  @override
  void initState() {
    super.initState();
    final rng = Random();
    _targetIndex = rng.nextInt(widget.dungeons.length);

    // Build a sequence: cycle through all dungeons multiple times, landing on target
    _sequence = [];
    for (var i = 0; i < _totalCycles; i++) {
      _sequence.add(i % widget.dungeons.length);
    }
    // Ensure the last item is the target
    _sequence.add(_targetIndex);

    // Spin animation: drives which dungeon is shown
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );

    // Reveal animation: glow + scale after landing
    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _spinController.addListener(_onSpinTick);
    _spinController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() => _landed = true);
        _revealController.forward();
      }
    });

    // Start after a brief pause
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _spinController.forward();
    });
  }

  void _onSpinTick() {
    // Map animation value (0->1) to sequence index with easeOut curve
    // (fast at start, slow at end)
    final curved = Curves.easeOutQuart.transform(_spinController.value);
    final idx = (curved * (_sequence.length - 1)).round().clamp(0, _sequence.length - 1);
    if (idx != _displayIndex) {
      setState(() => _displayIndex = idx);
    }
  }

  @override
  void dispose() {
    _spinController.removeListener(_onSpinTick);
    _spinController.dispose();
    _revealController.dispose();
    super.dispose();
  }

  TdDungeonDef get _currentDungeon => widget.dungeons[_sequence[_displayIndex]];

  void _onConfirm() {
    Navigator.of(context).pop(widget.dungeons[_targetIndex]);
  }

  @override
  Widget build(BuildContext context) {
    final dungeon = _currentDungeon;
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          // Dungeon background image (cycles with roulette, revealed on landing)
          if (dungeon.backgroundImage != null)
            AnimatedSwitcher(
              duration: Duration(milliseconds: _landed ? 500 : 60),
              child: Positioned.fill(
                key: ValueKey('${_displayIndex}_bg'),
                child: Opacity(
                  opacity: _landed ? 0.25 : 0.08,
                  child: Image.asset(
                    dungeon.backgroundImage!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          // Dark gradient overlay for text readability
          if (dungeon.backgroundImage != null)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.5),
                      Colors.black.withValues(alpha: 0.2),
                      Colors.black.withValues(alpha: 0.5),
                    ],
                  ),
                ),
              ),
            ),

          // Background glow
          if (_landed)
            AnimatedBuilder(
              animation: _revealController,
              builder: (context, _) {
                return Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(0, -0.2),
                        radius: 0.8,
                        colors: [
                          dungeon.bossColor
                              .withValues(alpha: 0.12 * _revealController.value),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),

          // Main content
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Keystone level badge
                Text(
                  'MYTHIC +${widget.keystoneLevel}',
                  style: GoogleFonts.rajdhani(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFA335EE),
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 32),

                // Dungeon icon — animated
                AnimatedSwitcher(
                  duration: Duration(milliseconds: _landed ? 300 : 60),
                  child: Container(
                    key: ValueKey('${_displayIndex}_icon'),
                    width: _landed ? 96 : 80,
                    height: _landed ? 96 : 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: dungeon.bossColor.withValues(alpha: _landed ? 0.7 : 0.3),
                        width: _landed ? 3 : 2,
                      ),
                      boxShadow: _landed
                          ? [
                              BoxShadow(
                                color: dungeon.bossColor.withValues(alpha: 0.3),
                                blurRadius: 32,
                                spreadRadius: 8,
                              ),
                            ]
                          : null,
                    ),
                    child: Icon(
                      TdIcons.getIcon(dungeon.bossIcon),
                      color: dungeon.bossColor,
                      size: _landed ? 44 : 36,
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Dungeon name — animated
                AnimatedSwitcher(
                  duration: Duration(milliseconds: _landed ? 300 : 50),
                  child: Text(
                    dungeon.name.toUpperCase(),
                    key: ValueKey('${_displayIndex}_name'),
                    style: GoogleFonts.rajdhani(
                      fontSize: _landed ? 32 : 24,
                      fontWeight: FontWeight.w700,
                      color: _landed ? AppTheme.textPrimary : AppTheme.textSecondary,
                      letterSpacing: _landed ? 4 : 2,
                      height: 1.0,
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                // Theme text (only after landing)
                AnimatedOpacity(
                  opacity: _landed ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 400),
                  child: Text(
                    dungeon.theme,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: dungeon.bossColor.withValues(alpha: 0.6),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                // Short name badge
                AnimatedSwitcher(
                  duration: Duration(milliseconds: _landed ? 300 : 50),
                  child: Container(
                    key: ValueKey('${_displayIndex}_badge'),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: dungeon.bossColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: dungeon.bossColor.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Text(
                      dungeon.shortName.isNotEmpty ? dungeon.shortName : dungeon.key.toUpperCase(),
                      style: GoogleFonts.rajdhani(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: dungeon.bossColor,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ),

                // Spinning indicator (before landing)
                if (!_landed) ...[
                  const SizedBox(height: 40),
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: const Color(0xFFA335EE).withValues(alpha: 0.5),
                    ),
                  ),
                ],

                // Dungeon intel link (after landing)
                if (_landed) ...[
                  const SizedBox(height: 20),
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => TdDungeonBriefingScreen(
                          dungeon: widget.dungeons[_targetIndex],
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          color: dungeon.bossColor.withValues(alpha: 0.7),
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'VIEW DUNGEON INTEL',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: dungeon.bossColor.withValues(alpha: 0.7),
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Confirm button (after landing)
                if (_landed) ...[
                  const SizedBox(height: 24),
                  GestureDetector(
                    onTap: _onConfirm,
                    child: AnimatedBuilder(
                      animation: _revealController,
                      builder: (context, _) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 36, vertical: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFA335EE),
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFA335EE)
                                    .withValues(alpha: 0.3 * _revealController.value),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Text(
                            'ENTER DUNGEON',
                            style: GoogleFonts.rajdhani(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 2,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Top label
          Positioned(
            top: topPadding + 16,
            left: 0,
            right: 0,
            child: Center(
              child: AnimatedOpacity(
                opacity: _landed ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 300),
                child: Text(
                  'SELECTING DUNGEON...',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textTertiary,
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
}
