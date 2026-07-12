import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../providers/app_state.dart';
import '../providers/torrent_provider.dart';
import '../../domain/entities/torrent_task.dart';
import '../widgets/magnet_confirmation_dialog.dart';
import 'torrent_detail_screen.dart';
import 'add_torrent_screen.dart';
import 'torrent_settings_screen.dart';
import 'storage_management_screen.dart';

class TorrentTab extends StatefulWidget {
  const TorrentTab({super.key});

  @override
  State<TorrentTab> createState() => _TorrentTabState();
}

class _TorrentTabState extends State<TorrentTab>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchController = TextEditingController();
  StreamSubscription<String>? _magnetSub;
  StreamSubscription<String>? _torrentFileSub;
  bool _tabVisible = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() => _tabVisible = _tabController.indexIsChanging == false);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final p = context.read<TorrentProvider>();
        p.init();
        p.addListener(_onProviderChange);
        final mh = p.magnetHandler;
        _magnetSub = mh.onMagnetReceived.listen((magnetUri) {
          if (mounted) {
            showMagnetConfirmationDialog(context, magnetUri: magnetUri);
          }
        });
        _torrentFileSub = mh.onTorrentFileReceived.listen((path) {
          if (mounted) {
            showMagnetConfirmationDialog(context, torrentFilePath: path);
          }
        });
      }
    });
  }

  void _onProviderChange() {
    if (mounted && _tabVisible) setState(() {});
  }

  @override
  void dispose() {
    try { context.read<TorrentProvider>().removeListener(_onProviderChange); } catch (_) {}
    _magnetSub?.cancel();
    _torrentFileSub?.cancel();
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _showProviderSelector(BuildContext context, TorrentProvider provider) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Search Providers',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                TextButton(
                  onPressed: provider.toggleSelectAllProviders,
                  child: Text(
                    provider.enabledProviders.length == torrentProviders.length
                        ? 'Deselect All'
                        : 'Select All',
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          SizedBox(
            height: 320,
            child: ListView(
              children: torrentProviders.map((p) {
                final enabled = provider.enabledProviders.contains(p);
                return SwitchListTile(
                  title: Text(p),
                  value: enabled,
                  onChanged: (_) => provider.toggleProvider(p),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final torrentProvider = context.read<TorrentProvider>();
    final appState = context.watch<AppState>();
    final isAmoled = appState.trueAmoledDark &&
        Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Torrents'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Search'),
            Tab(text: 'Active'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.storage),
            tooltip: 'Storage Management',
            onPressed: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => const StorageManagementScreen(),
            )),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Torrent Settings',
            onPressed: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => const TorrentSettingsScreen(),
            )),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Add Torrent',
            onPressed: () => showAddTorrentSheet(context),
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
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
            ),
          ),
          Column(
            children: [
              if (torrentProvider.results.isNotEmpty ||
                  torrentProvider.isSearching)
                _buildSearchBar(torrentProvider),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildSearchTab(context, torrentProvider),
                    _buildActiveTab(context, torrentProvider),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(TorrentProvider provider) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search torrents...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: provider.isSearching
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              provider.clearResults();
                            },
                          )
                        : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                isDense: true,
              ),
              onSubmitted: (val) => provider.search(val),
              textInputAction: TextInputAction.search,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Providers',
            onPressed: () => _showProviderSelector(context, provider),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            tooltip: 'Sort',
            onSelected: provider.setSortBy,
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                value: 'seeds',
                checked: provider.sortBy == 'seeds',
                child: const Text('By Seeds'),
              ),
              CheckedPopupMenuItem(
                value: 'size',
                checked: provider.sortBy == 'size',
                child: const Text('By Size'),
              ),
              CheckedPopupMenuItem(
                value: 'name',
                checked: provider.sortBy == 'name',
                child: const Text('By Name'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchTab(BuildContext context, TorrentProvider provider) {
    if (provider.results.isEmpty && !provider.isSearching) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.search, size: 64,
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4)),
              const SizedBox(height: 16),
              Text('Search Torrents',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                'Search across 10 torrent providers.\nYTS, 1337x, PirateBay, Nyaa, and more.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6)),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: TorrentCategory.values.map((cat) {
                  if (cat == TorrentCategory.all) return const SizedBox.shrink();
                  final selected = provider.selectedCategory == cat;
                  return FilterChip(
                    label: Text(categoryLabels[cat] ?? ''),
                    selected: selected,
                    onSelected: (_) => provider.setCategory(cat),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Add Torrent'),
                onPressed: () => showAddTorrentSheet(context),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: TorrentCategory.values.map((cat) {
                final selected = provider.selectedCategory == cat;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(categoryLabels[cat] ?? ''),
                    selected: selected,
                    onSelected: (_) => provider.setCategory(cat),
                    visualDensity: VisualDensity.compact,
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 80),
            itemCount: provider.results.length,
            itemBuilder: (context, index) {
              final result = provider.results[index];
              return _buildResultCard(context, result, provider);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildResultCard(
      BuildContext context, TorrentSearchResult result, TorrentProvider provider) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showResultDetail(context, result, provider),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                result.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  _buildBadge(result.provider, Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 6),
                  _buildBadge(result.size, Colors.orange),
                  const Spacer(),
                  Icon(Icons.arrow_upward,
                      size: 14, color: Colors.green.shade600),
                  const SizedBox(width: 2),
                  Text('${result.seeds}',
                      style: TextStyle(
                          color: Colors.green.shade600,
                          fontWeight: FontWeight.w600,
                          fontSize: 12)),
                  const SizedBox(width: 8),
                  Icon(Icons.arrow_downward,
                      size: 14, color: Colors.red.shade400),
                  const SizedBox(width: 2),
                  Text('${result.leechers}',
                      style: TextStyle(
                          color: Colors.red.shade400,
                          fontWeight: FontWeight.w600,
                          fontSize: 12)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text,
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  void _showResultDetail(BuildContext context, TorrentSearchResult result,
      TorrentProvider provider) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(16),
          children: [
            Text(result.title,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildInfoChip('Provider', result.provider),
                const SizedBox(width: 8),
                _buildInfoChip('Size', result.size),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildInfoChip(
                    'Seeds', result.seeds.toString(), color: Colors.green),
                const SizedBox(width: 8),
                _buildInfoChip('Leechers', result.leechers.toString(),
                    color: Colors.red),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.download),
                label: const Text('Download Torrent'),
                onPressed: () async {
                  provider.addMagnet(result.magnetUrl);
                  if (!mounted) return;
                  Navigator.pop(ctx);
                  _tabController.animateTo(1);
                },
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.copy),
                label: const Text('Copy Magnet Link'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: result.magnetUrl));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Magnet link copied to clipboard')),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip(String label, String value, {Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: (color ?? Theme.of(context).colorScheme.primary)
            .withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ',
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.6))),
          Text(value,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color)),
        ],
      ),
    );
  }

  Widget _buildActiveTab(BuildContext context, TorrentProvider provider) {
    final tasks = provider.tasks;

    if (tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.downloading, size: 64,
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text('No Active Torrents',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Add a magnet link or search for torrents\nto start downloading.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Add Torrent'),
              onPressed: () => showAddTorrentSheet(context),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        if (tasks.any((t) => t.isFinished))
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.clear_all, size: 18),
                  label: const Text('Clear Completed'),
                  onPressed: provider.clearCompleted,
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView.builder(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 80),
            itemCount: tasks.length,
            itemBuilder: (context, index) {
              final task = tasks[index];
              return _buildTaskCard(context, task, provider);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTaskCard(
      BuildContext context, TorrentTask task, TorrentProvider provider) {
    final showProgress = task.status == TorrentStatus.downloading ||
        task.status == TorrentStatus.paused ||
        task.status == TorrentStatus.checking;
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: CupertinoContextMenu(
        actions: [
          CupertinoContextMenuAction(
            child: const Text('Pause'),
            onPressed: () {
              Navigator.pop(context);
              provider.pauseTask(task.id);
            },
          ),
          CupertinoContextMenuAction(
            child: const Text('Resume'),
            onPressed: () {
              Navigator.pop(context);
              provider.resumeTask(task.id);
            },
          ),
          CupertinoContextMenuAction(
            child: const Text('Stop'),
            onPressed: () {
              Navigator.pop(context);
              provider.stopTask(task.id);
            },
          ),
          CupertinoContextMenuAction(
            child: const Text('Recheck'),
            onPressed: () {
              Navigator.pop(context);
              provider.recheckTask(task.id);
            },
          ),
          CupertinoContextMenuAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.pop(context);
              provider.removeTask(task.id);
            },
            child: const Text('Remove'),
          ),
        ],
        child: GestureDetector(
          onLongPress: () {},
          child: Card(
            margin: EdgeInsets.zero,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
            ),
            color: cs.surfaceContainerLow,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => TorrentDetailScreen(task: task),
              )),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: _iconColor(task.status).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            _torrentIcon(task.status),
                            size: 20,
                            color: _iconColor(task.status),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                task.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _statusSubtitle(task),
                                style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.5)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildStatusBadge(task.status),
                      ],
                    ),
                    if (showProgress) ...[
                      const SizedBox(height: 14),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: task.hasMetadata ? task.progress : null,
                          minHeight: 6,
                          backgroundColor: cs.surfaceContainerHighest,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Text(
                            task.hasMetadata
                                ? '${(task.progress * 100).toStringAsFixed(1)}%'
                                : 'Fetching metadata…',
                            style: TextStyle(
                                fontSize: 12,
                                color: cs.primary,
                                fontWeight: FontWeight.w600),
                          ),
                          const Spacer(),
                          if (task.downloadRate > 0)
                            _metaIcon(Icons.arrow_downward_rounded, task.speedDownFormatted, cs, Colors.green),
                          if (task.uploadRate > 0) ...[
                            const SizedBox(width: 8),
                            _metaIcon(Icons.arrow_upward_rounded, task.speedUpFormatted, cs, Colors.orange),
                          ],
                        ],
                      ),
                    ],
                    if (!showProgress && task.status == TorrentStatus.done) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.check_circle_rounded, size: 14, color: Colors.green.shade400),
                          const SizedBox(width: 4),
                          Text('Completed',
                              style: TextStyle(fontSize: 12, color: Colors.green.shade400, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        if (task.status == TorrentStatus.downloading && task.eta != null) ...[
                          _metaIcon(Icons.timer_outlined, task.etaFormatted, cs),
                          const SizedBox(width: 12),
                        ],
                        if (task.numPeers > 0) ...[
                          _metaIcon(Icons.people_outline, '${task.numSeeds}/${task.numPeers}', cs),
                          const SizedBox(width: 12),
                        ],
                        if (task.ratio > 0) ...[
                          _metaIcon(Icons.swap_horiz, task.ratioFormatted, cs),
                          const SizedBox(width: 12),
                        ],
                        const Spacer(),
                        if (task.totalDone > 0)
                          Text(task.downloadedFormatted,
                              style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.5))),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        _compactButton(
                          icon: task.status == TorrentStatus.downloading
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          tooltip: task.status == TorrentStatus.downloading ? 'Pause' : 'Resume',
                          onPressed: task.status == TorrentStatus.downloading
                              ? () => provider.pauseTask(task.id)
                              : () => provider.resumeTask(task.id),
                          cs: cs,
                        ),
                        const SizedBox(width: 4),
                        _compactButton(
                          icon: Icons.stop_rounded,
                          tooltip: 'Stop',
                          onPressed: () => provider.stopTask(task.id),
                          cs: cs,
                        ),
                        const SizedBox(width: 4),
                        _compactButton(
                          icon: Icons.refresh_rounded,
                          tooltip: 'Recheck',
                          onPressed: () => provider.recheckTask(task.id),
                          cs: cs,
                        ),
                        const SizedBox(width: 4),
                        _compactButton(
                          icon: Icons.delete_rounded,
                          tooltip: 'Remove',
                          color: CupertinoColors.destructiveRed,
                          onPressed: () => provider.removeTask(task.id),
                          cs: cs,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  IconData _torrentIcon(TorrentStatus status) {
    switch (status) {
      case TorrentStatus.downloading: return Icons.download_rounded;
      case TorrentStatus.seeding: return Icons.cloud_upload_rounded;
      case TorrentStatus.paused: return Icons.pause_rounded;
      case TorrentStatus.error: return Icons.error_outline_rounded;
      case TorrentStatus.checking: return Icons.manage_search_rounded;
      case TorrentStatus.queued: return Icons.hourglass_top_rounded;
      case TorrentStatus.done: return Icons.check_circle_rounded;
      default: return Icons.more_horiz_rounded;
    }
  }

  Color _iconColor(TorrentStatus status) {
    switch (status) {
      case TorrentStatus.downloading: return Colors.green;
      case TorrentStatus.seeding: return Colors.teal;
      case TorrentStatus.paused: return Colors.orange;
      case TorrentStatus.error: return Colors.red;
      case TorrentStatus.checking: return Colors.blueGrey;
      case TorrentStatus.queued: return Colors.grey;
      case TorrentStatus.done: return Colors.green.shade700;
      default: return Colors.grey;
    }
  }

  String _statusSubtitle(TorrentTask task) {
    if (task.status == TorrentStatus.downloading) {
      if (task.hasMetadata) {
        return '${task.downloadedFormatted} of ${task.sizeFormatted}';
      }
      return 'Fetching metadata…';
    }
    if (task.status == TorrentStatus.seeding) {
      return 'Uploaded ${task.uploadedFormatted}';
    }
    if (task.status == TorrentStatus.paused) {
      if (task.hasMetadata) {
        return '${(task.progress * 100).toStringAsFixed(1)}% — ${task.downloadedFormatted}';
      }
      return 'Paused';
    }
    if (task.status == TorrentStatus.error) return 'Error';
    if (task.status == TorrentStatus.checking) return 'Checking…';
    if (task.status == TorrentStatus.queued) return 'Queued';
    if (task.status == TorrentStatus.done) {
      return '${task.sizeFormatted} — ${task.ratioFormatted} ratio';
    }
    return 'Idle';
  }

  Widget _metaIcon(IconData icon, String text, ColorScheme cs, [Color? color]) {
    final c = color ?? cs.onSurface.withValues(alpha: 0.45);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: c),
        const SizedBox(width: 3),
        Text(text,
            style: TextStyle(fontSize: 11, color: c, fontWeight: color != null ? FontWeight.w600 : null)),
      ],
    );
  }

  Widget _compactButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    required ColorScheme cs,
    Color? color,
  }) {
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        padding: EdgeInsets.zero,
        icon: Icon(icon, size: 18, color: color ?? cs.onSurface.withValues(alpha: 0.7)),
        tooltip: tooltip,
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildStatusBadge(TorrentStatus status) {
    final color = _iconColor(status);
    final label = _statusLabel(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  String _statusLabel(TorrentStatus status) {
    switch (status) {
      case TorrentStatus.searching: return 'Searching';
      case TorrentStatus.downloading: return 'Downloading';
      case TorrentStatus.seeding: return 'Seeding';
      case TorrentStatus.paused: return 'Paused';
      case TorrentStatus.error: return 'Error';
      case TorrentStatus.checking: return 'Checking';
      case TorrentStatus.queued: return 'Queued';
      case TorrentStatus.done: return 'Done';
      default: return 'Idle';
    }
  }
}
