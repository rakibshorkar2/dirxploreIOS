import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:disk_space_2/disk_space_2.dart';
import 'package:path_provider/path_provider.dart';
import '../providers/torrent_provider.dart';
import '../../domain/entities/torrent_task.dart';
import '../../infrastructure/services/native_bridge.dart';

class StorageManagementScreen extends StatefulWidget {
  const StorageManagementScreen({super.key});

  @override
  State<StorageManagementScreen> createState() => _StorageManagementScreenState();
}

class _StorageManagementScreenState extends State<StorageManagementScreen> {
  double _freeSpace = 0;
  double _totalSpace = 0;
  bool _loading = true;
  bool _moving = false;
  bool _cleaningCache = false;
  bool _cleaningResume = false;

  @override
  void initState() {
    super.initState();
    _loadDiskInfo();
  }

  Future<void> _loadDiskInfo() async {
    setState(() => _loading = true);
    try {
      final bridge = TorrentNativeBridge();
      if (bridge.isAvailable) {
        final storage = await bridge.getDeviceStorage();
        _freeSpace = storage['free'] ?? 0;
        _totalSpace = storage['total'] ?? 0;
      } else {
        _totalSpace = await DiskSpace.getTotalDiskSpace ?? 0;
        _freeSpace = await DiskSpace.getFreeDiskSpace ?? 0;
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  int get _torrentStorageUsed {
    final provider = context.read<TorrentProvider>();
    return provider.tasks.fold<int>(0, (sum, t) => sum + t.totalDone);
  }

  int get _torrentStorageTotal {
    final provider = context.read<TorrentProvider>();
    return provider.tasks.fold<int>(0, (sum, t) => sum + t.totalWanted);
  }

  Future<void> _moveAllStorage() async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result == null) return;
    setState(() => _moving = true);
    final provider = context.read<TorrentProvider>();
    for (final task in provider.tasks) {
      if (task.totalDone > 0) {
        await provider.moveStorage(task.id, result);
      }
    }
    if (!mounted) return;
    setState(() => _moving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Moved ${provider.tasks.length} torrents to $result')),
    );
  }

  Future<void> _deleteCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Cache'),
        content: const Text('Remove temporary torrent cache data? Active torrents may need to re-check.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Delete', style: TextStyle(color: Colors.red.shade400))),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _cleaningCache = true);
    try {
      final bridge = TorrentNativeBridge();
      if (bridge.isAvailable) {
        await bridge.deleteTorrentCache();
      }
      final tempDir = await getTemporaryDirectory();
      int deleted = 0;
      await for (final entity in tempDir.list(recursive: true)) {
        if (entity is File && entity.path.contains('libtorrent')) {
          await entity.delete();
          deleted++;
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted $deleted cache files')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cache cleanup failed: $e')),
      );
    }
    if (mounted) setState(() => _cleaningCache = false);
  }

  Future<void> _cleanResumeData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clean Resume Data'),
        content: const Text('Remove fast-resume data for all torrents. '
            'Torrents will need to re-check files on next start. Continue?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Clean', style: TextStyle(color: Colors.red.shade400))),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _cleaningResume = true);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final resumeDir = Directory('${dir.path}/.resume');
      if (await resumeDir.exists()) {
        int deleted = 0;
        await for (final entity in resumeDir.list()) {
          if (entity is File) {
            await entity.delete();
            deleted++;
          }
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cleaned $deleted resume files')),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No resume data found')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Resume cleanup failed: $e')),
      );
    }
    if (mounted) setState(() => _cleaningResume = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final provider = context.watch<TorrentProvider>();
    final tasks = provider.tasks;
    final used = _torrentStorageUsed;
    final total = _torrentStorageTotal;

    return Scaffold(
      appBar: AppBar(title: const Text('Storage Management')),
      body: RefreshIndicator(
        onRefresh: _loadDiskInfo,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildOverviewCard(cs, used, total),
            const SizedBox(height: 24),
            _sectionHeader(cs, 'Torrent Storage', Icons.storage_rounded),
            if (tasks.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text('No active torrents',
                      style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5))),
                ),
              )
            else
              ...tasks.map((t) => _buildTorrentTile(cs, t)),
            const SizedBox(height: 24),
            _sectionHeader(cs, 'Actions', Icons.build_rounded),
            const SizedBox(height: 8),
            _actionCard(cs, Icons.drive_file_move_rounded, 'Move All Storage',
                'Move all torrent data to a new location', _moving, _moving ? 'Moving...' : null, _moveAllStorage),
            const SizedBox(height: 8),
            _actionCard(cs, Icons.cleaning_services_rounded, 'Delete Cache',
                'Remove temporary torrent cache files', _cleaningCache, null, _deleteCache),
            const SizedBox(height: 8),
            _actionCard(cs, Icons.restart_alt_rounded, 'Clean Resume Data',
                'Remove fast-resume data (forces re-check)', _cleaningResume, null, _cleanResumeData),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewCard(ColorScheme cs, int used, int total) {
    final usedGb = used / 1073741824;
    final freeGb = _freeSpace / 1073741824;
    final totalGb = _totalSpace / 1073741824;
    final pct = _totalSpace > 0 ? (_freeSpace / _totalSpace * 100) : 0;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      color: cs.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Row(
                    children: [
                      _statBox(cs, 'Torrent Data', usedGb, 'GB used', Colors.blue),
                      const SizedBox(width: 16),
                      _statBox(cs, 'Free Space', freeGb, 'GB free', Colors.green),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: (100 - pct) / 100,
                      minHeight: 10,
                      backgroundColor: Colors.green.withValues(alpha: 0.15),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        pct > 20 ? Colors.green : pct > 10 ? Colors.orange : Colors.red,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${pct.toStringAsFixed(1)}% free',
                          style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6))),
                      Text('${totalGb.toStringAsFixed(1)} GB total',
                          style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6))),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  Widget _statBox(ColorScheme cs, String label, double value, String unit, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6))),
            const SizedBox(height: 4),
            Text(value.toStringAsFixed(1),
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color)),
            Text(unit, style: TextStyle(fontSize: 12, color: color.withValues(alpha: 0.7))),
          ],
        ),
      ),
    );
  }

  Widget _buildTorrentTile(ColorScheme cs, TorrentTask task) {
    final pct = task.totalWanted > 0 ? task.totalDone / task.totalWanted : 0.0;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      color: cs.surfaceContainerLow,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _showMoveDialog(task),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.insert_drive_file_rounded, size: 18, color: cs.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(task.name,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(task.downloadedFormatted,
                            style: TextStyle(fontSize: 12, color: cs.primary)),
                        if (task.totalWanted > 0) ...[
                          Text(' / ${task.sizeFormatted}',
                              style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.5))),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: task.hasMetadata ? pct : null,
                        minHeight: 5,
                        backgroundColor: cs.surfaceContainerHighest,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, size: 20, color: cs.onSurface.withValues(alpha: 0.3)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showMoveDialog(TorrentTask task) async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result == null) return;
    final provider = context.read<TorrentProvider>();
    await provider.moveStorage(task.id, result);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Moved "${task.name}" to $result')),
    );
  }

  Widget _sectionHeader(ColorScheme cs, String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: cs.primary),
          const SizedBox(width: 8),
          Text(title,
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600, color: cs.onSurface.withValues(alpha: 0.8))),
        ],
      ),
    );
  }

  Widget _actionCard(ColorScheme cs, IconData icon, String title, String subtitle, bool loading, String? loadingLabel, VoidCallback onTap) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      color: cs.surfaceContainerLow,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: loading ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: loading
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(icon, size: 18, color: cs.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 2),
                    Text(loadingLabel ?? subtitle,
                        style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.5))),
                  ],
                ),
              ),
              if (!loading)
                Icon(Icons.chevron_right_rounded, size: 20, color: cs.onSurface.withValues(alpha: 0.3)),
            ],
          ),
        ),
      ),
    );
  }
}
