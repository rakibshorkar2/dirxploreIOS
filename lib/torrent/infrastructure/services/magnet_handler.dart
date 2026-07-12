import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class MagnetHandler {
  static const _channel = MethodChannel('com.dirxplorerakib.pro/magnet_receiver');

  final StreamController<String> _magnetStream = StreamController<String>.broadcast();
  final StreamController<String> _torrentFileStream = StreamController<String>.broadcast();

  Stream<String> get onMagnetReceived => _magnetStream.stream;
  Stream<String> get onTorrentFileReceived => _torrentFileStream.stream;

  bool _setup = false;

  Future<void> setup() async {
    if (_setup) return;
    _setup = true;
    _channel.setMethodCallHandler((call) async {
      try {
        switch (call.method) {
          case 'onMagnet':
            final uri = call.arguments as String;
            _magnetStream.add(uri);
          case 'onTorrentFile':
            final path = call.arguments as String;
            _torrentFileStream.add(path);
          default:
            debugPrint('[MagnetHandler] Unhandled method: ${call.method}');
        }
      } catch (e, s) {
        debugPrint('[MagnetHandler] Error handling ${call.method}: $e\n$s');
      }
    });
    try {
      await _channel.invokeMethod<void>('checkPendingIntent');
    } catch (e, s) {
      debugPrint('[MagnetHandler] checkPendingIntent failed: $e\n$s');
    }
  }

  String? getDisplayName(String magnetUri) {
    try {
      final uri = Uri.parse(magnetUri);
      final dn = uri.queryParameters['dn'];
      if (dn != null && dn.isNotEmpty) return Uri.decodeComponent(dn);
    } catch (_) {}
    return null;
  }

  int countTrackers(String magnetUri) {
    try {
      final uri = Uri.parse(magnetUri);
      final trs = uri.queryParametersAll['tr'];
      return trs?.length ?? 0;
    } catch (_) {
      return 0;
    }
  }

  String? getInfoHash(String magnetUri) {
    try {
      final uri = Uri.parse(magnetUri);
      final xt = uri.queryParameters['xt'];
      if (xt != null && xt.startsWith('urn:btih:')) {
        return xt.substring(9);
      }
    } catch (_) {}
    return null;
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
    _magnetStream.close();
    _torrentFileStream.close();
  }
}
