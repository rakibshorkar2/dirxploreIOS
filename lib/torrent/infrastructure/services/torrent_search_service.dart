import 'package:dio/dio.dart';
import '../../domain/entities/torrent_task.dart';

class TorrentSearchService {
  final Dio _dio;
  final List<TorrentSearchResult> _searchCache = [];
  bool _isSearching = false;

  TorrentSearchService()
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          },
        ));

  bool get isSearching => _isSearching;
  List<TorrentSearchResult> get searchCache => _searchCache;

  Future<void> search({
    required String query,
    required List<String> providers,
    required TorrentCategory category,
    void Function(TorrentSearchResult result)? onResult,
  }) async {
    if (query.isEmpty) return;
    _isSearching = true;
    _searchCache.clear();

    final futures = providers.map((p) => _searchProvider(p, query, category));
    final results = (await Future.wait(futures)).expand((x) => x).toList();

    results.sort((a, b) => b.seeds.compareTo(a.seeds));

    for (final r in results) {
      _searchCache.add(r);
      onResult?.call(r);
    }
    _isSearching = false;
  }

  Future<List<TorrentSearchResult>> _searchProvider(
      String provider, String query, TorrentCategory category) async {
    try {
      switch (provider) {
        case 'YTS':
          return _searchYts(query);
        case '1337x':
          return _search1337x(query);
        case 'PirateBay':
          return _searchPirateBay(query);
        case 'TorrentGalaxy':
          return _searchTorrentGalaxy(query);
        case 'Nyaa':
          return _searchNyaa(query);
        case 'Kickass':
          return _searchKickass(query);
        case 'LimeTorrents':
          return _searchLimeTorrents(query);
        case 'SolidTorrents':
          return _searchSolidTorrents(query);
        case 'EzTV':
          return _searchEzTv(query);
        case 'iDope':
          return _searchIDope(query);
        default:
          return [];
      }
    } catch (_) {
      return [];
    }
  }

  Future<List<TorrentSearchResult>> _searchYts(String query) async {
    final resp = await _dio.get('https://yts.mx/api/v2/list_movies.json',
        queryParameters: {'query_term': query, 'limit': 20});
    final data = resp.data;
    final movies = data['data']?['movies'] as List?;
    if (movies == null) return [];
    final results = <TorrentSearchResult>[];
    for (final m in movies) {
      final torrents = m['torrents'] as List? ?? [];
      for (final t in torrents) {
        final size = _formatSize(_parseSize(t['size'] ?? '0'));
        results.add(TorrentSearchResult(
          title: '${m['title']} (${t['quality']})',
          magnetUrl: t['url'] ?? '',
          seeds: t['seeds'] ?? 0,
          leechers: t['peers'] ?? 0,
          size: size,
          provider: 'YTS',
          category: TorrentCategory.movies,
        ));
      }
    }
    return results;
  }

  Future<List<TorrentSearchResult>> _search1337x(String query) async {
    final resp = await _dio.get('https://1337x.to/search/$query/1/');
    final html = resp.data as String;
    final results = <TorrentSearchResult>[];
    final regex = RegExp(
        r'<tr>.*?<a href="/(torrent/\\d+/[^"]+)".*?>(.*?)</a>.*?<td class="coll-2 seeds">(\\d+)</td>.*?<td class="coll-3 leeches">(\\d+)</td>.*?<td class="coll-4 size">(.*?)</td>',
        dotAll: true);
    for (final m in regex.allMatches(html).take(20)) {
      results.add(TorrentSearchResult(
        title: m.group(2)?.trim() ?? '',
        magnetUrl: 'https://1337x.to${m.group(1)}',
        seeds: int.tryParse(m.group(3) ?? '0') ?? 0,
        leechers: int.tryParse(m.group(4) ?? '0') ?? 0,
        size: m.group(5)?.trim() ?? '',
        provider: '1337x',
        category: _detectCategory(m.group(2) ?? ''),
      ));
    }
    return results;
  }

  Future<List<TorrentSearchResult>> _searchPirateBay(String query) async {
    final resp = await _dio.get('https://apibay.org/q.php',
        queryParameters: {'q': query, 'cat': '0'});
    final data = resp.data as List;
    final results = <TorrentSearchResult>[];
    for (final item in data.take(20)) {
      if (item['id'] == '0') continue;
      final name = item['name'] as String? ?? '';
      results.add(TorrentSearchResult(
        title: name,
        magnetUrl: item['info_hash'] != null
            ? 'magnet:?xt=urn:btih:${item['info_hash']}&dn=${Uri.encodeComponent(name)}'
            : '',
        seeds: int.tryParse('${item['seeders']}') ?? 0,
        leechers: int.tryParse('${item['leechers']}') ?? 0,
        size: _formatSize(int.tryParse('${item['size']}') ?? 0),
        provider: 'PirateBay',
        category: _detectCategory(name),
      ));
    }
    return results;
  }

  Future<List<TorrentSearchResult>> _searchTorrentGalaxy(String query) async {
    final resp = await _dio.get('https://torrentgalaxy.to/torrents.php',
        queryParameters: {'search': query, 'sort': 'id', 'order': 'DESC'});
    final html = resp.data as String;
    final results = <TorrentSearchResult>[];
    final regex = RegExp(
        r'<div class="tgxtable">.*?<a href="(.*?)".*?>(.*?)</a>.*?<span.*?>(\\d+)</span>.*?<span.*?>(\\d+)</span>',
        dotAll: true);
    for (final m in regex.allMatches(html).take(20)) {
      results.add(TorrentSearchResult(
        title: m.group(2)?.trim() ?? '',
        magnetUrl: m.group(1) != null ? 'https://torrentgalaxy.to${m.group(1)}' : '',
        seeds: int.tryParse(m.group(3) ?? '0') ?? 0,
        leechers: int.tryParse(m.group(4) ?? '0') ?? 0,
        size: '',
        provider: 'TorrentGalaxy',
        category: _detectCategory(m.group(2) ?? ''),
      ));
    }
    return results;
  }

  Future<List<TorrentSearchResult>> _searchNyaa(String query) async {
    final resp = await _dio.get('https://nyaa.si/?q=$query&s=seeders&o=desc');
    final html = resp.data as String;
    final results = <TorrentSearchResult>[];
    final regex = RegExp(
        r'<tr.*?>.*?<a href="(.*?)".*?>(.*?)</a>.*?<td class="text-center.*?">(\\d+)</td>.*?<td class="text-center.*?">(\\d+)</td>.*?<td class="text-center.*?">(.*?)</td>',
        dotAll: true);
    for (final m in regex.allMatches(html).take(20)) {
      results.add(TorrentSearchResult(
        title: m.group(2)?.trim() ?? '',
        magnetUrl: m.group(1) != null ? 'https://nyaa.si${m.group(1)}' : '',
        seeds: int.tryParse(m.group(3) ?? '0') ?? 0,
        leechers: int.tryParse(m.group(4) ?? '0') ?? 0,
        size: m.group(5)?.trim() ?? '',
        provider: 'Nyaa',
        category: TorrentCategory.movies,
      ));
    }
    return results;
  }

  Future<List<TorrentSearchResult>> _searchKickass(String query) async {
    final resp = await _dio.get('https://kickass.sx/usearch/$query/');
    final html = resp.data as String;
    final results = <TorrentSearchResult>[];
    final regex = RegExp(
        r'<tr.*?>.*?<a class="torrents_table_a".*?href="(.*?)".*?>(.*?)</a>.*?<td.*?class=".*?seeds.*?">(\\d+)</td>.*?<td.*?class=".*?leeches.*?">(\\d+)</td>.*?<td.*?class=".*?size.*?">(.*?)</td>',
        dotAll: true);
    for (final m in regex.allMatches(html).take(20)) {
      results.add(TorrentSearchResult(
        title: m.group(2)?.trim() ?? '',
        magnetUrl: m.group(1) != null ? 'https://kickass.sx${m.group(1)}' : '',
        seeds: int.tryParse(m.group(3) ?? '0') ?? 0,
        leechers: int.tryParse(m.group(4) ?? '0') ?? 0,
        size: m.group(5)?.trim() ?? '',
        provider: 'Kickass',
        category: _detectCategory(m.group(2) ?? ''),
      ));
    }
    return results;
  }

  Future<List<TorrentSearchResult>> _searchLimeTorrents(String query) async {
    final resp = await _dio.get('https://limetorrents.lol/search.php?q=$query');
    final html = resp.data as String;
    final results = <TorrentSearchResult>[];
    final regex = RegExp(
        r'<tr.*?>.*?<a href="(.*?)".*?>(.*?)</a>.*?<td.*?class=".*?seed.*?">(\\d+)</td>.*?<td.*?class=".*?leech.*?">(\\d+)</td>.*?<td.*?class=".*?size.*?">(.*?)</td>',
        dotAll: true);
    for (final m in regex.allMatches(html).take(20)) {
      results.add(TorrentSearchResult(
        title: m.group(2)?.trim() ?? '',
        magnetUrl: m.group(1) != null ? 'https://limetorrents.lol${m.group(1)}' : '',
        seeds: int.tryParse(m.group(3) ?? '0') ?? 0,
        leechers: int.tryParse(m.group(4) ?? '0') ?? 0,
        size: m.group(5)?.trim() ?? '',
        provider: 'LimeTorrents',
        category: _detectCategory(m.group(2) ?? ''),
      ));
    }
    return results;
  }

  Future<List<TorrentSearchResult>> _searchSolidTorrents(String query) async {
    final resp = await _dio.get('https://solidtorrents.to/search?q=$query');
    final html = resp.data as String;
    final results = <TorrentSearchResult>[];
    final regex = RegExp(
        r'<div class="torrent__name">.*?<a href="(.*?)".*?>(.*?)</a>.*?<span.*?class="seeds">(\\d+)</span>.*?<span.*?class="leeches">(\\d+)</span>',
        dotAll: true);
    for (final m in regex.allMatches(html).take(20)) {
      results.add(TorrentSearchResult(
        title: m.group(2)?.trim() ?? '',
        magnetUrl: m.group(1) != null ? 'https://solidtorrents.to${m.group(1)}' : '',
        seeds: int.tryParse(m.group(3) ?? '0') ?? 0,
        leechers: int.tryParse(m.group(4) ?? '0') ?? 0,
        size: '',
        provider: 'SolidTorrents',
        category: _detectCategory(m.group(2) ?? ''),
      ));
    }
    return results;
  }

  Future<List<TorrentSearchResult>> _searchEzTv(String query) async {
    final resp = await _dio.get('https://eztvx.to/search/$query');
    final html = resp.data as String;
    final results = <TorrentSearchResult>[];
    final regex = RegExp(
        r'<tr.*?>.*?<a href="(.*?)".*?>(.*?)</a>.*?<td.*?class=".*?seeds.*?">(\\d+)</td>.*?<td.*?class=".*?peers.*?">(\\d+)</td>.*?<td.*?class=".*?size.*?">(.*?)</td>',
        dotAll: true);
    for (final m in regex.allMatches(html).take(20)) {
      results.add(TorrentSearchResult(
        title: m.group(2)?.trim() ?? '',
        magnetUrl: m.group(1) != null ? 'https://eztvx.to${m.group(1)}' : '',
        seeds: int.tryParse(m.group(3) ?? '0') ?? 0,
        leechers: int.tryParse(m.group(4) ?? '0') ?? 0,
        size: m.group(5)?.trim() ?? '',
        provider: 'EzTV',
        category: TorrentCategory.movies,
      ));
    }
    return results;
  }

  Future<List<TorrentSearchResult>> _searchIDope(String query) async {
    final resp = await _dio.get('https://idope.top/search/$query/1/');
    final data = resp.data;
    final items = data['result']?['items'] as List?;
    if (items == null) return [];
    final results = <TorrentSearchResult>[];
    for (final item in items.take(20)) {
      final name = item['name'] as String? ?? '';
      final hash = item['info_hash'] as String? ?? '';
      results.add(TorrentSearchResult(
        title: name,
        magnetUrl: hash.isNotEmpty
            ? 'magnet:?xt=urn:btih:$hash&dn=${Uri.encodeComponent(name)}'
            : '',
        seeds: item['seeds'] ?? 0,
        leechers: item['leech'] ?? 0,
        size: _formatSize(item['size'] ?? 0),
        provider: 'iDope',
        category: _detectCategory(name),
      ));
    }
    return results;
  }

  TorrentCategory _detectCategory(String title) {
    final lower = title.toLowerCase();
    for (final entry in categoryKeywords.entries) {
      if (entry.key == TorrentCategory.all) continue;
      for (final keyword in entry.value) {
        if (lower.contains(keyword)) return entry.key;
      }
    }
    return TorrentCategory.movies;
  }

  int _parseSize(String size) {
    final number = RegExp(r'[\d.]+').firstMatch(size)?.group(0);
    if (number == null) return 0;
    final value = double.tryParse(number) ?? 0;
    if (size.contains('GB')) return (value * 1073741824).toInt();
    if (size.contains('MB')) return (value * 1048576).toInt();
    if (size.contains('KB')) return (value * 1024).toInt();
    return value.toInt();
  }

  String _formatSize(dynamic bytes) {
    if (bytes is! int) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1073741824) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    return '${(bytes / 1073741824).toStringAsFixed(1)} GB';
  }
}
