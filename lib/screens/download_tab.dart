import 'dart:math';
import 'dart:io' show File, Platform;
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/app_state.dart';
import '../providers/download_provider.dart';
import '../models/download_item.dart';
import '../services/thumbnail_service.dart';
import '../services/haptic_service.dart';
import 'new_download_sheet.dart';

class DownloadTab extends StatefulWidget {
  const DownloadTab({super.key});

  @override
  State<DownloadTab> createState() => _DownloadTabState();
}

class _DownloadTabState extends State<DownloadTab> {
  final Set<String> _expandedBatchIds = {};
  String _searchQuery = '';
  String _selectedFilter = 'All';
  String _sortBy = 'Newest';
  bool _showSearch = false;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  static const List<String> _sortOptions = [
    'Newest', 'Oldest', 'Largest', 'Smallest',
    'Progress', 'Name', 'Status', 'Recently Finished'
  ];

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  List<DownloadItem> _filterAndSort(List<DownloadItem> items) {
    var filtered = items.toList();

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = filtered.where((i) =>
        i.fileName.toLowerCase().contains(q) ||
        i.url.toLowerCase().contains(q) ||
        (i.host.toLowerCase().contains(q)) ||
        i.categoryLabel.toLowerCase().contains(q)
      ).toList();
    }

    switch (_selectedFilter) {
      case 'Downloading':
        filtered = filtered.where((i) => i.status == DownloadStatus.downloading).toList();
        break;
      case 'Queued':
        filtered = filtered.where((i) => i.status == DownloadStatus.queued).toList();
        break;
      case 'Paused':
        filtered = filtered.where((i) => i.status == DownloadStatus.paused).toList();
        break;
      case 'Completed':
        filtered = filtered.where((i) => i.status == DownloadStatus.done).toList();
        break;
      case 'Failed':
        filtered = filtered.where((i) => i.status == DownloadStatus.error).toList();
        break;
      case 'Today':
        final today = DateTime.now();
        filtered = filtered.where((i) =>
          i.addedAt.year == today.year &&
          i.addedAt.month == today.month &&
          i.addedAt.day == today.day
        ).toList();
        break;
      case 'Large Files':
        filtered = filtered.where((i) => i.totalBytes > 100 * 1024 * 1024).toList();
        break;
      case 'Media':
        filtered = filtered.where((i) =>
          i.category == DownloadCategory.movies ||
          i.category == DownloadCategory.music ||
          i.category == DownloadCategory.tvShows
        ).toList();
        break;
      case 'Documents':
        filtered = filtered.where((i) => i.category == DownloadCategory.documents).toList();
        break;
      case 'Archives':
        filtered = filtered.where((i) => i.category == DownloadCategory.archives).toList();
        break;
    }

    switch (_sortBy) {
      case 'Newest':
        filtered.sort((a, b) => b.addedAt.compareTo(a.addedAt));
        break;
      case 'Oldest':
        filtered.sort((a, b) => a.addedAt.compareTo(b.addedAt));
        break;
      case 'Largest':
        filtered.sort((a, b) => b.totalBytes.compareTo(a.totalBytes));
        break;
      case 'Smallest':
        filtered.sort((a, b) => a.totalBytes.compareTo(b.totalBytes));
        break;
      case 'Progress':
        filtered.sort((a, b) => b.progress.compareTo(a.progress));
        break;
      case 'Name':
        filtered.sort((a, b) => a.fileName.compareTo(b.fileName));
        break;
      case 'Status':
        filtered.sort((a, b) => a.status.index.compareTo(b.status.index));
        break;
      case 'Recently Finished':
        filtered.sort((a, b) {
          if (a.status == DownloadStatus.done && b.status == DownloadStatus.done) {
            return b.addedAt.compareTo(a.addedAt);
          }
          return a.status == DownloadStatus.done ? -1 : 1;
        });
        break;
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final dlProvider = context.watch<DownloadProvider>();
    final appState = context.watch<AppState>();
    final queue = dlProvider.queue;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isAmoled = appState.trueAmoledDark && isDark;
    final isSelectionMode = dlProvider.isSelectionMode;

    final filtered = _filterAndSort(queue);
    final activeItems = filtered.where((i) =>
      i.status == DownloadStatus.downloading ||
      i.status == DownloadStatus.queued
    ).toList();
    final pausedItems = filtered.where((i) => i.status == DownloadStatus.paused).toList();
    final failedItems = filtered.where((i) => i.status == DownloadStatus.error).toList();
    final completedItems = filtered.where((i) => i.status == DownloadStatus.done).toList();

    return Scaffold(
      backgroundColor: isAmoled ? Colors.black : null,
      appBar: isSelectionMode ? _buildSelectionAppBar(dlProvider, cs) : null,
      body: queue.isEmpty && _searchQuery.isEmpty
        ? _buildEmptyState(cs, isDark, isAmoled, dlProvider)
        : CustomScrollView(
            controller: _scrollController,
            slivers: [
              if (!isSelectionMode) _buildSliverAppBar(cs, isDark, isAmoled, dlProvider, queue),
              if (_showSearch && !isSelectionMode)
                SliverToBoxAdapter(child: _buildSearchBar(cs, isDark)),
              if (!isSelectionMode) SliverToBoxAdapter(child: _buildDashboard(cs, isDark, queue, dlProvider)),
              if (!isSelectionMode) SliverToBoxAdapter(child: _buildQuickActions(cs, isDark, dlProvider)),
              if (!isSelectionMode) SliverToBoxAdapter(child: _buildFilterChips(cs, isDark)),
              if (!isSelectionMode && queue.isNotEmpty)
                SliverToBoxAdapter(child: _buildSortRow(cs, isDark)),
              if (activeItems.isNotEmpty) ...[
                SliverToBoxAdapter(child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
                  child: _buildSectionHeader('Active Downloads', '${activeItems.length}', cs),
                )),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _buildDownloadCard(context, dlProvider, activeItems[index]),
                    childCount: activeItems.length,
                  ),
                ),
              ],
              if (pausedItems.isNotEmpty) ...[
                SliverToBoxAdapter(child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
                  child: _buildSectionHeader('Paused', '${pausedItems.length}', cs),
                )),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _buildDownloadCard(context, dlProvider, pausedItems[index]),
                    childCount: pausedItems.length,
                  ),
                ),
              ],
              if (failedItems.isNotEmpty) ...[
                SliverToBoxAdapter(child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
                  child: _buildSectionHeader('Failed', '${failedItems.length}', cs),
                )),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _buildDownloadCard(context, dlProvider, failedItems[index]),
                    childCount: failedItems.length,
                  ),
                ),
              ],
              if (completedItems.isNotEmpty) ...[
                SliverToBoxAdapter(child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
                  child: _buildSectionHeader('Completed', '${completedItems.length}', cs),
                )),
                ..._buildCompletedSections(cs, isDark, completedItems, dlProvider),
              ],
              SliverToBoxAdapter(child: SizedBox(height: MediaQuery.of(context).padding.bottom + 80)),
            ],
          ),
    );
  }

  PreferredSizeWidget _buildSelectionAppBar(DownloadProvider dlProvider, ColorScheme cs) {
    return AppBar(
      leading: CupertinoButton(
        padding: EdgeInsets.zero,
        child: Icon(CupertinoIcons.xmark, color: cs.onSurface),
        onPressed: dlProvider.clearSelection,
      ),
      title: Text('${dlProvider.selectedIds.length} Selected',
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: cs.onSurface)),
      actions: [
        IconButton(
          icon: Icon(Icons.select_all, color: cs.onSurface),
          onPressed: dlProvider.selectAll,
        ),
        PopupMenuButton<String>(
          icon: Icon(CupertinoIcons.ellipsis_circle, color: cs.onSurface),
          onSelected: (value) async {
            switch (value) {
              case 'resume':
                for (final id in dlProvider.selectedIds.toList()) {
                  dlProvider.resume(id);
                }
                dlProvider.clearSelection();
                break;
              case 'pause':
                for (final id in dlProvider.selectedIds.toList()) {
                  dlProvider.pause(id);
                }
                dlProvider.clearSelection();
                break;
              case 'retry':
                for (final id in dlProvider.selectedIds.toList()) {
                  dlProvider.resume(id);
                }
                dlProvider.clearSelection();
                break;
              case 'delete':
                _confirmDeleteSelected(context, dlProvider);
                break;
              case 'share':
                for (final id in dlProvider.selectedIds.toList()) {
                  final item = dlProvider.queue.firstWhere((i) => i.id == id);
                  final file = File(item.savePath);
                  if (file.existsSync()) {
                    Share.shareXFiles([XFile(item.savePath)], text: item.fileName);
                  }
                }
                dlProvider.clearSelection();
                break;
              case 'copy':
                for (final id in dlProvider.selectedIds.toList()) {
                  final item = dlProvider.queue.firstWhere((i) => i.id == id);
                  await Clipboard.setData(ClipboardData(text: item.url));
                }
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('URL(s) copied to clipboard')),
                  );
                }
                dlProvider.clearSelection();
                break;
              case 'export':
                await dlProvider.exportQueue();
                dlProvider.clearSelection();
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'resume', child: ListTile(leading: Icon(CupertinoIcons.play_circle, size: 20), title: Text('Resume', style: TextStyle(fontSize: 14)), dense: true, visualDensity: VisualDensity.compact)),
            const PopupMenuItem(value: 'pause', child: ListTile(leading: Icon(CupertinoIcons.pause_circle, size: 20), title: Text('Pause', style: TextStyle(fontSize: 14)), dense: true, visualDensity: VisualDensity.compact)),
            const PopupMenuItem(value: 'retry', child: ListTile(leading: Icon(CupertinoIcons.refresh, size: 20), title: Text('Retry', style: TextStyle(fontSize: 14)), dense: true, visualDensity: VisualDensity.compact)),
            const PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(CupertinoIcons.trash, size: 20, color: CupertinoColors.destructiveRed), title: Text('Delete', style: TextStyle(fontSize: 14, color: CupertinoColors.destructiveRed)), dense: true, visualDensity: VisualDensity.compact)),
            const PopupMenuItem(value: 'share', child: ListTile(leading: Icon(CupertinoIcons.share, size: 20), title: Text('Share', style: TextStyle(fontSize: 14)), dense: true, visualDensity: VisualDensity.compact)),
            const PopupMenuItem(value: 'copy', child: ListTile(leading: Icon(CupertinoIcons.doc_on_doc, size: 20), title: Text('Copy Link', style: TextStyle(fontSize: 14)), dense: true, visualDensity: VisualDensity.compact)),
            const PopupMenuItem(value: 'export', child: ListTile(leading: Icon(Icons.upload_file, size: 20), title: Text('Export', style: TextStyle(fontSize: 14)), dense: true, visualDensity: VisualDensity.compact)),
          ],
        ),
        IconButton(
          icon: Icon(CupertinoIcons.trash, color: CupertinoColors.destructiveRed),
          onPressed: () => _confirmDeleteSelected(context, dlProvider),
        ),
      ],
    );
  }

  Widget _buildSliverAppBar(ColorScheme cs, bool isDark, bool isAmoled, DownloadProvider dlProvider, List<DownloadItem> queue) {
    return SliverAppBar(
      floating: false,
      pinned: false,
      snap: false,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      title: Text('Downloads',
        style: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.bold,
          color: cs.onSurface,
          letterSpacing: -0.5,
        ),
      ),
      actions: [
        IconButton(
          icon: Icon(CupertinoIcons.search, color: cs.onSurface),
          onPressed: () => setState(() => _showSearch = !_showSearch),
        ),
        IconButton(
          icon: Icon(CupertinoIcons.plus, color: cs.onSurface),
          onPressed: () {
            HapticService.light();
            _showNewDownloadSheet(context);
          },
        ),
        PopupMenuButton<String>(
          icon: Icon(CupertinoIcons.ellipsis, color: cs.onSurface),
          onSelected: (value) {
            if (value == 'select') {
              HapticService.light();
              dlProvider.toggleSelectionMode();
            } else if (value == 'sort') {
              _showSortPicker(cs);
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'select', child: ListTile(leading: Icon(CupertinoIcons.checkmark_circle, size: 20), title: Text('Select Items', style: TextStyle(fontSize: 14)), dense: true, visualDensity: VisualDensity.compact)),
            const PopupMenuItem(value: 'sort', child: ListTile(leading: Icon(CupertinoIcons.arrow_up_arrow_down, size: 20), title: Text('Sort', style: TextStyle(fontSize: 14)), dense: true, visualDensity: VisualDensity.compact)),
            const PopupMenuDivider(),
            const PopupMenuItem(value: 'resume', child: ListTile(leading: Icon(CupertinoIcons.play_circle, size: 20), title: Text('Resume All', style: TextStyle(fontSize: 14)), dense: true, visualDensity: VisualDensity.compact)),
            const PopupMenuItem(value: 'pause', child: ListTile(leading: Icon(CupertinoIcons.pause_circle, size: 20), title: Text('Pause All', style: TextStyle(fontSize: 14)), dense: true, visualDensity: VisualDensity.compact)),
            const PopupMenuItem(value: 'clear', child: ListTile(leading: Icon(CupertinoIcons.trash, size: 20), title: Text('Clear Completed', style: TextStyle(fontSize: 14)), dense: true, visualDensity: VisualDensity.compact)),
            const PopupMenuDivider(),
            const PopupMenuItem(value: 'export', child: ListTile(leading: Icon(Icons.upload_file, size: 20), title: Text('Export Queue', style: TextStyle(fontSize: 14)), dense: true, visualDensity: VisualDensity.compact)),
            const PopupMenuItem(value: 'import', child: ListTile(leading: Icon(Icons.download_rounded, size: 20), title: Text('Import Queue', style: TextStyle(fontSize: 14)), dense: true, visualDensity: VisualDensity.compact)),
          ],
        ),
      ],
    );
  }

  void _showSortPicker(ColorScheme cs) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => Container(
        height: 320,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Sort by', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: cs.onSurface)),
                  CupertinoButton(
                    child: Text('Done', style: TextStyle(color: cs.primary)),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                itemCount: _sortOptions.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: cs.onSurface.withValues(alpha: 0.06)),
                itemBuilder: (context, index) {
                  final option = _sortOptions[index];
                  final isSelected = _sortBy == option;
                  return GestureDetector(
                    onTap: () {
                      setState(() => _sortBy = option);
                      Navigator.pop(ctx);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          Icon(
                            isSelected ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
                            size: 20,
                            color: isSelected ? cs.primary : cs.onSurface.withValues(alpha: 0.3),
                          ),
                          const SizedBox(width: 12),
                          Text(option, style: TextStyle(fontSize: 16, color: cs.onSurface)),
                          if (isSelected) ...[
                            const Spacer(),
                            Text('Selected', style: TextStyle(fontSize: 13, color: cs.primary)),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(ColorScheme cs, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            decoration: BoxDecoration(
              color: (isDark ? Colors.white : Colors.black).withValues(alpha: isDark ? 0.08 : 0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: (isDark ? Colors.white : Colors.black).withValues(alpha: isDark ? 0.06 : 0.04),
                width: 0.5,
              ),
            ),
            child: CupertinoTextField(
              controller: _searchController,
              placeholder: 'Search by filename, URL, extension...',
              placeholderStyle: TextStyle(color: cs.onSurface.withValues(alpha: 0.4), fontSize: 15),
              style: TextStyle(color: cs.onSurface, fontSize: 15),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              prefix: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(CupertinoIcons.search, size: 18, color: cs.onSurface.withValues(alpha: 0.4)),
              ),
              suffix: _searchQuery.isNotEmpty
                ? CupertinoButton(
                    padding: EdgeInsets.zero,
                    child: Icon(CupertinoIcons.xmark_circle_fill, size: 18, color: cs.onSurface.withValues(alpha: 0.4)),
                    onPressed: () {
                      setState(() {
                        _searchQuery = '';
                        _searchController.clear();
                      });
                    },
                  )
                : null,
              clearButtonMode: OverlayVisibilityMode.never,
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDashboard(ColorScheme cs, bool isDark, List<DownloadItem> queue, DownloadProvider dlProvider) {
    final activeCount = queue.where((i) => i.status == DownloadStatus.downloading).length;
    const dur = Duration(milliseconds: 300);

    return SizedBox(
      height: 100,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemCount: 7,
        itemBuilder: (context, index) {
          switch (index) {
            case 0:
              return _dashboardCard(
                icon: CupertinoIcons.arrow_down_circle,
                label: 'Active',
                value: '$activeCount',
                color: CupertinoColors.activeBlue,
                cs: cs, isDark: isDark, dur: dur,
              );
            case 1:
              return _dashboardCard(
                icon: CupertinoIcons.clock,
                label: 'Queued',
                value: '${queue.where((i) => i.status == DownloadStatus.queued).length}',
                color: CupertinoColors.systemOrange,
                cs: cs, isDark: isDark, dur: dur,
              );
            case 2:
              final today = DateTime.now();
              final completedToday = queue.where((i) =>
                i.status == DownloadStatus.done &&
                i.addedAt.year == today.year &&
                i.addedAt.month == today.month &&
                i.addedAt.day == today.day
              ).length;
              return _dashboardCard(
                icon: CupertinoIcons.checkmark_circle,
                label: 'Today',
                value: '$completedToday',
                color: CupertinoColors.activeGreen,
                cs: cs, isDark: isDark, dur: dur,
              );
            case 3:
              return _dashboardCard(
                icon: CupertinoIcons.pause_circle,
                label: 'Paused',
                value: '${queue.where((i) => i.status == DownloadStatus.paused).length}',
                color: CupertinoColors.systemYellow,
                cs: cs, isDark: isDark, dur: dur,
              );
            case 4:
              return _dashboardCard(
                icon: CupertinoIcons.exclamationmark_circle,
                label: 'Failed',
                value: '${queue.where((i) => i.status == DownloadStatus.error).length}',
                color: CupertinoColors.destructiveRed,
                cs: cs, isDark: isDark, dur: dur,
              );
            case 5: {
              final totalSpeed = queue
                .where((i) => i.status == DownloadStatus.downloading)
                .fold<double>(0, (sum, i) => sum + i.speedBytesPerSec);
              return _dashboardCard(
                icon: Icons.speed,
                label: 'Speed',
                value: _formatSpeedCompact(totalSpeed),
                color: CupertinoColors.systemPurple,
                cs: cs, isDark: isDark, dur: dur,
              );
            }
            case 6: {
              final totalDownloaded = queue
                .where((i) => i.status == DownloadStatus.done)
                .fold<int>(0, (sum, i) => sum + i.totalBytes);
              return _dashboardCard(
                icon: Icons.download_rounded,
                label: 'Downloaded',
                value: _formatBytesCompact(totalDownloaded),
                color: CupertinoColors.activeGreen,
                cs: cs, isDark: isDark, dur: dur,
              );
            }
            default:
              return const SizedBox.shrink();
          }
        },
      ),
    );
  }

  Widget _dashboardCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required ColorScheme cs,
    required bool isDark,
    required Duration dur,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          width: 88,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: (isDark ? Colors.white : Colors.black).withValues(alpha: isDark ? 0.06 : 0.03),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: (isDark ? Colors.white : Colors.black).withValues(alpha: isDark ? 0.05 : 0.03),
              width: 0.5,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: isDark ? 0.15 : 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 14, color: color),
              ),
              const SizedBox(height: 6),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: double.tryParse(value.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0),
                duration: dur,
                builder: (context, v, _) => Text(
                  value,
                  style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              const SizedBox(height: 1),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w400,
                  color: cs.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActions(ColorScheme cs, bool isDark, DownloadProvider dlProvider) {
    return SizedBox(
      height: 62,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemCount: 7,
        itemBuilder: (context, index) {
          switch (index) {
            case 0:
              return _quickActionButton(
                icon: CupertinoIcons.plus_circle_fill,
                label: 'New',
                color: CupertinoColors.activeBlue,
                cs: cs, isDark: isDark,
                onTap: () {
                  HapticService.light();
                  _showNewDownloadSheet(context);
                },
              );
            case 1:
              return _quickActionButton(
                icon: CupertinoIcons.doc_on_clipboard,
                label: 'Paste URL',
                color: CupertinoColors.systemPurple,
                cs: cs, isDark: isDark,
                onTap: () {
                  HapticService.light();
                  _showNewDownloadSheet(context, pasteUrl: true);
                },
              );
            case 2:
              return _quickActionButton(
                icon: CupertinoIcons.play_circle_fill,
                label: 'Resume All',
                color: CupertinoColors.activeGreen,
                cs: cs, isDark: isDark,
                onTap: () { HapticService.medium(); dlProvider.resumeAll(); },
              );
            case 3:
              return _quickActionButton(
                icon: CupertinoIcons.pause_circle_fill,
                label: 'Pause All',
                color: CupertinoColors.systemOrange,
                cs: cs, isDark: isDark,
                onTap: () { HapticService.medium(); dlProvider.pauseAll(); },
              );
            case 4:
              return _quickActionButton(
                icon: CupertinoIcons.refresh,
                label: 'Retry Failed',
                color: CupertinoColors.systemYellow,
                cs: cs, isDark: isDark,
                onTap: () {
                  HapticService.medium();
                  final failed = dlProvider.queue.where((i) => i.status == DownloadStatus.error).toList();
                  for (final item in failed) {
                    dlProvider.resume(item.id);
                  }
                },
              );
            case 5:
              return _quickActionButton(
                icon: CupertinoIcons.trash,
                label: 'Clear Done',
                color: CupertinoColors.destructiveRed,
                cs: cs, isDark: isDark,
                onTap: () => _confirmClearDone(context, dlProvider),
              );
            case 6:
              return _quickActionButton(
                icon: Icons.download_rounded,
                label: 'Import',
                color: CupertinoColors.systemTeal,
                cs: cs, isDark: isDark,
                onTap: () async {
                  HapticService.light();
                  final success = await dlProvider.importQueue();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(success ? 'Queue imported!' : 'Import cancelled or failed.')),
                    );
                  }
                },
              );
            default:
              return const SizedBox.shrink();
          }
        },
      ),
    );
  }

  Widget _quickActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required ColorScheme cs,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: color.withValues(alpha: isDark ? 0.12 : 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: color.withValues(alpha: isDark ? 0.15 : 0.1),
                width: 0.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Text(label,
                  style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w500, color: cs.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChips(ColorScheme cs, bool isDark) {
    final filters = ['All', 'Downloading', 'Queued', 'Paused', 'Completed', 'Failed', 'Today', 'Media', 'Documents', 'Archives'];
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemCount: filters.length,
        itemBuilder: (context, index) {
          final filter = filters[index];
          final isSelected = _selectedFilter == filter;
          return GestureDetector(
            onTap: () {
              HapticService.selection();
              setState(() => _selectedFilter = filter);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected
                  ? cs.primary.withValues(alpha: isDark ? 0.2 : 0.12)
                  : (isDark ? Colors.white : Colors.black).withValues(alpha: isDark ? 0.06 : 0.03),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected
                    ? cs.primary.withValues(alpha: isDark ? 0.3 : 0.2)
                    : (isDark ? Colors.white : Colors.black).withValues(alpha: isDark ? 0.05 : 0.03),
                  width: 0.5,
                ),
              ),
              child: Text(
                filter,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected ? cs.primary : cs.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSortRow(ColorScheme cs, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
      child: GestureDetector(
        onTap: () => _showSortPicker(cs),
        child: Row(
          children: [
            Icon(CupertinoIcons.arrow_up_arrow_down, size: 13, color: cs.onSurface.withValues(alpha: 0.5)),
            const SizedBox(width: 4),
            Text(
              'Sorted by $_sortBy',
              style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.5)),
            ),
            const Spacer(),
            if (_selectedFilter != 'All')
              GestureDetector(
                onTap: () => setState(() => _selectedFilter = 'All'),
                child: Text(
                  'Clear Filter',
                  style: TextStyle(fontSize: 12, color: cs.primary, fontWeight: FontWeight.w500),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, String count, ColorScheme cs) {
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: cs.onSurface.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            count,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurface.withValues(alpha: 0.6)),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildCompletedSections(ColorScheme cs, bool isDark, List<DownloadItem> items, DownloadProvider dlProvider) {
    final now = DateTime.now();
    final today = <DownloadItem>[];
    final yesterday = <DownloadItem>[];
    final thisWeek = <DownloadItem>[];
    final earlier = <DownloadItem>[];

    for (final item in items) {
      final diff = now.difference(item.addedAt);
      if (diff.inDays == 0) {
        today.add(item);
      } else if (diff.inDays == 1) {
        yesterday.add(item);
      } else if (diff.inDays < 7) {
        thisWeek.add(item);
      } else {
        earlier.add(item);
      }
    }

    final sections = <Widget>[];

    void addSection(String label, List<DownloadItem> sectionItems) {
      if (sectionItems.isEmpty) return;
      sections.add(Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
        child: _buildSectionHeader(label, '${sectionItems.length}', cs),
      ));
      for (final item in sectionItems) {
        sections.add(_buildDownloadCard(context, dlProvider, item));
      }
    }

    addSection('Today', today);
    addSection('Yesterday', yesterday);
    addSection('This Week', thisWeek);
    addSection('Earlier', earlier);

    return sections;
  }

  Widget _buildDownloadCard(BuildContext context, DownloadProvider dlProvider, DownloadItem item) {
    final bool isSelected = dlProvider.selectedIds.contains(item.id);
    final bool isSelectionMode = dlProvider.isSelectionMode;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final statusColor = _statusColor(item.status, cs);

    if (item.batchId != null) {
      return _buildBatchTile(context, dlProvider, dlProvider.queue.where((i) => i.batchId == item.batchId).toList());
    }

    Widget card = GestureDetector(
      onTap: isSelectionMode
        ? () => dlProvider.toggleSelection(item.id)
        : () => _showDownloadDetails(context, dlProvider, item),
      onLongPress: isSelectionMode
        ? null
        : () {
            HapticService.medium();
            dlProvider.toggleSelection(item.id);
          },
      child: RepaintBoundary(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected
                    ? cs.primary.withValues(alpha: isDark ? 0.15 : 0.08)
                    : (isDark ? Colors.white : Colors.black).withValues(alpha: isDark ? 0.06 : 0.03),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected
                      ? cs.primary.withValues(alpha: isDark ? 0.3 : 0.2)
                      : (isDark ? Colors.white : Colors.black).withValues(alpha: isDark ? 0.05 : 0.03),
                    width: 0.5,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (isSelectionMode) ...[
                            Padding(
                              padding: const EdgeInsets.only(right: 8, top: 2),
                              child: Icon(
                                isSelected ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
                                size: 22,
                                color: isSelected ? cs.primary : cs.onSurface.withValues(alpha: 0.3),
                              ),
                            ),
                          ],
                          _buildThumbnail(item),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.fileName,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: cs.onSurface,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  item.host,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: cs.onSurface.withValues(alpha: 0.5),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          if (item.category != DownloadCategory.other)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: cs.primary.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(item.categoryLabel,
                                style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: cs.primary),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _buildProgressWidget(item, cs, isDark),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (item.status == DownloadStatus.downloading && item.speedBytesPerSec > 0)
                            Text(
                              '${_formatSpeed(item.speedBytesPerSec)} \u00b7 ${_formatETA(item.etaSeconds)}',
                              style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.6)),
                            ),
                          const Spacer(),
                          Text(
                            '${_formatBytesCompact(item.downloadedBytes)} / ${_formatBytesCompact(item.totalBytes)}',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: cs.onSurface.withValues(alpha: 0.7)),
                          ),
                          const SizedBox(width: 8),
                          _buildStatusBadge(item, statusColor, cs),
                        ],
                      ),
                      if (item.errorMessage != null && item.status == DownloadStatus.error) ...[
                        const SizedBox(height: 4),
                        Text(item.errorMessage!,
                          style: TextStyle(fontSize: 11, color: cs.error),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (!isSelectionMode) ...[
                        const SizedBox(height: 8),
                        _buildCardActions(context, dlProvider, item, cs),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return card;
  }

  Widget _buildThumbnail(DownloadItem item) {
    return FutureBuilder<String?>(
      future: ThumbnailService().getThumbnail(item.savePath),
      builder: (context, snapshot) {
        final hasThumb = snapshot.hasData && snapshot.data != null;
        return Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
            image: hasThumb
              ? DecorationImage(image: FileImage(File(snapshot.data!)), fit: BoxFit.cover)
              : null,
          ),
          child: !hasThumb
            ? Icon(
                _fileTypeIcon(item.fileName),
                size: 20,
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
              )
            : null,
        );
      },
    );
  }

  IconData _fileTypeIcon(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    if (['mp4', 'mkv', 'avi', 'mov', 'webm', 'wmv', 'flv', 'm4v'].contains(ext)) return CupertinoIcons.play_circle;
    if (['mp3', 'flac', 'wav', 'aac', 'ogg', 'wma', 'm4a'].contains(ext)) return CupertinoIcons.music_note;
    if (['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'svg', 'heic'].contains(ext)) return CupertinoIcons.photo;
    if (['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'rtf', 'csv'].contains(ext)) return CupertinoIcons.doc;
    if (['zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz', 'iso'].contains(ext)) return CupertinoIcons.archivebox;
    if (['apk', 'ipa', 'exe', 'dmg', 'deb', 'rpm'].contains(ext)) return CupertinoIcons.app;
    return CupertinoIcons.doc;
  }

  Widget _buildProgressWidget(DownloadItem item, ColorScheme cs, bool isDark) {
    final progress = item.progress;
    final status = item.status;

    if (status == DownloadStatus.done) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Container(
          height: 6,
          decoration: BoxDecoration(
            color: CupertinoColors.activeGreen.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: FractionallySizedBox(
            widthFactor: 1.0,
            child: Container(
              decoration: BoxDecoration(
                color: CupertinoColors.activeGreen,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
      );
    }

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: progress),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Container(
                height: 6,
                decoration: BoxDecoration(
                  color: (isDark ? Colors.white : Colors.black).withValues(alpha: isDark ? 0.1 : 0.06),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: FractionallySizedBox(
                  widthFactor: value.clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: status == DownloadStatus.paused
                          ? [CupertinoColors.systemYellow, CupertinoColors.systemOrange]
                          : status == DownloadStatus.error
                            ? [CupertinoColors.destructiveRed, CupertinoColors.systemPink]
                            : [cs.primary, cs.primary.withValues(alpha: 0.7)],
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${(progress * 100).toInt()}%',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: cs.onSurface.withValues(alpha: 0.5)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatusBadge(DownloadItem item, Color color, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 0.5),
      ),
      child: Text(
        item.statusLabel,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Color _statusColor(DownloadStatus status, ColorScheme cs) {
    switch (status) {
      case DownloadStatus.queued:
        return CupertinoColors.activeBlue;
      case DownloadStatus.downloading:
        return cs.primary;
      case DownloadStatus.paused:
        return CupertinoColors.systemOrange;
      case DownloadStatus.error:
        return CupertinoColors.destructiveRed;
      case DownloadStatus.done:
        return CupertinoColors.activeGreen;
    }
  }

  Widget _buildCardActions(BuildContext context, DownloadProvider dlProvider, DownloadItem item, ColorScheme cs) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (item.status == DownloadStatus.downloading || item.status == DownloadStatus.queued)
          _miniButton(CupertinoIcons.pause_circle_fill, CupertinoColors.systemOrange, () {
            HapticService.selection();
            dlProvider.pause(item.id);
          }),
        if (item.status == DownloadStatus.paused)
          _miniButton(CupertinoIcons.play_circle_fill, CupertinoColors.activeGreen, () {
            HapticService.selection();
            dlProvider.resume(item.id);
          }),
        if (item.status == DownloadStatus.error) ...[
          _miniButton(CupertinoIcons.refresh, CupertinoColors.systemOrange, () {
            HapticService.light();
            _showRefreshLinkDialog(context, dlProvider, item);
          }),
          _miniButton(CupertinoIcons.play_circle_fill, CupertinoColors.activeGreen, () {
            HapticService.selection();
            dlProvider.resume(item.id);
          }),
        ],
        if (item.status == DownloadStatus.done) ...[
          _miniButton(CupertinoIcons.share, cs.primary, () {
            HapticService.light();
            final file = File(item.savePath);
            if (file.existsSync()) {
              Share.shareXFiles([XFile(item.savePath)], text: item.fileName);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('File not found on disk.')),
              );
            }
          }),
          if (Platform.isIOS)
            _miniButton(CupertinoIcons.folder, cs.secondary, () {
              HapticService.light();
              final file = File(item.savePath);
              if (file.existsSync()) {
                dlProvider.revealFile(item.savePath);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('File not found on disk.')),
                );
              }
            }),
          if (Platform.isIOS)
            _miniButton(Icons.download_rounded, cs.tertiary, () {
              HapticService.light();
              final file = File(item.savePath);
              if (file.existsSync()) {
                dlProvider.saveToFiles(item.savePath);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('File not found on disk.')),
                );
              }
            }),
          _miniButton(CupertinoIcons.checkmark_alt_circle, CupertinoColors.activeGreen, () {
            HapticService.light();
            _showVerifyHashDialog(context, dlProvider, item);
          }),
        ],
        _miniButton(CupertinoIcons.trash, CupertinoColors.destructiveRed, () {
          HapticService.medium();
          _confirmSafeDelete(context, dlProvider, item);
        }),
        _miniButton(CupertinoIcons.ellipsis, cs.onSurface.withValues(alpha: 0.5), () {
          _showItemOptions(context, dlProvider, item);
        }),
      ],
    );
  }

  Widget _miniButton(IconData icon, Color color, VoidCallback onPressed) {
    return Container(
      margin: const EdgeInsets.only(left: 2),
      child: CupertinoButton(
        padding: const EdgeInsets.all(6),
        minSize: 32,
        pressedOpacity: 0.6,
        onPressed: onPressed,
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }

  Widget _buildBatchTile(BuildContext context, DownloadProvider dlProvider, List<DownloadItem> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    final batchName = items.first.batchName ?? 'Folder Download';
    final String batchId = items.first.batchId!;
    final bool isExpanded = _expandedBatchIds.contains(batchId);
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final totalItems = items.length;
    final doneItems = items.where((i) => i.status == DownloadStatus.done).length;
    final avgProgress = items.fold<double>(0.0, (sum, i) => sum + i.progress) / totalItems;

    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                color: (isDark ? Colors.white : Colors.black).withValues(alpha: isDark ? 0.06 : 0.03),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: cs.primary.withValues(alpha: 0.15),
                  width: 0.5,
                ),
              ),
              child: Column(
                children: [
                  GestureDetector(
                    onTap: () {
                      HapticService.light();
                      setState(() {
                        if (isExpanded) {
                          _expandedBatchIds.remove(batchId);
                        } else {
                          _expandedBatchIds.add(batchId);
                        }
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(
                              color: cs.primary.withValues(alpha: isDark ? 0.15 : 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            alignment: Alignment.center,
                            child: Icon(CupertinoIcons.folder, size: 18, color: cs.primary),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(batchName,
                                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: cs.onSurface),
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text('$doneItems / $totalItems files \u00b7 ${(avgProgress * 100).toInt()}%',
                                  style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6)),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(CupertinoIcons.ellipsis, size: 18, color: cs.onSurface.withValues(alpha: 0.5)),
                            onPressed: () => _showBatchOptions(context, dlProvider, batchId, items),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                          const SizedBox(width: 4),
                          AnimatedRotation(
                            turns: isExpanded ? 0.5 : 0.0,
                            duration: const Duration(milliseconds: 200),
                            child: Icon(CupertinoIcons.chevron_down, size: 16, color: cs.onSurface.withValues(alpha: 0.5)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  AnimatedCrossFade(
                    firstChild: const SizedBox.shrink(),
                    secondChild: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: Column(
                        children: items.map((item) => _buildDownloadCard(context, dlProvider, item)).toList(),
                      ),
                    ),
                    crossFadeState: isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                    duration: const Duration(milliseconds: 250),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme cs, bool isDark, bool isAmoled, DownloadProvider dlProvider) {
    return Scaffold(
      backgroundColor: isAmoled ? Colors.black : null,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: Text('Downloads',
          style: TextStyle(
            fontSize: 34, fontWeight: FontWeight.bold, color: cs.onSurface,
            letterSpacing: -0.5,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(CupertinoIcons.plus, color: cs.onSurface),
            onPressed: () {
              HapticService.light();
              _showNewDownloadSheet(context);
            },
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: isDark ? 0.12 : 0.08),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(CupertinoIcons.arrow_down_circle, size: 40, color: cs.primary.withValues(alpha: 0.5)),
            ),
            const SizedBox(height: 20),
            Text('No Downloads Yet',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: cs.onSurface),
            ),
            const SizedBox(height: 8),
            Text('Start downloading files to build your library.',
              style: TextStyle(fontSize: 15, color: cs.onSurface.withValues(alpha: 0.5)),
            ),
            const SizedBox(height: 24),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: isDark ? 0.15 : 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: cs.primary.withValues(alpha: isDark ? 0.2 : 0.12),
                      width: 0.5,
                    ),
                  ),
                  child: CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    onPressed: () {
                      HapticService.light();
                      _showNewDownloadSheet(context);
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(CupertinoIcons.plus, size: 18, color: cs.primary),
                        const SizedBox(width: 6),
                        Text('New Download', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: cs.primary)),
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

  void _showNewDownloadSheet(BuildContext context, {bool pasteUrl = false}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => NewDownloadSheet(autoPaste: pasteUrl),
    );
  }

  void _showDownloadDetails(BuildContext context, DownloadProvider dlProvider, DownloadItem item) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        snap: true,
        snapSizes: const [0.4, 0.7, 0.9],
        builder: (context, scrollController) {
          return ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: Container(
                decoration: BoxDecoration(
                  color: (isDark ? Colors.grey.shade900 : Colors.white).withValues(alpha: 0.95),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                  border: Border(
                    top: BorderSide(
                      color: (isDark ? Colors.white : Colors.black).withValues(alpha: isDark ? 0.1 : 0.05),
                    ),
                  ),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 8),
                      child: Container(width: 40, height: 4,
                        decoration: BoxDecoration(
                          color: cs.onSurface.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(item.fileName,
                              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: cs.onSurface),
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          CupertinoButton(
                            padding: EdgeInsets.zero,
                            child: Icon(CupertinoIcons.xmark_circle_fill, size: 24, color: cs.onSurface.withValues(alpha: 0.4)),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: cs.onSurface.withValues(alpha: 0.08)),
                    Expanded(
                      child: ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.all(20),
                        children: [
                          _detailRow(cs, CupertinoIcons.arrow_down_circle, 'Status', item.statusLabel),
                          if (item.status == DownloadStatus.downloading || item.status == DownloadStatus.paused || item.status == DownloadStatus.done) ...[
                            const SizedBox(height: 8),
                            _detailRow(cs, Icons.download_rounded, 'Transferred',
                              '${_formatBytesCompact(item.downloadedBytes)} / ${_formatBytesCompact(item.totalBytes)}'),
                            const SizedBox(height: 8),
                            _detailRow(cs, Icons.speed, 'Speed',
                              item.speedBytesPerSec > 0 ? _formatSpeed(item.speedBytesPerSec) : '--'),
                            const SizedBox(height: 8),
                            _detailRow(cs, CupertinoIcons.timer, 'ETA',
                              item.etaSeconds > 0 ? _formatETA(item.etaSeconds) : '--'),
                            const SizedBox(height: 8),
                            _detailRow(cs, CupertinoIcons.clock, 'Progress', '${(item.progress * 100).toInt()}%'),
                          ],
                          const SizedBox(height: 16),
                          Divider(height: 1, color: cs.onSurface.withValues(alpha: 0.08)),
                          const SizedBox(height: 8),
                          _detailRow(cs, CupertinoIcons.link, 'Source URL', item.url),
                          const SizedBox(height: 8),
                          if (item.originalUrl != null && item.originalUrl != item.url)
                            _detailRow(cs, Icons.open_in_new, 'Original URL', item.originalUrl!),
                          if (item.originalUrl != null && item.originalUrl != item.url) const SizedBox(height: 8),
                          _detailRow(cs, CupertinoIcons.folder, 'Destination', item.savePath),
                          const SizedBox(height: 8),
                          _detailRow(cs, CupertinoIcons.doc, 'Filename', item.fileName),
                          const SizedBox(height: 8),
                          _detailRow(cs, Icons.language, 'Host', item.host),
                          if (item.resolvedUrl != null) ...[
                            const SizedBox(height: 8),
                            _detailRow(cs, Icons.alt_route, 'Resolved URL', item.resolvedUrl!),
                          ],
                          if (item.redirectCount > 0) ...[
                            const SizedBox(height: 8),
                            _detailRow(cs, CupertinoIcons.repeat, 'Redirects', '${item.redirectCount}'),
                          ],
                          if (item.customHeaders.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            _detailRow(cs, Icons.list_alt, 'Headers', '${item.customHeaders.length} header(s)'),
                          ],
                          if (item.expectedMd5 != null || item.expectedSha1 != null || item.expectedSha256 != null) ...[
                            const SizedBox(height: 16),
                            Divider(height: 1, color: cs.onSurface.withValues(alpha: 0.08)),
                            const SizedBox(height: 8),
                            Text('Verification', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface.withValues(alpha: 0.5))),
                            const SizedBox(height: 8),
                            if (item.expectedMd5 != null) ...[
                              _detailRow(cs, CupertinoIcons.shield, 'Expected MD5', item.expectedMd5!),
                              if (item.calculatedMd5 != null) ...[
                                const SizedBox(height: 4),
                                _detailRow(cs, Icons.verified_user, 'Calculated MD5', item.calculatedMd5!),
                              ],
                            ],
                            if (item.expectedSha1 != null) ...[
                              const SizedBox(height: 8),
                              _detailRow(cs, CupertinoIcons.shield, 'Expected SHA1', item.expectedSha1!),
                              if (item.calculatedSha1 != null) ...[
                                const SizedBox(height: 4),
                                _detailRow(cs, Icons.verified_user, 'Calculated SHA1', item.calculatedSha1!),
                              ],
                            ],
                            if (item.expectedSha256 != null) ...[
                              const SizedBox(height: 8),
                              _detailRow(cs, CupertinoIcons.shield, 'Expected SHA256', item.expectedSha256!),
                              if (item.calculatedSha256 != null) ...[
                                const SizedBox(height: 4),
                                _detailRow(cs, Icons.verified_user, 'Calculated SHA256', item.calculatedSha256!),
                              ],
                            ],
                          ],
                          const SizedBox(height: 24),
                          _buildDetailActions(context, dlProvider, item, cs),
                        ],
                      ),
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

  Widget _detailRow(ColorScheme cs, IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 14, color: cs.primary),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 80,
          child: Text(label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: cs.onSurface.withValues(alpha: 0.5)),
          ),
        ),
        Expanded(
          child: Text(value,
            style: TextStyle(fontSize: 12, color: cs.onSurface, fontWeight: FontWeight.w500),
            maxLines: 3, overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildDetailActions(BuildContext context, DownloadProvider dlProvider, DownloadItem item, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (item.status == DownloadStatus.downloading || item.status == DownloadStatus.queued)
          _detailActionButton(CupertinoIcons.pause_circle, CupertinoColors.systemOrange, 'Pause', () {
            HapticService.selection();
            dlProvider.pause(item.id);
            Navigator.pop(context);
          }),
        if (item.status == DownloadStatus.paused)
          _detailActionButton(CupertinoIcons.play_circle, CupertinoColors.activeGreen, 'Resume', () {
            HapticService.selection();
            dlProvider.resume(item.id);
            Navigator.pop(context);
          }),
        if (item.status == DownloadStatus.error)
          _detailActionButton(CupertinoIcons.refresh, CupertinoColors.systemOrange, 'Retry', () {
            HapticService.selection();
            dlProvider.resume(item.id);
            Navigator.pop(context);
          }),
        if (item.status == DownloadStatus.done) ...[
          _detailActionButton(CupertinoIcons.share, cs.primary, 'Share', () {
            HapticService.light();
            Navigator.pop(context);
            final file = File(item.savePath);
            if (file.existsSync()) {
              Share.shareXFiles([XFile(item.savePath)], text: item.fileName);
            }
          }),
          if (Platform.isIOS)
            _detailActionButton(CupertinoIcons.folder, cs.secondary, 'Reveal in Files', () {
              HapticService.light();
              Navigator.pop(context);
              dlProvider.revealFile(item.savePath);
            }),
          if (Platform.isIOS)
            _detailActionButton(Icons.download_rounded, cs.tertiary, 'Save to Files', () {
              HapticService.light();
              Navigator.pop(context);
              dlProvider.saveToFiles(item.savePath);
            }),
        ],
        _detailActionButton(CupertinoIcons.trash, CupertinoColors.destructiveRed, 'Delete Download', () {
          Navigator.pop(context);
          HapticService.medium();
          _confirmSafeDelete(context, dlProvider, item);
        }),
      ],
    );
  }

  Widget _detailActionButton(IconData icon, Color color, String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: CupertinoButton(
            padding: const EdgeInsets.symmetric(vertical: 12),
            onPressed: onTap,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 8),
                Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: color)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showItemOptions(BuildContext context, DownloadProvider dlProvider, DownloadItem item) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showCupertinoModalPopup(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.only(top: 8),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: cs.onSurface.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            CupertinoActionSheetAction(
              onPressed: () { HapticService.medium(); Navigator.pop(context); _showDownloadDetails(context, dlProvider, item); },
              child: const Text('Details'),
            ),
            if (item.status == DownloadStatus.paused)
              CupertinoActionSheetAction(
                isDefaultAction: true,
                onPressed: () { HapticService.selection(); Navigator.pop(context); dlProvider.resume(item.id); },
                child: const Text('Resume'),
              ),
            if (item.status == DownloadStatus.downloading || item.status == DownloadStatus.queued)
              CupertinoActionSheetAction(
                onPressed: () { HapticService.selection(); Navigator.pop(context); dlProvider.pause(item.id); },
                child: const Text('Pause'),
              ),
            if (item.status == DownloadStatus.error)
              CupertinoActionSheetAction(
                isDefaultAction: true,
                onPressed: () { HapticService.selection(); Navigator.pop(context); dlProvider.resume(item.id); },
                child: const Text('Retry'),
              ),
            if (item.status == DownloadStatus.error)
              CupertinoActionSheetAction(
                onPressed: () { HapticService.light(); Navigator.pop(context); _showRefreshLinkDialog(context, dlProvider, item); },
                child: const Text('Refresh Link'),
              ),
            if (item.status == DownloadStatus.done) ...[
              CupertinoActionSheetAction(
                onPressed: () { HapticService.light(); Navigator.pop(context); Share.shareXFiles([XFile(item.savePath)], text: item.fileName); },
                child: const Text('Share'),
              ),
              if (Platform.isIOS)
                CupertinoActionSheetAction(
                  onPressed: () { HapticService.light(); Navigator.pop(context); dlProvider.revealFile(item.savePath); },
                  child: const Text('Reveal in Files'),
                ),
              if (Platform.isIOS)
                CupertinoActionSheetAction(
                  onPressed: () { HapticService.light(); Navigator.pop(context); dlProvider.saveToFiles(item.savePath); },
                  child: const Text('Save to Files'),
                ),
            ],
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () { Navigator.pop(context); HapticService.medium(); _confirmSafeDelete(context, dlProvider, item); },
              child: const Text('Delete'),
            ),
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showBatchOptions(BuildContext context, DownloadProvider dlProvider, String batchId, List<DownloadItem> items) {
    showCupertinoModalPopup(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('Batch Actions'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () { HapticService.medium(); dlProvider.resumeBatch(batchId); Navigator.pop(context); },
            child: const Row(
              children: [
                Icon(CupertinoIcons.play_circle, color: CupertinoColors.activeGreen, size: 22),
                SizedBox(width: 12),
                Text('Resume All in Batch'),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () { HapticService.medium(); dlProvider.pauseBatch(batchId); Navigator.pop(context); },
            child: const Row(
              children: [
                Icon(CupertinoIcons.pause_circle, color: CupertinoColors.systemOrange, size: 22),
                SizedBox(width: 12),
                Text('Pause All in Batch'),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () { HapticService.heavy(); Navigator.pop(context); _confirmRemoveBatch(context, dlProvider, batchId); },
            child: const Row(
              children: [
                Icon(Icons.delete_sweep, color: CupertinoColors.destructiveRed, size: 22),
                SizedBox(width: 12),
                Text('Remove Batch'),
              ],
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  void _confirmRemoveBatch(BuildContext context, DownloadProvider dlProvider, String batchId) {
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Remove Batch?'),
        content: const Text('Are you sure you want to remove all items in this batch?'),
        actions: [
          CupertinoDialogAction(isDefaultAction: true, onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          CupertinoDialogAction(isDestructiveAction: true, onPressed: () { dlProvider.stopBatch(batchId); Navigator.pop(ctx); }, child: const Text('Remove')),
        ],
      ),
    );
  }

  void _showRefreshLinkDialog(BuildContext context, DownloadProvider dlProvider, DownloadItem item) {
    final controller = TextEditingController(text: item.originalUrl ?? item.url);
    bool isValidating = false;

    showCupertinoDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (context, setState) {
        return CupertinoAlertDialog(
          title: const Text('Refresh Download Link'),
          content: Column(
            children: [
              const Text('Enter a new URL for this download.\nProgress will be preserved if the server supports resume.',
                  style: TextStyle(fontSize: 12)),
              const SizedBox(height: 10),
              CupertinoTextField(
                controller: controller,
                placeholder: 'New URL',
                clearButtonMode: OverlayVisibilityMode.editing,
              ),
              if (isValidating) const SizedBox(height: 10),
              if (isValidating) const CupertinoActivityIndicator(),
            ],
          ),
          actions: [
            CupertinoDialogAction(isDefaultAction: true, onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            CupertinoDialogAction(
              isDestructiveAction: !isValidating ? false : true,
              onPressed: isValidating ? null : () async {
                setState(() => isValidating = true);
                final success = await dlProvider.refreshLink(item.id, controller.text.trim());
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(success ? 'Link updated successfully' : 'Failed to validate new link')),
                  );
                }
              },
              child: const Text('Update & Resume'),
            ),
          ],
        );
      }),
    );
  }

  void _confirmSafeDelete(BuildContext context, DownloadProvider dlProvider, DownloadItem item) {
    bool deleteFile = false;
    showCupertinoDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (context, setState) {
        return CupertinoAlertDialog(
          title: const Text('Delete Task?'),
          content: Column(
            children: [
              Text('Are you sure you want to remove "${item.fileName}" from the queue?'),
              const SizedBox(height: 10),
              Row(
                children: [
                  CupertinoCheckbox(value: deleteFile, onChanged: (val) => setState(() => deleteFile = val ?? false)),
                  const SizedBox(width: 8),
                  const Flexible(child: Text('Delete file from storage as well', style: TextStyle(fontSize: 13))),
                ],
              ),
            ],
          ),
          actions: [
            CupertinoDialogAction(isDefaultAction: true, onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            CupertinoDialogAction(isDestructiveAction: true, onPressed: () {
              dlProvider.stop(item.id);
              if (deleteFile) {
                final f = File(item.savePath);
                if (f.existsSync()) f.deleteSync();
              }
              Navigator.pop(ctx);
            }, child: const Text('Delete')),
          ],
        );
      }),
    );
  }

  void _confirmDeleteSelected(BuildContext context, DownloadProvider dlProvider) {
    bool deleteFile = false;
    showCupertinoDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (context, setState) {
        return CupertinoAlertDialog(
          title: const Text('Delete Selected?'),
          content: Column(
            children: [
              Text('Are you sure you want to remove ${dlProvider.selectedIds.length} items?'),
              const SizedBox(height: 10),
              Row(
                children: [
                  CupertinoCheckbox(value: deleteFile, onChanged: (val) => setState(() => deleteFile = val ?? false)),
                  const SizedBox(width: 8),
                  const Flexible(child: Text('Delete files from storage as well', style: TextStyle(fontSize: 13))),
                ],
              ),
            ],
          ),
          actions: [
            CupertinoDialogAction(isDefaultAction: true, onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            CupertinoDialogAction(isDestructiveAction: true, onPressed: () { dlProvider.deleteSelected(deleteFiles: deleteFile); Navigator.pop(ctx); }, child: const Text('Delete')),
          ],
        );
      }),
    );
  }

  void _confirmClearDone(BuildContext context, DownloadProvider dlProvider) {
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Clear Finished Tasks?'),
        content: const Text('This will remove completed and failed tasks from the list.'),
        actions: [
          CupertinoDialogAction(isDefaultAction: true, onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          CupertinoDialogAction(isDestructiveAction: true, onPressed: () { dlProvider.clearDone(); Navigator.pop(ctx); }, child: const Text('Clear List')),
        ],
      ),
    );
  }

  void _showVerifyHashDialog(BuildContext context, DownloadProvider dlProvider, DownloadItem item) {
    final ctrl = TextEditingController();
    bool isVerifying = false;
    bool? isValid;
    String? algorithm;

    final dialogCs = Theme.of(context).colorScheme;
    showCupertinoDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (dialogCtx, setState) {
        return CupertinoAlertDialog(
          title: const Text('Verify File Hash'),
          content: Column(
            children: [
              Text('Check hash for: ${item.fileName}', style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 10),
              Row(
                children: [
                  _hashAlgoChip('MD5', setState, algorithm, (v) => algorithm = v),
                  const SizedBox(width: 4),
                  _hashAlgoChip('SHA1', setState, algorithm, (v) => algorithm = v),
                  const SizedBox(width: 4),
                  _hashAlgoChip('SHA256', setState, algorithm, (v) => algorithm = v),
                ],
                mainAxisAlignment: MainAxisAlignment.center,
              ),
              const SizedBox(height: 10),
              CupertinoTextField(controller: ctrl, placeholder: 'Expected hash value'),
              const SizedBox(height: 10),
              if (isVerifying) const CupertinoActivityIndicator(),
              if (!isVerifying && isValid != null)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(isValid! ? CupertinoIcons.checkmark_circle : CupertinoIcons.xmark_circle,
                        color: isValid! ? Colors.green : Colors.red),
                    const SizedBox(width: 8),
                    Text(isValid! ? 'Hash Matches!' : 'Hash Mismatch!',
                        style: TextStyle(color: isValid! ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
                  ],
                ),
              if (item.calculatedMd5 != null || item.calculatedSha1 != null || item.calculatedSha256 != null) ...[
                const SizedBox(height: 8),
                Text('Auto-computed checksums:', style: TextStyle(fontSize: 10, color: dialogCs.onSurface.withValues(alpha: 0.6))),
                if (item.calculatedMd5 != null) Text('MD5: ${item.calculatedMd5}', style: const TextStyle(fontSize: 8)),
                if (item.calculatedSha1 != null) Text('SHA1: ${item.calculatedSha1}', style: const TextStyle(fontSize: 8)),
                if (item.calculatedSha256 != null) Text('SHA256: ${item.calculatedSha256}', style: const TextStyle(fontSize: 8)),
              ],
            ],
          ),
          actions: [
            if (!isVerifying)
              CupertinoDialogAction(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
            if (!isVerifying)
              CupertinoDialogAction(
                isDefaultAction: true,
                onPressed: () async {
                  if (ctrl.text.trim().isEmpty || algorithm == null) return;
                  setState(() { isVerifying = true; isValid = null; });
                  final result = await dlProvider.verifyFileHash(item.savePath, ctrl.text);
                  if (context.mounted) {
                    setState(() { isVerifying = false; isValid = result; });
                  }
                },
                child: const Text('Verify'),
              ),
          ],
        );
      }),
    );
  }

  Widget _hashAlgoChip(String label, StateSetter setState, String? selected, Function(String) onSelected) {
    final isSelected = selected == label;
    return GestureDetector(
      onTap: () => setState(() => onSelected(label)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? CupertinoColors.activeBlue : CupertinoColors.systemGrey5,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : Colors.black)),
      ),
    );
  }

  String _formatSpeed(double bytesPerSec) {
    if (bytesPerSec <= 0) return '0 B/s';
    if (bytesPerSec > 1024 * 1024) return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    if (bytesPerSec > 1024) return '${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    return '${bytesPerSec.toStringAsFixed(0)} B/s';
  }

  String _formatSpeedCompact(double bytesPerSec) {
    if (bytesPerSec <= 0) return '0 B/s';
    if (bytesPerSec > 1024 * 1024) return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    if (bytesPerSec > 1024) return '${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    return '${bytesPerSec.toStringAsFixed(0)} B/s';
  }

  String _formatETA(int seconds) {
    if (seconds <= 0) return '--';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  String _formatBytesCompact(int bytes) {
    if (bytes <= 0) return '0B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = (log(bytes) / log(1024)).floor();
    var val = bytes / pow(1024, i);
    if (val >= 100) return '${val.toStringAsFixed(0)}${suffixes[i]}';
    return '${val.toStringAsFixed(1)}${suffixes[i]}';
  }
}
