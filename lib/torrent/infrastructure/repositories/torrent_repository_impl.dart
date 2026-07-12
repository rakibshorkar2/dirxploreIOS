import 'dart:async';
import 'dart:io';
import 'package:libtorrent_flutter/libtorrent_flutter.dart' as lt;
import 'package:path_provider/path_provider.dart';
import '../../domain/entities/torrent_task.dart';
import '../../domain/entities/torrent_settings.dart';
import '../../domain/repositories/torrent_repository.dart';

class LiveTorrentRepository implements TorrentRepository {
  final StreamController<List<TorrentTask>> _taskController = StreamController.broadcast();
  StreamSubscription<Map<int, lt.TorrentInfo>>? _engineSub;

  @override
  Stream<List<TorrentTask>> get torrentUpdates => _taskController.stream;

  @override
  Future<void> init(TorrentSettings settings) async {
    final dir = settings.defaultSavePath.isNotEmpty
        ? settings.defaultSavePath
        : (await getApplicationDocumentsDirectory()).path;
    await lt.LibtorrentFlutter.init(defaultSavePath: dir);
    _engineSub = lt.LibtorrentFlutter.instance.torrentUpdates.listen(_onEngineUpdates);
  }

  void dispose() {
    _engineSub?.cancel();
    _taskController.close();
  }

  void _onEngineUpdates(Map<int, lt.TorrentInfo> engineMap) {
    final tasks = engineMap.entries.map((e) => _toDomainTask(e.key, e.value)).toList();
    _taskController.add(tasks);
  }

  TorrentTask _toDomainTask(int id, lt.TorrentInfo info) {
    return TorrentTask(
      id: id,
      name: info.name,
      savePath: info.savePath,
      status: _toStatus(info),
      progress: info.progress,
      downloadRate: info.downloadRate,
      uploadRate: info.uploadRate,
      totalDone: info.totalDone,
      totalWanted: info.totalWanted,
      totalUploaded: info.totalUploaded,
      numPeers: info.numPeers,
      numSeeds: info.numSeeds,
      hasMetadata: info.hasMetadata,
      isPaused: info.isPaused,
      isFinished: info.isFinished,
      errorMsg: info.errorMsg,
    );
  }

  TorrentStatus _toStatus(lt.TorrentInfo info) {
    if (info.isPaused && info.state == lt.TorrentState.downloading) {
      return TorrentStatus.paused;
    }
    switch (info.state) {
      case lt.TorrentState.error: return TorrentStatus.error;
      case lt.TorrentState.downloadingMetadata:
      case lt.TorrentState.downloading: return TorrentStatus.downloading;
      case lt.TorrentState.finished: return TorrentStatus.done;
      case lt.TorrentState.seeding: return TorrentStatus.seeding;
      case lt.TorrentState.checkingFiles:
      case lt.TorrentState.checkingResume: return TorrentStatus.checking;
      case lt.TorrentState.allocating:
      case lt.TorrentState.unknown: return TorrentStatus.idle;
    }
  }

  @override
  int addMagnet(String uri) => lt.LibtorrentFlutter.instance.addMagnet(uri);

  @override
  int addTorrentFile(String path) => lt.LibtorrentFlutter.instance.addTorrentFile(path);

  @override
  void pauseTorrent(int id) => lt.LibtorrentFlutter.instance.pauseTorrent(id);

  @override
  void resumeTorrent(int id) => lt.LibtorrentFlutter.instance.resumeTorrent(id);

  @override
  void removeTorrent(int id, {bool deleteFiles = false}) =>
      lt.LibtorrentFlutter.instance.removeTorrent(id, deleteFiles: deleteFiles);

  @override
  void recheckTorrent(int id) => lt.LibtorrentFlutter.instance.recheckTorrent(id);

  @override
  void stopTorrent(int id) => lt.LibtorrentFlutter.instance.removeTorrent(id);

  @override
  void setDownloadLimit(int id, int limitBytes) =>
      lt.LibtorrentFlutter.instance.setDownloadLimit(limitBytes);

  @override
  void setUploadLimit(int id, int limitBytes) =>
      lt.LibtorrentFlutter.instance.setUploadLimit(limitBytes);

  @override
  void setFilePriorities(int id, List<dynamic> priorities) =>
      lt.LibtorrentFlutter.instance.setFilePriorities(id, priorities.cast<int>());

  @override
  List<dynamic> getFiles(int id) => lt.LibtorrentFlutter.instance.getFiles(id).toList();

  @override
  void configureSession(dynamic config) {
    final btConfig = lt.BtConfig(
      forceEncrypt: config?['enable_encryption'] ?? false,
      disableDht: config?['enable_dht'] != true,
      disableUpload: false,
      downloadRateLimit: config?['download_limit_kb'] ?? 0,
      uploadRateLimit: config?['upload_limit_kb'] ?? 0,
      connectionsLimit: config?['max_peers'] ?? 50,
    );
    lt.LibtorrentFlutter.instance.configureSession(btConfig);
  }

  @override
  void applyLimits(int downKb, int upKb) {
    lt.LibtorrentFlutter.instance.setDownloadLimit(downKb * 1024);
    lt.LibtorrentFlutter.instance.setUploadLimit(upKb * 1024);
  }

  @override
  Future<TorrentInfoPreview> probeMagnet(String uri) async {
    final engine = lt.LibtorrentFlutter.instance;
    final engineId = engine.addMagnet(uri);
    engine.pauseTorrent(engineId);
    final completer = Completer<TorrentInfoPreview>();
    late StreamSubscription sub;
    sub = engine.torrentUpdates.listen((map) {
      final info = map[engineId];
      if (info == null) return;
      if (info.hasMetadata) {
        sub.cancel();
        final files = engine.getFiles(engineId);
        completer.complete(TorrentInfoPreview(
          engineId: engineId,
          name: info.name,
          size: info.totalWanted,
          fileCount: files.length,
          trackerCount: _parseTrackerCount(uri),
          magnetUri: uri,
        ));
      }
    });
    return completer.future.timeout(const Duration(seconds: 30));
  }

  @override
  Future<TorrentInfoPreview> probeTorrentFile(String path) async {
    final engine = lt.LibtorrentFlutter.instance;
    final engineId = engine.addTorrentFile(path);
    engine.pauseTorrent(engineId);
    final completer = Completer<TorrentInfoPreview>();
    late StreamSubscription sub;
    sub = engine.torrentUpdates.listen((map) {
      final info = map[engineId];
      if (info == null) return;
      if (info.hasMetadata) {
        sub.cancel();
        final files = engine.getFiles(engineId);
        completer.complete(TorrentInfoPreview(
          engineId: engineId,
          name: info.name,
          size: info.totalWanted,
          fileCount: files.length,
          trackerCount: 0,
          magnetUri: '',
        ));
      }
    });
    return completer.future.timeout(const Duration(seconds: 30));
  }

  @override
  void confirmMagnet(int engineId) => lt.LibtorrentFlutter.instance.resumeTorrent(engineId);

  @override
  void cancelMagnetProbe(int engineId) => lt.LibtorrentFlutter.instance.removeTorrent(engineId);

  @override
  String? getMagnetUri(int id) {
    return null;
  }

  @override
  void clearCompleted() {
    for (final entry in lt.LibtorrentFlutter.instance.torrents.entries) {
      if (entry.value.isFinished) {
        lt.LibtorrentFlutter.instance.removeTorrent(entry.key);
      }
    }
  }

  @override
  Future<void> moveStorage(int id, String newPath) async {
    final engine = lt.LibtorrentFlutter.instance;
    final info = engine.torrents[id];
    if (info == null) return;
    final oldPath = info.savePath;
    engine.pauseTorrent(id);
    await Future.delayed(const Duration(milliseconds: 500));
    final newDir = Directory(newPath);
    if (!await newDir.exists()) await newDir.create(recursive: true);
    final oldDir = Directory(oldPath);
    if (await oldDir.exists()) {
      try {
        await oldDir.rename(newPath);
      } catch (_) {
        await oldDir.list(recursive: true).forEach((entity) async {
          if (entity is File) {
            final relPath = entity.path.substring(oldPath.length + 1);
            final dest = File('$newPath/$relPath');
            await dest.parent.create(recursive: true);
            await entity.copy(dest.path);
            await entity.delete();
          }
        });
        await oldDir.delete();
      }
    }
  }

  int _parseTrackerCount(String uri) {
    final magnet = Uri.tryParse(uri);
    if (magnet == null) return 0;
    return magnet.queryParametersAll['tr']?.length ?? 0;
  }
}
