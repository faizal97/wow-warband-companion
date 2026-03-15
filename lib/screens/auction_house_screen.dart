import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import '../models/auction_item.dart';
import '../services/auction_house_provider.dart';
import '../theme/app_theme.dart';

class AuctionHouseScreen extends StatefulWidget {
  const AuctionHouseScreen({super.key});

  @override
  State<AuctionHouseScreen> createState() => _AuctionHouseScreenState();
}

class _AuctionHouseScreenState extends State<AuctionHouseScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuctionHouseProvider>().init();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      context.read<AuctionHouseProvider>().clearSearch();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () {
      context.read<AuctionHouseProvider>().search(query);
    });
  }

  @override
  Widget build(BuildContext context) {
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
          child: Consumer<AuctionHouseProvider>(
            builder: (context, provider, _) {
              final showSearch = _searchController.text.trim().isNotEmpty;

              return RefreshIndicator(
                onRefresh: () => provider.refreshPrices(),
                color: const Color(0xFFFFD700),
                backgroundColor: AppTheme.surfaceElevated,
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(child: _buildHeader()),
                    SliverToBoxAdapter(child: _buildSearchBar()),
                    SliverToBoxAdapter(
                      child: _buildSectionLabel(
                        showSearch ? 'RESULTS' : 'WATCHLIST',
                        showSearch ? null : '${provider.watchlist.length}',
                        showSearch ? null : provider.dataLastUpdated,
                      ),
                    ),
                    if (showSearch)
                      ..._buildSearchResults(provider)
                    else
                      ..._buildWatchlist(provider),
                    const SliverToBoxAdapter(child: SizedBox(height: 40)),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
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
                'AUCTION HOUSE',
                style: GoogleFonts.rajdhani(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textTertiary,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Price Check',
                style: GoogleFonts.rajdhani(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: TextField(
        controller: _searchController,
        style: GoogleFonts.inter(
          fontSize: 14,
          color: AppTheme.textPrimary,
        ),
        decoration: InputDecoration(
          hintText: 'Search items...',
          hintStyle: GoogleFonts.inter(
            fontSize: 14,
            color: AppTheme.textTertiary,
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: AppTheme.textTertiary,
            size: 18,
          ),
          suffixIcon: _searchController.text.isNotEmpty
              ? GestureDetector(
                  onTap: () {
                    _searchController.clear();
                    context.read<AuctionHouseProvider>().clearSearch();
                    setState(() {});
                  },
                  child: const Icon(
                    Icons.close_rounded,
                    color: AppTheme.textTertiary,
                    size: 18,
                  ),
                )
              : null,
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
            borderSide:
                const BorderSide(color: Color(0xFF3FC7EB), width: 1),
          ),
        ),
        onChanged: (value) {
          setState(() {});
          _onSearchChanged(value);
        },
      ),
    );
  }

  Widget _buildSectionLabel(String label, String? count, DateTime? lastUpdated) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        children: [
          Text(
            label,
            style: GoogleFonts.rajdhani(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.textTertiary,
              letterSpacing: 1.5,
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: 6),
            Text(
              '($count)',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: AppTheme.textTertiary,
              ),
            ),
          ],
          const Spacer(),
          if (lastUpdated != null)
            Text(
              _timeAgo(lastUpdated),
              style: GoogleFonts.inter(
                fontSize: 11,
                color: AppTheme.textTertiary,
              ),
            ),
        ],
      ),
    );
  }

  String _timeAgo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'just now';
  }

  List<Widget> _buildSearchResults(AuctionHouseProvider provider) {
    if (provider.isSearching) {
      return [
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(40),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF3FC7EB),
                ),
              ),
            ),
          ),
        ),
      ];
    }

    if (provider.searchResults.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Center(
              child: Text(
                'No items found',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: AppTheme.textTertiary,
                ),
              ),
            ),
          ),
        ),
      ];
    }

    return [
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final item = provider.searchResults[index];
            return _AuctionItemTile(
              item: item,
              isFavorited: provider.isInWatchlist(item.id),
              showPrice: false,
              onFavoriteTap: () {
                if (provider.isInWatchlist(item.id)) {
                  provider.removeFromWatchlist(item.id);
                } else {
                  provider.addToWatchlist(item);
                }
              },
            );
          },
          childCount: provider.searchResults.length,
        ),
      ),
    ];
  }

  List<Widget> _buildWatchlist(AuctionHouseProvider provider) {
    if (provider.watchlist.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 60),
            child: Column(
              children: [
                Icon(
                  Icons.store_rounded,
                  color: AppTheme.textTertiary.withValues(alpha: 0.5),
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(
                  'No items in watchlist',
                  style: GoogleFonts.rajdhani(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Search for items to track their prices',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppTheme.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ];
    }

    return [
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final item = provider.watchlist[index];
            return _AuctionItemTile(
              item: item,
              isFavorited: true,
              showPrice: true,
              isLoadingPrice: provider.isLoadingPrices && item.price == null,
              onFavoriteTap: () => provider.removeFromWatchlist(item.id),
            );
          },
          childCount: provider.watchlist.length,
        ),
      ),
    ];
  }
}

class _AuctionItemTile extends StatelessWidget {
  final AuctionItem item;
  final bool isFavorited;
  final bool showPrice;
  final bool isLoadingPrice;
  final VoidCallback onFavoriteTap;

  const _AuctionItemTile({
    required this.item,
    required this.isFavorited,
    required this.showPrice,
    this.isLoadingPrice = false,
    required this.onFavoriteTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.surfaceBorder, width: 1),
      ),
      child: Row(
        children: [
          _buildIcon(),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: GoogleFonts.rajdhani(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                if (showPrice && item.price != null)
                  _buildPriceRow()
                else if (showPrice && isLoadingPrice)
                  _buildPriceShimmer()
                else if (showPrice)
                  Text(
                    'Price unavailable',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: AppTheme.textTertiary,
                    ),
                  )
                else if (item.subclass != null)
                  Text(
                    item.subclass!,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          if (showPrice && item.totalQuantity != null) ...[
            Text(
              '${item.formattedQuantity} avail',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: AppTheme.textTertiary,
              ),
            ),
            const SizedBox(width: 12),
          ],
          GestureDetector(
            onTap: onFavoriteTap,
            child: Icon(
              isFavorited ? Icons.star_rounded : Icons.star_outline_rounded,
              color: isFavorited
                  ? const Color(0xFFFFD700)
                  : AppTheme.textTertiary,
              size: 24,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIcon() {
    if (item.iconUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 40,
          height: 40,
          child: CachedNetworkImage(
            imageUrl: item.iconUrl!,
            fit: BoxFit.cover,
            placeholder: (_, __) => _iconPlaceholder(),
            errorWidget: (_, __, ___) => _iconPlaceholder(),
          ),
        ),
      );
    }
    return _iconPlaceholder();
  }

  Widget _iconPlaceholder() {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: const Color(0xFFFFD700).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFFFFD700).withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: const Icon(
        Icons.inventory_2_outlined,
        color: Color(0xFFFFD700),
        size: 18,
      ),
    );
  }

  Widget _buildPriceRow() {
    return Row(
      children: [
        Text(
          '${item.gold}',
          style: GoogleFonts.rajdhani(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: const Color(0xFFFFD700),
          ),
        ),
        Text(
          'g ',
          style: GoogleFonts.rajdhani(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: const Color(0xFFFFD700).withValues(alpha: 0.6),
          ),
        ),
        Text(
          item.silver.toString().padLeft(2, '0'),
          style: GoogleFonts.rajdhani(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: const Color(0xFFC0C0C0),
          ),
        ),
        Text(
          's ',
          style: GoogleFonts.rajdhani(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: const Color(0xFFC0C0C0).withValues(alpha: 0.6),
          ),
        ),
        Text(
          item.copper.toString().padLeft(2, '0'),
          style: GoogleFonts.rajdhani(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: const Color(0xFFB87333),
          ),
        ),
        Text(
          'c',
          style: GoogleFonts.rajdhani(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: const Color(0xFFB87333).withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  Widget _buildPriceShimmer() {
    return Shimmer.fromColors(
      baseColor: AppTheme.surface,
      highlightColor: AppTheme.surfaceElevated,
      child: Container(
        width: 120,
        height: 16,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }
}
