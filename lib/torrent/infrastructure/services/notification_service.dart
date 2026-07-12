import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../../domain/entities/torrent_task.dart';

class TorrentNotificationService {
  FlutterLocalNotificationsPlugin? _plugin;
  bool _initialized = false;
  int _nextId = 1000;

  final Set<int> _notifiedCompleted = {};
  final Set<int> _notifiedError = {};
  final Set<int> _notifiedMetadata = {};

  Future<void> init() async {
    if (_initialized) return;
    _plugin = FlutterLocalNotificationsPlugin();
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _plugin!.initialize(
      settings,
      onDidReceiveNotificationResponse: (_) {},
    );
    final android = _plugin!.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      await android.createNotificationChannel(
        const AndroidNotificationChannel(
          'torrent_events',
          'Torrent Events',
          description: 'Notifications for torrent download events',
          importance: Importance.defaultImportance,
        ),
      );
    }
    _initialized = true;
  }

  void clearNotified(int torrentId) {
    _notifiedCompleted.remove(torrentId);
    _notifiedError.remove(torrentId);
    _notifiedMetadata.remove(torrentId);
  }

  void checkAndNotify({
    required TorrentTask current,
    required TorrentTask? previous,
    required bool notifyComplete,
    required bool notifyError,
    required bool notifyMetadata,
  }) {
    if (!_initialized || _plugin == null) return;

    if (notifyMetadata &&
        !_notifiedMetadata.contains(current.id) &&
        current.hasMetadata &&
        (previous == null || !previous.hasMetadata)) {
      _notifiedMetadata.add(current.id);
      _show(
        id: _nextId++,
        title: 'Metadata Fetched',
        body: current.name,
      );
    }

    if (notifyComplete &&
        !_notifiedCompleted.contains(current.id) &&
        current.isFinished &&
        (previous == null || !previous.isFinished)) {
      _notifiedCompleted.add(current.id);
      _show(
        id: _nextId++,
        title: 'Download Complete',
        body: current.name,
      );
    }

    if (notifyError &&
        !_notifiedError.contains(current.id) &&
        current.status == TorrentStatus.error &&
        (previous == null || previous.status != TorrentStatus.error)) {
      _notifiedError.add(current.id);
      _show(
        id: _nextId++,
        title: 'Torrent Error',
        body: '${current.name}\n${current.errorMsg}',
      );
    }
  }

  void _show({required int id, required String title, required String body}) {
    _plugin?.show(
      id,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'torrent_events',
          'Torrent Events',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: false,
          presentSound: true,
        ),
      ),
    );
  }
}
