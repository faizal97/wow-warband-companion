import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../data/effect_types.dart';

// ---------------------------------------------------------------------------
// TdDungeonBriefingScreen — dungeon intel and strategy
// ---------------------------------------------------------------------------

class TdDungeonBriefingScreen extends StatelessWidget {
  final TdDungeonDef dungeon;
  const TdDungeonBriefingScreen({super.key, required this.dungeon});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.textSecondary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: dungeon.bossColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                dungeon.shortName.isNotEmpty ? dungeon.shortName : dungeon.key.substring(0, 2).toUpperCase(),
                style: GoogleFonts.rajdhani(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: dungeon.bossColor,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'DUNGEON BRIEFING',
              style: GoogleFonts.rajdhani(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          // Full-screen dungeon background
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
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.3),
              ),
            ),
          ],
          // Scrollable content
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
            children: [
              // Section 1: Header
              _buildHeaderCompact(),
              const SizedBox(height: 24),

          // Section 2: Enemy Intel
          _buildSectionHeader('ENEMY INTEL', Icons.groups_rounded),
          const SizedBox(height: 12),
          _buildEnemyIntel(),
          const SizedBox(height: 24),

          // Section 3: Mini-Boss
          if (dungeon.miniBossModifiers.isNotEmpty) ...[
            _buildSectionHeader('MINI-BOSS — WAVE 5', Icons.star_rounded),
            const SizedBox(height: 12),
            _buildMiniBossSection(),
            const SizedBox(height: 24),
          ],

          // Section 4: Final Boss Mechanics
          if (dungeon.bossModifiers.isNotEmpty) ...[
            _buildSectionHeader('FINAL BOSS — WAVE 10', Icons.warning_amber_rounded),
            const SizedBox(height: 12),
            _buildBossMechanics(),
            const SizedBox(height: 24),
          ],

          // Section 4: Lane Pattern
          _buildSectionHeader('LANE PATTERN', Icons.view_column_rounded),
          const SizedBox(height: 12),
          _buildLanePattern(),
          const SizedBox(height: 24),

          // Section 5: Strategy Tips
          _buildSectionHeader('STRATEGY TIPS', Icons.lightbulb_outline_rounded),
          const SizedBox(height: 12),
              _buildStrategyTips(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCompact() {
    return Column(
      children: [
        // Dungeon icon
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: dungeon.bossColor.withValues(alpha: 0.4),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: dungeon.bossColor.withValues(alpha: 0.15),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: dungeon.bossImage != null
              ? ClipOval(
                  child: Image.asset(
                    dungeon.bossImage!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Icon(
                      TdIcons.getIcon(dungeon.bossIcon),
                      color: dungeon.bossColor.withValues(alpha: 0.9),
                      size: 26,
                    ),
                  ),
                )
              : Icon(
                  TdIcons.getIcon(dungeon.bossIcon),
                  color: dungeon.bossColor.withValues(alpha: 0.9),
                  size: 26,
                ),
        ),
        const SizedBox(height: 14),
        Text(
          dungeon.name.toUpperCase(),
          style: GoogleFonts.rajdhani(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
            letterSpacing: 3,
          ),
          textAlign: TextAlign.center,
        ),
        if (dungeon.theme.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            dungeon.theme,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              fontStyle: FontStyle.italic,
              color: dungeon.bossColor.withValues(alpha: 0.6),
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Section headers
  // -------------------------------------------------------------------------

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: dungeon.bossColor, size: 18),
        const SizedBox(width: 8),
        Text(
          title,
          style: GoogleFonts.rajdhani(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Section 2: Enemy Intel
  // -------------------------------------------------------------------------

  Widget _buildEnemyIntel() {
    return Column(
      children: [
        // Stat badges row
        Row(
          children: [
            _buildStatBadge(
              'HP x${dungeon.hpMultiplier.toStringAsFixed(1)}',
              dungeon.hpMultiplier > 1.2
                  ? const Color(0xFFFF5E5B)
                  : dungeon.hpMultiplier < 0.9
                      ? const Color(0xFF00FF98)
                      : AppTheme.textSecondary,
            ),
            const SizedBox(width: 8),
            _buildStatBadge(
              'SPEED x${dungeon.speedMultiplier.toStringAsFixed(1)}',
              dungeon.speedMultiplier > 1.0
                  ? const Color(0xFFFF5E5B)
                  : dungeon.speedMultiplier < 1.0
                      ? const Color(0xFF00FF98)
                      : AppTheme.textSecondary,
            ),
            const SizedBox(width: 8),
            if (dungeon.enemyCountModifier != 0)
              _buildStatBadge(
                '${dungeon.enemyCountModifier > 0 ? '+' : ''}${dungeon.enemyCountModifier} EXTRA',
                dungeon.enemyCountModifier > 0
                    ? const Color(0xFFFF5E5B)
                    : const Color(0xFF00FF98),
              ),
          ],
        ),
        const SizedBox(height: 12),
        // Enemy modifier cards
        if (dungeon.enemyModifiers.isEmpty)
          _buildInfoCard(
            'STANDARD',
            'No special enemy modifiers. Standard enemies only.',
            Icons.check_circle_outline_rounded,
            AppTheme.textSecondary,
          ),
        ...dungeon.enemyModifiers.map((mod) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _buildModifierCard(mod, dungeon.enemyColor),
        )),
      ],
    );
  }

  Widget _buildStatBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        text,
        style: GoogleFonts.rajdhani(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Section 3: Boss Mechanics
  // -------------------------------------------------------------------------

  Widget _buildMiniBossSection() {
    return Column(
      children: [
        // Mini-boss header card with image and name
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: dungeon.miniBossColor.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              if (dungeon.miniBossImage != null) ...[
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: dungeon.miniBossColor.withValues(alpha: 0.4),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: dungeon.miniBossColor.withValues(alpha: 0.15),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: Image.asset(
                      dungeon.miniBossImage!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Icon(
                        Icons.star_rounded,
                        color: dungeon.miniBossColor,
                        size: 24,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (dungeon.miniBossName ?? 'MINI-BOSS').toUpperCase(),
                      style: GoogleFonts.rajdhani(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: dungeon.miniBossColor,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Appears at Wave 5 \u2014 weaker than the final boss but with unique mechanics.',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: AppTheme.textTertiary,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Mini-boss modifier cards
        ...dungeon.miniBossModifiers.map((mod) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _buildModifierCard(mod, dungeon.miniBossColor),
        )),
      ],
    );
  }

  Widget _buildBossMechanics() {
    return Column(
      children: [
        // Final boss header card with image
        if (dungeon.bossImage != null) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: dungeon.bossColor.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: dungeon.bossColor.withValues(alpha: 0.4),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: dungeon.bossColor.withValues(alpha: 0.15),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: Image.asset(
                      dungeon.bossImage!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Icon(
                        TdIcons.getIcon(dungeon.bossIcon),
                        color: dungeon.bossColor,
                        size: 24,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'FINAL BOSS',
                        style: GoogleFonts.rajdhani(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: dungeon.bossColor,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Appears at Wave 10 \u2014 the ultimate challenge. Tyrannical affix increases boss HP.',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: AppTheme.textTertiary,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        // Boss modifier cards
        ...dungeon.bossModifiers.map((mod) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _buildModifierCard(mod, dungeon.bossColor),
        )),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Modifier card (used for enemy and boss modifiers)
  // -------------------------------------------------------------------------

  Widget _buildModifierCard(EffectDef modifier, Color accentColor) {
    final name = _effectName(modifier.type);
    final desc = _effectDescription(modifier);
    final icon = _effectIcon(modifier.type);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accentColor.withValues(alpha: 0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: accentColor, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.toUpperCase(),
                  style: GoogleFonts.rajdhani(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: accentColor,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  desc,
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
      ),
    );
  }

  Widget _buildInfoCard(String title, String desc, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.surfaceBorder),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.rajdhani(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: color,
                    letterSpacing: 1,
                  ),
                ),
                Text(
                  desc,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppTheme.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Section 4: Lane Pattern
  // -------------------------------------------------------------------------

  Widget _buildLanePattern() {
    final patternType = dungeon.lanePattern.type;
    final description = _lanePatternDescription(patternType);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Pattern name badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: dungeon.bossColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              patternType.toUpperCase().replaceAll('_', ' '),
              style: GoogleFonts.rajdhani(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: dungeon.bossColor,
                letterSpacing: 1,
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Visual lane diagram
          _buildLaneDiagram(patternType),
          const SizedBox(height: 12),
          // Description
          Text(
            description,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: AppTheme.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLaneDiagram(String patternType) {
    // Show a simple 3-lane visual with dot density indicating traffic
    final weights = _laneWeights(patternType);

    return Row(
      children: List.generate(3, (i) {
        final weight = weights[i];
        final barHeight = 8.0 + weight * 32.0;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              children: [
                Text(
                  'L${i + 1}',
                  style: GoogleFonts.rajdhani(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textTertiary,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  height: barHeight,
                  decoration: BoxDecoration(
                    color: dungeon.bossColor.withValues(alpha: 0.15 + weight * 0.35),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: dungeon.bossColor.withValues(alpha: 0.3),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${(weight * 100).round()}%',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: AppTheme.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  List<double> _laneWeights(String patternType) {
    switch (patternType) {
      case 'spread':
        return [0.33, 0.33, 0.33];
      case 'heavy_center':
        final w = (dungeon.lanePattern.params['centerWeight'] as num?)?.toDouble() ?? 0.6;
        return [(1 - w) / 2, w, (1 - w) / 2];
      case 'sequential':
        return [0.8, 0.5, 0.2]; // wave pattern: L1 first, L3 last
      case 'zerg':
        return [0.9, 0.9, 0.9]; // all lanes hit hard
      case 'packs':
        return [0.7, 0.2, 0.1]; // one lane at a time, rotating
      case 'weakest_lane':
        return [0.6, 0.2, 0.4]; // targets your weak spots
      case 'drift':
        return [0.4, 0.3, 0.5]; // unpredictable, uneven
      case 'lane_switch':
        return [0.35, 0.45, 0.35]; // start random, switch mid-path
      default:
        return [0.33, 0.33, 0.33];
    }
  }

  String _lanePatternDescription(String type) {
    switch (type) {
      case 'spread':
        return 'Enemies distributed evenly across all lanes.';
      case 'heavy_center':
        return '60% of enemies funnel through center lane.';
      case 'sequential':
        return 'Enemies attack one lane at a time: L1, then L2, then L3.';
      case 'zerg':
        return 'All lanes overwhelmed simultaneously with extra enemies.';
      case 'packs':
        return 'Enemies come in packs of 3 in one lane, then rotate.';
      case 'weakest_lane':
        return 'Enemies target the lane with the fewest towers.';
      case 'drift':
        return 'Random lanes, enemies may drift between lanes.';
      case 'lane_switch':
        return 'Enemies start in random lanes but switch mid-path.';
      default:
        return 'Standard lane distribution.';
    }
  }

  // -------------------------------------------------------------------------
  // Section 5: Strategy Tips
  // -------------------------------------------------------------------------

  Widget _buildStrategyTips() {
    final tips = <String>[];

    if (dungeon.hpMultiplier > 1.3) {
      tips.add('Tanky enemies \u2014 prioritize high DPS classes like Rogue (Ambush) and Evoker (Charged Blast).');
    }
    if (dungeon.speedMultiplier > 1.1) {
      tips.add('Fast enemies \u2014 use Death Knights to slow them with Frost Fever.');
    }
    if (dungeon.speedMultiplier < 0.7) {
      tips.add('Slow enemies \u2014 focus on raw damage over crowd control.');
    }
    if (dungeon.hpMultiplier < 0.8) {
      tips.add('Fragile enemies \u2014 AoE classes like Shaman will shine here.');
    }
    if (dungeon.enemyCountModifier > 2) {
      tips.add('Large swarms \u2014 bring AoE damage and multi-target classes.');
    }

    final hasShield = dungeon.enemyModifiers.any((m) => m.type == 'shield');
    final hasResurrect = dungeon.enemyModifiers.any((m) => m.type == 'resurrect');
    final hasSpectral = dungeon.enemyModifiers.any((m) => m.type == 'spectral');
    final hasPhase = dungeon.enemyModifiers.any((m) => m.type == 'phase');
    final hasFrostAura = dungeon.enemyModifiers.any((m) => m.type == 'frost_aura');
    final hasLaneSwitch = dungeon.enemyModifiers.any((m) => m.type == 'lane_switch');
    final hasAccelerate = dungeon.enemyModifiers.any((m) => m.type == 'accelerate');

    if (hasShield) {
      tips.add('Shielded enemies \u2014 use multi-hit classes (Warrior Cleave, Hunter Multi-Shot) to break shields quickly.');
    }
    if (hasResurrect) {
      tips.add('Enemies can resurrect \u2014 focus fire to prevent lane flooding.');
    }
    if (hasSpectral) {
      tips.add('Spectral enemies take reduced damage early \u2014 place towers toward the end of lanes.');
    }
    if (hasPhase) {
      tips.add('Phasing enemies become invulnerable periodically \u2014 sustained DPS outperforms burst.');
    }
    if (hasFrostAura) {
      tips.add('Frost auras slow your towers \u2014 use Support classes to offset the attack speed penalty.');
    }
    if (hasLaneSwitch) {
      tips.add('Enemies switch lanes \u2014 spread your towers evenly across all lanes.');
    }
    if (hasAccelerate) {
      tips.add('Enemies accelerate over time \u2014 kill them fast before they overwhelm your defenses.');
    }

    if (dungeon.lanePattern.type == 'heavy_center') {
      tips.add('Heavy center push \u2014 stack your strongest tower in Lane 2.');
    }
    if (dungeon.lanePattern.type == 'weakest_lane') {
      tips.add('Enemies target weak lanes \u2014 ensure every lane has at least one tower.');
    }
    if (dungeon.lanePattern.type == 'zerg') {
      tips.add('Zerg rush \u2014 AoE towers and support buffers are essential.');
    }

    // Mini-boss tips (wave 5)
    if (dungeon.miniBossModifiers.isNotEmpty) {
      final mbName = dungeon.miniBossName ?? 'Mini-boss';
      final mbHasWindPush = dungeon.miniBossModifiers.any((m) => m.type == 'wind_push');
      final mbHasKnockback = dungeon.miniBossModifiers.any((m) => m.type == 'knockback_tower');
      final mbHasSplit = dungeon.miniBossModifiers.any((m) => m.type == 'split_on_death');
      final mbHasReflect = dungeon.miniBossModifiers.any((m) => m.type == 'reflect_damage');
      final mbHasStacking = dungeon.miniBossModifiers.any((m) => m.type == 'stacking_damage');

      if (mbHasWindPush) {
        tips.add('$mbName pushes enemies forward \u2014 place towers near lane ends to catch pushed enemies.');
      }
      if (mbHasKnockback) {
        tips.add('$mbName displaces towers \u2014 reposition after wave 5 before starting Act 2.');
      }
      if (mbHasSplit) {
        tips.add('$mbName splits on death \u2014 save AoE cooldowns for the split.');
      }
      if (mbHasReflect) {
        tips.add('$mbName reflects damage \u2014 watch for reflect windows before committing abilities.');
      }
      if (mbHasStacking) {
        tips.add('$mbName deals stacking damage \u2014 burn it down fast before damage ramps.');
      }
    }

    // Final boss tips (wave 10)
    final hasEnrage = dungeon.bossModifiers.any((m) => m.type == 'enrage');
    final hasSplit = dungeon.bossModifiers.any((m) => m.type == 'split_on_death');
    final hasReflect = dungeon.bossModifiers.any((m) => m.type == 'reflect_damage');
    final hasKnockback = dungeon.bossModifiers.any((m) => m.type == 'knockback_tower');

    if (hasEnrage) {
      tips.add('Final boss enrages at low HP \u2014 save burst damage for the final phase.');
    }
    if (hasSplit) {
      tips.add('Final boss splits on death \u2014 keep AoE towers ready for the split phase.');
    }
    if (hasReflect) {
      tips.add('Final boss reflects damage \u2014 pull back high-DPS towers during reflect phases.');
    }
    if (hasKnockback) {
      tips.add('Final boss knocks back towers \u2014 keep a Support class in a safe lane to maintain buffs.');
    }

    if (tips.isEmpty) {
      tips.add('Balanced dungeon \u2014 bring a well-rounded party composition.');
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: tips.map((tip) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.arrow_right_rounded,
                  color: dungeon.bossColor.withValues(alpha: 0.7),
                  size: 16,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  tip,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        )).toList(),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Effect name/description/icon helpers
  // -------------------------------------------------------------------------

  static String _effectName(String type) {
    switch (type) {
      case 'spectral': return 'Spectral';
      case 'shield': return 'Arcane Shield';
      case 'resurrect': return 'Resurrection';
      case 'phase': return 'Void Phase';
      case 'frost_aura': return 'Frost Aura';
      case 'lane_switch': return 'Evasive';
      case 'ranged_attack': return 'Ranged Attack';
      case 'accelerate': return 'Accelerate';
      case 'fire_zone': return 'Fire Zone';
      case 'teleport_lanes': return 'Teleport';
      case 'enrage': return 'Enrage';
      case 'summon_adds': return 'Summon Adds';
      case 'split_on_death': return 'Split';
      case 'reflect_damage': return 'Reflect';
      case 'knockback_tower': return 'Knockback';
      case 'stacking_damage': return 'Void Corruption';
      case 'wind_push': return 'Wind Blast';
      default: return type.replaceAll('_', ' ').toUpperCase();
    }
  }

  static String _effectDescription(EffectDef effect) {
    final p = effect.params;
    switch (effect.type) {
      case 'spectral':
        final reduction = ((p['dmgReduction'] as num?)?.toDouble() ?? 0.5) * 100;
        final until = ((p['untilPosition'] as num?)?.toDouble() ?? 0.5) * 100;
        return '${reduction.round()}% damage reduction until ${until.round()}% through the lane.';
      case 'shield':
        final hits = (p['hits'] as num?)?.toInt() ?? 2;
        final chance = ((p['chance'] as num?)?.toDouble() ?? 0.3) * 100;
        return '${chance.round()}% chance: absorbs $hits hits before taking damage.';
      case 'resurrect':
        final chance = ((p['chance'] as num?)?.toDouble() ?? 0.3) * 100;
        final hpFrac = ((p['hpFraction'] as num?)?.toDouble() ?? 0.4) * 100;
        return '${chance.round()}% chance to revive with ${hpFrac.round()}% HP.';
      case 'phase':
        final dur = (p['invulnDuration'] as num?)?.toDouble() ?? 0.5;
        final interval = (p['interval'] as num?)?.toDouble() ?? 3.0;
        return 'Becomes invulnerable for ${dur}s every ${interval}s.';
      case 'frost_aura':
        final slow = ((p['slowPercent'] as num?)?.toDouble() ?? 0.05) * 100;
        return 'Slows nearby towers by ${slow.round()}% per enemy. Stacks.';
      case 'lane_switch':
        final chance = ((p['chance'] as num?)?.toDouble() ?? 0.4) * 100;
        return '${chance.round()}% chance to switch lanes mid-path.';
      case 'ranged_attack':
        final dmg = (p['damage'] as num?)?.toDouble() ?? 5.0;
        final interval = (p['interval'] as num?)?.toDouble() ?? 3.0;
        return 'Attacks towers for $dmg damage every ${interval}s.';
      case 'accelerate':
        final start = (p['startSpeedMult'] as num?)?.toDouble() ?? 0.5;
        final end = (p['endSpeedMult'] as num?)?.toDouble() ?? 1.5;
        return 'Speed ramps from ${start}x to ${end}x as they travel.';
      case 'fire_zone':
        final dur = (p['duration'] as num?)?.toDouble() ?? 3.0;
        final interval = (p['interval'] as num?)?.toDouble() ?? 5.0;
        return 'Drops fire zones lasting ${dur}s every ${interval}s. Debuffs towers in the zone.';
      case 'teleport_lanes':
        final interval = (p['interval'] as num?)?.toDouble() ?? 4.0;
        return 'Teleports to a random lane every ${interval}s.';
      case 'enrage':
        final threshold = ((p['hpThreshold'] as num?)?.toDouble() ?? 0.3) * 100;
        final speedMult = (p['speedMult'] as num?)?.toDouble() ?? 2.0;
        return 'Below ${threshold.round()}% HP: moves ${speedMult}x faster.';
      case 'summon_adds':
        final count = (p['count'] as num?)?.toInt() ?? 2;
        final interval = (p['interval'] as num?)?.toDouble() ?? 6.0;
        return 'Summons $count adds every ${interval}s.';
      case 'split_on_death':
        final count = (p['count'] as num?)?.toInt() ?? 3;
        final hpFrac = ((p['hpFraction'] as num?)?.toDouble() ?? 0.3) * 100;
        return 'Splits into $count enemies with ${hpFrac.round()}% HP each on death.';
      case 'reflect_damage':
        final dur = (p['duration'] as num?)?.toDouble() ?? 2.0;
        final interval = (p['interval'] as num?)?.toDouble() ?? 6.0;
        return 'Reflects damage for ${dur}s every ${interval}s. Debuffs attacking towers.';
      case 'knockback_tower':
        final interval = (p['interval'] as num?)?.toDouble() ?? 5.0;
        return 'Knocks a random tower to a different lane every ${interval}s.';
      case 'stacking_damage':
        final dps = (p['damagePerSecond'] as num?)?.toDouble() ?? 2.0;
        return 'Deals $dps stacking damage per second to all towers. Increases over time.';
      case 'wind_push':
        final push = ((p['pushAmount'] as num?)?.toDouble() ?? 0.3) * 100;
        final interval = (p['interval'] as num?)?.toDouble() ?? 4.0;
        return 'Pushes all enemies forward ${push.round()}% every ${interval}s.';
      default:
        return 'Unknown modifier effect.';
    }
  }

  static IconData _effectIcon(String type) {
    switch (type) {
      case 'spectral': return Icons.blur_on_rounded;
      case 'shield': return Icons.shield_rounded;
      case 'resurrect': return Icons.refresh_rounded;
      case 'phase': return Icons.dark_mode_rounded;
      case 'frost_aura': return Icons.ac_unit_rounded;
      case 'lane_switch': return Icons.swap_horiz_rounded;
      case 'ranged_attack': return Icons.gps_fixed_rounded;
      case 'accelerate': return Icons.speed_rounded;
      case 'fire_zone': return Icons.local_fire_department_rounded;
      case 'teleport_lanes': return Icons.blur_circular_rounded;
      case 'enrage': return Icons.flash_on_rounded;
      case 'summon_adds': return Icons.group_add_rounded;
      case 'split_on_death': return Icons.call_split_rounded;
      case 'reflect_damage': return Icons.replay_rounded;
      case 'knockback_tower': return Icons.push_pin_rounded;
      case 'stacking_damage': return Icons.trending_up_rounded;
      case 'wind_push': return Icons.air_rounded;
      default: return Icons.help_outline_rounded;
    }
  }
}
