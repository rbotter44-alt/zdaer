import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

typedef WindowsMediaCandidate = void Function(
  String url, {
  String? pageUrl,
  String? mimeType,
  String? source,
  String? resourceType,
});

class WindowsPcMediaCapture {
  WindowsPcMediaCapture._();

  static final Expando<_WindowsCdpState> _states =
      Expando<_WindowsCdpState>('windows-cdp-state');

  static bool get isWindows => Platform.isWindows;

  static String? normalizeUrl(String? raw) {
    if (raw == null) return null;
    var u = raw.trim();
    if (u.isEmpty) return null;
    u = u
        .replaceAll(r'\u0026', '&')
        .replaceAll(r'\/', '/')
        .replaceAll('&amp;', '&');
    if (u.startsWith('blob:') || u.startsWith('data:')) return null;
    if (!(u.startsWith('http://') || u.startsWith('https://'))) return null;
    return u;
  }

  static bool hasPlayableMime(String? mimeType, String? resourceType) {
    final mime = (mimeType ?? '').toLowerCase();
    final type = (resourceType ?? '').toLowerCase();
    return type == 'media' ||
        mime.contains('video') ||
        mime.contains('mpegurl') ||
        mime.contains('dash') ||
        mime.contains('mp4') ||
        mime.contains('mp2t') ||
        mime.contains('octet-stream');
  }

  static bool isDefinitelyDecorativeOrAdCandidate(String? raw) {
    final url = normalizeUrl(raw);
    if (url == null) return true;
    final lower = url.toLowerCase();
    final uri = Uri.tryParse(url);
    final host = uri?.host.toLowerCase() ?? '';
    final path = uri?.path.toLowerCase() ?? lower;

    const assetHints = [
      'favicon',
      '/favicon/',
      'site.webm',
      '/logo',
      '/icons/',
      '/icon/',
      '/sprite',
      '/loader',
      '/placeholder',
      '/poster',
      '/thumb',
      '/thumbnail',
      '.css',
      '.woff',
      '.woff2',
      '.ttf',
      '.otf',
      '.svg',
      '.png',
      '.jpg',
      '.jpeg',
      '.gif',
      '.avif',
      '.webp',
    ];
    if (assetHints.any(lower.contains)) return true;

    const adHosts = [
      '1xbet',
      'melbet',
      'doubleclick',
      'googlesyndication',
      'pagead',
      'adnxs',
      'taboola',
      'outbrain',
      'mgid',
      'propeller',
      'exoclick',
      'imasdk',
      'adsterra',
      'popads',
      'popcash',
      'trafficjunky',
      'hilltopads',
    ];
    if (adHosts.any(host.contains)) return true;

    const adPaths = [
      '/ads/',
      '/ad/',
      '/pagead',
      '/gpt/',
      '/async/ads',
      '/content/stream/agl/',
      'ad_unit',
      'adunit',
      'interstitial',
      'rewarded',
    ];
    if (adPaths.any(path.contains)) return true;

    return false;
  }

  static bool isLikelyPlayableEndpoint(String? raw) {
    final url = normalizeUrl(raw);
    if (url == null || isDefinitelyDecorativeOrAdCandidate(url)) return false;
    final lower = url.toLowerCase();
    final uri = Uri.tryParse(url);
    final host = uri?.host.toLowerCase() ?? '';
    final path = uri?.path.toLowerCase() ?? '';

    const directHints = [
      '.m3u8',
      '.mp4',
      '.mpd',
      '.m4v',
      '.webm',
      '.mkv',
      '.mov',
      'mime=video',
      'contenttype=video',
      '/hls/',
      '/dash/',
      '/playlist',
      '/manifest',
    ];
    if (directHints.any(lower.contains)) return true;

    const knownMediaHosts = [
      'vid3rb',
      'videasy',
      'vidfast',
      'vidsrc',
      'egydead',
      'egydeadcdn',
      'stmruby',
      'streamruby',
      'streamhg',
      'streamix',
      'deathstream',
      'earnvids',
      'forafile',
      'krakenfiles',
      'mixdrop',
      'uqload',
      'dood',
      'dooood',
      'streamtape',
      'stape',
      'voe',
      'jwplatform',
      'jwpcdn',
      'hglink',
      'vibuxer',
      'audinifer',
      'huntrexus',
      'hanerix',
      'pixibay',
      'workers.dev',
      'megafiles.store',
      'rainorbit',
      'nightbreeze',
      'quietlynx',
      'thunderleaf',
      '1cloudfile',
      'vidtube',
      'masukestin',
      'cdn-tube',
      'server-hls',
      'server-hls2-stream',
      'cdn-stream',
      'stellarcrestcreative',
      'bunnycdn',
      'b-cdn',
      'storage.googleapis',
      's3.amazonaws',
      'megaup',
      '1fichier',
      'vikingfile',
      'koramaup',
      'bowfile',
      'cloudfront',
      'akamaized',
    ];
    final knownHost = knownMediaHosts.any(host.contains);
    if (!knownHost) return false;

    const pathHints = [
      '/file/',
      '/files/',
      '/stream',
      '/download',
      '/media',
      '/video',
      '/source',
      '/sources',
      '/get',
      '/play',
      '/embed',
      '/watch',
      '/video/',
      '/videos/',
      '/cdn/',
      '/e/',
      '/f/',
    ];
    return pathHints.any(path.contains) ||
        uri?.queryParameters.keys.any((k) {
              final key = k.toLowerCase();
              return key == 'token' ||
                  key == 't' ||
                  key == 'expires' ||
                  key == 'signature' ||
                  key == 'quality' ||
                  key == 'q';
            }) ==
            true;
  }

  static bool isCandidateUrl(
    String? raw, {
    String? mimeType,
    String? resourceType,
  }) {
    final url = normalizeUrl(raw);
    if (url == null) return false;
    return hasPlayableMime(mimeType, resourceType) ||
        isLikelyPlayableEndpoint(url);
  }

  static String? inferMimeType(String? raw, [String? hinted]) {
    final hint = hinted?.toLowerCase().trim();
    if (hint != null && hint.isNotEmpty) return hint;
    final lower = (raw ?? '').toLowerCase();
    if (lower.contains('.m3u8')) return 'application/x-mpegURL';
    if (lower.contains('.mpd')) return 'application/dash+xml';
    if (lower.contains('.mp4') || lower.contains('.m4v')) return 'video/mp4';
    if (lower.contains('.webm')) return 'video/webm';
    if (lower.contains('.mkv')) return 'video/x-matroska';
    if (lower.contains('.ts')) return 'video/mp2t';
    if (lower.contains('.mov')) return 'video/quicktime';
    return null;
  }

  static String inferQualityLabel(String? raw) {
    final lower = (raw ?? '').toLowerCase();
    final match = RegExp(r'(2160|1440|1080|720|540|480|360|240)p?')
        .firstMatch(lower);
    if (match == null) return '';
    return '${match.group(1)}p';
  }

  static Future<void> installDevToolsNetworkBridge({
    required InAppWebViewController controller,
    required WindowsMediaCandidate onCandidate,
    String? Function()? pageUrlProvider,
    void Function(String message)? onDebug,
    bool readResponseBodies = false,
  }) async {
    if (!Platform.isWindows) return;
    final existing = _states[controller];
    if (existing != null && existing.installed) return;

    final state = _WindowsCdpState();
    _states[controller] = state;
    state.installed = true;

    void emit(
      String? raw,
      String source, {
      String? mimeType,
      String? resourceType,
    }) {
      final url = normalizeUrl(raw);
      if (url == null) return;
      if (!isCandidateUrl(url, mimeType: mimeType, resourceType: resourceType)) {
        return;
      }
      final key = '$source|${url.toLowerCase()}|${mimeType ?? ''}|${resourceType ?? ''}';
      if (!state.seen.add(key)) return;
      onDebug?.call('candidate $source/$resourceType ${mimeType ?? ''} $url');
      onCandidate(
        url,
        pageUrl: pageUrlProvider?.call(),
        mimeType: inferMimeType(url, mimeType),
        source: source,
        resourceType: resourceType,
      );
    }

    void scanText(String? text, String source, {String? resourceType}) {
      if (text == null || text.isEmpty) return;
      final body = text
          .replaceAll(r'\/', '/')
          .replaceAll(r'\u0026', '&')
          .replaceAll('&amp;', '&');
      final re = RegExp(
        r'''https?:\/\/[^\s"'<>\\]+?(?:\.m3u8|\.mp4|\.mpd|\.m4v|\.webm|\.mkv|\.mov)(?:\?[^\s"'<>\\]*)?''',
        caseSensitive: false,
      );
      for (final match in re.allMatches(body)) {
        emit(match.group(0), '$source-body', resourceType: resourceType);
      }
    }

    Future<void> tryReadBody(String? requestId, String source) async {
      if (!readResponseBodies || requestId == null || requestId.isEmpty) return;
      final url = state.requestUrlById[requestId] ?? '';
      final mime = state.mimeById[requestId] ?? '';
      final type = state.typeById[requestId] ?? '';
      final lower = url.toLowerCase();
      final lm = mime.toLowerCase();
      final shouldRead = lower.contains('source') ||
          lower.contains('playlist') ||
          lower.contains('manifest') ||
          lower.contains('player') ||
          lower.contains('embed') ||
          lower.contains('api') ||
          lm.contains('json') ||
          lm.contains('javascript') ||
          lm.contains('text');
      if (!shouldRead) return;
      try {
        final body = await controller.callDevToolsProtocolMethod(
          methodName: 'Network.getResponseBody',
          parameters: {'requestId': requestId},
        );
        final text = body is Map ? body['body']?.toString() : null;
        scanText(text, source, resourceType: type);
      } catch (_) {}
    }

    try {
      await controller.callDevToolsProtocolMethod(methodName: 'Network.enable');
      onDebug?.call('Network.enable ok');
    } catch (e) {
      onDebug?.call('Network.enable failed $e');
      return;
    }

    Future<void> addListener(
      String eventName,
      FutureOr<void> Function(dynamic data) callback,
    ) async {
      try {
        await controller.addDevToolsProtocolEventListener(
          eventName: eventName,
          callback: callback,
        );
        onDebug?.call('listener $eventName ok');
      } catch (e) {
        onDebug?.call('listener $eventName failed $e');
      }
    }

    await addListener('Network.requestWillBeSent', (dynamic data) {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        final id = map['requestId']?.toString();
        final type = map['type']?.toString();
        final req = map['request'];
        final url = req is Map ? req['url']?.toString() : null;
        if (id != null) {
          if (url != null) state.requestUrlById[id] = url;
          if (type != null) state.typeById[id] = type;
        }
        emit(url, 'request', resourceType: type);
      } catch (_) {}
    });

    await addListener('Network.responseReceived', (dynamic data) {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        final id = map['requestId']?.toString();
        final type = map['type']?.toString();
        final resp = map['response'];
        final url = resp is Map ? resp['url']?.toString() : null;
        final mime = resp is Map ? resp['mimeType']?.toString() : null;
        if (id != null) {
          if (url != null) state.requestUrlById[id] = url;
          if (mime != null) state.mimeById[id] = mime;
          if (type != null) state.typeById[id] = type;
        }
        emit(url, 'response', mimeType: mime, resourceType: type);
      } catch (_) {}
    });

    await addListener('Network.loadingFinished', (dynamic data) async {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        final id = map['requestId']?.toString();
        emit(
          state.requestUrlById[id],
          'finished',
          mimeType: state.mimeById[id],
          resourceType: state.typeById[id],
        );
        await tryReadBody(id, 'finished');
      } catch (_) {}
    });
  }
}

class _WindowsCdpState {
  bool installed = false;
  final Set<String> seen = <String>{};
  final Map<String, String> requestUrlById = <String, String>{};
  final Map<String, String> mimeById = <String, String>{};
  final Map<String, String> typeById = <String, String>{};
}
