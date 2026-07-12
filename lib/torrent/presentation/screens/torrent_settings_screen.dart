import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/torrent_provider.dart';
import '../../domain/entities/torrent_settings.dart';

class TorrentSettingsScreen extends StatefulWidget {
  const TorrentSettingsScreen({super.key});

  @override
  State<TorrentSettingsScreen> createState() => _TorrentSettingsScreenState();
}

class _TorrentSettingsScreenState extends State<TorrentSettingsScreen> {
  late TorrentSettings _draft;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _draft = context.read<TorrentProvider>().settings;
  }

  Future<void> _pickDefaultPath() async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      setState(() => _draft = _draft.copyWith(defaultSavePath: result));
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await context.read<TorrentProvider>().applySettings(_draft);
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Torrent Settings'),
        actions: [
          _saving
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : TextButton(
                  onPressed: _save,
                  child: const Text('Save'),
                ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionHeader(cs, 'Downloads', Icons.download_rounded),
          _pathTile(cs),
          const SizedBox(height: 4),
          _switchTile(cs, 'Auto Start', 'Start torrents when added', _draft.autoStart, (v) {
            setState(() => _draft = _draft.copyWith(autoStart: v));
          }),
          _switchTile(cs, 'Auto Seed', 'Continue seeding after completion', _draft.autoSeed, (v) {
            setState(() => _draft = _draft.copyWith(autoSeed: v));
          }),
          _switchTile(cs, 'Auto Delete .torrent', 'Remove .torrent file after import', _draft.autoDeleteTorrentFile, (v) {
            setState(() => _draft = _draft.copyWith(autoDeleteTorrentFile: v));
          }),
          _switchTile(cs, 'Sequential Download', 'Download pieces in order', _draft.enableSequentialDownload, (v) {
            setState(() => _draft = _draft.copyWith(enableSequentialDownload: v));
          }),
          const SizedBox(height: 24),
          _sectionHeader(cs, 'Speed & Limits', Icons.speed_rounded),
          _limitSlider(cs, 'Download Limit', _draft.downloadLimitKb, (v) {
            setState(() => _draft = _draft.copyWith(downloadLimitKb: v));
          }),
          _limitSlider(cs, 'Upload Limit', _draft.uploadLimitKb, (v) {
            setState(() => _draft = _draft.copyWith(uploadLimitKb: v));
          }),
          _intStepper(cs, 'Max Active Torrents', _draft.maxActiveTorrents, 1, 50, (v) {
            setState(() => _draft = _draft.copyWith(maxActiveTorrents: v));
          }),
          _intStepper(cs, 'Max Active Downloads', _draft.maxActiveDownloads, 1, 20, (v) {
            setState(() => _draft = _draft.copyWith(maxActiveDownloads: v));
          }),
          _intStepper(cs, 'Max Active Uploads', _draft.maxActiveUploads, 1, 20, (v) {
            setState(() => _draft = _draft.copyWith(maxActiveUploads: v));
          }),
          const SizedBox(height: 24),
          _sectionHeader(cs, 'Network', Icons.wifi_rounded),
          _intStepper(cs, 'Max Peers per Torrent', _draft.maxPeersPerTorrent, 1, 500, (v) {
            setState(() => _draft = _draft.copyWith(maxPeersPerTorrent: v));
          }),
          _intStepper(cs, 'Max Connections', _draft.maxConnections, 1, 2000, (v) {
            setState(() => _draft = _draft.copyWith(maxConnections: v));
          }),
          _switchTile(cs, 'Enable DHT', 'Distributed Hash Table for peer discovery', _draft.enableDht, (v) {
            setState(() => _draft = _draft.copyWith(enableDht: v));
          }),
          _switchTile(cs, 'Enable PEX', 'Peer Exchange between peers', _draft.enablePex, (v) {
            setState(() => _draft = _draft.copyWith(enablePex: v));
          }),
          _switchTile(cs, 'Enable LSD', 'Local Service Discovery on LAN', _draft.enableLsd, (v) {
            setState(() => _draft = _draft.copyWith(enableLsd: v));
          }),
          _switchTile(cs, 'Enable Encryption', 'Force encrypted connections', _draft.enableEncryption, (v) {
            setState(() => _draft = _draft.copyWith(enableEncryption: v));
          }),
          const SizedBox(height: 24),
          _sectionHeader(cs, 'Session', Icons.restart_alt_rounded),
          _switchTile(cs, 'Resume Previous Session', 'Restore active torrents on startup', _draft.resumeSession, (v) {
            setState(() => _draft = _draft.copyWith(resumeSession: v));
          }),
          const SizedBox(height: 24),
          _sectionHeader(cs, 'Notifications', Icons.notifications_rounded),
          _switchTile(cs, 'Download Complete', 'Notify when a torrent finishes', _draft.notifyDownloadComplete, (v) {
            setState(() => _draft = _draft.copyWith(notifyDownloadComplete: v));
          }),
          _switchTile(cs, 'Download Started', 'Notify when a torrent starts', _draft.notifyDownloadStarted, (v) {
            setState(() => _draft = _draft.copyWith(notifyDownloadStarted: v));
          }),
          const SizedBox(height: 32),
        ],
      ),
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

  Widget _glassCard(ColorScheme cs, {required Widget child}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      color: cs.surfaceContainerLow,
      child: child,
    );
  }

  Widget _pathTile(ColorScheme cs) {
    return _glassCard(cs,
      child: ListTile(
        leading: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.folder_rounded, size: 18, color: cs.primary),
        ),
        title: const Text('Default Download Directory', style: TextStyle(fontSize: 14)),
        subtitle: Text(
          _draft.defaultSavePath.isNotEmpty ? _draft.defaultSavePath : 'App documents directory',
          style: const TextStyle(fontSize: 12),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: TextButton(
          onPressed: _pickDefaultPath,
          child: const Text('Change'),
        ),
      ),
    );
  }

  Widget _switchTile(ColorScheme cs, String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return _glassCard(cs,
      child: SwitchListTile(
        title: Text(title, style: const TextStyle(fontSize: 14)),
        subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6))),
        value: value,
        onChanged: onChanged,
        dense: true,
      ),
    );
  }

  Widget _limitSlider(ColorScheme cs, String label, int valueKb, ValueChanged<int> onChanged) {
    final display = valueKb == 0 ? 'Unlimited' : valueKb >= 1024 ? '${(valueKb / 1024).toStringAsFixed(1)} MB/s' : '$valueKb KB/s';
    return _glassCard(cs,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(label, style: const TextStyle(fontSize: 14)),
                const Spacer(),
                Text(display, style: TextStyle(fontSize: 13, color: cs.primary, fontWeight: FontWeight.w600)),
              ],
            ),
            Slider(
              value: valueKb.toDouble(),
              min: 0,
              max: 10240,
              divisions: 40,
              onChanged: (v) => onChanged(v.round()),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('0', style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.4))),
                Text('10 MB/s', style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.4))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _intStepper(ColorScheme cs, String label, int value, int min, int max, ValueChanged<int> onChanged) {
    return _glassCard(cs,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline_rounded, size: 20),
              onPressed: value > min ? () => onChanged(value - 1) : null,
            ),
            SizedBox(
              width: 40,
              child: Text(
                '$value',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
              onPressed: value < max ? () => onChanged(value + 1) : null,
            ),
          ],
        ),
      ),
    );
  }
}
