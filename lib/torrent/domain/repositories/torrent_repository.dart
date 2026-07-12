import '../entities/torrent_task.dart';
import '../entities/torrent_settings.dart';

abstract class TorrentRepository {
  Future<void> init(TorrentSettings settings);
  Stream<List<TorrentTask>> get torrentUpdates;
  int addMagnet(String uri);
  int addTorrentFile(String path);
  void pauseTorrent(int id);
  void resumeTorrent(int id);
  void removeTorrent(int id, {bool deleteFiles = false});
  void recheckTorrent(int id);
  void stopTorrent(int id);
  void setDownloadLimit(int id, int limitBytes);
  void setUploadLimit(int id, int limitBytes);
  void setFilePriorities(int id, List<dynamic> priorities);
  List<dynamic> getFiles(int id);
  void configureSession(dynamic config);
  void applyLimits(int downKb, int upKb);
  Future<TorrentInfoPreview> probeMagnet(String uri);
  Future<TorrentInfoPreview> probeTorrentFile(String path);
  void confirmMagnet(int engineId);
  void cancelMagnetProbe(int engineId);
  String? getMagnetUri(int id);
  void clearCompleted();
  Future<void> moveStorage(int id, String newPath);
}
