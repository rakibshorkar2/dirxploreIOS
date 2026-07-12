import 'dart:async';
import '../domain/entities/torrent_task.dart';
import '../domain/entities/torrent_settings.dart';
import '../domain/repositories/torrent_repository.dart';
import '../domain/repositories/settings_repository.dart';

class TorrentManager {
  final TorrentRepository _repository;
  final SettingsRepository _settingsRepository;

  TorrentSettings _settings = const TorrentSettings();
  StreamSubscription<List<TorrentTask>>? _updateSub;
  final StreamController<List<TorrentTask>> _taskController = StreamController.broadcast();

  TorrentManager({
    required TorrentRepository repository,
    required SettingsRepository settingsRepository,
  })  : _repository = repository,
        _settingsRepository = settingsRepository;

  TorrentSettings get settings => _settings;
  List<TorrentTask> get tasks => _currentTasks;
  List<TorrentTask> _currentTasks = [];
  Stream<List<TorrentTask>> get taskUpdates => _taskController.stream;

  Future<void> init() async {
    _settings = await _settingsRepository.load();
    await _repository.init(_settings);
    _updateSub = _repository.torrentUpdates.listen(_onUpdates);
    _applySettingsToEngine();
  }

  void dispose() {
    _updateSub?.cancel();
    _taskController.close();
  }

  void _onUpdates(List<TorrentTask> updatedTasks) {
    _currentTasks = updatedTasks;
    _taskController.add(List.unmodifiable(_currentTasks));
  }

  int addMagnet(String uri) => _repository.addMagnet(uri);
  int addTorrentFile(String path) => _repository.addTorrentFile(path);
  void pauseTask(int id) => _repository.pauseTorrent(id);
  void resumeTask(int id) => _repository.resumeTorrent(id);
  void removeTask(int id) => _repository.removeTorrent(id);
  void recheckTask(int id) => _repository.recheckTorrent(id);
  void stopTask(int id) => _repository.stopTorrent(id);
  void clearCompleted() => _repository.clearCompleted();
  void setFilePriorities(int id, List<dynamic> priorities) =>
      _repository.setFilePriorities(id, priorities);
  List<dynamic> getFiles(int id) => _repository.getFiles(id);
  String? getMagnetUri(int id) => _repository.getMagnetUri(id);
  void setDownloadLimit(int id, int bytes) => _repository.setDownloadLimit(id, bytes);
  void setUploadLimit(int id, int bytes) => _repository.setUploadLimit(id, bytes);

  Future<TorrentInfoPreview> probeMagnet(String uri) => _repository.probeMagnet(uri);
  Future<TorrentInfoPreview> probeTorrentFile(String path) => _repository.probeTorrentFile(path);
  void confirmMagnet(int engineId) => _repository.confirmMagnet(engineId);
  void cancelMagnetProbe(int engineId) => _repository.cancelMagnetProbe(engineId);

  Future<void> moveStorage(int id, String newPath) => _repository.moveStorage(id, newPath);

  Future<void> applySettings(TorrentSettings newSettings) async {
    _settings = newSettings;
    await _settingsRepository.save(newSettings);
    _applySettingsToEngine();
  }

  void _applySettingsToEngine() {
    final config = {
      'enable_encryption': _settings.enableEncryption,
      'enable_dht': _settings.enableDht,
      'enable_pex': _settings.enablePex,
      'enable_lsd': _settings.enableLsd,
      'max_peers': _settings.maxPeersPerTorrent,
      'max_connections': _settings.maxConnections,
      'download_limit_kb': _settings.downloadLimitKb,
      'upload_limit_kb': _settings.uploadLimitKb,
    };
    _repository.configureSession(config);
    _repository.applyLimits(_settings.downloadLimitKb, _settings.uploadLimitKb);
  }
}
