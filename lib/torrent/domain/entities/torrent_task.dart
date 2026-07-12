enum TorrentCategory { all, movies, series, games, music, books, apps }

enum TorrentStatus { idle, searching, downloading, seeding, checking, paused, error, done, queued }

class TorrentSearchResult {
  final String title;
  final String magnetUrl;
  final String? torrentUrl;
  final int seeds;
  final int leechers;
  final String size;
  final String provider;
  final TorrentCategory category;

  TorrentSearchResult({
    required this.title,
    required this.magnetUrl,
    this.torrentUrl,
    required this.seeds,
    required this.leechers,
    required this.size,
    required this.provider,
    required this.category,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'magnetUrl': magnetUrl,
        'torrentUrl': torrentUrl,
        'seeds': seeds,
        'leechers': leechers,
        'size': size,
        'provider': provider,
        'category': category.index,
      };
}

class TorrentInfoPreview {
  final int engineId;
  final String name;
  final int size;
  final int fileCount;
  final int trackerCount;
  final String magnetUri;

  TorrentInfoPreview({
    required this.engineId,
    required this.name,
    required this.size,
    required this.fileCount,
    required this.trackerCount,
    required this.magnetUri,
  });
}

class TorrentTask {
  final int id;
  final String name;
  final String savePath;
  final TorrentStatus status;
  final double progress;
  final int downloadRate;
  final int uploadRate;
  final int totalDone;
  final int totalWanted;
  final int totalUploaded;
  final int numPeers;
  final int numSeeds;
  final bool hasMetadata;
  final bool isPaused;
  final bool isFinished;
  final String errorMsg;
  final String? magnetLink;
  final String? torrentFilePath;
  final DateTime addedAt;
  final int downloadRateLimit;
  final int uploadRateLimit;
  final bool sequentialDownload;

  TorrentTask({
    required this.id,
    required this.name,
    required this.savePath,
    required this.status,
    required this.progress,
    required this.downloadRate,
    required this.uploadRate,
    required this.totalDone,
    required this.totalWanted,
    required this.totalUploaded,
    required this.numPeers,
    required this.numSeeds,
    required this.hasMetadata,
    required this.isPaused,
    required this.isFinished,
    this.errorMsg = '',
    this.magnetLink,
    this.torrentFilePath,
    DateTime? addedAt,
    this.downloadRateLimit = 0,
    this.uploadRateLimit = 0,
    this.sequentialDownload = false,
  }) : addedAt = addedAt ?? DateTime.now();

  int get leechers => (numPeers - numSeeds).clamp(0, numPeers);

  Duration? get eta {
    if (downloadRate <= 0) return null;
    final remaining = totalWanted - totalDone;
    if (remaining <= 0) return Duration.zero;
    return Duration(seconds: remaining ~/ downloadRate);
  }

  double get ratio {
    if (totalDone <= 0) return 0;
    return totalUploaded / totalDone;
  }

  String get etaFormatted {
    final e = eta;
    if (e == null) return '∞';
    if (e == Duration.zero) return 'Done';
    if (e.inDays > 0) return '${e.inDays}d ${e.inHours.remainder(24)}h';
    if (e.inHours > 0) return '${e.inHours}h ${e.inMinutes.remainder(60)}m';
    if (e.inMinutes > 0) return '${e.inMinutes}m ${e.inSeconds.remainder(60)}s';
    return '${e.inSeconds}s';
  }

  String get ratioFormatted => ratio.toStringAsFixed(2);
  String get downloadedFormatted => formatSize(totalDone);
  String get uploadedFormatted => formatSize(totalUploaded);
  String get sizeFormatted => formatSize(totalWanted);
  String get speedDownFormatted => formatSpeed(downloadRate);
  String get speedUpFormatted => formatSpeed(uploadRate);
}

String formatSpeed(int bytesPerSec) {
  if (bytesPerSec < 1024) return '$bytesPerSec B/s';
  if (bytesPerSec < 1048576) return '${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s';
  return '${(bytesPerSec / 1048576).toStringAsFixed(1)} MB/s';
}

String formatSize(dynamic bytes) {
  if (bytes is String) return bytes;
  if (bytes is! int) return '0 B';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1073741824) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  return '${(bytes / 1073741824).toStringAsFixed(1)} GB';
}

const List<String> torrentProviders = [
  'YTS',
  '1337x',
  'PirateBay',
  'TorrentGalaxy',
  'Nyaa',
  'Kickass',
  'LimeTorrents',
  'SolidTorrents',
  'EzTV',
  'iDope',
];

const Map<TorrentCategory, String> categoryLabels = {
  TorrentCategory.all: 'All',
  TorrentCategory.movies: 'Movies',
  TorrentCategory.series: 'Series',
  TorrentCategory.games: 'Games',
  TorrentCategory.music: 'Music',
  TorrentCategory.books: 'Books',
  TorrentCategory.apps: 'Apps',
};

const Map<TorrentCategory, List<String>> categoryKeywords = {
  TorrentCategory.all: [],
  TorrentCategory.movies: ['movie', '1080p', '720p', '4k', 'bluray', 'x264', 'x265'],
  TorrentCategory.series: ['s01', 's02', 's03', 'season', 'episode', 'ep'],
  TorrentCategory.games: ['game', 'repack', 'gog', 'steam', 'fitgirl'],
  TorrentCategory.music: ['mp3', 'flac', 'album', 'discography'],
  TorrentCategory.books: ['pdf', 'epub', 'book', 'mobi'],
  TorrentCategory.apps: ['app', 'software', 'windows', 'macos', 'crack'],
};
