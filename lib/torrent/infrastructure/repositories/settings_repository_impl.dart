import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/entities/torrent_settings.dart';
import '../../domain/repositories/settings_repository.dart';

class SharedPrefsSettingsRepository implements SettingsRepository {
  static const _keyDefaultPath = 'torrent_defaultPath';
  static const _keyEnableDht = 'torrent_enableDht';
  static const _keyEnablePex = 'torrent_enablePex';
  static const _keyEnableLsd = 'torrent_enableLsd';
  static const _keyEnableEncryption = 'torrent_enableEncryption';
  static const _keyEnableSequential = 'torrent_enableSequential';
  static const _keyMaxActiveTorrents = 'torrent_maxActiveTorrents';
  static const _keyMaxActiveDownloads = 'torrent_maxActiveDownloads';
  static const _keyMaxActiveUploads = 'torrent_maxActiveUploads';
  static const _keyDownloadLimit = 'torrent_downloadLimit';
  static const _keyUploadLimit = 'torrent_uploadLimit';
  static const _keyMaxPeers = 'torrent_maxPeers';
  static const _keyMaxConnections = 'torrent_maxConnections';
  static const _keyAutoStart = 'torrent_autoStart';
  static const _keyAutoSeed = 'torrent_autoSeed';
  static const _keyAutoDeleteTorrent = 'torrent_autoDeleteTorrent';
  static const _keyResumeSession = 'torrent_resumeSession';
  static const _keyNotifyDownloadComplete = 'torrent_notifyDownloadComplete';
  static const _keyNotifyDownloadStarted = 'torrent_notifyDownloadStarted';

  @override
  Future<TorrentSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return TorrentSettings(
      defaultSavePath: prefs.getString(_keyDefaultPath) ?? '',
      enableDht: prefs.getBool(_keyEnableDht) ?? true,
      enablePex: prefs.getBool(_keyEnablePex) ?? true,
      enableLsd: prefs.getBool(_keyEnableLsd) ?? true,
      enableEncryption: prefs.getBool(_keyEnableEncryption) ?? false,
      enableSequentialDownload: prefs.getBool(_keyEnableSequential) ?? false,
      maxActiveTorrents: prefs.getInt(_keyMaxActiveTorrents) ?? 5,
      maxActiveDownloads: prefs.getInt(_keyMaxActiveDownloads) ?? 3,
      maxActiveUploads: prefs.getInt(_keyMaxActiveUploads) ?? 2,
      downloadLimitKb: prefs.getInt(_keyDownloadLimit) ?? 0,
      uploadLimitKb: prefs.getInt(_keyUploadLimit) ?? 0,
      maxPeersPerTorrent: prefs.getInt(_keyMaxPeers) ?? 50,
      maxConnections: prefs.getInt(_keyMaxConnections) ?? 200,
      autoStart: prefs.getBool(_keyAutoStart) ?? true,
      autoSeed: prefs.getBool(_keyAutoSeed) ?? true,
      autoDeleteTorrentFile: prefs.getBool(_keyAutoDeleteTorrent) ?? true,
      resumeSession: prefs.getBool(_keyResumeSession) ?? true,
      notifyDownloadComplete: prefs.getBool(_keyNotifyDownloadComplete) ?? true,
      notifyDownloadStarted: prefs.getBool(_keyNotifyDownloadStarted) ?? false,
    );
  }

  @override
  Future<void> save(TorrentSettings s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDefaultPath, s.defaultSavePath);
    await prefs.setBool(_keyEnableDht, s.enableDht);
    await prefs.setBool(_keyEnablePex, s.enablePex);
    await prefs.setBool(_keyEnableLsd, s.enableLsd);
    await prefs.setBool(_keyEnableEncryption, s.enableEncryption);
    await prefs.setBool(_keyEnableSequential, s.enableSequentialDownload);
    await prefs.setInt(_keyMaxActiveTorrents, s.maxActiveTorrents);
    await prefs.setInt(_keyMaxActiveDownloads, s.maxActiveDownloads);
    await prefs.setInt(_keyMaxActiveUploads, s.maxActiveUploads);
    await prefs.setInt(_keyDownloadLimit, s.downloadLimitKb);
    await prefs.setInt(_keyUploadLimit, s.uploadLimitKb);
    await prefs.setInt(_keyMaxPeers, s.maxPeersPerTorrent);
    await prefs.setInt(_keyMaxConnections, s.maxConnections);
    await prefs.setBool(_keyAutoStart, s.autoStart);
    await prefs.setBool(_keyAutoSeed, s.autoSeed);
    await prefs.setBool(_keyAutoDeleteTorrent, s.autoDeleteTorrentFile);
    await prefs.setBool(_keyResumeSession, s.resumeSession);
    await prefs.setBool(_keyNotifyDownloadComplete, s.notifyDownloadComplete);
    await prefs.setBool(_keyNotifyDownloadStarted, s.notifyDownloadStarted);
  }
}
