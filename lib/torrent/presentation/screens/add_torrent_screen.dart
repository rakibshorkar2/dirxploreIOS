import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../widgets/magnet_confirmation_dialog.dart';

void showAddTorrentSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => const AddTorrentSheet(),
  );
}

class AddTorrentSheet extends StatefulWidget {
  const AddTorrentSheet({super.key});

  @override
  State<AddTorrentSheet> createState() => _AddTorrentSheetState();
}

class _AddTorrentSheetState extends State<AddTorrentSheet> {
  final _magnetController = TextEditingController();
  final _urlController = TextEditingController();
  bool _downloadingUrl = false;

  @override
  void dispose() {
    _magnetController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  void _addMagnet(String magnetUri) {
    final uri = magnetUri.trim();
    if (uri.isEmpty) return;
    Navigator.pop(context);
    showMagnetConfirmationDialog(context, magnetUri: uri);
  }

  Future<void> _pickTorrentFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['torrent'],
    );
    if (result != null && result.files.single.path != null) {
      if (!mounted) return;
      final path = result.files.single.path!;
      Navigator.pop(context);
      showMagnetConfirmationDialog(context, torrentFilePath: path);
    }
  }

  Future<void> _browseFilesApp() async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result == null) return;
    final dir = Directory(result);
    final torrentFiles = <File>[];
    try {
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File && entity.path.endsWith('.torrent')) {
          torrentFiles.add(entity);
        }
      }
    } catch (_) {}
    if (!mounted) return;
    if (torrentFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No .torrent files found in selected folder')),
      );
      return;
    }
    if (torrentFiles.length == 1) {
      Navigator.pop(context);
      showMagnetConfirmationDialog(context, torrentFilePath: torrentFiles.first.path);
      return;
    }
    _showFilePickerList(torrentFiles);
  }

  void _showFilePickerList(List<File> files) {
    Navigator.pop(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${files.length} torrents found'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView.builder(
            itemCount: files.length,
            itemBuilder: (_, i) {
              final f = files[i];
              return ListTile(
                dense: true,
                leading: const Icon(Icons.insert_drive_file, size: 18),
                title: Text(f.path.split(Platform.pathSeparator).last, style: const TextStyle(fontSize: 13)),
                subtitle: Text(_formatSize(f.lengthSync()), style: const TextStyle(fontSize: 11)),
                onTap: () {
                  Navigator.pop(ctx);
                  showMagnetConfirmationDialog(context, torrentFilePath: f.path);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadFromUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid HTTP/HTTPS URL')),
      );
      return;
    }
    setState(() => _downloadingUrl = true);
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }
      final dir = await getTemporaryDirectory();
      final name = url.split('/').last;
      final file = File('${dir.path}/${name.endsWith('.torrent') ? name : '$name.torrent'}');
      await file.writeAsBytes(response.bodyBytes);
      if (!mounted) return;
      Navigator.pop(context);
      showMagnetConfirmationDialog(context, torrentFilePath: file.path);
    } catch (e) {
      if (!mounted) return;
      setState(() => _downloadingUrl = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollController) => Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Add Torrent',
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold, color: cs.onSurface)),
            const SizedBox(height: 24),
            _sectionCard(
              icon: Icons.link_rounded,
              title: 'Magnet Link',
              cs: cs,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _magnetController,
                          decoration: InputDecoration(
                            hintText: 'magnet:?xt=urn:btih:...',
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: cs.outlineVariant)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            isDense: true,
                            filled: true,
                            fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.3),
                          ),
                          maxLines: 2,
                          textInputAction: TextInputAction.done,
                          onSubmitted: _addMagnet,
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(44, 44),
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => _addMagnet(_magnetController.text),
                        child: const Icon(Icons.add, size: 20),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _chipButton(
                        icon: Icons.content_paste_rounded,
                        label: 'Paste',
                        onPressed: () async {
                          final data = await Clipboard.getData(Clipboard.kTextPlain);
                          if (data?.text != null && data!.text!.startsWith('magnet:')) {
                            _magnetController.text = data.text!;
                          } else {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('No magnet link in clipboard')),
                            );
                          }
                        },
                        cs: cs,
                      ),
                      const SizedBox(width: 8),
                      _chipButton(
                        icon: Icons.search_rounded,
                        label: 'Parse Clipboard',
                        onPressed: () async {
                          final data = await Clipboard.getData(Clipboard.kTextPlain);
                          final text = data?.text;
                          if (text != null && text.isNotEmpty) {
                            final url = text.trim();
                            if (url.startsWith('http://') || url.startsWith('https://')) {
                              _urlController.text = url;
                            } else if (url.startsWith('magnet:')) {
                              _magnetController.text = url;
                            } else {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('No URL or magnet found in clipboard')),
                              );
                            }
                          }
                        },
                        cs: cs,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _sectionCard(
              icon: Icons.insert_drive_file_rounded,
              title: 'Torrent File',
              cs: cs,
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.folder_open_rounded, size: 18),
                      label: const Text('Import .torrent'),
                      onPressed: _pickTorrentFile,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        side: BorderSide(color: cs.outlineVariant),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.devices_rounded, size: 18),
                      label: const Text('Browse Files App'),
                      onPressed: _browseFilesApp,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        side: BorderSide(color: cs.outlineVariant),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _sectionCard(
              icon: Icons.cloud_download_rounded,
              title: 'Download from URL',
              cs: cs,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _urlController,
                      decoration: InputDecoration(
                        hintText: 'https://example.com/file.torrent',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: cs.outlineVariant)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        isDense: true,
                        filled: true,
                        fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.3),
                      ),
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _downloadFromUrl(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(44, 44),
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _downloadingUrl ? null : _downloadFromUrl,
                    child: _downloadingUrl
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.download_rounded, size: 20),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _sectionCard(
              icon: Icons.share_rounded,
              title: 'Share Extension',
              cs: cs,
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 20, color: cs.onSurface.withValues(alpha: 0.5)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Share magnet links or .torrent files to this app from other apps. '
                      'They will be automatically detected.',
                      style: TextStyle(fontSize: 13, color: cs.onSurface.withValues(alpha: 0.7)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _sectionCard(
              icon: Icons.drag_indicator_rounded,
              title: 'Drag & Drop',
              cs: cs,
              child: Row(
                children: [
                  Icon(Icons.hourglass_empty_rounded, size: 20, color: cs.onSurface.withValues(alpha: 0.4)),
                  const SizedBox(width: 12),
                  Text(
                    'Coming soon — drag and drop .torrent files directly into this screen.',
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancel', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6))),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard({
    required IconData icon,
    required String title,
    required ColorScheme cs,
    required Widget child,
  }) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      color: cs.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Text(title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface.withValues(alpha: 0.8),
                    )),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _chipButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required ColorScheme cs,
  }) {
    return TextButton.icon(
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
        ),
        backgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.2),
      ),
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 13)),
      onPressed: onPressed,
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1073741824) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    return '${(bytes / 1073741824).toStringAsFixed(1)} GB';
  }
}
