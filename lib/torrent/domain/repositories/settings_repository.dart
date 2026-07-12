import '../entities/torrent_settings.dart';

abstract class SettingsRepository {
  Future<TorrentSettings> load();
  Future<void> save(TorrentSettings settings);
}
