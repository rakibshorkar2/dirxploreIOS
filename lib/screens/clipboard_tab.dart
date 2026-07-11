import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:ui';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/app_state.dart';
import '../providers/download_provider.dart';
import '../providers/clipboard_provider.dart';
import '../models/clipboard_item.dart';
import '../services/haptic_service.dart';

class ClipboardTab extends StatefulWidget {
  const ClipboardTab({super.key});

  @override
  State<ClipboardTab> createState() => _ClipboardTabState();
}

class _ClipboardTabState extends State<ClipboardTab>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _scrollController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _pulseController.repeat(reverse: true);
      context.read<ClipboardProvider>().checkForNewClipboard();
    } else if (state == AppLifecycleState.paused) {
      _pulseController.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final provider = context.watch<ClipboardProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isAmoled = appState.trueAmoledDark && isDark;
    final items = provider.items;
    final urlItems = items.where((i) => i.type == ClipboardContentType.url).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          color: isAmoled ? Colors.black : null,
          gradient: isAmoled
              ? null
              : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Theme.of(context).colorScheme.surface,
                    Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.8),
                  ],
                ),
        ),
        child: CustomScrollView(
          controller: _scrollController,
          slivers: _buildSlivers(
              context, provider, appState, isDark, isAmoled, items, urlItems),
        ),
      ),
    );
  }

  List<Widget> _buildSlivers(
    BuildContext context,
    ClipboardProvider provider,
    AppState appState,
    bool isDark,
    bool isAmoled,
    List<ClipboardItem> items,
    List<ClipboardItem> urlItems,
  ) {
    if (items.isEmpty &&
        !provider.showFavoritesOnly &&
        provider.searchQuery.isEmpty &&
        provider.newlyDetectedItem == null) {
      return [
        _buildAppBar(context, provider, isDark),
        SliverFillRemaining(
          hasScrollBody: false,
          child: _buildEmptyState(context, isDark),
        ),
      ];
    }

    final slivers = <Widget>[
      _buildAppBar(context, provider, isDark),
      SliverToBoxAdapter(
        child: _buildStatusCard(context, provider, appState, isDark),
      ),
      SliverToBoxAdapter(
        child: _buildSmartActions(context, provider, isDark),
      ),
      if (urlItems.isNotEmpty)
        SliverToBoxAdapter(
          child:
              _buildRecentlyDetected(context, provider, urlItems, isDark),
        ),
      SliverPersistentHeader(
        pinned: true,
        delegate: _SearchHeaderDelegate(
          _buildSearchAndFilters(context, provider, isDark),
        ),
      ),
    ];

    if (provider.newlyDetectedItem != null && items.isEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: _buildDetectionBanner(context, provider),
        ),
      );
    }

    if (items.isNotEmpty) {
      if (provider.isMultiSelectMode) {
        slivers.add(
          SliverToBoxAdapter(
            child: _buildMultiSelectBar(context, provider),
          ),
        );
      }
      if (provider.newlyDetectedItem != null) {
        slivers.add(
          SliverToBoxAdapter(
            child: _buildDetectionBanner(context, provider),
          ),
        );
      }
      slivers.addAll(_buildHistorySections(
          context, provider, items));
    }

    if (items.isEmpty && provider.searchQuery.isNotEmpty) {
      slivers.add(
        SliverFillRemaining(
          hasScrollBody: false,
          child: _buildSearchEmptyState(context, isDark),
        ),
      );
    }

    if (items.isEmpty && provider.showFavoritesOnly) {
      slivers.add(
        SliverFillRemaining(
          hasScrollBody: false,
          child: _buildFavoritesEmptyState(context, isDark),
        ),
      );
    }

    slivers.add(const SliverToBoxAdapter(
      child: SizedBox(height: 100),
    ));

    return slivers;
  }

  Widget _buildAppBar(
      BuildContext context, ClipboardProvider provider, bool isDark) {
    final cs = Theme.of(context).colorScheme;
    return SliverAppBar(
      expandedHeight: 108,
      floating: false,
      pinned: true,
      stretch: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      flexibleSpace: _buildGlassAppbarBg(isDark),
      title: Padding(
        padding: const EdgeInsetsDirectional.only(start: 4, bottom: 6),
        child: Text(
          'Clipboard',
          style: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.37,
            color: cs.onSurface,
          ),
        ),
      ),
      centerTitle: false,
      actions: [
        if (provider.isMultiSelectMode)
          CupertinoButton(
            padding: EdgeInsets.zero,
            child: Icon(CupertinoIcons.xmark_circle_fill,
                color: cs.onSurface.withValues(alpha: 0.6), size: 22),
            onPressed: () => provider.toggleMultiSelectMode(),
          )
        else ...[
          CupertinoButton(
            padding: const EdgeInsets.all(8),
            child: Icon(CupertinoIcons.star,
                color: provider.showFavoritesOnly
                    ? CupertinoColors.systemYellow
                    : cs.onSurface.withValues(alpha: 0.5),
                size: 22),
            onPressed: () {
              HapticService.selection();
              provider.setShowFavoritesOnly(!provider.showFavoritesOnly);
            },
          ),
          CupertinoButton(
            padding: const EdgeInsets.all(8),
            child: Icon(CupertinoIcons.doc_on_clipboard_fill,
                color: cs.onSurface.withValues(alpha: 0.5), size: 22),
            onPressed: () async {
              HapticService.medium();
              await provider.captureCurrentClipboard();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  _glassSnackBar(context, 'Clipboard captured'),
                );
              }
            },
          ),
          CupertinoButton(
            padding: const EdgeInsets.all(8),
            child: Icon(CupertinoIcons.chart_bar_square,
                color: cs.onSurface.withValues(alpha: 0.5), size: 22),
            onPressed: () => _showStatistics(context),
          ),
          CupertinoButton(
            padding: const EdgeInsets.all(8),
            child: Icon(CupertinoIcons.ellipsis_circle,
                color: cs.onSurface.withValues(alpha: 0.5), size: 22),
            onPressed: () => _showMoreMenu(context),
          ),
          const SizedBox(width: 4),
        ],
      ],
    );
  }

  Widget _buildGlassAppbarBg(bool isDark) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          color: (isDark ? Colors.black : Colors.white).withValues(alpha: 0.15),
        ),
      ),
    );
  }

  Widget _buildStatusCard(BuildContext context, ClipboardProvider provider,
      AppState appState, bool isDark) {
    final cs = Theme.of(context).colorScheme;
    final monitoring = appState.clipboardMonitoring;
    final totalLinks = provider.service.linkCount;
    final totalItems = provider.service.totalItems;
    final lastItem = provider.service.items.isNotEmpty
        ? provider.service.items.first.createdAt
        : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: (isDark ? Colors.white : Colors.black)
                  .withValues(alpha: isDark ? 0.07 : 0.04),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: (isDark ? Colors.white : Colors.black)
                    .withValues(alpha: isDark ? 0.06 : 0.04),
                width: 0.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AnimatedBuilder(
                      animation: _pulseAnimation,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: monitoring
                              ? CupertinoColors.activeGreen
                              : cs.onSurface.withValues(alpha: 0.3),
                          boxShadow: monitoring
                              ? [
                                  BoxShadow(
                                    color: CupertinoColors.activeGreen
                                        .withValues(alpha: 0.4),
                                    blurRadius: 6,
                                    spreadRadius: 1,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                      builder: (context, child) {
                        return Transform.scale(
                          scale: monitoring ? _pulseAnimation.value : 1.0,
                          child: child,
                        );
                      },
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Clipboard Monitoring',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      monitoring
                          ? CupertinoIcons.eye_fill
                          : CupertinoIcons.eye_slash,
                      size: 18,
                      color: monitoring
                          ? CupertinoColors.activeGreen
                          : cs.onSurface.withValues(alpha: 0.3),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Automatically detects downloadable links copied from Safari, browsers and other apps.',
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurface.withValues(alpha: 0.55),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _statusStat(
                        cs,
                        CupertinoIcons.link,
                        '$totalLinks',
                        'Detected Links',
                        isDark),
                    const SizedBox(width: 12),
                    _statusStat(
                        cs,
                        CupertinoIcons.doc_on_clipboard,
                        '$totalItems',
                        'Total Items',
                        isDark),
                    const SizedBox(width: 12),
                    _statusStat(
                        cs,
                        CupertinoIcons.clock,
                        lastItem != null ? _formatTimeAgo(lastItem) : '--',
                        'Last Detection',
                        isDark),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusStat(ColorScheme cs, IconData icon, String value,
      String label, bool isDark) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: (isDark ? Colors.white : Colors.black)
              .withValues(alpha: isDark ? 0.05 : 0.03),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, size: 16,
                color: cs.onSurface.withValues(alpha: 0.4)),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: cs.onSurface.withValues(alpha: 0.4),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSmartActions(
      BuildContext context, ClipboardProvider provider, bool isDark) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: SizedBox(
        height: 72,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            _smartActionButton(
                context, CupertinoIcons.doc_on_clipboard_fill, 'Paste URL',
                () async {
              HapticService.selection();
              await provider.captureCurrentClipboard();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  _glassSnackBar(context, 'URL pasted from clipboard'),
                );
              }
            }, isDark, cs),
            _smartActionButton(
                context, CupertinoIcons.eye, 'Scan Clipboard', () async {
              HapticService.light();
              await provider.checkForNewClipboard();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  _glassSnackBar(context, 'Clipboard scanned'),
                );
              }
            }, isDark, cs),
            _smartActionButton(
                context, CupertinoIcons.delete, 'Clear History', () {
              HapticService.selection();
              _confirmClearAll(context);
            }, isDark, cs),
            _smartActionButton(
                context, CupertinoIcons.arrow_up_doc, 'Import Links', () {
              HapticService.light();
              _showImportDialog(context);
            }, isDark, cs),
          ],
        ),
      ),
    );
  }

  Widget _smartActionButton(BuildContext context, IconData icon, String label,
      VoidCallback onTap, bool isDark, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: GestureDetector(
        onTap: () {
          HapticService.light();
          onTap();
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              width: 80,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: (isDark ? Colors.white : Colors.black)
                    .withValues(alpha: isDark ? 0.06 : 0.04),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: (isDark ? Colors.white : Colors.black)
                      .withValues(alpha: isDark ? 0.08 : 0.05),
                  width: 0.5,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 22,
                      color: cs.onSurface.withValues(alpha: 0.7)),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: cs.onSurface.withValues(alpha: 0.6),
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecentlyDetected(BuildContext context,
      ClipboardProvider provider, List<ClipboardItem> urlItems, bool isDark) {
    final cs = Theme.of(context).colorScheme;
    final recentUrls = urlItems.take(3).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Row(
              children: [
                Icon(CupertinoIcons.link, size: 16,
                    color: cs.onSurface.withValues(alpha: 0.4)),
                const SizedBox(width: 6),
                Text(
                  'Recently Detected',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface.withValues(alpha: 0.5),
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          ...recentUrls.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _buildLinkCard(context, item, provider, isDark),
              )),
        ],
      ),
    );
  }

  Widget _buildLinkCard(BuildContext context, ClipboardItem item,
      ClipboardProvider provider, bool isDark) {
    final cs = Theme.of(context).colorScheme;
    final domain = item.domain ?? 'unknown';

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: (isDark ? Colors.white : Colors.black)
                .withValues(alpha: isDark ? 0.07 : 0.04),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: (isDark ? Colors.white : Colors.black)
                  .withValues(alpha: isDark ? 0.06 : 0.04),
              width: 0.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Icon(CupertinoIcons.link,
                        size: 18, color: cs.primary),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          domain,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 1),
                        Text(
                          _formatTimeAgo(item.createdAt),
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurface.withValues(alpha: 0.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (item.isFavorite)
                    Icon(CupertinoIcons.star_fill,
                        size: 16,
                        color: CupertinoColors.systemYellow
                            .withValues(alpha: 0.7)),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () => _showDetail(context, item),
                    child: Icon(CupertinoIcons.chevron_right,
                        size: 14,
                        color: cs.onSurface.withValues(alpha: 0.2)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: (isDark ? Colors.white : Colors.black)
                      .withValues(alpha: isDark ? 0.04 : 0.02),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  item.content,
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withValues(alpha: 0.6),
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _linkActionButton(context, CupertinoIcons.arrow_down_circle,
                        'Download', cs.primary, () {
                      HapticService.light();
                      _sendToDownloadManager(context, item.content);
                    }, isDark),
                    const SizedBox(width: 4),
                    _linkActionButton(context, CupertinoIcons.link, 'Open',
                        cs.onSurface.withValues(alpha: 0.6), () async {
                      HapticService.light();
                      final uri = Uri.tryParse(item.content);
                      if (uri != null) {
                        try {
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri,
                                mode: LaunchMode.externalApplication);
                          }
                        } catch (_) {}
                      }
                    }, isDark),
                    const SizedBox(width: 4),
                    _linkActionButton(
                        context, CupertinoIcons.doc_on_doc, 'Copy', null, () {
                      HapticService.light();
                      Clipboard.setData(
                          ClipboardData(text: item.content));
                      ScaffoldMessenger.of(context).showSnackBar(
                        _glassSnackBar(context, 'Copied to clipboard'),
                      );
                    }, isDark),
                    const SizedBox(width: 4),
                    _linkActionButton(context, CupertinoIcons.share, 'Share',
                        null, () {
                      HapticService.light();
                      Share.share(item.content);
                    }, isDark),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () {
                        HapticService.medium();
                        _showLinkContextSheet(context, item, provider);
                      },
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: (isDark ? Colors.white : Colors.black)
                              .withValues(alpha: isDark ? 0.06 : 0.03),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(CupertinoIcons.ellipsis, size: 16,
                            color: cs.onSurface.withValues(alpha: 0.4)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _linkActionButton(BuildContext context, IconData icon, String label,
      Color? color, VoidCallback onTap, bool isDark) {
    final cs = Theme.of(context).colorScheme;
    final btnColor = color ?? cs.onSurface.withValues(alpha: 0.5);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: btnColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: btnColor.withValues(alpha: 0.12),
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: btnColor),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: btnColor),
            ),
          ],
        ),
      ),
    );
  }

  void _showLinkContextSheet(
      BuildContext context, ClipboardItem item, ClipboardProvider provider) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            padding: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: (isDark ? Colors.grey.shade900 : Colors.white)
                  .withValues(alpha: 0.92),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: cs.onSurface.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                _contextAction(
                    CupertinoIcons.star,
                    item.isFavorite ? 'Unfavorite' : 'Favorite', () {
                  provider.toggleFavorite(item.id);
                  Navigator.pop(ctx);
                }, isDark: isDark),
                _contextAction(
                    CupertinoIcons.pin,
                    item.isPinned ? 'Unpin' : 'Pin', () {
                  provider.togglePin(item.id);
                  Navigator.pop(ctx);
                }, isDark: isDark),
                _contextAction(
                    CupertinoIcons.pencil, 'Edit', () {
                  Navigator.pop(ctx);
                  _showEditDialog(context, item);
                }, isDark: isDark),
                _contextAction(
                    CupertinoIcons.tag, 'Add Tag', () {
                  Navigator.pop(ctx);
                  _showAddTagDialog(context, item);
                }, isDark: isDark),
                _contextAction(CupertinoIcons.delete, 'Delete', () {
                  Navigator.pop(ctx);
                  provider.deleteItem(item.id);
                  HapticService.medium();
                }, isDark: isDark, isDestructive: true),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _contextAction(IconData icon, String label, VoidCallback onTap,
      {bool isDark = false, bool isDestructive = false}) {
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      onPressed: onTap,
      child: Row(
        children: [
          Icon(icon, size: 20,
              color: isDestructive
                  ? CupertinoColors.destructiveRed
                  : isDark
                      ? Colors.white.withValues(alpha: 0.7)
                      : Colors.black.withValues(alpha: 0.6)),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w400,
              color: isDestructive
                  ? CupertinoColors.destructiveRed
                  : isDark
                      ? Colors.white.withValues(alpha: 0.85)
                      : Colors.black.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilters(
      BuildContext context, ClipboardProvider provider, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context)
                .colorScheme
                .outlineVariant
                .withValues(alpha: 0.1),
            width: 0.5,
          ),
        ),
      ),
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            color: (isDark ? Colors.black : Colors.white)
                .withValues(alpha: isDark ? 0.6 : 0.7),
            child: Column(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: _buildSearchBar(context, provider, isDark),
                ),
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      _filterChip(context, 'All',
                          ClipboardContentType.text, provider.selectedFilter.index == 0,
                          provider, isDark),
                      _filterChip(context, 'Videos',
                          ClipboardContentType.url, provider.selectedFilter == ClipboardContentType.url,
                          provider, isDark),
                      _filterChip(context, 'Images',
                          ClipboardContentType.image, provider.selectedFilter == ClipboardContentType.image,
                          provider, isDark),
                      _filterChip(context, 'Archives',
                          ClipboardContentType.filePath, provider.selectedFilter == ClipboardContentType.filePath,
                          provider, isDark),
                      _filterChip(context, 'Documents',
                          ClipboardContentType.richText, provider.selectedFilter == ClipboardContentType.richText,
                          provider, isDark),
                      _filterChip(context, 'Audio',
                          ClipboardContentType.richText, provider.selectedFilter == ClipboardContentType.richText,
                          provider, isDark),
                      _filterChip(context, 'Code',
                          ClipboardContentType.code, provider.selectedFilter == ClipboardContentType.code,
                          provider, isDark),
                      _filterChip(context, 'Colors',
                          ClipboardContentType.color, provider.selectedFilter == ClipboardContentType.color,
                          provider, isDark),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar(
      BuildContext context, ClipboardProvider provider, bool isDark) {
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          height: 40,
          decoration: BoxDecoration(
            color: (isDark ? Colors.white : Colors.black)
                .withValues(alpha: isDark ? 0.08 : 0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: (isDark ? Colors.white : Colors.black)
                  .withValues(alpha: isDark ? 0.08 : 0.05),
              width: 0.5,
            ),
          ),
          child: CupertinoTextField(
            controller: _searchController,
            style: TextStyle(
                fontSize: 14,
                color: cs.onSurface),
            placeholder: 'Search URLs, domains, filenames...',
            placeholderStyle: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.3),
                fontSize: 14),
            prefix: Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Icon(CupertinoIcons.search,
                  size: 18,
                  color: cs.onSurface.withValues(alpha: 0.3)),
            ),
            suffix: _searchController.text.isNotEmpty
                ? CupertinoButton(
                    padding: EdgeInsets.zero,
                    child: Icon(CupertinoIcons.xmark_circle_fill,
                        size: 18,
                        color: cs.onSurface.withValues(alpha: 0.3)),
                    onPressed: () {
                      _searchController.clear();
                      provider.setSearchQuery('');
                    },
                  )
                : null,
            decoration: const BoxDecoration(),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            onChanged: (val) => provider.setSearchQuery(val),
          ),
        ),
      ),
    );
  }

  Widget _filterChip(
      BuildContext context,
      String label,
      ClipboardContentType type,
      bool isSelected,
      ClipboardProvider provider,
      bool isDark) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: GestureDetector(
        onTap: () {
          HapticService.selection();
          provider.setFilter(type);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? cs.primary.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? cs.primary.withValues(alpha: 0.3)
                  : (isDark ? Colors.white : Colors.black)
                      .withValues(alpha: isDark ? 0.1 : 0.06),
              width: 0.5,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              color: isSelected
                  ? cs.primary
                  : cs.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetectionBanner(
      BuildContext context, ClipboardProvider provider) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final item = provider.newlyDetectedItem!;

    return GestureDetector(
      onVerticalDragEnd: (_) => provider.dismissNewlyDetected(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: (isDark ? Colors.white : Colors.black)
                    .withValues(alpha: isDark ? 0.08 : 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: cs.primary.withValues(alpha: 0.2),
                  width: 0.5,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(CupertinoIcons.eye,
                        size: 18, color: cs.primary),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'New clipboard detected',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: cs.primary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    borderRadius: BorderRadius.circular(8),
                    color: (isDark ? Colors.white : Colors.black)
                        .withValues(alpha: 0.06),
                    onPressed: provider.saveNewlyDetected,
                    child: Text('Save',
                        style: TextStyle(
                            fontSize: 12, color: cs.primary)),
                  ),
                  const SizedBox(width: 4),
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 6),
                    borderRadius: BorderRadius.circular(8),
                    onPressed: provider.dismissNewlyDetected,
                    child: Icon(CupertinoIcons.xmark,
                        size: 14,
                        color: cs.onSurface.withValues(alpha: 0.4)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMultiSelectBar(
      BuildContext context, ClipboardProvider provider) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.06),
        border: Border(
          bottom: BorderSide(
              color: cs.primary.withValues(alpha: 0.1), width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Text(
            '${provider.selectedIds.length} selected',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: cs.primary,
            ),
          ),
          const Spacer(),
          CupertinoButton(
            padding: const EdgeInsets.all(6),
            onPressed: provider.selectAll,
            child: Icon(CupertinoIcons.collections, size: 18,
                color: cs.onSurface.withValues(alpha: 0.6)),
          ),
          CupertinoButton(
            padding: const EdgeInsets.all(6),
            onPressed: provider.toggleFavoriteSelected,
            child: Icon(CupertinoIcons.star, size: 18,
                color: cs.onSurface.withValues(alpha: 0.6)),
          ),
          CupertinoButton(
            padding: const EdgeInsets.all(6),
            onPressed: provider.selectedIds.isNotEmpty
                ? () => _confirmDeleteSelected(context, provider)
                : null,
            child: Icon(CupertinoIcons.delete, size: 18,
                color: CupertinoColors.destructiveRed
                    .withValues(alpha: 0.7)),
          ),
        ],
      ),
    );
  }



  List<Widget> _buildHistorySections(
    BuildContext context,
    ClipboardProvider provider,
    List<ClipboardItem> items,
  ) {
    final groups = _groupItemsByDate(items);
    final sections = <Widget>[];

    for (final entry in groups.entries) {
      sections.add(
        SliverToBoxAdapter(
          child: _buildSectionHeader(context, entry.key),
        ),
      );
      sections.add(
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              return Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  bottom: index == entry.value.length - 1 ? 8 : 0,
                ),
                child: _buildHistoryTile(
                    context, entry.value[index], provider),
              );
            },
            childCount: entry.value.length,
          ),
        ),
      );
    }

    return sections;
  }

  Map<String, List<ClipboardItem>> _groupItemsByDate(
      List<ClipboardItem> items) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    final groups = <String, List<ClipboardItem>>{};
    for (final item in items) {
      final itemDate =
          DateTime(item.createdAt.year, item.createdAt.month, item.createdAt.day);
      String key;
      if (itemDate == today) {
        key = 'Today';
      } else if (itemDate == yesterday) {
        key = 'Yesterday';
      } else {
        key = 'Earlier';
      }
      groups.putIfAbsent(key, () => []);
      groups[key]!.add(item);
    }
    return groups;
  }

  Widget _buildSectionHeader(
      BuildContext context, String title) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
      child: Row(
        children: [
          Icon(CupertinoIcons.chevron_down, size: 12,
              color: cs.onSurface.withValues(alpha: 0.3)),
          const SizedBox(width: 6),
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: cs.onSurface.withValues(alpha: 0.5),
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTile(BuildContext context, ClipboardItem item,
      ClipboardProvider provider) {
    final cs = Theme.of(context).colorScheme;
    final isSelected = provider.selectedIds.contains(item.id);

    return GestureDetector(
      onTap: () {
        if (provider.isMultiSelectMode) {
          provider.toggleSelection(item.id);
          HapticService.selection();
        } else {
          _showDetail(context, item);
        }
      },
      onLongPress: () {
        if (!provider.isMultiSelectMode) {
          HapticService.medium();
          provider.toggleMultiSelectMode();
          provider.toggleSelection(item.id);
        } else {
          provider.toggleSelection(item.id);
          HapticService.selection();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? cs.primary.withValues(alpha: 0.06)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: isSelected
              ? Border.all(
                  color: cs.primary.withValues(alpha: 0.15), width: 0.5)
              : null,
        ),
        child: Row(
          children: [
            if (provider.isMultiSelectMode) ...[
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected
                      ? cs.primary
                      : Colors.transparent,
                  border: Border.all(
                    color: isSelected
                        ? cs.primary
                        : cs.onSurface.withValues(alpha: 0.2),
                    width: 1.5,
                  ),
                ),
                child: isSelected
                    ? Icon(CupertinoIcons.check_mark,
                        size: 13, color: cs.onPrimary)
                    : null,
              ),
              const SizedBox(width: 10),
            ],
            _typeIcon(item.type, cs, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.preview,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                      color: cs.onSurface,
                      height: 1.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        _typeLabel(item.type),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: _typeColor(item.type)
                              .withValues(alpha: 0.5),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 3,
                        height: 3,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: cs.onSurface.withValues(alpha: 0.2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatTimeAgo(item.createdAt),
                        style: TextStyle(
                          fontSize: 11,
                          color:
                              cs.onSurface.withValues(alpha: 0.35),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (item.isPinned)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(CupertinoIcons.pin_fill,
                    size: 12,
                    color: CupertinoColors.systemOrange
                        .withValues(alpha: 0.5)),
              ),
            if (item.isFavorite)
              Icon(CupertinoIcons.star_fill,
                  size: 14,
                  color: CupertinoColors.systemYellow
                      .withValues(alpha: 0.6)),
            const SizedBox(width: 4),
            Icon(CupertinoIcons.chevron_right,
                size: 14,
                color: cs.onSurface.withValues(alpha: 0.15)),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(
      BuildContext context, bool isDark) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: _pulseAnimation,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: cs.primary.withValues(alpha: 0.15),
                    width: 0.5,
                  ),
                ),
                child: Icon(CupertinoIcons.doc_on_clipboard,
                    size: 36,
                    color: cs.primary.withValues(alpha: 0.5)),
              ),
              builder: (context, child) {
                return Transform.scale(
                  scale: 0.9 + (_pulseAnimation.value * 0.1),
                  child: child,
                );
              },
            ),
            const SizedBox(height: 28),
            Text(
              'Clipboard is Empty',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Copy a downloadable link and DirXplore will automatically detect it.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: cs.onSurface.withValues(alpha: 0.5),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 32),
            GestureDetector(
              onTap: () async {
                HapticService.medium();
                await context.read<ClipboardProvider>().captureCurrentClipboard();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    _glassSnackBar(context, 'Checking clipboard...'),
                  );
                }
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 14),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: cs.primary.withValues(alpha: 0.2),
                        width: 0.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(CupertinoIcons.doc_on_clipboard_fill,
                            size: 18, color: cs.primary),
                        const SizedBox(width: 8),
                        Text(
                          'Paste URL',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: cs.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchEmptyState(
      BuildContext context, bool isDark) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: cs.onSurface.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(CupertinoIcons.search,
                size: 28,
                color: cs.onSurface.withValues(alpha: 0.2)),
          ),
          const SizedBox(height: 20),
          Text(
            'No Results Found',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: cs.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try a different search term',
            style: TextStyle(
              fontSize: 14,
              color: cs.onSurface.withValues(alpha: 0.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFavoritesEmptyState(
      BuildContext context, bool isDark) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: CupertinoColors.systemYellow.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(CupertinoIcons.star,
                size: 28,
                color: CupertinoColors.systemYellow
                    .withValues(alpha: 0.3)),
          ),
          const SizedBox(height: 20),
          Text(
            'No Favorites Yet',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: cs.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Star items to add them here',
            style: TextStyle(
              fontSize: 14,
              color: cs.onSurface.withValues(alpha: 0.35),
            ),
          ),
        ],
      ),
    );
  }

  void _showMoreMenu(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            padding: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: (isDark ? Colors.grey.shade900 : Colors.white)
                  .withValues(alpha: 0.92),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: cs.onSurface.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                _contextAction(CupertinoIcons.doc_on_doc, 'Export All', () {
                  Navigator.pop(ctx);
                  _showExportDialog(context);
                }, isDark: isDark),
                _contextAction(CupertinoIcons.arrow_up_doc, 'Import', () {
                  Navigator.pop(ctx);
                  _showImportDialog(context);
                }, isDark: isDark),
                _contextAction(CupertinoIcons.chart_bar_square,
                    'Statistics', () {
                  Navigator.pop(ctx);
                  _showStatistics(context);
                }, isDark: isDark),
                _contextAction(CupertinoIcons.delete, 'Clear All', () {
                  Navigator.pop(ctx);
                  _confirmClearAll(context);
                }, isDark: isDark, isDestructive: true),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showDetail(BuildContext context, ClipboardItem item) {
    HapticService.light();

    if (item.type == ClipboardContentType.image && item.imagePath != null) {
      _showImageViewer(context, item);
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _buildDetailSheet(ctx, item),
    );
  }

  Widget _buildDetailSheet(BuildContext context, ClipboardItem item) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final provider = context.read<ClipboardProvider>();

    final bottomInset = MediaQuery.of(context).padding.bottom;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.85 +
              bottomInset,
          padding: EdgeInsets.only(bottom: bottomInset),
          decoration: BoxDecoration(
            color: (isDark ? Colors.grey.shade900 : Colors.white)
                .withValues(alpha: 0.92),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(
              top: BorderSide(
                color: (isDark ? Colors.white : Colors.black)
                    .withValues(alpha: isDark ? 0.1 : 0.08),
              ),
            ),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.2)
                      : Colors.black.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    _typeIcon(item.type, cs, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _typeLabel(item.type),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              letterSpacing: -0.5,
                              color: _typeColor(item.type),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _formatDetailTimestamp(item.createdAt),
                            style: TextStyle(
                              fontSize: 12,
                              color:
                                  cs.onSurface.withValues(alpha: 0.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      child: Icon(
                          item.isFavorite
                              ? CupertinoIcons.star_fill
                              : CupertinoIcons.star,
                          color: item.isFavorite
                              ? CupertinoColors.systemYellow
                              : null,
                          size: 22),
                      onPressed: () =>
                          provider.toggleFavorite(item.id),
                    ),
                    const SizedBox(width: 8),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      child: Icon(
                          item.isPinned
                              ? CupertinoIcons.pin_fill
                              : CupertinoIcons.pin,
                          color: item.isPinned
                              ? CupertinoColors.systemOrange
                              : null,
                          size: 22),
                      onPressed: () {
                        provider.togglePin(item.id);
                        if (context.mounted) Navigator.pop(context);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    if (item.type == ClipboardContentType.url)
                      _buildUrlPreview(context, item),
                    if (item.type == ClipboardContentType.code)
                      _buildCodePreview(context, item),
                    if (item.type == ClipboardContentType.json)
                      _buildCodePreview(context, item, isJson: true),
                    if (item.type == ClipboardContentType.color)
                      _buildColorPreview(context, item),
                    _buildContentSection(context, item),
                    const SizedBox(height: 20),
                    _buildMetadataSection(context, item),
                    if (item.tags.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildTagsSection(context, item),
                    ],
                  ],
                ),
              ),
              _buildDetailActions(context, item),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUrlPreview(BuildContext context, ClipboardItem item) {
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: cs.primary.withValues(alpha: 0.12),
              width: 0.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (item.domain != null) ...[
                Row(
                  children: [
                    Icon(CupertinoIcons.link, size: 16,
                        color: cs.primary),
                    const SizedBox(width: 8),
                    Text(
                      item.domain!,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: cs.primary,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              if (item.fileExtension != null)
                Row(
                  children: [
                    Icon(CupertinoIcons.doc,
                        size: 14,
                        color: cs.onSurface.withValues(alpha: 0.5)),
                    const SizedBox(width: 6),
                    Text(
                      'File type: .${item.fileExtension}',
                      style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurface.withValues(alpha: 0.6)),
                    ),
                  ],
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _miniActionButton(CupertinoIcons.link,
                      'Open', cs.primary, () async {
                    final uri = Uri.tryParse(item.content);
                    if (uri != null) {
                      try {
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri,
                              mode: LaunchMode.externalApplication);
                        }
                      } catch (_) {}
                    }
                  }),
                  const SizedBox(width: 8),
                  _miniActionButton(
                      CupertinoIcons.doc_on_doc, 'Copy',
                      cs.onSurface.withValues(alpha: 0.6), () async {
                    await Clipboard.setData(
                        ClipboardData(text: item.content));
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        _glassSnackBar(context, 'Copied'),
                      );
                    }
                  }),
                  const SizedBox(width: 8),
                  if (item.content.startsWith('http://') ||
                      item.content.startsWith('https://'))
                    _miniActionButton(CupertinoIcons.arrow_down_circle,
                        'Download', CupertinoColors.activeGreen, () {
                      Navigator.pop(context);
                      _sendToDownloadManager(context, item.content);
                    }),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCodePreview(
      BuildContext context, ClipboardItem item,
      {bool isJson = false}) {
    final lang = isJson ? 'json' : (item.language ?? 'code');
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.code, size: 16,
                      color: Colors.greenAccent),
                  const SizedBox(width: 8),
                  Text(
                    lang.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 1,
                    ),
                  ),
                  const Spacer(),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    child: const Icon(CupertinoIcons.doc_on_doc,
                        size: 16, color: Colors.white70),
                    onPressed: () async {
                      await Clipboard.setData(
                          ClipboardData(text: item.content));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          _glassSnackBar(context, 'Copied'),
                        );
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    child: const Icon(CupertinoIcons.share,
                        size: 16, color: Colors.white70),
                    onPressed: () => Share.share(item.content),
                  ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(16)),
              ),
              child: SelectableText(
                item.content,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Colors.white,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColorPreview(BuildContext context, ClipboardItem item) {
    final cs = Theme.of(context).colorScheme;
    Color? swatch;
    try {
      final hex = item.content.trim();
      if (hex.startsWith('#')) {
        final h = hex.replaceFirst('#', '');
        if (h.length == 6) {
          swatch = Color(int.parse('FF$h', radix: 16));
        } else if (h.length == 3) {
          final r = h[0] * 2;
          final g = h[1] * 2;
          final b = h[2] * 2;
          swatch = Color(int.parse('FF$r$g$b', radix: 16));
        }
      } else if (hex.startsWith('rgb')) {
        final nums = RegExp(r'\d+')
            .allMatches(hex)
            .map((m) => int.parse(m.group(0)!))
            .toList();
        if (nums.length >= 3) {
          swatch = Color.fromARGB(255, nums[0], nums[1], nums[2]);
        }
      }
    } catch (_) {}

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.15),
              width: 0.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Color Preview',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: cs.onSurface)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: swatch ?? Colors.grey,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color:
                            cs.outlineVariant.withValues(alpha: 0.2),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.content,
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: cs.onSurface,
                              fontFamily: 'monospace')),
                      if (swatch != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'R: ${(swatch.r * 255.0).round().clamp(0, 255)}  G: ${(swatch.g * 255.0).round().clamp(0, 255)}  B: ${(swatch.b * 255.0).round().clamp(0, 255)}',
                          style: TextStyle(
                              fontSize: 11,
                              color:
                                  cs.onSurface.withValues(alpha: 0.6)),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTagsSection(
      BuildContext context, ClipboardItem item) {
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.15),
              width: 0.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(CupertinoIcons.tag, size: 16,
                      color: cs.onSurface.withValues(alpha: 0.5)),
                  const SizedBox(width: 8),
                  Text('Tags',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: cs.onSurface)),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: item.tags
                    .map((tag) => Chip(
                          label: Text(tag,
                              style: const TextStyle(fontSize: 11)),
                          deleteIcon: const Icon(
                              CupertinoIcons.xmark, size: 14),
                          onDeleted: () => context
                              .read<ClipboardProvider>()
                              .removeTag(item.id, tag),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          padding:
                              const EdgeInsets.symmetric(horizontal: 4),
                        ))
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContentSection(
      BuildContext context, ClipboardItem item) {
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.15),
              width: 0.5,
            ),
          ),
          child: SelectableText(
            item.content,
            style: TextStyle(
              fontSize: 14,
              color: cs.onSurface,
              height: 1.5,
              fontFamily: item.type == ClipboardContentType.code
                  ? 'monospace'
                  : null,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMetadataSection(
      BuildContext context, ClipboardItem item) {
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.15),
              width: 0.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Details',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              _metaRow(cs, 'Type', _typeLabel(item.type)),
              _metaRow(cs, 'Created',
                  _formatDetailTimestamp(item.createdAt)),
              _metaRow(cs, 'Characters',
                  item.characterCount.toString()),
              _metaRow(cs, 'Words', item.wordCount.toString()),
              _metaRow(cs, 'Lines', item.lineCount.toString()),
              if (item.domain != null)
                _metaRow(cs, 'Domain', item.domain!),
              if (item.language != null)
                _metaRow(cs, 'Language',
                    item.language!.toUpperCase()),
              if (item.tags.isNotEmpty)
                _metaRow(cs, 'Tags', item.tags.join(', ')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metaRow(ColorScheme cs, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: cs.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailActions(
      BuildContext context, ClipboardItem item) {
    final cs = Theme.of(context).colorScheme;
    final provider = context.read<ClipboardProvider>();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
              color: cs.outlineVariant.withValues(alpha: 0.15)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _detailAction(CupertinoIcons.doc_on_doc, 'Copy', () async {
            await Clipboard.setData(
                ClipboardData(text: item.content));
            if (context.mounted) {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                _glassSnackBar(context, 'Copied'),
              );
            }
          }, cs),
          _detailAction(CupertinoIcons.share, 'Share',
              () => Share.share(item.content), cs),
          _detailAction(CupertinoIcons.pencil, 'Edit', () {
            Navigator.pop(context);
            _showEditDialog(context, item);
          }, cs),
          _detailAction(CupertinoIcons.tag, 'Tag', () {
            Navigator.pop(context);
            _showAddTagDialog(context, item);
          }, cs),
          _detailAction(
              item.isFavorite
                  ? CupertinoIcons.star_fill
                  : CupertinoIcons.star,
              item.isFavorite ? 'Unfavorite' : 'Favorite', () {
            provider.toggleFavorite(item.id);
          }, cs),
          _detailAction(CupertinoIcons.delete, 'Delete', () {
            Navigator.pop(context);
            provider.deleteItem(item.id);
          }, cs,
              color: CupertinoColors.destructiveRed),
        ],
      ),
    );
  }

  Widget _detailAction(IconData icon, String label,
      VoidCallback onPressed, ColorScheme cs,
      {Color? color}) {
    return GestureDetector(
      onTap: onPressed,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              color: color ?? cs.onSurface.withValues(alpha: 0.6),
              size: 22),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color ?? cs.onSurface.withValues(alpha: 0.5),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniActionButton(
      IconData icon, String label, Color color, VoidCallback onPressed) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: color.withValues(alpha: 0.15),
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _typeIcon(ClipboardContentType type, ColorScheme cs,
      {double size = 20}) {
    IconData icon;
    Color color;
    switch (type) {
      case ClipboardContentType.url:
        icon = CupertinoIcons.link;
        color = Colors.blue;
      case ClipboardContentType.image:
        icon = CupertinoIcons.photo;
        color = Colors.purple;
      case ClipboardContentType.email:
        icon = CupertinoIcons.envelope;
        color = Colors.teal;
      case ClipboardContentType.phone:
        icon = CupertinoIcons.phone;
        color = Colors.green;
      case ClipboardContentType.json:
        icon = CupertinoIcons.doc;
        color = Colors.orange;
      case ClipboardContentType.code:
        icon = Icons.code;
        color = Colors.greenAccent;
      case ClipboardContentType.color:
        icon = CupertinoIcons.paintbrush;
        color = Colors.pink;
      case ClipboardContentType.filePath:
        icon = CupertinoIcons.folder;
        color = Colors.amber;
      case ClipboardContentType.richText:
        icon = CupertinoIcons.textformat;
        color = Colors.indigo;
      case ClipboardContentType.text:
        icon = CupertinoIcons.textformat;
        color = cs.primary;
    }
    return Container(
      padding: EdgeInsets.all(size > 20 ? 8 : 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: size > 20 ? 22 : 16, color: color),
    );
  }

  Color _typeColor(ClipboardContentType type) {
    switch (type) {
      case ClipboardContentType.url:
        return Colors.blue;
      case ClipboardContentType.image:
        return Colors.purple;
      case ClipboardContentType.email:
        return Colors.teal;
      case ClipboardContentType.phone:
        return Colors.green;
      case ClipboardContentType.json:
        return Colors.orange;
      case ClipboardContentType.code:
        return Colors.greenAccent;
      case ClipboardContentType.color:
        return Colors.pink;
      case ClipboardContentType.filePath:
        return Colors.amber;
      case ClipboardContentType.richText:
        return Colors.indigo;
      case ClipboardContentType.text:
        return Colors.blueGrey;
    }
  }

  String _typeLabel(ClipboardContentType type) {
    switch (type) {
      case ClipboardContentType.text:
        return 'TEXT';
      case ClipboardContentType.url:
        return 'URL';
      case ClipboardContentType.image:
        return 'IMAGE';
      case ClipboardContentType.richText:
        return 'RICH TEXT';
      case ClipboardContentType.phone:
        return 'PHONE';
      case ClipboardContentType.email:
        return 'EMAIL';
      case ClipboardContentType.json:
        return 'JSON';
      case ClipboardContentType.code:
        return 'CODE';
      case ClipboardContentType.color:
        return 'COLOR';
      case ClipboardContentType.filePath:
        return 'FILE PATH';
    }
  }

  String _formatTimeAgo(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.month}/${dt.day}/${dt.year}';
  }

  String _formatDetailTimestamp(DateTime dt) {
    return '${dt.month}/${dt.day}/${dt.year} at ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  SnackBar _glassSnackBar(BuildContext context, String message) {
    return SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.transparent,
      elevation: 0,
      padding: EdgeInsets.zero,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14)),
    );
  }

  void _sendToDownloadManager(
      BuildContext context, String url) {
    final appState = context.read<AppState>();
    final downloads = context.read<DownloadProvider>();
    final fileName = url.split('/').last.isNotEmpty
        ? url.split('/').last
        : 'download';
    downloads.addDownload(url, fileName, appState.defaultSavePath);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        _glassSnackBar(context, 'URL sent to Download Manager'),
      );
    }
  }

  void _showImageViewer(
      BuildContext context, ClipboardItem item) {
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: CupertinoNavigationBar(
            backgroundColor: Colors.transparent,
            leading: CupertinoButton(
              padding: EdgeInsets.zero,
              child: const Icon(CupertinoIcons.xmark,
                  color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            trailing: CupertinoButton(
              padding: EdgeInsets.zero,
              child: const Icon(CupertinoIcons.share,
                  color: Colors.white),
              onPressed: () => Share.share(item.content),
            ),
          ),
          body: Center(
            child: InteractiveViewer(
              maxScale: 5,
              child: item.imagePath != null &&
                      File(item.imagePath!).existsSync()
                  ? Image.file(File(item.imagePath!),
                      fit: BoxFit.contain)
                  : const Icon(CupertinoIcons.photo,
                      size: 100, color: Colors.white30),
            ),
          ),
        ),
      ),
    );
  }

  void _showStatistics(BuildContext context) {
    final provider = context.read<ClipboardProvider>();
    final service = provider.service;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dist = provider.typeDistribution;
    final total = service.totalItems;

    final bottomInset = MediaQuery.of(context).padding.bottom;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.75 +
                    bottomInset),
            decoration: BoxDecoration(
              color: (isDark ? Colors.grey.shade900 : Colors.white)
                  .withValues(alpha: 0.92),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border(
                top: BorderSide(
                  color: (isDark ? Colors.white : Colors.white)
                      .withValues(alpha: isDark ? 0.1 : 0.5),
                ),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.max,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.2)
                        : Colors.black.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                Text('Clipboard Statistics',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        letterSpacing: -0.5,
                        color: cs.onSurface)),
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    child: Column(
                      children: [
                        Row(children: [
                          _statTile(cs, CupertinoIcons.doc_on_clipboard,
                              '${service.totalItems}', 'Saved Items'),
                          _statTile(cs, CupertinoIcons.photo,
                              '${service.imageCount}', 'Images'),
                        ]),
                        const SizedBox(height: 12),
                        Row(children: [
                          _statTile(cs, CupertinoIcons.link,
                              '${service.linkCount}', 'Links'),
                          _statTile(cs, CupertinoIcons.textformat,
                              '${service.textCount}', 'Text'),
                        ]),
                        const SizedBox(height: 12),
                        Row(children: [
                          _statTile(cs, CupertinoIcons.star,
                              '${service.favoriteCount}', 'Favorites'),
                          _statTile(cs, CupertinoIcons.tray_full,
                              service.storageFormatted, 'Storage'),
                        ]),
                        if (dist.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: cs.surfaceContainerHighest
                                      .withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Type Distribution',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            color: cs.onSurface)),
                                    const SizedBox(height: 12),
                                    ...dist.entries.map((e) {
                                      final pct = total > 0
                                          ? (e.value / total * 100)
                                          : 0.0;
                                      return Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 8),
                                        child: Row(
                                          children: [
                                            SizedBox(
                                              width: 80,
                                              child: Text(
                                                e.key,
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    color: cs.onSurface
                                                        .withValues(alpha: 0.7)),
                                              ),
                                            ),
                                            Expanded(
                                              child: ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                child: LinearProgressIndicator(
                                                  value: pct / 100,
                                                  minHeight: 8,
                                                  backgroundColor:
                                                      cs.surfaceContainerHighest,
                                                ),
                                              ),
                                            ),
                                            SizedBox(
                                              width: 40,
                                              child: Text(
                                                '${pct.toInt()}%',
                                                textAlign: TextAlign.right,
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                    color: cs.onSurface),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statTile(ColorScheme cs, IconData icon, String value,
      String label) {
    return Expanded(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest
                  .withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Icon(icon, color: cs.primary, size: 24),
                const SizedBox(height: 8),
                Text(value,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                        color: cs.onSurface)),
                Text(label,
                    style: TextStyle(
                        fontSize: 11,
                        color:
                            cs.onSurface.withValues(alpha: 0.5))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showExportDialog(BuildContext context) {
    final provider = context.read<ClipboardProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.transparent,
        contentPadding: EdgeInsets.zero,
        content: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: (isDark ? Colors.grey.shade900 : Colors.white)
                    .withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: (isDark ? Colors.white : Colors.white)
                      .withValues(alpha: isDark ? 0.1 : 0.5),
                  width: 0.5,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Export Clipboard',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: cs.onSurface)),
                  const SizedBox(height: 20),
                  _exportOption(ctx, CupertinoIcons.doc_text, 'Text',
                      () {
                    Navigator.pop(ctx);
                    Clipboard.setData(
                        ClipboardData(text: provider.exportAsText));
                    ScaffoldMessenger.of(context).showSnackBar(
                      _glassSnackBar(context, 'Copied as text'),
                    );
                  }, cs),
                  _exportOption(ctx, CupertinoIcons.doc, 'JSON', () {
                    Navigator.pop(ctx);
                    Clipboard.setData(
                        ClipboardData(text: provider.exportAsJson));
                    ScaffoldMessenger.of(context).showSnackBar(
                      _glassSnackBar(context, 'Copied as JSON'),
                    );
                  }, cs),
                  _exportOption(
                      ctx, CupertinoIcons.doc, 'CSV', () {
                    Navigator.pop(ctx);
                    Clipboard.setData(
                        ClipboardData(text: provider.exportAsCsv));
                    ScaffoldMessenger.of(context).showSnackBar(
                      _glassSnackBar(context, 'Copied as CSV'),
                    );
                  }, cs),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _exportOption(BuildContext ctx, IconData icon, String label,
      VoidCallback onTap, ColorScheme cs) {
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(vertical: 8),
      onPressed: onTap,
      child: Row(
        children: [
          Icon(icon, size: 20,
              color: cs.onSurface.withValues(alpha: 0.6)),
          const SizedBox(width: 12),
          Text(label,
              style: TextStyle(
                  fontSize: 16, color: cs.onSurface)),
        ],
      ),
    );
  }

  void _showImportDialog(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.transparent,
        contentPadding: EdgeInsets.zero,
        content: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: (isDark ? Colors.grey.shade900 : Colors.white)
                    .withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: (isDark ? Colors.white : Colors.white)
                      .withValues(alpha: isDark ? 0.1 : 0.5),
                  width: 0.5,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Import Clipboard',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: cs.onSurface)),
                  const SizedBox(height: 20),
                  _exportOption(ctx, CupertinoIcons.doc, 'JSON', () {
                    Navigator.pop(ctx);
                    _showImportTextField(context, isJson: true);
                  }, cs),
                  _exportOption(ctx, CupertinoIcons.doc_text, 'Text',
                      () {
                    Navigator.pop(ctx);
                    _showImportTextField(context, isJson: false);
                  }, cs),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showImportTextField(BuildContext context,
      {bool isJson = true}) {
    final controller = TextEditingController();
    final cs = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.transparent,
        contentPadding: EdgeInsets.zero,
        content: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: (Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey.shade900
                        : Colors.white)
                    .withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.2),
                  width: 0.5,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(isJson ? 'Import JSON' : 'Import Text',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                          color: cs.onSurface)),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest
                          .withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: cs.outlineVariant
                            .withValues(alpha: 0.15),
                        width: 0.5,
                      ),
                    ),
                    child: TextField(
                      controller: controller,
                      maxLines: 8,
                      style: TextStyle(
                          fontSize: 13, color: cs.onSurface),
                      decoration: InputDecoration(
                        hintText: isJson
                            ? 'Paste JSON data here...'
                            : 'Paste text data here...',
                        hintStyle: TextStyle(
                            fontSize: 13,
                            color: cs.onSurface
                                .withValues(alpha: 0.3)),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16),
                        child: Text('Cancel',
                            style: TextStyle(
                                color: cs.onSurface
                                    .withValues(alpha: 0.5))),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                      const SizedBox(width: 8),
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16),
                        color: cs.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        child: Text('Import',
                            style: TextStyle(
                                color: cs.primary,
                                fontWeight: FontWeight.w600)),
                        onPressed: () async {
                          final provider =
                              context.read<ClipboardProvider>();
                          final count = isJson
                              ? await provider.importFromJson(
                                  controller.text)
                              : await provider.importFromText(
                                  controller.text);
                          if (context.mounted) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              _glassSnackBar(context,
                                  'Imported $count items'),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ).then((_) => controller.dispose());
  }

  void _showEditDialog(
      BuildContext context, ClipboardItem item) {
    final controller =
        TextEditingController(text: item.content);
    final cs = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.transparent,
        contentPadding: EdgeInsets.zero,
        content: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: (Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey.shade900
                        : Colors.white)
                    .withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.2),
                  width: 0.5,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Edit Content',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                          color: cs.onSurface)),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest
                          .withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: cs.outlineVariant
                            .withValues(alpha: 0.15),
                        width: 0.5,
                      ),
                    ),
                    child: TextField(
                      controller: controller,
                      maxLines: 8,
                      style: TextStyle(
                          fontSize: 13, color: cs.onSurface),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16),
                        child: Text('Cancel',
                            style: TextStyle(
                                color: cs.onSurface
                                    .withValues(alpha: 0.5))),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                      const SizedBox(width: 8),
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16),
                        color: cs.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        child: Text('Save',
                            style: TextStyle(
                                color: cs.primary,
                                fontWeight: FontWeight.w600)),
                        onPressed: () async {
                          final newContent = controller.text.trim();
                          if (newContent.isNotEmpty &&
                              newContent != item.content) {
                            await context
                                .read<ClipboardProvider>()
                                .updateItemContent(
                                    item.id, newContent);
                          }
                          if (context.mounted) Navigator.pop(ctx);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ).then((_) => controller.dispose());
  }

  void _showAddTagDialog(
      BuildContext context, ClipboardItem item) {
    final controller = TextEditingController();
    final cs = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.transparent,
        contentPadding: EdgeInsets.zero,
        content: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: (Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey.shade900
                        : Colors.white)
                    .withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.2),
                  width: 0.5,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Add Tag',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                          color: cs.onSurface)),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest
                          .withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: cs.outlineVariant
                            .withValues(alpha: 0.15),
                        width: 0.5,
                      ),
                    ),
                    child: TextField(
                      controller: controller,
                      autofocus: true,
                      style: TextStyle(
                          fontSize: 14, color: cs.onSurface),
                      decoration: InputDecoration(
                        hintText: 'Enter tag name...',
                        hintStyle: TextStyle(
                            fontSize: 14,
                            color: cs.onSurface
                                .withValues(alpha: 0.3)),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16),
                        child: Text('Cancel',
                            style: TextStyle(
                                color: cs.onSurface
                                    .withValues(alpha: 0.5))),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                      const SizedBox(width: 8),
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16),
                        color: cs.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        child: Text('Add',
                            style: TextStyle(
                                color: cs.primary,
                                fontWeight: FontWeight.w600)),
                        onPressed: () async {
                          final tag = controller.text.trim();
                          if (tag.isNotEmpty) {
                            await context
                                .read<ClipboardProvider>()
                                .addTags(item.id, [tag]);
                          }
                          if (context.mounted) Navigator.pop(ctx);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ).then((_) => controller.dispose());
  }

  void _confirmClearAll(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.transparent,
        contentPadding: EdgeInsets.zero,
        content: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: (isDark ? Colors.grey.shade900 : Colors.white)
                    .withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: (isDark ? Colors.white : Colors.white)
                      .withValues(alpha: isDark ? 0.1 : 0.5),
                  width: 0.5,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: CupertinoColors.destructiveRed
                              .withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                            CupertinoIcons.delete,
                            color: CupertinoColors.destructiveRed,
                            size: 22),
                      ),
                      const SizedBox(width: 14),
                      Text('Clear All',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: cs.onSurface)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'This will permanently delete all clipboard items.',
                    style: TextStyle(
                        fontSize: 14,
                        color: cs.onSurface
                            .withValues(alpha: 0.7)),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16),
                        child: Text('Cancel',
                            style: TextStyle(
                                color: cs.onSurface
                                    .withValues(alpha: 0.6))),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                      const SizedBox(width: 12),
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16),
                        color: CupertinoColors.destructiveRed
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        child: const Text('Clear All',
                            style: TextStyle(
                                color:
                                    CupertinoColors.destructiveRed,
                                fontWeight: FontWeight.w600)),
                        onPressed: () {
                          context
                              .read<ClipboardProvider>()
                              .clearAll();
                          Navigator.pop(ctx);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _confirmDeleteSelected(
      BuildContext context, ClipboardProvider provider) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.transparent,
        contentPadding: EdgeInsets.zero,
        content: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: (isDark ? Colors.grey.shade900 : Colors.white)
                    .withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.2),
                  width: 0.5,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Delete ${provider.selectedIds.length} items?',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface)),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16),
                        child: Text('Cancel',
                            style: TextStyle(
                                color: cs.onSurface
                                    .withValues(alpha: 0.5))),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                      const SizedBox(width: 8),
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16),
                        color: CupertinoColors.destructiveRed
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        child: const Text('Delete',
                            style: TextStyle(
                                color:
                                    CupertinoColors.destructiveRed,
                                fontWeight: FontWeight.w600)),
                        onPressed: () async {
                          await provider.deleteSelected();
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  _SearchHeaderDelegate(this.child);

  @override
  double get minExtent => 100;
  @override
  double get maxExtent => 100;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return child;
  }

  @override
  bool shouldRebuild(_SearchHeaderDelegate oldDelegate) =>
      child != oldDelegate.child;
}
