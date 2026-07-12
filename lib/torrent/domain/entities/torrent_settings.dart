class TorrentSettings {
  final String defaultSavePath;
  final bool enableDht;
  final bool enablePex;
  final bool enableLsd;
  final bool enableEncryption;
  final bool enableSequentialDownload;
  final int maxActiveTorrents;
  final int maxActiveDownloads;
  final int maxActiveUploads;
  final int downloadLimitKb;
  final int uploadLimitKb;
  final int maxPeersPerTorrent;
  final int maxConnections;
  final bool autoStart;
  final bool autoSeed;
  final bool autoDeleteTorrentFile;
  final bool resumeSession;
  final bool notifyDownloadComplete;
  final bool notifyDownloadStarted;

  const TorrentSettings({
    this.defaultSavePath = '',
    this.enableDht = true,
    this.enablePex = true,
    this.enableLsd = true,
    this.enableEncryption = false,
    this.enableSequentialDownload = false,
    this.maxActiveTorrents = 5,
    this.maxActiveDownloads = 3,
    this.maxActiveUploads = 2,
    this.downloadLimitKb = 0,
    this.uploadLimitKb = 0,
    this.maxPeersPerTorrent = 50,
    this.maxConnections = 200,
    this.autoStart = true,
    this.autoSeed = true,
    this.autoDeleteTorrentFile = true,
    this.resumeSession = true,
    this.notifyDownloadComplete = true,
    this.notifyDownloadStarted = false,
  });

  TorrentSettings copyWith({
    String? defaultSavePath,
    bool? enableDht,
    bool? enablePex,
    bool? enableLsd,
    bool? enableEncryption,
    bool? enableSequentialDownload,
    int? maxActiveTorrents,
    int? maxActiveDownloads,
    int? maxActiveUploads,
    int? downloadLimitKb,
    int? uploadLimitKb,
    int? maxPeersPerTorrent,
    int? maxConnections,
    bool? autoStart,
    bool? autoSeed,
    bool? autoDeleteTorrentFile,
    bool? resumeSession,
    bool? notifyDownloadComplete,
    bool? notifyDownloadStarted,
  }) {
    return TorrentSettings(
      defaultSavePath: defaultSavePath ?? this.defaultSavePath,
      enableDht: enableDht ?? this.enableDht,
      enablePex: enablePex ?? this.enablePex,
      enableLsd: enableLsd ?? this.enableLsd,
      enableEncryption: enableEncryption ?? this.enableEncryption,
      enableSequentialDownload: enableSequentialDownload ?? this.enableSequentialDownload,
      maxActiveTorrents: maxActiveTorrents ?? this.maxActiveTorrents,
      maxActiveDownloads: maxActiveDownloads ?? this.maxActiveDownloads,
      maxActiveUploads: maxActiveUploads ?? this.maxActiveUploads,
      downloadLimitKb: downloadLimitKb ?? this.downloadLimitKb,
      uploadLimitKb: uploadLimitKb ?? this.uploadLimitKb,
      maxPeersPerTorrent: maxPeersPerTorrent ?? this.maxPeersPerTorrent,
      maxConnections: maxConnections ?? this.maxConnections,
      autoStart: autoStart ?? this.autoStart,
      autoSeed: autoSeed ?? this.autoSeed,
      autoDeleteTorrentFile: autoDeleteTorrentFile ?? this.autoDeleteTorrentFile,
      resumeSession: resumeSession ?? this.resumeSession,
      notifyDownloadComplete: notifyDownloadComplete ?? this.notifyDownloadComplete,
      notifyDownloadStarted: notifyDownloadStarted ?? this.notifyDownloadStarted,
    );
  }
}
