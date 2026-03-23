import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/character.dart';
import '../../theme/app_theme.dart';
import '../../theme/wow_class_colors.dart';
import '../data/effect_types.dart';
import '../data/td_balance_config.dart';
import '../data/td_class_registry.dart';
import '../data/td_hero_registry.dart';
import '../data/td_run_state.dart';

// ---------------------------------------------------------------------------
// TdUpgradeScreen — spend Valor on tower upgrades between keys
// ---------------------------------------------------------------------------

class TdUpgradeScreen extends StatefulWidget {
  final TdRunState runState;
  final List<WowCharacter> selectedCharacters;
  final TdClassRegistry classRegistry;
  final TdHeroRegistry? heroRegistry;
  final TdBalanceConfig config;

  const TdUpgradeScreen({
    super.key,
    required this.runState,
    required this.selectedCharacters,
    required this.classRegistry,
    this.heroRegistry,
    this.config = TdBalanceConfig.defaults,
  });

  @override
  State<TdUpgradeScreen> createState() => _TdUpgradeScreenState();
}

class _TdUpgradeScreenState extends State<TdUpgradeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _entryController;

  TdRunState get _run => widget.runState;
  TdBalanceConfig get _cfg => widget.config;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
  }

  @override
  void dispose() {
    _entryController.dispose();
    super.dispose();
  }

  void _purchaseUpgrade(int characterId, UpgradeType type) {
    final success = _run.purchaseUpgrade(characterId, type, _cfg);
    if (success) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Column(
        children: [
          // ── Header: Valor balance ──────────────────────────────────────
          Container(
            padding: EdgeInsets.fromLTRB(20, topPad + 16, 20, 16),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              border: Border(
                bottom: BorderSide(
                  color: const Color(0xFFD4A017).withValues(alpha: 0.15),
                ),
              ),
            ),
            child: Row(
              children: [
                // Back button
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: const Icon(Icons.arrow_back_rounded,
                      color: AppTheme.textSecondary, size: 22),
                ),
                const SizedBox(width: 16),
                Text(
                  'FORGE',
                  style: GoogleFonts.rajdhani(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                    letterSpacing: 3,
                  ),
                ),
                const Spacer(),
                // Valor balance
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFFD4A017).withValues(alpha: 0.15),
                        const Color(0xFFD4A017).withValues(alpha: 0.05),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFFD4A017).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.diamond_rounded,
                          color: Color(0xFFD4A017), size: 16),
                      const SizedBox(width: 6),
                      Text(
                        '${_run.valor}',
                        style: GoogleFonts.rajdhani(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFD4A017),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'VALOR',
                        style: GoogleFonts.rajdhani(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFFD4A017).withValues(alpha: 0.6),
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Subtitle ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 14,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD4A017),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'UPGRADE YOUR TOWERS',
                  style: GoogleFonts.rajdhani(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textTertiary,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),

          // ── Tower cards ───────────────────────────────────────────────
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              itemCount: widget.selectedCharacters.length,
              itemBuilder: (context, index) {
                final delay = index * 0.08;
                return AnimatedBuilder(
                  animation: _entryController,
                  builder: (context, child) {
                    final t = Curves.easeOutCubic.transform(
                      (_entryController.value - delay).clamp(0, 1),
                    );
                    return Transform.translate(
                      offset: Offset(0, 20 * (1 - t)),
                      child: Opacity(opacity: t, child: child),
                    );
                  },
                  child: _buildTowerCard(widget.selectedCharacters[index]),
                );
              },
            ),
          ),

          // ── Continue button ───────────────────────────────────────────
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
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFA335EE),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFA335EE).withValues(alpha: 0.25),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      'CONTINUE',
                      style: GoogleFonts.rajdhani(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
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
  // Class icon fallback helper
  // -----------------------------------------------------------------------

  Widget _classIconOrPerson(WowCharacter character, Color classColor, double size) {
    final classIcon = TdClassIcons.assetPath(character.characterClass);
    if (classIcon != null) {
      return Image.asset(
        classIcon,
        width: size * 0.7, height: size * 0.7, fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Icon(Icons.person, color: classColor, size: size),
      );
    }
    return Icon(Icons.person, color: classColor, size: size);
  }

  // -----------------------------------------------------------------------
  // Tower upgrade card
  // -----------------------------------------------------------------------

  Widget _buildTowerCard(WowCharacter character) {
    final classDef = widget.heroRegistry?.getHeroClassDef(
            character.name, widget.classRegistry) ??
        widget.classRegistry.getClass(character.characterClass);
    final classColor = WowClassColors.forClass(character.characterClass);
    final upgrades =
        _run.getUpgrades(character.id) ?? TowerUpgrades();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: classColor.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        children: [
          // Top row: avatar + name + archetype
          Row(
            children: [
              // Avatar
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: classColor.withValues(alpha: 0.5), width: 2),
                ),
                child: ClipOval(
                  child: character.avatarUrl != null
                      ? (character.avatarUrl!.startsWith('asset:')
                          ? Image.asset(
                              character.avatarUrl!.substring(6),
                              width: 38,
                              height: 38,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: classColor.withValues(alpha: 0.2),
                                child: _classIconOrPerson(character, classColor, 20),
                              ),
                            )
                          : CachedNetworkImage(
                              imageUrl: character.avatarUrl!,
                              width: 38,
                              height: 38,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => Container(
                                color: classColor.withValues(alpha: 0.2),
                                child: _classIconOrPerson(character, classColor, 20),
                              ),
                              errorWidget: (_, __, ___) => Container(
                                color: classColor.withValues(alpha: 0.2),
                                child: _classIconOrPerson(character, classColor, 20),
                              ),
                            ))
                      : Container(
                          color: classColor.withValues(alpha: 0.2),
                          child: _classIconOrPerson(character, classColor, 20),
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      character.name,
                      style: GoogleFonts.rajdhani(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: classColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${classDef.archetype.name.toUpperCase()} \u00B7 ${character.characterClass}',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        color: AppTheme.textTertiary,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Upgrade slots row
          Row(
            children: [
              Expanded(
                child: _buildUpgradeSlot(
                  character: character,
                  type: UpgradeType.sharpen,
                  icon: Icons.auto_fix_high_rounded,
                  label: 'SHARPEN',
                  detail: '+${(_cfg.sharpenDamageBonus * 100).round()}% DMG',
                  cost: _cfg.sharpenCost,
                  stacks: upgrades.sharpenStacks,
                  maxStacks: _cfg.sharpenMaxStacks,
                  isMaxed: upgrades.sharpenStacks >= _cfg.sharpenMaxStacks,
                  accentColor: const Color(0xFFFF6B35),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildUpgradeSlot(
                  character: character,
                  type: UpgradeType.fortify,
                  icon: Icons.shield_rounded,
                  label: 'FORTIFY',
                  detail: 'BOSS -${_cfg.fortifyBossLeakReduction}',
                  cost: _cfg.fortifyCost,
                  isMaxed: upgrades.hasFortify,
                  isPurchased: upgrades.hasFortify,
                  accentColor: const Color(0xFF4FC3F7),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildUpgradeSlot(
                  character: character,
                  type: UpgradeType.empower,
                  icon: Icons.star_rounded,
                  label: 'EMPOWER',
                  detail: classDef.empoweredPassive?.name ?? 'ENHANCED',
                  cost: _cfg.empowerCost,
                  isMaxed: upgrades.hasEmpower,
                  isPurchased: upgrades.hasEmpower,
                  accentColor: const Color(0xFFA335EE),
                  hasEmpower: classDef.empoweredPassive != null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Single upgrade slot
  // -----------------------------------------------------------------------

  Widget _buildUpgradeSlot({
    required WowCharacter character,
    required UpgradeType type,
    required IconData icon,
    required String label,
    required String detail,
    required int cost,
    required bool isMaxed,
    required Color accentColor,
    int stacks = 0,
    int maxStacks = 1,
    bool isPurchased = false,
    bool hasEmpower = true,
  }) {
    final canAfford = _run.valor >= cost;
    final isAvailable = !isMaxed && canAfford && hasEmpower;

    return GestureDetector(
      onTap: isAvailable
          ? () => _purchaseUpgrade(character.id, type)
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: isPurchased || (type == UpgradeType.sharpen && stacks > 0)
              ? accentColor.withValues(alpha: 0.08)
              : AppTheme.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isAvailable
                ? accentColor.withValues(alpha: 0.4)
                : isPurchased
                    ? accentColor.withValues(alpha: 0.2)
                    : AppTheme.surfaceBorder,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isMaxed
                  ? accentColor.withValues(alpha: 0.4)
                  : isAvailable
                      ? accentColor
                      : AppTheme.textTertiary,
              size: 18,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.rajdhani(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: isMaxed
                    ? AppTheme.textTertiary
                    : AppTheme.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
            // Stack indicator or detail
            if (type == UpgradeType.sharpen)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(maxStacks, (i) {
                  return Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < stacks
                          ? accentColor
                          : accentColor.withValues(alpha: 0.15),
                      border: Border.all(
                        color: accentColor.withValues(alpha: 0.3),
                        width: 0.5,
                      ),
                    ),
                  );
                }),
              )
            else
              Text(
                isPurchased ? 'ACTIVE' : detail,
                style: GoogleFonts.inter(
                  fontSize: 8,
                  fontWeight: isPurchased ? FontWeight.w600 : FontWeight.w400,
                  color: isPurchased
                      ? accentColor
                      : AppTheme.textTertiary,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: 4),
            // Cost badge
            if (!isMaxed)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: canAfford
                      ? const Color(0xFFD4A017).withValues(alpha: 0.15)
                      : Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.diamond_rounded,
                      size: 8,
                      color: canAfford
                          ? const Color(0xFFD4A017)
                          : Colors.red.withValues(alpha: 0.5),
                    ),
                    const SizedBox(width: 2),
                    Text(
                      '$cost',
                      style: GoogleFonts.rajdhani(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: canAfford
                            ? const Color(0xFFD4A017)
                            : Colors.red.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              )
            else
              Text(
                type == UpgradeType.sharpen ? 'MAX' : 'OWNED',
                style: GoogleFonts.rajdhani(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: accentColor.withValues(alpha: 0.5),
                  letterSpacing: 1,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
