import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:libtorrent_flutter/libtorrent_flutter.dart' as lt;

class TorrentNativeBridge {
  static const _methodChannel = MethodChannel('com.dirxplorerakib.pro/torrent_engine');
  static const _eventChannel = EventChannel('com.dirxplorerakib.pro/torrent_engine_events');

  static TorrentNativeBridge? _instance;
  factory TorrentNativeBridge() => _instance ??= TorrentNativeBridge._();
  TorrentNativeBridge._();

  bool get isAvailable => Platform.isIOS;

  StreamSubscription? _eventSub;
  final StreamController<Map<int, lt.TorrentInfo>> _updateController = StreamController.broadcast();

  Stream<Map<int, lt.TorrentInfo>> get nativeUpdates => _updateController.stream;

  void startBackgroundUpdates() {
    _eventSub = _eventChannel.receiveBroadcastStream().listen((data) {
      if (data is Map) {
        final map = <int, lt.TorrentInfo>{};
        for (final entry in data.entries) {
          final id = int.tryParse('${entry.key}');
          final info = _mapToTorrentInfo(entry.value);
          if (id != null && info != null) {
            map[id] = info;
          }
        }
        _updateController.add(map);
      }
    });
  }

  Future<Map<String, double>> getDeviceStorage() async {
    try {
      final result = await _methodChannel.invokeMethod<Map>('getDeviceStorage');
      return {
        'free': (result?['free'] ?? 0).toDouble(),
        'total': (result?['total'] ?? 0).toDouble(),
      };
    } catch (_) {
      return {'free': 0, 'total': 0};
    }
  }

  Future<void> moveTorrentData(String oldPath, String newPath) async {
    await _methodChannel.invokeMethod('moveTorrentData', {'oldPath': oldPath, 'newPath': newPath});
  }

  Future<void> deleteTorrentCache() async {
    await _methodChannel.invokeMethod('deleteTorrentCache');
  }

  lt.TorrentInfo? _mapToTorrentInfo(dynamic map) {
    if (map is! Map) return null;
    final info = lt.TorrentInfo(
      id: map['id'] ?? 0,
      name: map['name'] ?? '',
      savePath: map['savePath'] ?? '',
      progress: (map['progress'] ?? 0).toDouble(),
      downloadRate: map['downloadRate'] ?? 0,
      uploadRate: map['uploadRate'] ?? 0,
      totalDone: map['totalDone'] ?? 0,
      totalWanted: map['totalWanted'] ?? 0,
      totalUploaded: map['totalUploaded'] ?? 0,
      numPeers: map['numPeers'] ?? 0,
      numSeeds: map['numSeeds'] ?? 0,
      isPaused: map['isPaused'] ?? false,
      isFinished: map['isFinished'] ?? false,
      state: _mapState(map['state']),
      hasMetadata: map['hasMetadata'] ?? false,
      errorMsg: map['errorMsg'] ?? '',
      queuePosition: map['queuePosition'] ?? 0,
    );
    return info;
  }

  lt.TorrentState _mapState(dynamic state) {
    if (state is int) return lt.TorrentState.values[state];
    return lt.TorrentState.unknown;
  }

  void dispose() {
    _eventSub?.cancel();
    _updateController.close();
  }
}
