import 'dart:math';
import 'dart:io';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:dio/dio.dart';
import '../providers/download_provider.dart';
import '../providers/app_state.dart';
import '../services/dio_client.dart';
import '../services/haptic_service.dart';

class NewDownloadSheet extends StatefulWidget {
  final bool autoPaste;
  const NewDownloadSheet({super.key, this.autoPaste = false});

  @override
  State<NewDownloadSheet> createState() => _NewDownloadSheetState();
}

class _NewDownloadSheetState extends State<NewDownloadSheet> {
  final _urlController = TextEditingController();
  final _filenameController = TextEditingController();
  final _batchController = TextEditingController();
  final _customHeadersController = TextEditingController();
  bool _isLoading = false;
  String? _error;
  bool _metadataFailed = false;

  bool _infoFetched = false;
  int _fileSize = -1;
  String _fileType = '';
  bool? _resumeSupported;
  String _detectedFileName = '';
  String _resolvedUrl = '';
  String _originalUrl = '';
  int _redirectCount = 0;
  String _host = '';

  bool _isBatchMode = false;
  bool _showAdvanced = false;

  // Download options
  bool _downloadImmediately = true;
  bool _createSubfolder = false;
  bool _autoExtract = false;
  bool _overwriteExisting = false;

  final Map<String, String> _customHeaders = {};

  @override
  void initState() {
    super.initState();
    if (widget.autoPaste) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _pasteFromClipboard());
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _filenameController.dispose();
    _batchController.dispose();
    _customHeadersController.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      if (_isBatchMode) {
        _batchController.text = data.text!.trim();
      } else {
        _urlController.text = data.text!.trim();
      }
      if (_infoFetched) {
        setState(() {
          _infoFetched = false;
          _error = null;
        });
      }
      HapticService.light();
      _fetchInfo();
    }
  }

  void _clearUrl() {
    setState(() {
      _urlController.clear();
      _infoFetched = false;
      _error = null;
      _metadataFailed = false;
      _fileSize = -1;
      _fileType = '';
      _resumeSupported = null;
      _detectedFileName = '';
      _resolvedUrl = '';
      _host = '';
      _filenameController.clear();
    });
  }

  String? _validateUrl(String url) {
    if (url.isEmpty) return 'Please enter a URL';
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      return 'Invalid URL format';
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return 'Only HTTP and HTTPS URLs are supported';
    }
    return null;
  }

  String _fileNameFromUrl(String url) {
    final uri = Uri.parse(url);
    final path = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (path.isNotEmpty) return path.last;
    return 'download';
  }

  String _fileNameFromContentDisposition(String? disposition) {
    if (disposition == null) return '';
    final match = RegExp(
      r"filename\*?=(?:UTF-8''\s*)?([^;\s]+)",
    ).firstMatch(disposition);
    if (match != null) {
      return Uri.decodeComponent(
        match.group(1)!.trim().replaceAll(RegExp(r'^"|"$'), ''),
      );
    }
    return '';
  }

  String _formatFileSizeCompact(int bytes) {
    if (bytes <= 0) return 'Unknown';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = (log(bytes) / log(1024)).floor();
    var val = bytes / pow(1024, i);
    if (val >= 100) return '${val.toStringAsFixed(0)}${suffixes[i]}';
    return '${val.toStringAsFixed(1)}${suffixes[i]}';
  }

  String get _linkAnalysisSummary {
    final parts = <String>[];
    if (_fileType.isNotEmpty) {
      final mime = _fileType.split('/').last;
      parts.add(mime.toUpperCase());
    }
    if (_fileSize > 0) {
      parts.add(_formatFileSizeCompact(_fileSize));
    }
    if (_resumeSupported == true) {
      parts.add('Resume Supported');
    } else if (_resumeSupported == false) {
      parts.add('No Resume');
    }
    if (parts.isEmpty) return 'Metadata unavailable';
    return parts.join(' \u2022 ');
  }

  Future<bool> _tryHeadRequest(String url) async {
    try {
      final dio = DioClient().dio;
      final headers = <String, dynamic>{};
      if (_customHeaders.isNotEmpty) headers.addAll(_customHeaders);
      final response = await dio.head(url, options: Options(headers: headers.isNotEmpty ? headers : null));
      _parseHeaders(response.headers);
      return true;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.badResponse &&
          e.response?.statusCode == 405) {
        return false;
      }
      rethrow;
    }
  }

  Future<void> _tryGetFallback(String url) async {
    final dio = DioClient().dio;
    final headers = <String, dynamic>{'Range': 'bytes=0-0'};
    if (_customHeaders.isNotEmpty) headers.addAll(_customHeaders);
    final response = await dio.get(
      url,
      options: Options(
        responseType: ResponseType.stream,
        followRedirects: true,
        headers: headers,
      ),
    );
    _parseHeaders(response.headers);
    if (_fileSize <= 0) {
      final contentRange = response.headers.value(HttpHeaders.contentRangeHeader);
      if (contentRange != null) {
        final match = RegExp(r'/(\d+)$').firstMatch(contentRange);
        if (match != null) {
          _fileSize = int.tryParse(match.group(1)!) ?? -1;
        }
      }
    }
  }

  void _parseHeaders(Headers headers) {
    final contentLength = headers.value(HttpHeaders.contentLengthHeader);
    final contentType = headers.value(HttpHeaders.contentTypeHeader);
    final contentDisposition = headers.value('content-disposition');
    final acceptRanges = headers.value(HttpHeaders.acceptRangesHeader);

    _fileSize = int.tryParse(contentLength ?? '') ?? -1;

    if (contentType != null) {
      _fileType = contentType.split(';').first;
    }

    final ranges = acceptRanges?.toLowerCase();
    if (ranges == 'bytes') {
      _resumeSupported = true;
    } else if (ranges != null && ranges.isNotEmpty) {
      _resumeSupported = false;
    } else {
      _resumeSupported = null;
    }

    if (_detectedFileName.isEmpty) {
      final cd = _fileNameFromContentDisposition(contentDisposition);
      if (cd.isNotEmpty) {
        _detectedFileName = cd;
      }
    }
  }

  Future<void> _fetchInfo() async {
    final url = _urlController.text.trim();
    final validationError = _validateUrl(url);
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _infoFetched = false;
      _metadataFailed = false;
      _fileSize = -1;
      _fileType = '';
      _resumeSupported = null;
    });

    try {
      HapticService.medium();

      _originalUrl = url;
      _host = Uri.parse(url).host;
      _redirectCount = 0;

      String resolvedUrl;
      try {
        resolvedUrl = await DioClient().resolveRedirects(url);
        _redirectCount = 1;
      } catch (_) {
        resolvedUrl = url;
      }
      _resolvedUrl = resolvedUrl;

      try {
        final headOk = await _tryHeadRequest(resolvedUrl);
        if (!headOk) {
          await _tryGetFallback(resolvedUrl);
        }
      } catch (_) {}

      if (_detectedFileName.isEmpty) {
        _detectedFileName = _fileNameFromUrl(resolvedUrl);
      }
      if (_detectedFileName.isEmpty) {
        _detectedFileName = _fileNameFromUrl(url);
      }

      if (_filenameController.text.trim().isEmpty && _detectedFileName.isNotEmpty) {
        _filenameController.text = _detectedFileName;
      }

      if (!mounted) return;
      setState(() {
        _infoFetched = true;
        _isLoading = false;
      });
    } catch (e) {
      if (_detectedFileName.isEmpty) {
        _detectedFileName = _fileNameFromUrl(url);
      }
      if (_filenameController.text.trim().isEmpty && _detectedFileName.isNotEmpty) {
        _filenameController.text = _detectedFileName;
      }
      if (!mounted) return;
      setState(() {
        _infoFetched = true;
        _metadataFailed = true;
        _isLoading = false;
        _error = 'Metadata could not be retrieved. Download anyway?';
      });
    }
  }

  String? _currentFileTypeIcon() {
    if (_fileType.isEmpty) return null;
    final mime = _fileType.toLowerCase();
    if (mime.startsWith('video/')) return 'video';
    if (mime.startsWith('audio/')) return 'audio';
    if (mime.startsWith('image/')) return 'image';
    if (mime.startsWith('text/') || mime.contains('pdf')) return 'document';
    if (mime.contains('zip') || mime.contains('rar') || mime.contains('tar') || mime.contains('7z')) return 'archive';
    return 'file';
  }

  IconData _previewIcon() {
    final type = _currentFileTypeIcon();
    switch (type) {
      case 'video': return CupertinoIcons.play_circle;
      case 'audio': return CupertinoIcons.music_note;
      case 'image': return CupertinoIcons.photo;
      case 'document': return CupertinoIcons.doc_text;
      case 'archive': return CupertinoIcons.archivebox;
      default: return CupertinoIcons.doc;
    }
  }

  Future<void> _startDownload() async {
    final url = _resolvedUrl.isNotEmpty ? _resolvedUrl : _urlController.text.trim();
    final fileName = _filenameController.text.trim();
    final originalUrl = _originalUrl.isNotEmpty ? _originalUrl : url;

    if (!mounted) return;
    final appState = context.read<AppState>();
    final dlProvider = context.read<DownloadProvider>();
    await dlProvider.addDownload(url, fileName, appState.defaultSavePath,
        originalUrl: originalUrl,
        customHeaders: _customHeaders.isNotEmpty ? _customHeaders : null,
        redirectCount: _redirectCount,
        resolvedUrl: _resolvedUrl.isNotEmpty ? _resolvedUrl : null);
    if (mounted) {
      Navigator.pop(context);
      HapticService.success();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added: $fileName')),
      );
    }
  }

  Future<void> _startBatchDownload() async {
    final text = _batchController.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Please enter at least one URL');
      return;
    }

    if (!mounted) return;
    final appState = context.read<AppState>();
    final dlProvider = context.read<DownloadProvider>();
    final result = await dlProvider.batchAddDownloads(text, appState.defaultSavePath);

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added ${result['valid']} download(s)${result['invalid']! > 0 ? ', ${result['invalid']} invalid URL(s) skipped' : ''}'),
        ),
      );
    }
  }

  void _addCustomHeader() {
    final text = _customHeadersController.text.trim();
    if (text.isEmpty) return;
    final eq = text.indexOf(':');
    if (eq <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Use format: Header: Value')),
      );
      return;
    }
    final key = text.substring(0, eq).trim();
    final value = text.substring(eq + 1).trim();
    if (key.isEmpty || value.isEmpty) return;
    setState(() {
      _customHeaders[key] = value;
      _customHeadersController.clear();
    });
  }

  void _removeCustomHeader(String key) {
    setState(() => _customHeaders.remove(key));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        snap: true,
        snapSizes: const [0.4, 0.7, 0.85, 0.95],
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
                    _buildDragHandle(cs),
                    _buildTitleRow(cs),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: scrollController,
                        physics: const ClampingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (!_isBatchMode) ...[
                              _buildUrlField(cs, isDark),
                              const SizedBox(height: 8),
                              _buildUrlActions(cs, isDark),
                              if (_infoFetched && !_metadataFailed) ...[
                                const SizedBox(height: 12),
                                _buildPreviewCard(cs, isDark),
                              ],
                              if (_infoFetched && _detectedFileName.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                _buildFilenameField(cs, isDark),
                              ],
                              if (_metadataFailed) ...[
                                const SizedBox(height: 12),
                                _buildMetadataFailedWarning(cs),
                              ],
                              if (_infoFetched) ...[
                                const SizedBox(height: 12),
                                _buildDownloadOptions(cs, isDark),
                                const SizedBox(height: 8),
                                _buildDestinationSection(cs, isDark),
                              ],
                              const SizedBox(height: 8),
                              _buildAdvancedToggle(cs, isDark),
                              if (_showAdvanced) ...[
                                const SizedBox(height: 8),
                                _buildAdvancedSection(cs, isDark),
                              ],
                            ] else ...[
                              _buildBatchField(cs, isDark),
                              const SizedBox(height: 8),
                              _buildBatchActions(cs, isDark),
                            ],
                            const SizedBox(height: 120),
                          ],
                        ),
                      ),
                    ),
                    _buildBottomActions(cs, isDark),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDragHandle(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Center(
        child: Container(
          width: 40, height: 4,
          decoration: BoxDecoration(
            color: cs.onSurface.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  Widget _buildTitleRow(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(CupertinoIcons.arrow_down_circle, size: 18, color: cs.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text('New Download',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: cs.onSurface, letterSpacing: -0.3),
            ),
          ),
          ToggleButtons(
            isSelected: [!_isBatchMode, _isBatchMode],
            onPressed: (i) {
              setState(() {
                _isBatchMode = i == 1;
                _infoFetched = false;
                _error = null;
              });
            },
            borderRadius: BorderRadius.circular(10),
            constraints: const BoxConstraints(minWidth: 56, minHeight: 28),
            textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
            children: const [
              Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('Single')),
              Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('Batch')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUrlField(ColorScheme cs, bool isDark) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: (isDark ? Colors.white : Colors.black).withValues(alpha: isDark ? 0.06 : 0.03),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _error != null
                ? CupertinoColors.destructiveRed.withValues(alpha: 0.3)
                : (isDark ? Colors.white : Colors.black).withValues(alpha: isDark ? 0.08 : 0.05),
              width: 0.5,
            ),
          ),
          child: CupertinoTextField(
            controller: _urlController,
            placeholder: 'https://example.com/file.zip',
            placeholderStyle: TextStyle(color: cs.onSurface.withValues(alpha: 0.3), fontSize: 16),
            style: TextStyle(color: cs.onSurface, fontSize: 16),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            prefix: Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(CupertinoIcons.link, size: 18, color: cs.primary.withValues(alpha: 0.6)),
            ),
            suffix: _urlController.text.isNotEmpty
              ? CupertinoButton(
                  padding: EdgeInsets.zero,
                  child: Icon(CupertinoIcons.xmark_circle_fill, size: 18, color: cs.onSurface.withValues(alpha: 0.3)),
                  onPressed: _clearUrl,
                )
              : null,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.go,
            autocorrect: false,
            clearButtonMode: OverlayVisibilityMode.never,
            onChanged: (_) {
              if (_infoFetched) setState(() { _infoFetched = false; _error = null; _metadataFailed = false; });
            },
            onSubmitted: (_) => _fetchInfo(),
          ),
        ),
      ),
    );
  }

  Widget _buildUrlActions(ColorScheme cs, bool isDark) {
    return Row(
      children: [
        _glassButton(cs, isDark, CupertinoIcons.doc_on_clipboard, 'Paste', _pasteFromClipboard),
        const SizedBox(width: 6),
        _glassButton(cs, isDark, CupertinoIcons.eye, 'Detect', () {
          if (_urlController.text.trim().isNotEmpty) _fetchInfo();
        }),
        const Spacer(),
        if (_infoFetched)
          Text(_linkAnalysisSummary,
            style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.5)),
          ),
      ],
    );
  }

  Widget _glassButton(ColorScheme cs, bool isDark, IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: (isDark ? Colors.white : Colors.black).withValues(alpha: isDark ? 0.06 : 0.03),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: (isDark ? Colors.white : Colors.black).withValues(alpha: isDark ? 0.06 : 0.04),
                width: 0.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: cs.primary),
                const SizedBox(width: 4),
                Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: cs.onSurface)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewCard(ColorScheme cs, bool isDark) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          decoration: BoxDecoration(
            color: (isDark ? Colors.white : Colors.black).withValues(alpha: isDark ? 0.06 : 0.03),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: cs.primary.withValues(alpha: 0.15),
              width: 0.5,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: isDark ? 0.12 : 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Icon(_previewIcon(), size: 24, color: cs.primary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _detectedFileName.isNotEmpty ? _detectedFileName : 'Fetching metadata...',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: cs.onSurface),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _host.isNotEmpty ? _host : 'Unknown source',
                        style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.5)),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (_fileType.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: cs.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _fileType.split('/').last.toUpperCase(),
                                style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: cs.primary),
                              ),
                            ),
                          const SizedBox(width: 6),
                          if (_fileSize > 0)
                            Text(
                              _formatFileSizeCompact(_fileSize),
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: cs.onSurface.withValues(alpha: 0.6)),
                            ),
                          const Spacer(),
                          if (_resumeSupported == true)
                            Icon(CupertinoIcons.checkmark_seal_fill, size: 14, color: CupertinoColors.activeGreen),
                        ],
                      ),
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

  Widget _buildFilenameField(ColorScheme cs, bool isDark) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          decoration: BoxDecoration(
            color: (isDark ? Colors.white : Colors.black).withValues(alpha: isDark ? 0.04 : 0.02),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: (isDark ? Colors.white : Colors.black).withValues(alpha: isDark ? 0.06 : 0.04),
              width: 0.5,
            ),
          ),
          child: CupertinoTextField(
            controller: _filenameController,
            placeholder: 'Filename (auto-detected)',
            placeholderStyle: TextStyle(color: cs.onSurface.withValues(alpha: 0.3), fontSize: 14),
            style: TextStyle(color: cs.onSurface, fontSize: 14),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            prefix: Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Icon(CupertinoIcons.doc, size: 16, color: cs.onSurface.withValues(alpha: 0.4)),
            ),
            textInputAction: TextInputAction.done,
            onChanged: (_) {
              if (_infoFetched) setState(() => _infoFetched = false);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildDownloadOptions(ColorScheme cs, bool isDark) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            color: (isDark ? Colors.white : Colors.black).withValues(alpha: isDark ? 0.05 : 0.02),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: (isDark ? Colors.white : Colors.black).withValues(alpha: isDark ? 0.06 : 0.04),
              width: 0.5,
            ),
          ),
          child: Column(
            children: [
              _optionTile(cs, CupertinoIcons.arrow_down_circle, 'Download Immediately', null, _downloadImmediately, (v) {
                setState(() => _downloadImmediately = v);
              }),
              _optionDivider(cs),
              _optionTile(cs, CupertinoIcons.clock, 'Queue Instead', 'Add to queue without starting', !_downloadImmediately, (v) {
                setState(() => _downloadImmediately = !v);
              }),
              _optionDivider(cs),
              _optionTile(cs, Icons.create_new_folder, 'Create Subfolder', 'Organize in a subdirectory', _createSubfolder, (v) {
                setState(() => _createSubfolder = v);
              }),
              _optionDivider(cs),
              _optionTile(cs, CupertinoIcons.archivebox, 'Auto Extract', 'Extract archives after download', _autoExtract, (v) {
                setState(() => _autoExtract = v);
              }),
              _optionDivider(cs),
              _optionTile(cs, CupertinoIcons.doc_on_doc, 'Overwrite Existing', 'Replace if file exists', _overwriteExisting, (v) {
                setState(() => _overwriteExisting = v);
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _optionTile(ColorScheme cs, IconData icon, String title, String? subtitle, bool value, ValueChanged<bool> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: cs.onSurface)),
                if (subtitle != null)
                  Text(subtitle, style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.5))),
              ],
            ),
          ),
          CupertinoSwitch(
            value: value,
            activeTrackColor: CupertinoColors.activeGreen,
            onChanged: (v) {
              HapticService.light();
              onChanged(v);
            },
          ),
        ],
      ),
    );
  }

  Widget _optionDivider(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(left: 52),
      child: Divider(height: 0.5, thickness: 0.5, color: cs.onSurface.withValues(alpha: 0.06)),
    );
  }

  Widget _buildDestinationSection(ColorScheme cs, bool isDark) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            color: (isDark ? Colors.white : Colors.black).withValues(alpha: isDark ? 0.05 : 0.02),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: (isDark ? Colors.white : Colors.black).withValues(alpha: isDark ? 0.06 : 0.04),
              width: 0.5,
            ),
          ),
          child: Consumer<AppState>(
            builder: (context, appState, _) {
              final savePath = appState.defaultSavePath;
              final freeBytes = context.watch<DownloadProvider>().freeStorage;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Icon(CupertinoIcons.folder, size: 14, color: cs.primary),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Save to',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: cs.onSurface.withValues(alpha: 0.5)),
                          ),
                          const SizedBox(height: 2),
                          Text(savePath.split('/').last,
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: cs.onSurface),
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (freeBytes > 0)
                          Text('${_formatFileSizeCompact(freeBytes ~/ 1)} free',
                            style: TextStyle(fontSize: 10, color: CupertinoColors.activeGreen),
                          ),
                        if (_fileSize > 0)
                          Text('Needs: ${_formatFileSizeCompact(_fileSize)}',
                            style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.5)),
                          ),
                      ],
                    ),
                    const SizedBox(width: 8),
                    Icon(CupertinoIcons.chevron_right, size: 14, color: cs.onSurface.withValues(alpha: 0.2)),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildAdvancedToggle(ColorScheme cs, bool isDark) {
    return GestureDetector(
      onTap: () {
        HapticService.light();
        setState(() => _showAdvanced = !_showAdvanced);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(CupertinoIcons.slider_horizontal_3, size: 14, color: cs.onSurface.withValues(alpha: 0.4)),
            const SizedBox(width: 6),
            Text(
              _showAdvanced ? 'Hide Advanced' : 'Advanced Options',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: cs.onSurface.withValues(alpha: 0.5)),
            ),
            const Spacer(),
            AnimatedRotation(
              turns: _showAdvanced ? 0.5 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Icon(CupertinoIcons.chevron_down, size: 14, color: cs.onSurface.withValues(alpha: 0.4)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdvancedSection(ColorScheme cs, bool isDark) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            decoration: BoxDecoration(
              color: (isDark ? Colors.white : Colors.black).withValues(alpha: isDark ? 0.05 : 0.02),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: cs.primary.withValues(alpha: 0.1),
                width: 0.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                  child: Text('Custom Headers',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface.withValues(alpha: 0.5)),
                  ),
                ),
                if (_customHeaders.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Wrap(
                      spacing: 6, runSpacing: 4,
                      children: _customHeaders.entries.map((e) => Chip(
                        label: Text('${e.key}: ${e.value}', style: const TextStyle(fontSize: 10)),
                        deleteIcon: const Icon(Icons.close, size: 14),
                        onDeleted: () => _removeCustomHeader(e.key),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      )).toList(),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 36,
                          child: CupertinoTextField(
                            controller: _customHeadersController,
                            placeholder: 'Header: Value',
                            placeholderStyle: TextStyle(color: cs.onSurface.withValues(alpha: 0.3), fontSize: 12),
                            style: TextStyle(color: cs.onSurface, fontSize: 12),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _addCustomHeader(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        child: Icon(CupertinoIcons.plus_circle_fill, size: 22, color: cs.primary),
                        onPressed: _addCustomHeader,
                      ),
                    ],
                  ),
                ),
                Divider(height: 0.5, thickness: 0.5, color: cs.onSurface.withValues(alpha: 0.06)),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(CupertinoIcons.info_circle, size: 13, color: cs.onSurface.withValues(alpha: 0.4)),
                      const SizedBox(width: 6),
                      Text('Custom headers, authentication, and advanced settings',
                        style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.4)),
                      ),
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

  Widget _buildBatchField(ColorScheme cs, bool isDark) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: (isDark ? Colors.white : Colors.black).withValues(alpha: isDark ? 0.06 : 0.03),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _error != null
                ? CupertinoColors.destructiveRed.withValues(alpha: 0.3)
                : (isDark ? Colors.white : Colors.black).withValues(alpha: isDark ? 0.08 : 0.05),
              width: 0.5,
            ),
          ),
          child: CupertinoTextField(
            controller: _batchController,
            placeholder: 'Paste URLs (one per line)',
            placeholderStyle: TextStyle(color: cs.onSurface.withValues(alpha: 0.3), fontSize: 14),
            style: TextStyle(color: cs.onSurface, fontSize: 14),
            padding: const EdgeInsets.all(14),
            maxLines: 6,
            keyboardType: TextInputType.multiline,
          ),
        ),
      ),
    );
  }

  Widget _buildBatchActions(ColorScheme cs, bool isDark) {
    return Row(
      children: [
        _glassButton(cs, isDark, CupertinoIcons.doc_on_clipboard, 'Paste from Clipboard', _pasteFromClipboard),
        const SizedBox(width: 8),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text(_error!, style: TextStyle(fontSize: 11, color: cs.error)),
          ),
      ],
    );
  }

  Widget _buildMetadataFailedWarning(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.error.withValues(alpha: 0.2), width: 0.5),
      ),
      child: Row(
        children: [
          Icon(CupertinoIcons.exclamationmark_triangle, size: 16, color: cs.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Metadata could not be retrieved. Download anyway?',
              style: TextStyle(color: cs.error, fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomActions(ColorScheme cs, bool isDark) {
    final bool canStart = (_infoFetched || _metadataFailed) && !_isLoading;
    final bool urlNotEmpty = _urlController.text.trim().isNotEmpty;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).padding.bottom > 0 ? MediaQuery.of(context).padding.bottom : 16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: cs.onSurface.withValues(alpha: 0.08)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: (isDark ? Colors.white : Colors.black).withValues(alpha: isDark ? 0.06 : 0.03),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: (isDark ? Colors.white : Colors.black).withValues(alpha: isDark ? 0.06 : 0.04),
                      width: 0.5,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text('Cancel',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: cs.onSurface.withValues(alpha: 0.7)),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              child: _isLoading
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [cs.primary, cs.primary.withValues(alpha: 0.8)],
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.center,
                      child: const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                    ),
                  )
                : _isBatchMode
                    ? _primaryButton(cs, Icons.download_rounded, 'Add All', _startBatchDownload)
                    : canStart
                        ? _primaryButton(cs, CupertinoIcons.arrow_down_circle, 'Start Download', _startDownload)
                        : _primaryButton(cs, CupertinoIcons.search, urlNotEmpty ? 'Fetch Info' : 'Enter URL', urlNotEmpty ? _fetchInfo : null),
            ),
          ),
        ],
      ),
    );
  }

  Widget _primaryButton(ColorScheme cs, IconData icon, String label, VoidCallback? onPressed) {
    return GestureDetector(
      onTap: onPressed,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: onPressed != null
                ? [cs.primary, cs.primary.withValues(alpha: 0.8)]
                : [cs.onSurface.withValues(alpha: 0.1), cs.onSurface.withValues(alpha: 0.05)],
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (onPressed != null)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(icon, size: 18, color: Colors.white),
                ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: onPressed != null ? Colors.white : cs.onSurface.withValues(alpha: 0.3),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
