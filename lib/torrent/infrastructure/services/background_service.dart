import 'dart:io';
import 'package:flutter/services.dart';
import '../../domain/entities/torrent_task.dart';

class TorrentBackgroundService {
  static const _channel = MethodChannel('com.dirxplorerakib.pro/torrent_background');

  static TorrentBackgroundService? _instance;
  factory TorrentBackgroundService() => _instance ??= TorrentBackgroundService._();
  TorrentBackgroundService._();

  bool get isAvailable => Platform.isIOS;

  Future<void> update(List<TorrentTask> tasks) async {
    if (!isAvailable) return;
    for (final task in tasks) {
      if (task.status == TorrentStatus.downloading) {
        await _channel.invokeMethod('update', _buildPayload(task));
      }
    }
  }

  Future<void> onAppBackground() async {
    if (!isAvailable) return;
    await _channel.invokeMethod('start');
  }

  Future<void> onAppForeground() async {
    if (!isAvailable) return;
    await _channel.invokeMethod('stop');
  }

  Map<String, dynamic> _buildPayload(TorrentTask task) {
    return {
      'progress': task.progress,
      'downloadSpeed': task.downloadRate,
      'uploadSpeed': task.uploadRate,
      'totalSize': task.sizeFormatted,
      'downloaded': task.downloadedFormatted,
      'state': task.status.name,
      'eta': task.etaFormatted,
      'seeds': task.numSeeds,
      'peers': task.numPeers,
    };
  }
}
