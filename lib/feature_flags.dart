/// Temporary feature flags for incremental startup testing.
/// Set all to `true` for production; toggle off to isolate faulty modules.
class FeatureFlags {
  FeatureFlags._();

  /// Core torrent engine (libtorrent init, magnet handler, TorrentProvider)
  static const bool torrent = false;

  /// iOS Live Activities (Dynamic Island / Lock Screen widgets)
  static const bool liveActivities = false;

  /// Flutter background tasks (workmanager periodic task)
  static const bool backgroundTasks = false;

  /// Proxy tab + ProxyTunnel HTTP server
  static const bool proxy = false;

  /// Local notifications (UNUserNotificationCenter permission request)
  static const bool notifications = false;
}
