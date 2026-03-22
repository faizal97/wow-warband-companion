import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/achievement.dart';
import '../models/achievement_enrichment.dart';
import '../services/achievement_provider.dart';
import '../theme/app_theme.dart';

/// Full-screen achievement detail with enriched Wago data.
class AchievementDetailScreen extends StatefulWidget {
  final AchievementDisplay display;

  const AchievementDetailScreen({super.key, required this.display});

  @override
  State<AchievementDetailScreen> createState() =>
      _AchievementDetailScreenState();
}

class _AchievementDetailScreenState extends State<AchievementDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context
          .read<AchievementProvider>()
          .fetchEnrichment(widget.display.achievement.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ach = widget.display.achievement;
    final display = widget.display;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0.0, 0.3, 1.0],
            colors: [
              Color(0xFF101018),
              AppTheme.background,
              AppTheme.background,
            ],
          ),
        ),
        child: SafeArea(
          child: Consumer<AchievementProvider>(
            builder: (context, provider, _) {
              final enrichment = provider.getEnrichment(ach.id);
              final isEnrichmentLoading = provider.isEnrichmentLoading(ach.id);

              return CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _buildHeader(context)),
                  SliverToBoxAdapter(
                      child: _buildAchievementCard(ach, display, enrichment)),

                  // Criteria section
                  if (ach.criteria != null &&
                      ach.criteria!.childCriteria.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: _buildCriteriaHeader(display, isEnrichmentLoading && enrichment == null),
                    ),
                    SliverToBoxAdapter(
                      child: _buildCriteriaChecklist(
                          ach.criteria!, display, enrichment, provider),
                    ),
                  ],

                  const SliverToBoxAdapter(child: SizedBox(height: 40)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_rounded,
                color: AppTheme.textSecondary, size: 22),
          ),
          Text(
            'Achievement',
            style: GoogleFonts.rajdhani(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.textTertiary,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAchievementCard(Achievement ach, AchievementDisplay display, AchievementEnrichment? enrichment) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: display.isCompleted
              ? const Color(0xFF1EFF00).withValues(alpha: 0.2)
              : AppTheme.surfaceBorder,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AchievementIcon(iconUrl: ach.iconUrl, size: 56),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ach.name,
                        style: GoogleFonts.rajdhani(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (ach.points > 0) _PointsBadge(points: ach.points),
                        if (ach.isAccountWide)
                          _TagBadge(
                              label: 'Account',
                              color: const Color(0xFF3FC7EB)),
                        if (display.isCompleted)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.check_circle_rounded,
                                  color: Color(0xFF1EFF00), size: 16),
                              const SizedBox(width: 4),
                              Text(display.formattedDate ?? 'Completed',
                                  style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: const Color(0xFF1EFF00))),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(ach.description,
              style: GoogleFonts.inter(
                  fontSize: 14, color: AppTheme.textSecondary, height: 1.5)),
          if (display.totalCriteria > 0 && !display.isCompleted) ...[
            const SizedBox(height: 16),
            _CriteriaProgressBar(
                completed: display.completedCriteria,
                total: display.totalCriteria),
          ],
          // Enrichment metadata
          if (enrichment != null) ...[
            if (enrichment.instanceName != null) ...[
              const SizedBox(height: 12),
              _MetadataRow(
                icon: Icons.castle_rounded,
                color: const Color(0xFFA855F7),
                label: enrichment.instanceName!,
              ),
            ],
            if (enrichment.rewardText != null &&
                enrichment.rewardText!.isNotEmpty) ...[
              const SizedBox(height: 8),
              _MetadataRow(
                icon: Icons.card_giftcard_rounded,
                color: const Color(0xFFF59E0B),
                label: enrichment.rewardText!,
              ),
            ],
            if (enrichment.rewardItemName != null) ...[
              const SizedBox(height: 8),
              _MetadataRow(
                icon: Icons.inventory_2_outlined,
                color: const Color(0xFF3FC7EB),
                label: 'Reward: ${enrichment.rewardItemName}',
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildCriteriaHeader(AchievementDisplay display, bool loading) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
      child: Row(
        children: [
          Text('CRITERIA',
              style: GoogleFonts.rajdhani(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textTertiary,
                  letterSpacing: 1.5)),
          if (display.totalCriteria > 0) ...[
            const SizedBox(width: 8),
            Text('${display.completedCriteria}/${display.totalCriteria}',
                style: GoogleFonts.rajdhani(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFFFD100))),
          ],
          if (loading) ...[
            const SizedBox(width: 12),
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: AppTheme.textTertiary.withValues(alpha: 0.4),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCriteriaChecklist(
    AchievementCriteria criteria,
    AchievementDisplay display,
    AchievementEnrichment? enrichment,
    AchievementProvider provider,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: criteria.childCriteria.map((child) {
          final isCompleted = display.criteriaProgress[child.id] ?? false;
          final enriched = enrichment?.findCriterion(child.id);

          // Meta-criterion (links to another achievement)
          if (child.isMetaCriterion) {
            return _MetaCriterionRow(
              criteria: child,
              isCompleted: isCompleted,
              provider: provider,
            );
          }

          // Group/container criterion (e.g., "Suspicious Minds" with sub-criteria)
          if (child.childCriteria.isNotEmpty) {
            return _GroupCriterionSection(
              criteria: child,
              display: display,
              enrichment: enrichment,
              provider: provider,
            );
          }

          // Regular criterion — flat checklist row
          return _CriterionChecklistRow(
            criteria: child,
            isCompleted: isCompleted,
            enriched: enriched,
          );
        }).toList(),
      ),
    );
  }
}

// =============================================================================
// Criterion row — expandable when quest chain data is available
// =============================================================================

class _CriterionChecklistRow extends StatefulWidget {
  final AchievementCriteria criteria;
  final bool isCompleted;
  final EnrichedCriterion? enriched;

  const _CriterionChecklistRow({
    required this.criteria,
    required this.isCompleted,
    this.enriched,
  });

  @override
  State<_CriterionChecklistRow> createState() => _CriterionChecklistRowState();
}

class _CriterionChecklistRowState extends State<_CriterionChecklistRow> {
  bool _expanded = false;

  /// Builds a contextual subtitle from enrichment data.
  Widget? _buildSubtitle() {
    final enriched = widget.enriched;
    if (enriched == null) return null;

    final parts = <String>[];
    final questLine = enriched.questLine;
    final criterionName = widget.criteria.description;

    // Asset name (creature, faction, currency)
    if (enriched.assetName != null) {
      parts.add(enriched.assetName!);
    }

    // Amount
    if (enriched.amount != null && enriched.amount! > 1) {
      final typeVerb = switch (enriched.type) {
        'kill' => 'Kill',
        'currency' => 'Collect',
        'reputation' => 'Earn',
        _ => 'Complete',
      };
      // If we have an asset name, show "Kill 500 x Creature"
      // otherwise just "Kill 500"
      if (enriched.assetName != null) {
        parts.clear();
        parts.add('$typeVerb ${enriched.amount} x ${enriched.assetName}');
      } else {
        parts.add('$typeVerb ${enriched.amount}');
      }
    }

    // Quest chain info
    if (questLine != null && questLine.questCount > 0) {
      final showName = questLine.name.isNotEmpty &&
          questLine.name.toLowerCase() != criterionName.toLowerCase();
      if (showName) {
        parts.add('${questLine.name} — ${questLine.questCount} quest${questLine.questCount == 1 ? '' : 's'}');
      } else {
        parts.add('${questLine.questCount} quest${questLine.questCount == 1 ? '' : 's'} in chain');
      }
    }

    if (parts.isEmpty) return null;

    final (IconData icon, Color color) = switch (enriched.type) {
      'quest' || 'daily_quest' || 'world_quest' || 'questline' =>
        (Icons.auto_stories_rounded, const Color(0xFFFFD100)),
      'kill' => (Icons.gps_fixed_rounded, const Color(0xFFFF6B6B)),
      'reputation' => (Icons.handshake_outlined, const Color(0xFF9B59B6)),
      'currency' => (Icons.monetization_on_outlined, const Color(0xFFF39C12)),
      _ => (Icons.info_outline_rounded, AppTheme.textTertiary),
    };

    return Row(
      children: [
        Icon(icon, size: 11, color: color.withValues(alpha: 0.5)),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            parts.join(' — '),
            style: GoogleFonts.inter(
              fontSize: 11,
              color: color.withValues(alpha: 0.5),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final questLine = widget.enriched?.questLine;
    final hasQuestChain = questLine != null && questLine.questCount > 0;
    // Only show expandable quest list if at least some quests have names
    final hasNamedQuests = hasQuestChain &&
        questLine.quests.any((q) => q.name != null);
    final criterionName = widget.criteria.description.isNotEmpty
        ? widget.criteria.description
        : 'Criterion #${widget.criteria.id}';

    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            color: widget.isCompleted
                ? const Color(0xFF1EFF00).withValues(alpha: 0.03)
                : Colors.transparent,
            border: Border(
              left: BorderSide(
                color: widget.isCompleted
                    ? const Color(0xFF1EFF00).withValues(alpha: 0.6)
                    : AppTheme.surfaceBorder.withValues(alpha: 0.3),
                width: 3,
              ),
            ),
          ),
          child: Column(
            children: [
              // Main row — tappable if has quest chain
              GestureDetector(
                onTap: hasNamedQuests
                    ? () => setState(() => _expanded = !_expanded)
                    : null,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      Icon(
                        widget.isCompleted
                            ? Icons.check_circle_rounded
                            : Icons.circle_outlined,
                        color: widget.isCompleted
                            ? const Color(0xFF1EFF00)
                            : AppTheme.textTertiary.withValues(alpha: 0.4),
                        size: 18,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              criterionName,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                color: widget.isCompleted
                                    ? AppTheme.textTertiary
                                    : AppTheme.textPrimary,
                                decoration: widget.isCompleted
                                    ? TextDecoration.lineThrough
                                    : null,
                                decorationColor:
                                    AppTheme.textTertiary.withValues(alpha: 0.5),
                              ),
                            ),
                            // Enrichment subtitle: asset name, amount, quest chain
                            if (_buildSubtitle() != null) ...[
                              const SizedBox(height: 3),
                              _buildSubtitle()!,
                            ],
                          ],
                        ),
                      ),
                      if (widget.enriched != null && !widget.enriched!.isGroup)
                        _TypeTag(type: widget.enriched!.type),
                      if (hasNamedQuests) ...[
                        const SizedBox(width: 8),
                        AnimatedRotation(
                          turns: _expanded ? 0.25 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: Icon(Icons.chevron_right_rounded,
                              size: 18,
                              color:
                                  AppTheme.textTertiary.withValues(alpha: 0.5)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // Expanded quest chain guide
              if (_expanded && hasNamedQuests)
                _QuestChainGuide(questLine: questLine),
            ],
          ),
        ),
      ),
    );
  }
}

/// Expanded quest chain — shows ordered list of quests in the chain.
class _QuestChainGuide extends StatelessWidget {
  final QuestLineInfo questLine;

  const _QuestChainGuide({required this.questLine});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(44, 0, 14, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFFFFD100).withValues(alpha: 0.08),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Quest chain header
          Row(
            children: [
              Icon(Icons.auto_stories_rounded,
                  size: 14,
                  color: const Color(0xFFFFD100).withValues(alpha: 0.7)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  questLine.name.isNotEmpty
                      ? questLine.name
                      : 'Quest Chain',
                  style: GoogleFonts.rajdhani(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFFFD100).withValues(alpha: 0.8),
                  ),
                ),
              ),
              Text(
                '${questLine.questCount} quest${questLine.questCount == 1 ? '' : 's'}',
                style: GoogleFonts.inter(
                    fontSize: 10, color: AppTheme.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Quest list — only show quests that have names
          ...questLine.quests.where((q) => q.name != null).toList().asMap().entries.map((entry) {
            final index = entry.key;
            final quest = entry.value;
            final namedQuests = questLine.quests.where((q) => q.name != null).toList();
            final isLast = index == namedQuests.length - 1;
            final stepNum = index + 1;

            return Padding(
              padding: const EdgeInsets.only(bottom: 1),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Step number + connector line
                  SizedBox(
                    width: 24,
                    child: Column(
                      children: [
                        Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isLast
                                ? const Color(0xFFFFD100).withValues(alpha: 0.12)
                                : AppTheme.surfaceBorder.withValues(alpha: 0.3),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '$stepNum',
                            style: GoogleFonts.rajdhani(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: isLast
                                  ? const Color(0xFFFFD100)
                                      .withValues(alpha: 0.8)
                                  : AppTheme.textTertiary,
                            ),
                          ),
                        ),
                        if (!isLast)
                          Container(
                            width: 1,
                            height: 8,
                            color:
                                AppTheme.surfaceBorder.withValues(alpha: 0.2),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Quest name or ID
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        quest.name ?? 'Quest #${quest.id}',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: quest.name != null
                              ? AppTheme.textSecondary
                              : AppTheme.textTertiary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// =============================================================================
// Meta-criterion — links to another achievement
// =============================================================================

class _MetaCriterionRow extends StatelessWidget {
  final AchievementCriteria criteria;
  final bool isCompleted;
  final AchievementProvider provider;

  const _MetaCriterionRow({
    required this.criteria,
    required this.isCompleted,
    required this.provider,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openLinked(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Container(
            decoration: BoxDecoration(
              color: isCompleted
                  ? const Color(0xFF1EFF00).withValues(alpha: 0.03)
                  : const Color(0xFF3FC7EB).withValues(alpha: 0.03),
              border: Border(
                left: BorderSide(
                  color: isCompleted
                      ? const Color(0xFF1EFF00).withValues(alpha: 0.6)
                      : const Color(0xFF3FC7EB).withValues(alpha: 0.5),
                  width: 3,
                ),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(
                  isCompleted
                      ? Icons.check_circle_rounded
                      : Icons.emoji_events_outlined,
                  color: isCompleted
                      ? const Color(0xFF1EFF00)
                      : const Color(0xFF3FC7EB).withValues(alpha: 0.6),
                  size: 18,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    criteria.linkedAchievementName ?? criteria.description,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: isCompleted
                          ? AppTheme.textTertiary
                          : const Color(0xFF3FC7EB),
                      decoration:
                          isCompleted ? TextDecoration.lineThrough : null,
                      decorationColor:
                          AppTheme.textTertiary.withValues(alpha: 0.5),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: isCompleted
                        ? AppTheme.textTertiary
                        : const Color(0xFF3FC7EB).withValues(alpha: 0.5),
                    size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openLinked(BuildContext context) async {
    final id = criteria.linkedAchievementId;
    if (id == null) return;

    final progress = provider.progress;
    final ach = await provider.fetchAchievement(id);
    if (ach == null || !context.mounted) return;

    final entry = progress?.achievements[id];
    int cc = 0, tc = 0;
    if (ach.criteria != null && ach.criteria!.childCriteria.isNotEmpty) {
      tc = ach.criteria!.childCriteria.length;
      for (final c in ach.criteria!.childCriteria) {
        if (entry?.criteriaProgress[c.id] == true) cc++;
      }
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AchievementDetailScreen(
          display: AchievementDisplay(
            achievement: ach,
            isCompleted: entry?.isCompleted ?? false,
            completedTimestamp: entry?.completedTimestamp,
            criteriaProgress: entry?.criteriaProgress ?? {},
            completedCriteria: cc,
            totalCriteria: tc,
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Group/container criterion — expandable section with sub-criteria
// =============================================================================

class _GroupCriterionSection extends StatelessWidget {
  final AchievementCriteria criteria;
  final AchievementDisplay display;
  final AchievementEnrichment? enrichment;
  final AchievementProvider provider;

  const _GroupCriterionSection({
    required this.criteria,
    required this.display,
    required this.enrichment,
    required this.provider,
  });

  @override
  Widget build(BuildContext context) {
    // Check if all sub-criteria are completed
    final allDone = criteria.childCriteria.every(
        (c) => display.criteriaProgress[c.id] ?? false);

    return Container(
      margin: const EdgeInsets.only(bottom: 2, top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Group header
          if (criteria.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 6),
              child: Row(
                children: [
                  Icon(
                    allDone
                        ? Icons.check_circle_rounded
                        : Icons.circle_outlined,
                    color: allDone
                        ? const Color(0xFF1EFF00)
                        : AppTheme.textTertiary.withValues(alpha: 0.4),
                    size: 14,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    criteria.description.toUpperCase(),
                    style: GoogleFonts.rajdhani(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textTertiary,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          // Sub-criteria
          Container(
            margin: const EdgeInsets.only(left: 6),
            child: Column(
              children: criteria.childCriteria.map((child) {
                final isCompleted =
                    display.criteriaProgress[child.id] ?? false;
                final childEnriched = enrichment?.findCriterion(child.id);

                if (child.isMetaCriterion) {
                  return _MetaCriterionRow(
                    criteria: child,
                    isCompleted: isCompleted,
                    provider: provider,
                  );
                }

                return _CriterionChecklistRow(
                  criteria: child,
                  isCompleted: isCompleted,
                  enriched: childEnriched,
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Small building blocks
// =============================================================================

/// Subtle inline tag showing criteria type.
class _TypeTag extends StatelessWidget {
  final String type;

  const _TypeTag({required this.type});

  @override
  Widget build(BuildContext context) {
    final (String label, Color color) = switch (type) {
      'quest' || 'daily_quest' || 'world_quest' || 'questline' =>
        ('Quest', const Color(0xFFFFD100)),
      'kill' => ('Kill', const Color(0xFFFF6B6B)),
      'achievement' => ('Achievement', const Color(0xFF3FC7EB)),
      'reputation' => ('Rep', const Color(0xFF9B59B6)),
      'currency' => ('Currency', const Color(0xFFF39C12)),
      _ => ('', Colors.transparent),
    };

    if (label.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: GoogleFonts.rajdhani(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color.withValues(alpha: 0.6),
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _TagBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _TagBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: GoogleFonts.inter(
              fontSize: 11, fontWeight: FontWeight.w500, color: color)),
    );
  }
}

class _AchievementIcon extends StatelessWidget {
  final String? iconUrl;
  final double size;

  const _AchievementIcon({this.iconUrl, required this.size});

  @override
  Widget build(BuildContext context) {
    if (iconUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: iconUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          placeholder: (_, __) => _placeholder(),
          errorWidget: (_, __, ___) => _placeholder(),
        ),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.surfaceBorder, width: 1),
      ),
      child: Icon(Icons.emoji_events_outlined,
          color: AppTheme.textTertiary, size: size * 0.5),
    );
  }
}

class _PointsBadge extends StatelessWidget {
  final int points;

  const _PointsBadge({required this.points});

  @override
  Widget build(BuildContext context) {
    if (points == 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFFFD100).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text('$points',
          style: GoogleFonts.rajdhani(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: const Color(0xFFFFD100))),
    );
  }
}

/// Row showing enrichment metadata (instance name, reward, etc.)
class _MetadataRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;

  const _MetadataRow(
      {required this.icon, required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color.withValues(alpha: 0.6)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: color.withValues(alpha: 0.7),
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _CriteriaProgressBar extends StatelessWidget {
  final int completed;
  final int total;

  const _CriteriaProgressBar(
      {required this.completed, required this.total});

  @override
  Widget build(BuildContext context) {
    final fraction = total > 0 ? completed / total : 0.0;
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction,
              backgroundColor: AppTheme.surfaceBorder,
              valueColor: const AlwaysStoppedAnimation(Color(0xFF3FC7EB)),
              minHeight: 4,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text('$completed/$total',
            style: GoogleFonts.rajdhani(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary)),
      ],
    );
  }
}
