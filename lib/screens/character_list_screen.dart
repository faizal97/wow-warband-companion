import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import '../models/character.dart';
import '../services/character_provider.dart';
import '../theme/app_theme.dart';
import '../theme/wow_class_colors.dart';
import '../widgets/update_dialog.dart';
import 'character_dashboard_screen.dart';

enum GroupBy { realm, characterClass, race, faction }

enum SortBy { none, levelAsc, levelDesc, nameAsc, nameDesc, lastLoginAsc, lastLoginDesc }

class CharacterListScreen extends StatefulWidget {
  const CharacterListScreen({super.key});

  @override
  State<CharacterListScreen> createState() => _CharacterListScreenState();
}

class _CharacterListScreenState extends State<CharacterListScreen> {
  String _searchQuery = '';
  GroupBy? _groupBy = GroupBy.realm;
  SortBy _sortBy = SortBy.none;
  final _searchController = TextEditingController();
  bool _showSearch = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      UpdateDialog.checkAndShow(context);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<WowCharacter> _filterCharacters(List<WowCharacter> characters) {
    if (_searchQuery.isEmpty) return characters;
    final query = _searchQuery.toLowerCase();
    return characters
        .where((c) => c.name.toLowerCase().contains(query))
        .toList();
  }

  List<WowCharacter> _sortCharacters(List<WowCharacter> characters) {
    if (_sortBy == SortBy.none) return characters;
    final sorted = List<WowCharacter>.from(characters);
    sorted.sort((a, b) => switch (_sortBy) {
      SortBy.levelAsc => a.level.compareTo(b.level),
      SortBy.levelDesc => b.level.compareTo(a.level),
      SortBy.nameAsc => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      SortBy.nameDesc => b.name.toLowerCase().compareTo(a.name.toLowerCase()),
      SortBy.lastLoginAsc => (a.lastLoginTimestamp ?? 0).compareTo(b.lastLoginTimestamp ?? 0),
      SortBy.lastLoginDesc => (b.lastLoginTimestamp ?? 0).compareTo(a.lastLoginTimestamp ?? 0),
      SortBy.none => 0,
    });
    return sorted;
  }

  Map<String, List<WowCharacter>> _groupCharacters(
      List<WowCharacter> characters) {
    if (_groupBy == null) return {};
    final grouped = <String, List<WowCharacter>>{};
    for (final char in characters) {
      final key = switch (_groupBy!) {
        GroupBy.realm => char.realm,
        GroupBy.characterClass => char.characterClass,
        GroupBy.race => char.race,
        GroupBy.faction => char.faction,
      };
      grouped.putIfAbsent(key, () => []).add(char);
    }
    return grouped;
  }

  String _groupByLabel(GroupBy groupBy) {
    return switch (groupBy) {
      GroupBy.realm => 'Realm',
      GroupBy.characterClass => 'Class',
      GroupBy.race => 'Race',
      GroupBy.faction => 'Faction',
    };
  }

  String _sortByLabel(SortBy sortBy) {
    return switch (sortBy) {
      SortBy.none => 'Default',
      SortBy.levelAsc => 'Level ↑',
      SortBy.levelDesc => 'Level ↓',
      SortBy.nameAsc => 'Name A-Z',
      SortBy.nameDesc => 'Name Z-A',
      SortBy.lastLoginAsc => 'Oldest login',
      SortBy.lastLoginDesc => 'Recent login',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<CharacterProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Color(0xFF148EFF),
              ),
            );
          }

          final filtered = _filterCharacters(provider.characters);
          final sorted = _sortCharacters(filtered);
          final isGrouped = _groupBy != null && _sortBy == SortBy.none;
          final grouped = isGrouped ? _groupCharacters(sorted) : null;

          return Container(
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
              child: RefreshIndicator(
                onRefresh: () => provider.forceRefresh(),
                color: const Color(0xFF3FC7EB),
                backgroundColor: AppTheme.surface,
                child: CustomScrollView(
                slivers: [
                  // Header
                  SliverToBoxAdapter(
                    child: _buildHeader(context, provider),
                  ),

                  // Search bar
                  if (_showSearch)
                    SliverToBoxAdapter(
                      child: _buildSearchBar(),
                    ),

                  // Toolbar
                  SliverToBoxAdapter(
                    child: _buildToolbar(provider, filtered),
                  ),

                  // Empty state
                  if (filtered.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(40),
                        child: Center(
                          child: Text(
                            _searchQuery.isNotEmpty
                                ? 'No characters matching "$_searchQuery"'
                                : 'No characters found',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: AppTheme.textTertiary,
                            ),
                          ),
                        ),
                      ),
                    ),

                  // Grouped list
                  if (isGrouped && grouped != null)
                    for (final group in grouped.keys) ...[
                      SliverToBoxAdapter(
                        child: _buildGroupHeader(group,
                            count: grouped[group]!.length),
                      ),
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final character = grouped[group]![index];
                            return _CharacterCard(
                              character: character,
                              onTap: () =>
                                  _openCharacter(context, provider, character),
                            );
                          },
                          childCount: grouped[group]!.length,
                        ),
                      ),
                    ],

                  // Flat sorted list
                  if (!isGrouped)
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final character = sorted[index];
                          return _CharacterCard(
                            character: character,
                            onTap: () =>
                                _openCharacter(context, provider, character),
                          );
                        },
                        childCount: sorted.length,
                      ),
                    ),

                  const SliverToBoxAdapter(
                    child: SizedBox(height: 40),
                  ),
                ],
              ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context, CharacterProvider provider) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Icon(
              Icons.arrow_back_rounded,
              color: AppTheme.textSecondary,
              size: 22,
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'WOW WARBAND',
                style: GoogleFonts.rajdhani(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textTertiary,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Characters',
                style: GoogleFonts.rajdhani(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                  height: 1.0,
                ),
              ),
            ],
          ),
          const Spacer(),
          // Search toggle
          IconButton(
            onPressed: () {
              setState(() {
                _showSearch = !_showSearch;
                if (!_showSearch) {
                  _searchQuery = '';
                  _searchController.clear();
                }
              });
            },
            icon: Icon(
              _showSearch ? Icons.close_rounded : Icons.search_rounded,
              color: _showSearch
                  ? AppTheme.textPrimary
                  : AppTheme.textTertiary,
              size: 20,
            ),
          ),
          IconButton(
            onPressed: () => provider.forceRefresh(),
            icon: const Icon(
              Icons.refresh_rounded,
              color: AppTheme.textTertiary,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: TextField(
        controller: _searchController,
        autofocus: true,
        style: GoogleFonts.inter(
          fontSize: 14,
          color: AppTheme.textPrimary,
        ),
        decoration: InputDecoration(
          hintText: 'Search by name...',
          hintStyle: GoogleFonts.inter(
            fontSize: 14,
            color: AppTheme.textTertiary,
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: AppTheme.textTertiary,
            size: 18,
          ),
          filled: true,
          fillColor: AppTheme.surface,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppTheme.surfaceBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppTheme.surfaceBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
                color: Color(0xFF3FC7EB), width: 1),
          ),
        ),
        onChanged: (value) => setState(() => _searchQuery = value),
      ),
    );
  }

  Widget _buildToolbar(CharacterProvider provider,
      List<WowCharacter> filtered) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Row(
        children: [
          Text(
            '${filtered.length} characters',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: AppTheme.textTertiary,
            ),
          ),
          const Spacer(),
          _buildSortByButton(),
          const SizedBox(width: 8),
          _buildGroupByButton(),
        ],
      ),
    );
  }

  Widget _buildSortByButton() {
    final isActive = _sortBy != SortBy.none;

    return GestureDetector(
      onTap: () => _showSortOptions(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF3FC7EB).withValues(alpha: 0.08)
              : AppTheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive
                ? const Color(0xFF3FC7EB).withValues(alpha: 0.3)
                : AppTheme.surfaceBorder,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.swap_vert_rounded,
              color: isActive
                  ? const Color(0xFF3FC7EB)
                  : AppTheme.textTertiary,
              size: 14,
            ),
            const SizedBox(width: 6),
            Text(
              isActive ? _sortByLabel(_sortBy) : 'Sort',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isActive
                    ? const Color(0xFF3FC7EB)
                    : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSortOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Text(
                'SORT BY',
                style: GoogleFonts.rajdhani(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textTertiary,
                  letterSpacing: 1.5,
                ),
              ),
            ),
            for (final sort in SortBy.values)
              _buildSortOption(sort),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildSortOption(SortBy sortBy) {
    final isSelected = _sortBy == sortBy;

    return GestureDetector(
      onTap: () {
        setState(() {
          _sortBy = sortBy;
          // When sorting, disable grouping
          if (sortBy != SortBy.none) {
            _groupBy = null;
          } else {
            _groupBy = GroupBy.realm;
          }
        });
        Navigator.pop(context);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        color: isSelected
            ? const Color(0xFF3FC7EB).withValues(alpha: 0.06)
            : Colors.transparent,
        child: Row(
          children: [
            Icon(
              isSelected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: isSelected
                  ? const Color(0xFF3FC7EB)
                  : AppTheme.textTertiary,
              size: 18,
            ),
            const SizedBox(width: 14),
            Text(
              _sortByLabel(sortBy),
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected
                    ? AppTheme.textPrimary
                    : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupByButton() {
    final isActive = _groupBy != null;

    return GestureDetector(
      onTap: () => _showGroupByOptions(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF3FC7EB).withValues(alpha: 0.08)
              : AppTheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive
                ? const Color(0xFF3FC7EB).withValues(alpha: 0.3)
                : AppTheme.surfaceBorder,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.workspaces_outline,
              color: isActive
                  ? const Color(0xFF3FC7EB)
                  : AppTheme.textTertiary,
              size: 14,
            ),
            const SizedBox(width: 6),
            Text(
              isActive ? _groupByLabel(_groupBy!) : 'Group',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isActive
                    ? const Color(0xFF3FC7EB)
                    : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showGroupByOptions() {
    final provider = context.read<CharacterProvider>();
    final characters = provider.characters;

    // Build options with counts from actual data
    final options = <GroupBy, List<String>>{};
    for (final gb in GroupBy.values) {
      final values = <String>{};
      for (final c in characters) {
        values.add(switch (gb) {
          GroupBy.realm => c.realm,
          GroupBy.characterClass => c.characterClass,
          GroupBy.race => c.race,
          GroupBy.faction => c.faction,
        });
      }
      options[gb] = values.toList()..sort();
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Text(
                'GROUP BY',
                style: GoogleFonts.rajdhani(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textTertiary,
                  letterSpacing: 1.5,
                ),
              ),
            ),
            for (final gb in GroupBy.values)
              _buildGroupByOption(gb, options[gb]!),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupByOption(GroupBy groupBy, List<String> values) {
    final isSelected = _groupBy == groupBy;

    return GestureDetector(
      onTap: () {
        setState(() {
          _groupBy = groupBy;
          _sortBy = SortBy.none; // Clear sorting when grouping
        });
        Navigator.pop(context);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        color: isSelected
            ? const Color(0xFF3FC7EB).withValues(alpha: 0.06)
            : Colors.transparent,
        child: Row(
          children: [
            Icon(
              isSelected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: isSelected
                  ? const Color(0xFF3FC7EB)
                  : AppTheme.textTertiary,
              size: 18,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _groupByLabel(groupBy),
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w400,
                      color: isSelected
                          ? AppTheme.textPrimary
                          : AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    values.join(', '),
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppTheme.textTertiary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Text(
              '${values.length}',
              style: GoogleFonts.rajdhani(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupHeader(String group, {int count = 0}) {
    final bool showClassDot = _groupBy == GroupBy.characterClass;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          if (showClassDot) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: WowClassColors.forClass(group),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            group.toUpperCase(),
            style: GoogleFonts.rajdhani(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: showClassDot
                  ? WowClassColors.forClass(group)
                  : AppTheme.textTertiary,
              letterSpacing: 1.5,
            ),
          ),
          if (count > 0) ...[
            const SizedBox(width: 6),
            Text(
              '($count)',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: AppTheme.textTertiary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _openCharacter(
      BuildContext context, CharacterProvider provider, WowCharacter character) {
    provider.selectCharacter(character);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const CharacterDashboardScreen(),
      ),
    );
  }

}

/// A character card for the list — shows avatar/level, name, spec, ilvl.
class _CharacterCard extends StatelessWidget {
  final WowCharacter character;
  final VoidCallback onTap;

  const _CharacterCard({required this.character, required this.onTap});

  bool get _isEnriched => character.activeSpec != 'Unknown';
  bool get _isLowLevel => character.level < 70;

  @override
  Widget build(BuildContext context) {
    final classColor = WowClassColors.forClass(character.characterClass);

    return Opacity(
      opacity: _isLowLevel ? 0.5 : 1.0,
      child: GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppTheme.surfaceBorder,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            _buildAvatar(classColor),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    character.name,
                    style: GoogleFonts.rajdhani(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: classColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(child: _buildSubtitle(classColor)),
                    ],
                  ),
                ],
              ),
            ),
            _buildItemLevel(),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: character.faction == 'Horde'
                    ? const Color(0xFF8C1616).withValues(alpha: 0.2)
                    : const Color(0xFF162E8C).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                character.faction == 'Horde' ? 'H' : 'A',
                style: GoogleFonts.rajdhani(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: character.faction == 'Horde'
                      ? const Color(0xFFCC3333)
                      : const Color(0xFF3366CC),
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppTheme.textTertiary,
              size: 20,
            ),
          ],
        ),
      ),
    ),
    );
  }

  Widget _buildAvatar(Color classColor) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (character.avatarUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 48,
                height: 48,
                child: CachedNetworkImage(
                  imageUrl: character.avatarUrl!,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => _levelBadge(classColor),
                  errorWidget: (_, __, ___) => _levelBadge(classColor),
                ),
              ),
            )
          else
            _levelBadge(classColor),
          if (character.avatarUrl != null)
            Positioned(
              right: -4,
              bottom: -4,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: classColor.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Text(
                  character.level.toString(),
                  style: GoogleFonts.rajdhani(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: classColor,
                    height: 1.2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _levelBadge(Color classColor) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: classColor.withValues(alpha: 0.1),
        border: Border.all(
          color: classColor.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Center(
        child: Text(
          character.level.toString(),
          style: GoogleFonts.rajdhani(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: classColor,
          ),
        ),
      ),
    );
  }

  Widget _buildSubtitle(Color classColor) {
    if (_isEnriched) {
      final lastLogin = _formatLastLogin();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${character.activeSpec} ${character.characterClass}',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: AppTheme.textSecondary,
            ),
          ),
          if (lastLogin != null)
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                lastLogin,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: AppTheme.textTertiary,
                ),
              ),
            ),
        ],
      );
    }

    return Shimmer.fromColors(
      baseColor: AppTheme.textSecondary,
      highlightColor: AppTheme.textTertiary,
      child: Text(
        '${character.race} ${character.characterClass}',
        style: GoogleFonts.inter(
          fontSize: 13,
          color: AppTheme.textSecondary,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  String? _formatLastLogin() {
    if (character.lastLoginTimestamp == null) return null;
    final lastLogin = DateTime.fromMillisecondsSinceEpoch(
        character.lastLoginTimestamp!);
    final diff = DateTime.now().difference(lastLogin);

    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 30) return '${diff.inDays}d ago';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}mo ago';
    return '${(diff.inDays / 365).floor()}y ago';
  }

  Widget _buildItemLevel() {
    if (_isEnriched && character.equippedItemLevel != null) {
      final ilvl = character.equippedItemLevel!;
      final ilvlColor = _ilvlRarityColor(ilvl);

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: ilvlColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: ilvlColor.withValues(alpha: 0.25),
            width: 1,
          ),
        ),
        child: Text(
          '$ilvl',
          style: GoogleFonts.rajdhani(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: ilvlColor,
          ),
        ),
      );
    }

    if (!_isEnriched) {
      return Shimmer.fromColors(
        baseColor: AppTheme.surfaceElevated,
        highlightColor: AppTheme.surfaceBorder,
        child: Container(
          width: 36,
          height: 22,
          decoration: BoxDecoration(
            color: AppTheme.surfaceElevated,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Color _ilvlRarityColor(int ilvl) {
    if (ilvl >= 620) return const Color(0xFFFF8000);
    if (ilvl >= 610) return const Color(0xFFA335EE);
    if (ilvl >= 600) return const Color(0xFF0070DD);
    if (ilvl >= 580) return const Color(0xFF1EFF00);
    return AppTheme.textSecondary;
  }
}
