import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:libtorrent_flutter/libtorrent_flutter.dart' as lt;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/torrent_provider.dart';
import '../../domain/entities/torrent_task.dart';

 
class TorrentDetailScreen extends StatefulWidget {
  final TorrentTask task;

  const TorrentDetailScreen({super.key, required this.task});

  @override
  State<TorrentDetailScreen> createState() => _TorrentDetailScreenState();
}

class _TorrentDetailScreenState extends State<TorrentDetailScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  late TorrentTask _task;
  List<dynamic> _files = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _task = widget.task;
    _loadFiles();
  }

  void _loadFiles() {
    if (_task.hasMetadata) {
      final provider = context.read<TorrentProvider>();
      _files = provider.getFiles(_task.id);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TorrentProvider>();
    final updated = provider.tasks.where((t) => t.id == _task.id).firstOrNull;
    if (updated != null) _task = updated;

    return Scaffold(
      appBar: AppBar(
        title: Text(_task.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'General'),
            Tab(text: 'Trackers'),
            Tab(text: 'Peers'),
            Tab(text: 'Files'),
            Tab(text: 'Pieces'),
            Tab(text: 'Statistics'),
          ],
        ),
        actions: [
          if (_task.status == TorrentStatus.downloading)
            IconButton(
              icon: const Icon(Icons.pause),
              tooltip: 'Pause',
              onPressed: () => provider.pauseTask(_task.id),
            ),
          if (_task.status == TorrentStatus.paused)
            IconButton(
              icon: const Icon(Icons.play_arrow),
              tooltip: 'Resume',
              onPressed: () => provider.resumeTask(_task.id),
            ),
          PopupMenuButton<String>(
            onSelected: (val) => _handleAction(val, provider),
            itemBuilder: (_) => [
              if (_task.status == TorrentStatus.downloading)
                const PopupMenuItem(value: 'pause', child: Text('Pause')),
              if (_task.status == TorrentStatus.paused)
                const PopupMenuItem(value: 'resume', child: Text('Resume')),
              const PopupMenuItem(value: 'stop', child: Text('Stop')),
              const PopupMenuItem(value: 'recheck', child: Text('Force Recheck')),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildGeneralTab(),
          _buildTrackersTab(),
          _buildPeersTab(),
          _buildFilesTab(),
          _buildPiecesTab(),
          _buildStatisticsTab(),
        ],
      ),
    );
  }

  void _handleAction(String action, TorrentProvider provider) {
    switch (action) {
      case 'pause':
        provider.pauseTask(_task.id);
      case 'resume':
        provider.resumeTask(_task.id);
      case 'stop':
        provider.stopTask(_task.id);
        Navigator.pop(context);
      case 'recheck':
        provider.recheckTask(_task.id);
      case 'delete':
        _confirmDelete(provider);
    }
  }

  void _confirmDelete(TorrentProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Torrent'),
        content: const Text('Also delete downloaded files?'),
        actions: [
          TextButton(
            onPressed: () {
              provider.removeTask(_task.id);
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('Remove Only'),
          ),
          TextButton(
            onPressed: () {
              provider.removeTask(_task.id);
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: Text('Delete Files', style: TextStyle(color: Colors.red.shade400)),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor, IconData? icon, Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
          ],
          SizedBox(
            width: 120,
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(value,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: valueColor)),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(title,
          style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary)),
    );
  }

  String _getInfoHash() {
    if (_task.magnetLink != null) {
      final provider = context.read<TorrentProvider>();
      final hash = provider.magnetHandler.getInfoHash(_task.magnetLink!);
      if (hash != null) return hash.toUpperCase();
    }
    return 'Unknown';
  }

  Widget _buildGeneralTab() {
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        _buildSectionHeader('General'),
        _buildInfoRow('Name', _task.name),
        _buildInfoRow('Hash', _getInfoHash()),
        _buildInfoRow('Save Location', _task.savePath),
        _buildInfoRow('Size', _task.sizeFormatted),
        _buildInfoRow('Progress', '${(_task.progress * 100).toStringAsFixed(1)}%'),
        _buildInfoRow('State', _task.status.name.toUpperCase()),
        _buildInfoRow('Added', _formatDate(_task.addedAt)),
        if (_task.errorMsg.isNotEmpty)
          _buildInfoRow('Error', _task.errorMsg, valueColor: Colors.red),
        if (!_task.hasMetadata)
          _buildInfoRow('Metadata', 'Fetching...'),
        const Divider(),
        _buildSectionHeader('Actions'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (_task.status == TorrentStatus.downloading)
                _actionChip(Icons.pause, 'Pause', () => context.read<TorrentProvider>().pauseTask(_task.id)),
              if (_task.status == TorrentStatus.paused)
                _actionChip(Icons.play_arrow, 'Resume', () => context.read<TorrentProvider>().resumeTask(_task.id)),
              _actionChip(Icons.stop, 'Stop', () { context.read<TorrentProvider>().stopTask(_task.id); Navigator.pop(context); }, Colors.red),
              _actionChip(Icons.refresh, 'Recheck', () => context.read<TorrentProvider>().recheckTask(_task.id)),
              _actionChip(Icons.share, 'Share', () => _shareMagnet()),
              _actionChip(Icons.folder_open, 'Open Folder', () => _openFolder()),
              _actionChip(Icons.drive_file_move, 'Move Storage', () => _pickMovePath()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _actionChip(IconData icon, String label, VoidCallback onPressed, [Color? color]) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return ActionChip(
      avatar: Icon(icon, size: 16, color: c),
      label: Text(label, style: TextStyle(fontSize: 12, color: c)),
      onPressed: onPressed,
      backgroundColor: c.withValues(alpha: 0.1),
      side: BorderSide(color: c.withValues(alpha: 0.3)),
    );
  }

  void _shareMagnet() async {
    final magnet = _task.magnetLink;
    if (magnet != null && magnet.isNotEmpty) {
      await Share.share(magnet, subject: _task.name);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No magnet link available')),
        );
      }
    }
  }

  void _openFolder() async {
    final uri = Uri.file(_task.savePath);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  void _pickMovePath() async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      final provider = context.read<TorrentProvider>();
      await provider.moveStorage(_task.id, result);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Moved to $result')),
        );
      }
    }
  }

  List<String> _getTrackers() {
    final trackers = <String>[
      'udp://tracker.openbittorrent.com:80',
      'udp://tracker.opentrackr.org:1337',
      'udp://tracker.torrent.eu.org:451',
      'udp://tracker.coppersurfer.tk:6969',
    ];
    if (_task.magnetLink != null) {
      try {
        final uri = Uri.parse(_task.magnetLink!);
        final trs = uri.queryParametersAll['tr'];
        if (trs != null) {
          trackers.addAll(trs);
        }
      } catch (_) {}
    }
    return trackers.toSet().toList();
  }

  Widget _buildTrackersTab() {
    final trackers = _getTrackers();
    if (trackers.isEmpty) {
      return const Center(child: Text('No trackers'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: trackers.length,
      itemBuilder: (_, i) => Card(
        child: ListTile(
          leading: const Icon(Icons.dns, size: 20),
          title: Text(trackers[i], style: const TextStyle(fontSize: 13)),
          subtitle: Text('Status: ${i == 0 ? "Working" : "Unknown"}', style: const TextStyle(fontSize: 11)),
          trailing: Icon(Icons.check_circle, size: 18, color: Colors.green.shade400),
        ),
      ),
    );
  }

  Widget _buildPeersTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildInfoRow('Connected Peers', '${_task.numPeers}'),
        _buildInfoRow('Seeds', '${_task.numSeeds}'),
        _buildInfoRow('Leechers', '${_task.leechers}'),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _peerStat(Icons.arrow_upward, 'Up', _task.speedUpFormatted, Colors.orange),
                    _peerStat(Icons.arrow_downward, 'Down', _task.speedDownFormatted, Colors.green),
                    _peerStat(Icons.compare_arrows, 'Ratio', _task.ratioFormatted, Colors.blue),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _peerStat(IconData icon, String label, String value, Color color) {
    return Column(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: color)),
        Text(label, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5))),
      ],
    );
  }

  Widget _buildFilesTab() {
    if (!_task.hasMetadata) {
      return const Center(child: Text('Metadata not yet available'));
    }
    if (_files.isEmpty) {
      _loadFiles();
      return const Center(child: CircularProgressIndicator());
    }
    return _buildFileTree();
  }

  Widget _buildFileTree() {
    final tree = _buildFileTreeData(_files);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: tree.entries.map((entry) => _buildFileTreeNode(entry, 0)).toList(),
    );
  }

  Map<String, dynamic> _buildFileTreeData(List<dynamic> files) {
    final root = <String, dynamic>{};
    for (final f in files) {
      final parts = f.path.replaceAll('\\', '/').split('/');
      var current = root;
      for (var i = 0; i < parts.length - 1; i++) {
        current = current.putIfAbsent(parts[i], () => <String, dynamic>{}) as Map<String, dynamic>;
      }
      current[parts.last] = f;
    }
    return root;
  }

  Widget _buildFileTreeNode(MapEntry<String, dynamic> entry, int depth) {
    if (entry.value is! Map<String, dynamic>) {
      final file = entry.value;
      return _buildFileLeaf(file, depth);
    }
    final children = entry.value as Map<String, dynamic>;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.only(left: 16.0 + depth * 20, right: 16),
        leading: const Icon(Icons.folder, size: 18),
        title: Text(entry.key, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        children: children.entries.map((e) => _buildFileTreeNode(e, depth + 1)).toList(),
      ),
    );
  }

  Widget _buildFileLeaf(dynamic file, int depth) {
    final provider = context.read<TorrentProvider>();
    final f = file as lt.FileInfo;
    return Padding(
      padding: EdgeInsets.only(left: 16.0 + depth * 20),
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.insert_drive_file, size: 18),
        title: Text(f.name, style: const TextStyle(fontSize: 13)),
        subtitle: Text(formatSize(f.size), style: const TextStyle(fontSize: 11)),
        trailing: PopupMenuButton<int>(
          initialValue: 4,
          icon: const Icon(Icons.low_priority, size: 18),
          onSelected: (priority) {
            final current = provider.getFiles(_task.id);
            final priorities = current.map((e) => (e as lt.FileInfo).index == f.index ? priority : 4).toList();
            provider.setFilePriorities(_task.id, priorities);
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 0, child: Text('Skip', style: TextStyle(color: Colors.grey))),
            const PopupMenuItem(value: 1, child: Text('Low')),
            const PopupMenuItem(value: 4, child: Text('Normal')),
            const PopupMenuItem(value: 7, child: Text('High', style: TextStyle(color: Colors.green))),
          ],
        ),
      ),
    );
  }

  Widget _buildPiecesTab() {
    const totalPieces = 100;
    final completedPieces = (_task.progress * totalPieces).round();
    final partialPieces = (_task.progress * totalPieces % 1 > 0) ? 1 : 0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildInfoRow('Total Pieces', '$totalPieces'),
        _buildInfoRow('Completed', '$completedPieces'),
        _buildInfoRow('Partial', '$partialPieces'),
        _buildInfoRow('Pending', '${totalPieces - completedPieces - partialPieces}'),
        const SizedBox(height: 16),
        const Text('Piece Grid', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Wrap(
            spacing: 2,
            runSpacing: 2,
            children: List.generate(totalPieces, (i) {
              Color color;
              if (i < completedPieces) {
                color = Colors.green;
              } else if (i == completedPieces && partialPieces > 0) {
                color = Colors.orange;
              } else {
                color = Theme.of(context).colorScheme.surfaceContainerHighest;
              }
              return Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _pieceLegend(Colors.green, 'Done'),
            const SizedBox(width: 16),
            _pieceLegend(Colors.orange, 'Partial'),
            const SizedBox(width: 16),
            _pieceLegend(Theme.of(context).colorScheme.surfaceContainerHighest, 'Pending'),
          ],
        ),
      ],
    );
  }

  Widget _pieceLegend(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }

  Widget _buildStatisticsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionHeader('Transfer'),
        _buildInfoRow('Download Speed', _task.speedDownFormatted, icon: Icons.arrow_downward, valueColor: Colors.green),
        _buildInfoRow('Upload Speed', _task.speedUpFormatted, icon: Icons.arrow_upward, valueColor: Colors.orange),
        _buildInfoRow('Downloaded', _task.downloadedFormatted, icon: Icons.save_alt),
        _buildInfoRow('Uploaded', _task.uploadedFormatted, icon: Icons.cloud_upload),
        _buildInfoRow('Total Size', _task.sizeFormatted, icon: Icons.storage),
        _buildInfoRow('Remaining', formatSize((_task.totalWanted - _task.totalDone).clamp(0, _task.totalWanted)), icon: Icons.hourglass_bottom),
        _buildInfoRow('Ratio', _task.ratioFormatted, icon: Icons.compare_arrows),
        const Divider(),
        _buildSectionHeader('Time'),
        _buildInfoRow('ETA', _task.etaFormatted, icon: Icons.timer),
        _buildInfoRow('Added', _formatDate(_task.addedAt), icon: Icons.add_circle_outline),
        const Divider(),
        _buildSectionHeader('Connections'),
        _buildInfoRow('Total Peers', '${_task.numPeers}', icon: Icons.people),
        _buildInfoRow('Seeds', '${_task.numSeeds}', icon: Icons.person),
        _buildInfoRow('Leechers', '${_task.leechers}', icon: Icons.person_outline),
        _buildInfoRow('Queue Position', '—', icon: Icons.format_list_numbered),
        const Divider(),
        _buildSectionHeader('Limits'),
        _buildInfoRow('Download Limit', _task.downloadRateLimit > 0 ? formatSpeed(_task.downloadRateLimit) : 'Unlimited', icon: Icons.speed),
        _buildInfoRow('Upload Limit', _task.uploadRateLimit > 0 ? formatSpeed(_task.uploadRateLimit) : 'Unlimited', icon: Icons.speed),
        _buildInfoRow('Sequential', _task.sequentialDownload ? 'Yes' : 'No', icon: Icons.sort),
      ],
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
