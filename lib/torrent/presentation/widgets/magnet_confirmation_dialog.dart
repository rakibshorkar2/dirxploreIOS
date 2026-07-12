import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/torrent_task.dart';
import '../providers/torrent_provider.dart';

void showMagnetConfirmationDialog(
  BuildContext context, {
  String? magnetUri,
  String? torrentFilePath,
}) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => MagnetConfirmationDialog(
      magnetUri: magnetUri,
      torrentFilePath: torrentFilePath,
    ),
  );
}

class MagnetConfirmationDialog extends StatefulWidget {
  final String? magnetUri;
  final String? torrentFilePath;
  const MagnetConfirmationDialog({
    super.key,
    this.magnetUri,
    this.torrentFilePath,
  });

  @override
  State<MagnetConfirmationDialog> createState() => _MagnetConfirmationDialogState();
}

class _MagnetConfirmationDialogState extends State<MagnetConfirmationDialog> {
  TorrentInfoPreview? _preview;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchInfo();
  }

  Future<void> _fetchInfo() async {
    final provider = context.read<TorrentProvider>();
    try {
      final preview = widget.magnetUri != null
          ? await provider.probeMagnet(widget.magnetUri!)
          : await provider.probeTorrentFile(widget.torrentFilePath!);
      if (mounted) {
        setState(() {
          _preview = preview;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _confirm() {
    if (_preview == null) return;
    context.read<TorrentProvider>().confirmMagnet(_preview!.engineId);
    Navigator.pop(context);
  }

  void _cancel() {
    if (_preview != null) {
      context.read<TorrentProvider>().cancelMagnetProbe(_preview!.engineId);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(
        _loading
            ? 'Fetching Info…'
            : _error != null
                ? 'Error'
                : 'Add Torrent',
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: _loading
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            : _error != null
                ? Text('Failed to load torrent info: $_error')
                : _preview != null
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_preview!.name,
                              style: theme.textTheme.titleMedium),
                          const SizedBox(height: 16),
                          _infoRow('Size', formatSize(_preview!.size)),
                          _infoRow('Files', '${_preview!.fileCount}'),
                          _infoRow('Trackers', '${_preview!.trackerCount}'),
                          if (widget.magnetUri != null)
                            _infoRow('Source', 'Magnet Link'),
                          if (widget.torrentFilePath != null)
                            _infoRow('Source', '.torrent File'),
                        ],
                      )
                    : const Text('No preview available'),
      ),
      actions: [
        TextButton(onPressed: _cancel, child: const Text('Cancel')),
        if (_preview != null)
          FilledButton(onPressed: _confirm, child: const Text('Add Torrent')),
      ],
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text('$label: ',
              style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value),
        ],
      ),
    );
  }
}
