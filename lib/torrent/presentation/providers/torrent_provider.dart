import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../domain/entities/torrent_task.dart';
import '../../domain/entities/torrent_settings.dart';
import '../../application/torrent_manager.dart';
import '../../infrastructure/services/torrent_search_service.dart';
import '../../infrastructure/services/notification_service.dart';
import '../../infrastructure/services/background_service.dart';
import '../../infrastructure/services/magnet_handler.dart';

class TorrentProvider with ChangeNotifier {
  final TorrentManager _manager;
  final TorrentSearchService _searchService;
  final TorrentNotificationService _notifService;
  final TorrentBackgroundService _bgService;
  final MagnetHandler _magnetHandler;

  final List<TorrentSearchResult> _results = [];
  final Set<String> _enabledProviders = {};
  bool _isSearching = false;
  String _searchQuery = '';
  TorrentCategory _selectedCategory = TorrentCategory.all;
  String _sortBy = 'seeds';
  bool _initialized = false;
  StreamSubscription<List<TorrentTask>>? _taskSub;

  Timer? _debounceTimer;
  int _activeCountCache = 0;
  bool _activeCountDirty = true;

  TorrentProvider({
    required TorrentManager manager,
    required TorrentSearchService searchService,
    required TorrentNotificationService notificationService,
    required TorrentBackgroundService backgroundService,
    required MagnetHandler magnetHandler,
  })  : _manager = manager,
        _searchService = searchService,
        _notifService = notificationService,
        _bgService = backgroundService,
        _magnetHandler = magnetHandler {
    _enabledProviders.addAll(torrentProviders.take(3));
  }

  TorrentManager get manager => _manager;
  TorrentSearchService get searchService => _searchService;
  TorrentNotificationService get notifService => _notifService;
  MagnetHandler get magnetHandler => _magnetHandler;
  TorrentSettings get settings => _manager.settings;
  List<TorrentTask> get tasks => _manager.tasks;
  List<TorrentSearchResult> get results => _results;
  bool get isSearching => _isSearching;
  String get searchQuery => _searchQuery;
  TorrentCategory get selectedCategory => _selectedCategory;
  String get sortBy => _sortBy;
  Set<String> get enabledProviders => _enabledProviders;
  bool get initialized => _initialized;

  int get activeCount {
    if (_activeCountDirty) {
      _activeCountCache = _manager.tasks
          .where((t) => t.status == TorrentStatus.downloading || t.status == TorrentStatus.seeding)
          .length;
      _activeCountDirty = false;
    }
    return _activeCountCache;
  }

  Future<void> init() async {
    if (_initialized) return;
    await _notifService.init();
    try {
      await _manager.init();
      _initialized = true;
      _taskSub = _manager.taskUpdates.listen(_onTasksUpdated);
      _notify();
    } catch (e) {
      debugPrint('TorrentProvider init failed: $e');
    }
  }

  void _onTasksUpdated(List<TorrentTask> tasks) {
    _activeCountDirty = true;
    _notify();
    if (_bgService.isAvailable) {
      _bgService.update(tasks);
    }
  }

  void _notify() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    notifyListeners();
  }

  void _markDirty() {
    _activeCountDirty = true;
    _notify();
  }

  int addMagnet(String magnetUri) => _manager.addMagnet(magnetUri);
  int addTorrentFile(String path) => _manager.addTorrentFile(path);
  void pauseTask(int id) => _manager.pauseTask(id);
  void resumeTask(int id) => _manager.resumeTask(id);
  void removeTask(int id) => _manager.removeTask(id);
  void recheckTask(int id) => _manager.recheckTask(id);
  void stopTask(int id) => _manager.stopTask(id);
  void clearCompleted() => _manager.clearCompleted();
  void setFilePriorities(int id, List<dynamic> priorities) =>
      _manager.setFilePriorities(id, priorities);
  List<dynamic> getFiles(int id) => _manager.getFiles(id);
  String? getMagnetUri(int id) => _manager.getMagnetUri(id);
  void setDownloadLimit(int id, int bytes) => _manager.setDownloadLimit(id, bytes);
  void setUploadLimit(int id, int bytes) => _manager.setUploadLimit(id, bytes);
  Future<TorrentInfoPreview> probeMagnet(String uri) => _manager.probeMagnet(uri);
  Future<TorrentInfoPreview> probeTorrentFile(String path) => _manager.probeTorrentFile(path);
  void confirmMagnet(int engineId) {
    _manager.confirmMagnet(engineId);
    _markDirty();
  }

  void cancelMagnetProbe(int engineId) {
    _manager.cancelMagnetProbe(engineId);
    _notify();
  }

  Future<void> moveStorage(int id, String newPath) => _manager.moveStorage(id, newPath);

  Future<void> applySettings(TorrentSettings s) async {
    await _manager.applySettings(s);
    _notify();
  }

  Future<void> search(String query) async {
    if (query.isEmpty) return;
    _searchQuery = query;
    _isSearching = true;
    _results.clear();
    _notify();

    final buffer = <TorrentSearchResult>[];
    await _searchService.search(
      query: query,
      providers: _enabledProviders.toList(),
      category: _selectedCategory,
      onResult: (result) => buffer.add(result),
    );

    if (buffer.isNotEmpty) {
      _results.addAll(buffer);
      _sortResults();
    }
    _isSearching = false;
    _notify();
  }

  void setCategory(TorrentCategory category) {
    _selectedCategory = category;
    if (_searchQuery.isNotEmpty) {
      search(_searchQuery);
    } else {
      _notify();
    }
  }

  void setSortBy(String sort) {
    _sortBy = sort;
    _sortResults();
    _notify();
  }

  void _sortResults() {
    switch (_sortBy) {
      case 'seeds':
        _results.sort((a, b) => b.seeds.compareTo(a.seeds));
      case 'size':
        _results.sort((a, b) => b.size.compareTo(a.size));
      case 'name':
        _results.sort((a, b) => a.title.compareTo(b.title));
    }
  }

  void toggleProvider(String provider) {
    if (_enabledProviders.contains(provider)) {
      _enabledProviders.remove(provider);
    } else {
      _enabledProviders.add(provider);
    }
    _notify();
  }

  void toggleSelectAllProviders() {
    if (_enabledProviders.length == torrentProviders.length) {
      _enabledProviders.clear();
    } else {
      _enabledProviders.addAll(torrentProviders);
    }
    _notify();
  }

  void clearResults() {
    _results.clear();
    _searchQuery = '';
    _notify();
  }

  void onAppBackground() {
    _bgService.onAppBackground();
  }

  void onAppForeground() {
    _bgService.onAppForeground();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _taskSub?.cancel();
    _manager.dispose();
    super.dispose();
  }
}
