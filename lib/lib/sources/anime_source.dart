import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import '../pwa/io_compat.dart';
import '../pwa/isolate_compat.dart';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../pwa/path_provider_compat.dart';
import '../pwa/refresh_rate_compat.dart';
import '../pwa/video_thumbnail_compat.dart';

import '../background_download_bridge.dart';
import '../secure_strings.dart';
import '../native_security_guard.dart';
import '../universal_media_player.dart';
import '../pwa/file_image_compat.dart';

final String kCatalogHomeUrl = AppSecureText.s('ftQiJ5KlEXdzJtLr8XC_FCTCftvO');
const String kScraperUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

@pragma('vm:entry-point')
void animeSourceMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(NativeSecurityGuard.ensureClean());

  try {
    RefreshRate.enable();
    RefreshRate.preferMax();
  } catch (_) {}

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: AsdPicsPlayer(),
  ));
}

class DownloadItem {
  final String id;
  final String url;
  String fileName;
  double progress;
  String status;
  String? savedPath;
  String? thumbnailPath;
  String? tempPath;
  String? finalPath;
  CancelToken? cancelToken;
  String? errorMessage;
  bool pauseRequested;
  Completer<void>? resumeCompleter;

  DownloadItem({
    required this.id,
    required this.url,
    required this.fileName,
    this.progress = 0,
    this.status = 'downloading',
    this.savedPath,
    this.thumbnailPath,
    this.tempPath,
    this.finalPath,
    this.cancelToken,
    this.errorMessage,
    this.pauseRequested = false,
    this.resumeCompleter,
  });
}

class CapturedMediaItem {
  final String id;
  final String url;
  final String pageUrl;
  final String? mimeType;
  final String fileName;
  final DateTime foundAt;
  final bool isDirectFile;
  final bool isStream;
  final String? qualityLabel;
  final Map<String, String>? headers;

  const CapturedMediaItem({
    required this.id,
    required this.url,
    required this.pageUrl,
    required this.fileName,
    required this.foundAt,
    required this.isDirectFile,
    required this.isStream,
    this.mimeType,
    this.qualityLabel,
    this.headers,
  });
}

class PageQualityOption {
  final String label;
  final String key;
  final String? url;
  final bool selected;

  const PageQualityOption({
    required this.label,
    required this.key,
    this.url,
    this.selected = false,
  });

  factory PageQualityOption.fromMap(Map<String, dynamic> map) {
    return PageQualityOption(
      label: (map['label']?.toString().trim().isNotEmpty ?? false)
          ? map['label'].toString().trim()
          : 'Quality',
      key: map['key']?.toString() ?? '',
      url: map['url']?.toString(),
      selected: map['selected'] == true,
    );
  }

  Map<String, String> toMap() => {
        'label': label,
        'key': key,
        if (url != null && url!.isNotEmpty) 'url': url!,
      };
}

class PageServerOption {
  final String label;
  final String key;
  final String? embedUrl;
  final bool selected;

  const PageServerOption({
    required this.label,
    required this.key,
    this.embedUrl,
    this.selected = false,
  });

  factory PageServerOption.fromMap(Map<String, dynamic> map) {
    return PageServerOption(
      label: (map['label']?.toString().trim().isNotEmpty ?? false)
          ? map['label'].toString().trim()
          : 'Server',
      key: map['key']?.toString() ?? '',
      embedUrl: map['embedUrl']?.toString(),
      selected: map['selected'] == true,
    );
  }

  Map<String, String> toMap() => {
        'label': label,
        'key': key,
        if (embedUrl != null && embedUrl!.isNotEmpty) 'embedUrl': embedUrl!,
      };
}

class AsdPicsPlayer extends StatefulWidget {
  final String initialUrl;
  final String? headerTitle;
  final bool autoDownloadPrompt;
  final bool launchHidden;
  final bool downloadOnlyMode;
  final String? loadingPosterUrl;

  const AsdPicsPlayer({
    super.key,
    this.initialUrl = 'https://anime3rb.com/',
    this.headerTitle,
    this.autoDownloadPrompt = false,
    this.launchHidden = false,
    this.downloadOnlyMode = false,
    this.loadingPosterUrl,
  });

  @override
  State<AsdPicsPlayer> createState() => _AsdPicsPlayerState();
}

class _AsdPicsPlayerState extends State<AsdPicsPlayer>
    with WidgetsBindingObserver {
  InAppWebViewController? _wc;
  PullToRefreshController? _ptr;

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 25),
      receiveTimeout: const Duration(minutes: 30),
      followRedirects: true,
      maxRedirects: 10,
      validateStatus: (status) => status != null && status >= 200 && status < 400,
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
      },
    ),
  );

  double _progress = 0;
  bool _fullscreen = false;
  bool _videoPlaying = false;
  bool _inPip = false;
  bool _videoDetected = false;
  bool _nativePlayerActive = false;
  bool _nativePlayerOpening = false;
  bool _nativePauseSentForBackground = false;
  bool _nativeAutoOpenQueued = false;
  bool _preventAutoReopenAfterClose = false;
  bool _botCompleted = false;      
  String? _botConfirmedQuality;    
  String? _botPreferredTargetQuality;
  bool _revealHiddenLaunchUi = false;
  bool _webViewSuspendedForNative = false;
  String? _lastNativePlayerUrl;
  int _nativeOpenTicket = 0;
  int _suppressAutoOpenUntil = 0;
  List<PageQualityOption> _pageQualityOptions = const [];
  List<PageServerOption> _pageServerOptions = const [];
  String? _currentPageQualityLabel;
  String? _currentServerLabel;
  bool _qualitySwitchPending = false;
  bool _manualPlayAfterQualitySwitchPending = false;
  bool _serverSwitchPending = false;
  bool _autoQualityApplied = false;
  bool _qualityDownloadSwitchPending = false;
  final bool _hiddenQualityHarvesting = false;
  final Map<String, String> _qualityDirectUrls = {};
  String? _currentVideoUuid;
  String? _currentVideoFolder;
  String? _currentVideoBaseToken;
  double _pendingNativeStartTime = 0;
  String? _pendingDownloadQualityLabel;
  String? _hiddenHarvestCurrentQuality;
  final Set<String> _harvestedQualityLabels = <String>{};
  final int _qualityHarvestTicket = 0;
  String? _qualityHarvestOriginUrl;
  bool _deferredAdBlockInjected = false;
  bool _deferredAdBlockScheduleActive = false;
  int _cloudflareSafeInjectTicket = 0;

  bool _preferredQualityBotPending = false;
  bool _preferredQualityBotReady = false;
  int _preferredQualityBotStartedAt = 0;
  bool _currentQualityIsPremium = false;

  String? _lastTrusted;
  String? _currentHost;
  String? _currentPageUrl;
  String? _currentPageTitle;
  String? _currentMediaTitle;
  String? _lastStableWatchUrl;
  String? _lastGoodAnimePageUrl;
  final List<String> _animePageHistory = <String>[];
  bool _safeBackInProgress = false;

  String? _capturedVideoUrl;
  double _capturedVideoTime = 0;
  String? _capturedVideoPageUrl;
  String? _capturedVideoMimeType;

  int _videoAspectW = 16;
  int _videoAspectH = 9;

  final List<DownloadItem> _downloads = [];
  Timer? _backgroundDownloadSyncTimer;
  final Set<String> _discoveredDownloadUrls = {};
  final Set<String> _runtimeAllowedHosts = {};
  final List<CapturedMediaItem> _capturedMedia = [];
  final Set<String> _capturedMediaSeen = {};

  bool _showDownloads = false;
  bool _showMediaGrabber = false;
  bool _fullscreenBusy = false;
  String? _lastDetectedMediaUrl;
  String? _lastDetectedMediaType;
  bool _autoDownloadPromptShown = false;
  Rect? _sitePlayerOverlayRect;
  int _sitePlayerRectTrackToken = 0;
  bool _sitePlayerRectTracking = false;
  bool _watchButtonWaitingForCapture = false;
  bool _downloadButtonWaitingForCapture = false;
  int _quickActionCaptureTicket = 0;
  int _blockAnimeQualityPageNavigationUntil = 0;

  static final MethodChannel _pip = MethodChannel(AppSecureText.s('ocxecOv8d7yQIInjeQ'));

  static const String _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/124.0.0.0 Safari/537.36';

  static const _videoExts = [
    '.m3u8', '.mp4', '.mkv', '.webm', '.ts', '.m4v', '.avi', '.mov',
  ];

  static const _dlExts = [
    '.mp4', '.mkv', '.avi', '.mov', '.webm', '.m4v',
  ];

  // ─── FIX 3: Added download site domains to whitelist ───────────────────
  final _white = const [
    "anime3rb.com", "vid3rb.com", "video.vid3rb.com", "files.vid3rb.com", "hglink", "vibuxer", "audinifer", "huntrexus", "hanerix",
    "dood", "doods", "dooood", "ds2play", "d0o0d", "doodstream", "dood.li",
    "uqload", "uqloads", "minochinos", "minomax", "pixibay", "streamtape",
    "stape", "voe.sx", "voeunblok", "voe", "jwplatform", "jwpcdn",
    "akamaized", "cloudfront", "cdnjs.cloudflare", "fonts.googleapis",
    "fonts.gstatic", "kit-pro.fontawesome", "kit-free.fontawesome",
    "static.cloudflareinsights", "vidtube", "1cloudfile", "masukestin",
    "cdn.vidtube", "s3.amazonaws", "googleapis", "gstatic", "bunnycdn",
    "b-cdn", "storage.googleapis", "cdn-tube", "stellarcrestcreative",
    "server-hls2-stream", "server-hls", "cdn-stream", "anime3rb",
    "anime3rb.com", "anime3rb.com",
    // ✅ FIX 3+: Download hosting sites + redirect targets actually used by ArabSeed
    "mega.nz", "mediafire", "1fichier", "uploadrar", "uptobox",
    "usersdrive", "filerio", "clicknupload", "hexupload", "sendcm",
    "dailyuploads", "turbobit", "nitroflare", "rapidgator", "katfile",
    "filefox", "racaty", "gofile", "pixeldrain", "fembed", "mixdrop",
    "reviewrate", "reviewrate.net", "m.reviewrate.net",
    "fredl", "fredl.ru", "frdl",
    "filespayouts", "filespayouts.com",
    "up-4ever", "up-4ever.net", "up4ever",
  ];

  final _blocked = const [
    "pyppo.com", "popcash.net", "popads.net", "popunder.net", "pop.pro",
    "clickunder.net", "trafficshop.com", "plugrush.com", "adcash.com",
    "zeropark.com", "richpush.co", "doubleclick.net", "googlesyndication.com",
    "adservice.google.com", "pagead2.googlesyndication.com",
    "tpc.googlesyndication.com", "adnxs.com", "rubiconproject.com",
    "openx.net", "casalemedia.com", "criteo.com", "taboola.com",
    "outbrain.com", "revcontent.com", "mgid.com", "propellerads.com",
    "hilltopads.net", "exoclick.com", "juicyads.com", "trafficjunky.net",
    "adsterra.com", "bvtpk.com", "b7510.com", "405kk.com", "071kk.com",
    "crummydevioussucculent.com", "yawncollaremotion.com",
    "preferencenail.com", "newshinyd.com", "bobapsoabauns.com",
    "fleraprt.com", "tzegilo.com", "imasdk.googleapis.com",
    "googletagmanager.com", "mc.yandex.ru", "dtscout.com", "dtscdn.com",
    "mrktmtrcs.net", "onaudience.com", "histats.com", "rtmark.net",
    "44555games.com", "trffk.g2afse.com", "tiktokcdn.com", "llvpn.com",
    "affidavitheadfirstonward.com", "omoonsih.net", "jnbhi.com", "oyo4d.com",
    "sourshaped.com", "deductpursue.com", "protrafficinspector.com",
    "tfnvuckb.pro", "waust.at", "whacmoltibsay.net",
    "fundingchoicesmessages.google.com",
    "ads.pubmatic.com", "securepubads.g.doubleclick.net",
  ];

  final _redirectOk = const [
    "anime3rb.com", "vid3rb.com", "video.vid3rb.com", "files.vid3rb.com", "hglink", "vibuxer", "audinifer", "huntrexus", "hanerix",
    "dood", "doods", "ds2play", "d0o0d", "doodstream", "uqload", "uqloads",
    "minochinos", "minomax", "streamtape", "stape", "voe.sx", "voeunblok",
    "voe", "jwplatform", "jwpcdn", "vidtube", "1cloudfile", "masukestin",
    "cdn.vidtube", "s3.amazonaws", "googleapis", "bunnycdn", "b-cdn",
    "cdn-tube", "stellarcrestcreative", "server-hls2-stream", "server-hls",
    "anime3rb", "anime3rb.com", "anime3rb.com",
    "reviewrate", "reviewrate.net", "m.reviewrate.net",
    "fredl", "fredl.ru", "frdl",
    "filespayouts", "filespayouts.com",
    "up-4ever", "up-4ever.net", "up4ever",
  ];

  bool _isVideoUrl(String url) {
    final lower = url.toLowerCase().split('?').first;
    return _videoExts.any((e) => lower.endsWith(e));
  }

  bool _isDownloadUrl(String url) {
    final lower = url.toLowerCase().split('?').first;
    return _dlExts.any((e) => lower.endsWith(e));
  }

  bool _isW(String u) => _white.any((d) => u.contains(d));
  bool _isB(String u) => _blocked.any((d) => u.contains(d));
  bool _canRedir(String u) => _redirectOk.any((d) => u.contains(d));

  String? _hostOf(String? rawUrl) {
    final host = Uri.tryParse(rawUrl ?? '')?.host.toLowerCase();
    if (host == null || host.isEmpty) return null;
    return host;
  }

  void _rememberAllowedHost(String? rawUrl) {
    final host = _hostOf(rawUrl);
    if (host == null) return;
    _runtimeAllowedHosts.add(host);
  }

  bool _isRuntimeAllowed(String? rawUrl) {
    final host = _hostOf(rawUrl);
    if (host == null) return false;
    return _runtimeAllowedHosts.any((allowed) =>
        host == allowed || host.endsWith('.$allowed') || allowed.endsWith('.$host'));
  }

  String? _decodeArabseedRedirect(String? rawUrl) {
    final uri = Uri.tryParse(rawUrl ?? '');
    if (uri == null) return null;
    final host = uri.host.toLowerCase();
    if (!(host.contains('anime3rb.com') || host.contains('anime3rb'))) return null;
    if (uri.pathSegments.isEmpty) return null;
    if (uri.pathSegments.first != 'l') return null;

    try {
      var encoded = uri.pathSegments.last;
      encoded = encoded.replaceAll('-', '+').replaceAll('_', '/');
      while (encoded.length % 4 != 0) {
        encoded += '=';
      }
      final decoded = utf8.decode(base64.decode(encoded), allowMalformed: true).trim();
      if (decoded.startsWith('http://') || decoded.startsWith('https://')) {
        return decoded;
      }
    } catch (_) {}
    return null;
  }

  bool _isLikelyDownloadLandingUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('/downloadz') ||
        lower.contains('/download/') ||
        lower.contains('/l/') ||
        lower.contains('reviewrate') ||
        lower.contains('fredl') ||
        lower.contains('frdl') ||
        lower.contains('filespayouts') ||
        lower.contains('up-4ever') ||
        lower.contains('up4ever');
  }

  String _sanitizeFileName(String input) {
    final clean = input.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
    return clean.isEmpty ? 'video.mp4' : clean;
  }

  String _inferFileName(String url, [String fallback = 'video.mp4']) {
    try {
      final uri = Uri.parse(url);
      final last = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : fallback;
      final decoded = Uri.decodeComponent(last);
      if (decoded.isNotEmpty && decoded.contains('.')) {
        return _sanitizeFileName(decoded);
      }
    } catch (_) {}
    return _sanitizeFileName(fallback);
  }

  String _cleanMediaTitle(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return '';
    value = value.replaceAll(RegExp(r'\s*[|｜\-–—]\s*(anime3rb|anime\s*3rb|انمي\s*عرب|arabseed|asd\s*pics|عرب\s*سيد).*$', caseSensitive: false), ' ');
    value = value.replaceAll(RegExp(r'\b(Anime3rb|Anime\s*3rb|انمي\s*عرب|ArabSeed|ASD\s*Pics)\b', caseSensitive: false), ' ');
    value = value.replaceAll(RegExp(r'\b(مشاهدة|تحميل|اون\s*لاين|أون\s*لاين|كامل|مترجم)\b', caseSensitive: false), ' ');
    value = value.replaceAll(RegExp(r'[_\-]+'), ' ');
    value = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return _sanitizeFileName(value);
  }

  String _fallbackTitleFromUrl([String? rawUrl]) {
    final url = (rawUrl ?? _currentPageUrl ?? _capturedVideoPageUrl ?? '').trim();
    if (url.isEmpty) return '';
    try {
      final uri = Uri.parse(url);
      final segs = uri.pathSegments.where((e) => e.trim().isNotEmpty).toList();
      if (segs.isEmpty) return '';
      var slug = Uri.decodeComponent(segs.last);
      slug = slug.replaceAll(RegExp(r'\.(html?|php)$', caseSensitive: false), '');
      return _cleanMediaTitle(slug);
    } catch (_) {
      return '';
    }
  }

  String _preferredMediaBaseName() {
    for (final candidate in <String?>[_currentMediaTitle, _currentPageTitle, _fallbackTitleFromUrl()]) {
      final clean = _cleanMediaTitle(candidate ?? '');
      if (clean.isNotEmpty) return clean;
    }
    return 'video';
  }

  String _contextualFileName(String url, {String? qualityLabel, String fallbackExt = 'mp4'}) {
    final inferred = _inferFileName(url, 'video.$fallbackExt');
    final dot = inferred.lastIndexOf('.');
    final ext = dot > 0 ? inferred.substring(dot) : '.${fallbackExt.replaceAll('.', '')}';
    final base = _preferredMediaBaseName();
    return _appendQualitySuffixToFileName('$base$ext', qualityLabel);
  }

  Future<void> _refreshCurrentMediaTitle() async {
    if (_wc == null) return;
    try {
      final raw = await _wc!.evaluateJavascript(source: r'''(function(){
        function pick(selectors){
          for (var i = 0; i < selectors.length; i++) {
            var el = document.querySelector(selectors[i]);
            var txt = (el && (el.textContent || el.innerText || '')) ? (el.textContent || el.innerText || '') : '';
            txt = txt.replace(/\s+/g, ' ').trim();
            if (txt && txt.length >= 2 && txt.length <= 180) return txt;
          }
          return '';
        }
        return JSON.stringify({
          mediaTitle: pick(['h1','.entry-title','.single-title','.movie-title','.watch-title','[class*=\"title\"] h1','[class*=\"single\"] h1']),
          pageTitle: (document.title || '').trim()
        });
      })();''');
      String? decoded;
      if (raw is String) {
        decoded = raw;
      } else if (raw != null) {
        decoded = raw.toString();
      }
      if (decoded != null && decoded.isNotEmpty) {
        try {
          final map = jsonDecode(decoded);
          final mediaTitle = _cleanMediaTitle((map['mediaTitle'] ?? '').toString());
          final pageTitle = _cleanMediaTitle((map['pageTitle'] ?? '').toString());
          if (mediaTitle.isNotEmpty) _currentMediaTitle = mediaTitle;
          if (pageTitle.isNotEmpty) _currentPageTitle = pageTitle;
          if (mounted) setState(() {});
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<Directory> _downloadsBaseDir() async {
    if (Platform.isAndroid) {
      final ext = await getExternalStorageDirectory();
      if (ext != null) {
        final dir = Directory('${ext.path}/Videos/Anime');
        if (!await dir.exists()) await dir.create(recursive: true);
        return dir;
      }
    }
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/Videos/Anime');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  String _buildReferer(String downloadUrl) {
    try {
      final host = Uri.parse(downloadUrl).host.toLowerCase();
      if (host.contains('cdn-tube') || host.contains('server-hls') || host.contains('cdn-stream')) {
        return _currentHost != null ? 'https://$_currentHost/' : 'https://anime3rb.com/';
      }
      if (host.contains('1cloudfile')) return 'https://1cloudfile.com/';
      if (host.contains('vidtube')) return 'https://vidtube.one/';
    } catch (_) {}
    if (_currentHost != null) return 'https://$_currentHost/';
    return 'https://anime3rb.com/';
  }

  Map<String, dynamic> _downloadHeaders(String url) {
    return {
      'User-Agent': _ua,
      'Accept': '*/*',
      'Connection': 'keep-alive',
      'Referer': _buildReferer(url),
      'Origin': 'https://${_currentHost ?? 'anime3rb.com'}',
    };
  }

  bool _isVid3rbDirectVideoUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return false;
    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();
    final isVid3rbHost =
        host == 'video.vid3rb.com' ||
        host.endsWith('.video.vid3rb.com') ||
        host == 'vid3rb.com' ||
        host.endsWith('.vid3rb.com');
    return isVid3rbHost && (path == '/video' || path.startsWith('/video/'));
  }

  String _inferInterceptedQualityLabel(String? url, {Map<String, String>? headers}) {
    final lower = (url ?? '').toLowerCase();
    final directMatch = RegExp(
      r'/(2160|1440|1080|720|540|480|360|240)p(?:[._/]|$)',
      caseSensitive: false,
    ).firstMatch(lower);
    if (directMatch != null) {
      return '${directMatch.group(1)}p';
    }

    String headerValue(String name) {
      if (headers == null || headers.isEmpty) return '';
      for (final entry in headers.entries) {
        if (entry.key.toLowerCase() == name.toLowerCase()) {
          return entry.value.trim();
        }
      }
      return '';
    }

    final hinted = _normalizeQualityLabel(
      _pendingDownloadQualityLabel ??
          _hiddenHarvestCurrentQuality ??
          _currentPageQualityLabel ??
          '',
    );
    if (hinted.isNotEmpty) return hinted;

    final referer = headerValue('Referer').toLowerCase();
    final refererMatch = RegExp(
      r'/(2160|1440|1080|720|540|480|360|240)p(?:[._/]|$)',
      caseSensitive: false,
    ).firstMatch(referer);
    if (refererMatch != null) {
      return '${refererMatch.group(1)}p';
    }

    final h = _videoAspectH;
    if (h >= 1800) return '2160p';
    if (h >= 1260) return '1440p';
    if (h >= 900) return '1080p';
    if (h >= 630) return '720p';
    if (h >= 510) return '540p';
    if (h >= 430) return '480p';
    if (h >= 300) return '360p';
    if (h >= 200) return '240p';

    return '';
  }

  bool _looksLikePlayableMediaUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    final lower = url.toLowerCase();
    if (lower.startsWith('blob:')) return false;
    return _isVid3rbDirectVideoUrl(url) ||
        lower.contains('.m3u8') || lower.contains('.mp4') ||
        lower.contains('.mkv') || lower.contains('.webm') ||
        lower.contains('.m4v') || lower.contains('.ts') ||
        lower.contains('.mov') || lower.contains('.mpd') ||
        lower.contains('mime=video') || lower.contains('contenttype=video') ||
        lower.contains('/hls/') || lower.contains('/playlist') ||
        lower.contains('/manifest');
  }

  String? _inferMimeType(String? url, [String? hinted]) {
    final hint = hinted?.toLowerCase().trim();
    if (hint != null && hint.isNotEmpty) return hint;
    final lower = (url ?? '').toLowerCase();
    if (_isVid3rbDirectVideoUrl(url)) return 'video/mp4';
    if (lower.contains('.m3u8')) return 'application/x-mpegURL';
    if (lower.contains('.mpd')) return 'application/dash+xml';
    if (lower.contains('.mp4') || lower.contains('.m4v')) return 'video/mp4';
    if (lower.contains('.webm')) return 'video/webm';
    if (lower.contains('.ts')) return 'video/mp2t';
    if (lower.contains('.mov')) return 'video/quicktime';
    return null;
  }


  bool _isStreamUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    final u = url.toLowerCase();
    return u.contains('.m3u8') ||
        u.contains('.mpd') ||
        u.contains('/manifest') ||
        u.contains('/playlist') ||
        u.contains('/hls/');
  }

  bool _isDirectMediaFile(String? url) {
    if (url == null || url.isEmpty) return false;
    final u = url.toLowerCase().split('?').first;
    return _isVid3rbDirectVideoUrl(url) ||
        u.endsWith('.mp4') ||
        u.endsWith('.mkv') ||
        u.endsWith('.webm') ||
        u.endsWith('.m4v') ||
        u.endsWith('.avi') ||
        u.endsWith('.mov');
  }

  String _mediaKindLabel(CapturedMediaItem item) {
    if (item.qualityLabel != null && item.qualityLabel!.isNotEmpty) {
      return item.qualityLabel!;
    }
    if (item.isDirectFile) return 'Direct';
    if (item.isStream) return 'HLS/DASH';
    return 'Media';
  }

  int _qualityRankLabel(String? label) {
    switch (_normalizeQualityLabel(label ?? '')) {
      case '2160p':
        return 2160;
      case '1440p':
        return 1440;
      case '1080p':
        return 1080;
      case '720p':
        return 720;
      case '540p':
        return 540;
      case '480p':
        return 480;
      case '360p':
        return 360;
      case '240p':
        return 240;
      default:
        return 0;
    }
  }

  String _appendQualitySuffixToFileName(String fileName, String? qualityLabel) {
    final label = _normalizeQualityLabel(qualityLabel ?? '');
    if (label.isEmpty) return _sanitizeFileName(fileName);
    final clean = _sanitizeFileName(fileName);
    final dot = clean.lastIndexOf('.');
    if (dot <= 0) return _sanitizeFileName('${clean}_$label');
    final base = clean.substring(0, dot);
    final ext = clean.substring(dot);
    if (base.endsWith('_$label')) return clean;
    return _sanitizeFileName('${base}_$label$ext');
  }

  List<PageQualityOption> get _sortedQualityOptions {
    final list = List<PageQualityOption>.from(_pageQualityOptions);
    list.sort((a, b) {
      final rank = _qualityRankLabel(b.label).compareTo(_qualityRankLabel(a.label));
      if (rank != 0) return rank;
      return a.label.compareTo(b.label);
    });
    return list;
  }

  PageQualityOption? _bestPreferredQualityOption() {
    if (_pageQualityOptions.isEmpty) return null;
    const preferred = ['1080p', '720p', '480p', '360p', '240p'];
    for (final q in preferred) {
      for (final opt in _sortedQualityOptions) {
        if (_normalizeQualityLabel(opt.label) == q) return opt;
      }
    }
    return _sortedQualityOptions.first;
  }

  bool _sameWatchPage(String? a, [String? b]) {
    final first = (a ?? '').trim();
    final second = (b ?? _currentPageUrl ?? _capturedVideoPageUrl ?? '').trim();
    if (first.isEmpty || second.isEmpty) return false;
    final ua = Uri.tryParse(first);
    final ub = Uri.tryParse(second);
    if (ua == null || ub == null) return first == second;
    return ua.host.toLowerCase() == ub.host.toLowerCase() && ua.path == ub.path;
  }

  CapturedMediaItem? _bestQuickMediaForQuality([String? qualityLabel]) {
    final wanted = _normalizeQualityLabel(qualityLabel ?? '');
    final pool = _capturedMedia.where((item) {
      if (!_sameWatchPage(item.pageUrl)) return false;
      if (wanted.isEmpty) return true;
      return _normalizeQualityLabel(item.qualityLabel ?? '') == wanted;
    }).toList();
    if (pool.isEmpty) return null;
    pool.sort((a, b) {
      if (a.isDirectFile != b.isDirectFile) {
        return b.isDirectFile ? 1 : -1;
      }
      final rank = _qualityRankLabel(b.qualityLabel).compareTo(_qualityRankLabel(a.qualityLabel));
      if (rank != 0) return rank;
      return b.foundAt.compareTo(a.foundAt);
    });
    return pool.first;
  }

  void _addCapturedMedia(
    String url, {
    String? pageUrl,
    String? mimeType,
    String? qualityLabel,
    Map<String, String>? headers,
  }) {
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty) return;
    if (_isYouTubeUrl(cleanUrl)) return;
    if (!_looksLikePlayableMediaUrl(cleanUrl)) return;

    final resolvedPageUrl = (pageUrl != null && pageUrl.isNotEmpty)
        ? pageUrl
        : (_lastTrusted ?? 'https://anime3rb.com/');
    final normalizedQuality = _normalizeQualityLabel(
      qualityLabel ?? _pendingDownloadQualityLabel ?? _hiddenHarvestCurrentQuality ?? _currentPageQualityLabel ?? '',
    );

    final key = '${cleanUrl.toLowerCase()}|${resolvedPageUrl.toLowerCase()}|${normalizedQuality.toLowerCase()}';
    if (_capturedMediaSeen.contains(key)) return;
    _capturedMediaSeen.add(key);

    final mime = _inferMimeType(cleanUrl, mimeType);
    final item = CapturedMediaItem(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      url: cleanUrl,
      pageUrl: resolvedPageUrl,
      fileName: _contextualFileName(cleanUrl, qualityLabel: normalizedQuality),
      foundAt: DateTime.now(),
      isDirectFile: _isDirectMediaFile(cleanUrl),
      isStream: _isStreamUrl(cleanUrl),
      mimeType: mime,
      qualityLabel: normalizedQuality.isEmpty ? null : normalizedQuality,
      headers: headers,
    );

    _capturedMedia.insert(0, item);

    if (item.qualityLabel != null && item.qualityLabel!.isNotEmpty) {
      _harvestedQualityLabels.add(item.qualityLabel!);
    }

    if (_capturedMedia.length > 150) {
      final removed = _capturedMedia.removeLast();
      _capturedMediaSeen.remove(
        '${removed.url.toLowerCase()}|${removed.pageUrl.toLowerCase()}|${_normalizeQualityLabel(removed.qualityLabel ?? '').toLowerCase()}',
      );
    }

    _lastDetectedMediaUrl = cleanUrl;
    _lastDetectedMediaType = mime;

    if (mounted) setState(() {});
  }

  
  bool _isYouTubeUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    final u = url.toLowerCase();
    return u.contains('youtube.com') ||
        u.contains('youtu.be') ||
        u.contains('googlevideo.com') ||
        u.contains('youtube-nocookie.com') ||
        u.contains('ytimg.com');
  }

  bool _isAdResourceUrl(String url) {
    final u = url.toLowerCase();
    if (_isB(url)) return true;
    final adHostHints = <String>[
      'doubleclick.net', 'googlesyndication.com', 'pagead2',
      'googletagmanager.com', 'adnxs.com', 'adnxs',
      'adservice.google.', 'pubmatic.com', 'rubiconproject.com',
      'criteo.com', 'taboola.com', 'outbrain.com', 'revcontent.com',
      'mgid.com', 'propellerads', 'exoclick', 'imasdk',
      'imasdk.googleapis.com', 'gstatic.com/pagead',
      'pagead2.googlesyndication.com',
      'google-analytics.com', 'googleads.', 'e7cod.com',
    ];
    if (widget.launchHidden || widget.downloadOnlyMode) {
      adHostHints.addAll(const [
        'static.cloudflareinsights.com',
        'cloudflareinsights.com',
        'cdn.lordicon.com',
        'lordicon.com',
        'site-assets.fontawesome.com',
        'fonts.googleapis.com',
        'fonts.gstatic.com',
      ]);
    }
    const adPathHints = <String>[
      '/ads/', '/ad/', '/gpt/', 'ad_unit', 'adunit',
      'interstitial', 'rewarded', 'adsbygoogle', '/async/ads',
      '/pagead', 'gpt-ad',
    ];
    return adHostHints.any((h) => u.contains(h)) ||
        adPathHints.any((h) => u.contains(h));
  }

  void _capturePlayableUrl(
    String? rawUrl, {
    String? pageUrl,
    double? currentTime,
    String? mimeType,
    String? qualityLabel,
  }) {
    final url = rawUrl?.trim();
    if (!_looksLikePlayableMediaUrl(url)) return;
    if (_isYouTubeUrl(url)) return;

    final normalizedQuality = _normalizeQualityLabel(
      qualityLabel ?? _pendingDownloadQualityLabel ?? _hiddenHarvestCurrentQuality ?? _currentPageQualityLabel ?? '',
    );

    _addCapturedMedia(
      url!,
      pageUrl: pageUrl,
      mimeType: mimeType,
      qualityLabel: normalizedQuality,
      headers: {
        'User-Agent': _ua,
        'Referer': pageUrl ?? (_lastTrusted ?? 'https://anime3rb.com/'),
      },
    );

    final isHls = url.toLowerCase().contains('.m3u8');
    final current = _capturedVideoUrl?.toLowerCase() ?? '';
    final currentIsHls = current.contains('.m3u8');
    final currentRank = _qualityRankLabel(_currentPageQualityLabel);
    final newRank = _qualityRankLabel(normalizedQuality);
    if (_capturedVideoUrl == null ||
        (isHls && !currentIsHls) ||
        (_capturedVideoUrl?.startsWith('blob:') ?? false) ||
        newRank > currentRank) {
      _capturedVideoUrl = url;
      if (normalizedQuality.isNotEmpty) {
        _currentPageQualityLabel = normalizedQuality;
      }
    }

    _capturedVideoMimeType = _inferMimeType(url, mimeType);
    if (pageUrl != null && pageUrl.isNotEmpty) _capturedVideoPageUrl = pageUrl;
    if (currentTime != null && currentTime >= 0) _capturedVideoTime = currentTime;
    if (mounted && !_videoDetected) setState(() => _videoDetected = true);

    if (_looksLikeHlsManifestUrl(url) && _pageQualityOptions.length < 2) {
      Future.microtask(() async {
        try {
          final headers = await _buildPipHeaders(
            url,
            pageUrl: _capturedVideoPageUrl ?? pageUrl ?? _currentPageUrl ?? _lastTrusted,
          );
          await _prepareBestNativeMediaUrl(url, headers);
        } catch (_) {}
      });
    }

    if (widget.launchHidden &&
        _isBotAcceptedQuality(normalizedQuality) &&
        (_isDirectMediaFile(url) || _isVid3rbDirectVideoUrl(url))) {
      _markBotGateReady('capture_playable', quality: normalizedQuality);
    }

    
    
    if (_allowNativeAutoOpen &&
        !widget.downloadOnlyMode &&
        !_nativePlayerActive &&
        !_nativePlayerOpening &&
        (!widget.launchHidden || _botCompleted)) {
      _tryAutoOpenBestQuickMedia();
    }

    if (_watchButtonWaitingForCapture || _downloadButtonWaitingForCapture) {
      Future.microtask(_tryCompletePendingQuickAction);
    }
  }

  Future<Map<String, String>> _buildPipHeaders(String mediaUrl, {String? pageUrl}) async {
    final referer = (pageUrl != null && pageUrl.isNotEmpty) ? pageUrl : (_lastTrusted ?? 'https://anime3rb.com/');
    String origin = 'https://anime3rb.com';
    try { origin = Uri.parse(referer).origin; } catch (_) {}

    final cookieManager = CookieManager.instance();
    final cookieMap = <String, String>{};

    Future<void> appendCookies(String? url) async {
      if (url == null || url.isEmpty) return;
      try {
        final cookies = await cookieManager.getCookies(url: WebUri(url));
        for (final cookie in cookies) {
          if (cookie.name.isNotEmpty) cookieMap[cookie.name] = cookie.value;
        }
      } catch (_) {}
    }

    await appendCookies(pageUrl);
    await appendCookies(mediaUrl);

    final headers = <String, String>{
      'User-Agent': _ua, 'Accept': '*/*', 'Connection': 'keep-alive',
      'Referer': referer, 'Origin': origin,
    };
    if (cookieMap.isNotEmpty) {
      headers['Cookie'] = cookieMap.entries.map((e) => '${e.key}=${e.value}').join('; ');
    }
    return headers;
  }

  bool _looksLikeHlsManifestUrl(String? url) {
    final value = (url ?? '').toLowerCase();
    return value.contains('.m3u8');
  }

  List<String> _buildHlsManifestCandidates(String mediaUrl) {
    final uri = Uri.tryParse(mediaUrl);
    if (uri == null || uri.pathSegments.isEmpty) return <String>[mediaUrl];

    final names = <String>[
      'master.m3u8',
      'playlist.m3u8',
      'manifest.m3u8',
      'index.m3u8',
      'main.m3u8',
    ];
    final candidates = <String>[];
    final seen = <String>{};

    void addFrom(List<String> baseSegments, String fileName, {bool encode = false}) {
      var segment = fileName;
      if (encode) {
        segment = '${base64.encode(utf8.encode(fileName))}.m3u8';
      }
      final url = uri.replace(pathSegments: [...baseSegments, segment]).toString();
      if (seen.add(url)) candidates.add(url);
    }

    final segs = List<String>.from(uri.pathSegments);
    if (seen.add(mediaUrl)) candidates.add(mediaUrl);

    for (final depth in <int>[1, 2]) {
      if (segs.length <= depth) continue;
      final base = segs.sublist(0, segs.length - depth);
      for (final name in names) {
        addFrom(base, name, encode: true);
        addFrom(base, name, encode: false);
      }
    }

    return candidates;
  }

  bool _playlistLooksLikeMaster(String body) {
    final value = body.toUpperCase();
    return value.contains('#EXT-X-STREAM-INF') ||
        value.contains('#EXT-X-MEDIA:TYPE=SUBTITLES') ||
        value.contains('#EXT-X-I-FRAME-STREAM-INF');
  }

  Future<String?> _fetchPlaylistBody(String url, Map<String, String> headers) async {
    try {
      final response = await _dio.get<String>(
        url,
        options: Options(
          headers: headers,
          responseType: ResponseType.plain,
          validateStatus: (status) => status != null && status >= 200 && status < 400,
          receiveTimeout: const Duration(seconds: 8),
        ),
      );
      final body = response.data?.toString();
      return (body == null || body.trim().isEmpty) ? null : body;
    } catch (_) {
      return null;
    }
  }

  String _resolvePlaylistUrl(String baseUrl, String rawValue) {
    final value = rawValue.trim();
    if (value.isEmpty) return value;
    final uri = Uri.tryParse(value);
    if (uri != null && uri.hasScheme) return uri.toString();
    final base = Uri.tryParse(baseUrl);
    if (base == null) return value;
    return base.resolve(value).toString();
  }

  Map<String, String> _parseM3uAttributes(String line) {
    final out = <String, String>{};
    final idx = line.indexOf(':');
    final raw = idx >= 0 ? line.substring(idx + 1) : line;
    final regex = RegExp(r'([A-Z0-9-]+)=((?:"[^"]*")|[^,]*)');
    for (final m in regex.allMatches(raw)) {
      final key = (m.group(1) ?? '').trim();
      var value = (m.group(2) ?? '').trim();
      if (value.startsWith('"') && value.endsWith('"') && value.length >= 2) {
        value = value.substring(1, value.length - 1);
      }
      if (key.isNotEmpty) out[key] = value;
    }
    return out;
  }

  void _applyOptionsFromHlsMaster(String masterUrl, String body) {
    final lines = body.split(RegExp(r'\r?\n'));
    final qualityOptions = <PageQualityOption>[];
    final seen = <String>{};

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (!line.startsWith('#EXT-X-STREAM-INF:')) continue;
      final attrs = _parseM3uAttributes(line);
      String? nextUrl;
      for (var j = i + 1; j < lines.length; j++) {
        final candidate = lines[j].trim();
        if (candidate.isEmpty) continue;
        if (!candidate.startsWith('#')) {
          nextUrl = candidate;
          break;
        }
      }
      if (nextUrl == null || nextUrl.trim().isEmpty) continue;

      final resolved = _resolvePlaylistUrl(masterUrl, nextUrl);
      final resolution = attrs['RESOLUTION'] ?? '';
      final heightMatch = RegExp(r'\d+x(\d+)', caseSensitive: false).firstMatch(resolution);
      final label = heightMatch != null
          ? '${heightMatch.group(1)}p'
          : ((attrs['NAME']?.trim().isNotEmpty == true) ? attrs['NAME']!.trim() : 'Auto');
      final normalized = _normalizeQualityLabel(label);
      if (normalized.isEmpty) continue;
      final dedupe = '${normalized.toLowerCase()}|${resolved.toLowerCase()}';
      if (!seen.add(dedupe)) continue;

      qualityOptions.add(PageQualityOption(
        label: normalized,
        key: 'hls_${normalized.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}_${qualityOptions.length}',
        url: resolved,
        selected: qualityOptions.isEmpty,
      ));
    }

    if (qualityOptions.isEmpty) return;

    qualityOptions.sort((a, b) => _qualityRankLabel(b.label).compareTo(_qualityRankLabel(a.label)));
    final preferredCurrent = _normalizeQualityLabel(_currentPageQualityLabel ?? '');
    _updatePageQualityOptions(
      qualityOptions,
      preferredCurrent.isNotEmpty ? preferredCurrent : qualityOptions.first.label,
    );

    if (_nativePlayerActive) {
      _pip.invokeMethod('updateQualityOptions', {
        'qualityOptions': _pageQualityOptions.map((e) => e.toMap()).toList(),
        'currentQualityLabel': _currentPageQualityLabel,
      }).catchError((_) {});
    }
  }

  Future<String> _prepareBestNativeMediaUrl(String mediaUrl, Map<String, String> headers) async {
    if (!_looksLikeHlsManifestUrl(mediaUrl)) return mediaUrl;

    final candidates = _buildHlsManifestCandidates(mediaUrl);
    for (final candidate in candidates) {
      final body = await _fetchPlaylistBody(candidate, headers);
      if (body == null) continue;
      if (_playlistLooksLikeMaster(body)) {
        _applyOptionsFromHlsMaster(candidate, body);
        return candidate;
      }
    }

    return mediaUrl;
  }

  Future<void> _ensureDownloadQualityChoicesReady() async {
    if (_pageQualityOptions.isNotEmpty) return;

    final candidate = (_bestQuickMedia?.url ?? _capturedVideoUrl ?? '').trim();
    if (!_looksLikeHlsManifestUrl(candidate)) return;

    final pageUrl = (_bestQuickMedia?.pageUrl ?? _capturedVideoPageUrl ?? _currentPageUrl ?? '').trim();
    try {
      final headers = await _buildPipHeaders(
        candidate,
        pageUrl: pageUrl.isEmpty ? null : pageUrl,
      );
      await _prepareBestNativeMediaUrl(candidate, headers);
    } catch (_) {}

    if (_pageQualityOptions.isNotEmpty) return;

    final normalized = _normalizeQualityLabel(
      _bestQuickMedia?.qualityLabel ?? _currentPageQualityLabel ?? '',
    );
    if (normalized.isEmpty) return;

    _updatePageQualityOptions(
      [
        PageQualityOption(
          label: normalized,
          key: 'captured_${normalized.toLowerCase()}',
          url: candidate,
          selected: true,
        ),
      ],
      normalized,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Stealth ad blocker — injected at DOCUMENT_START
  // ─────────────────────────────────────────────────────────────────────────
  static const String _stealthAdBlock = r"""
(function(){
  'use strict';
  if (window.__asdSABv2) return;
  window.__asdSABv2 = true;

  var fakeSlot = {
    addService: function(){ return fakeSlot; },
    defineSizeMapping: function(){ return fakeSlot; },
    setTargeting: function(){ return fakeSlot; },
    setCollapseEmptyDiv: function(){ return fakeSlot; },
    getSlotElementId: function(){ return 'div-gpt-ad-fake'; },
    getAdUnitPath: function(){ return '/fake/ad'; },
    getResponseInformation: function(){ return null; }
  };

  var fakePubads = {
    enableSingleRequest: function(){},
    setTargeting: function(){ return fakePubads; },
    refresh: function(){},
    clear: function(){ return true; },
    addEventListener: function(){},
    removeEventListener: function(){},
    collapseEmptyDivs: function(){},
    enableLazyLoad: function(){},
    disableInitialLoad: function(){},
    setPrivacySettings: function(){},
    updateCorrelator: function(){},
    getTargeting: function(){ return []; },
    getTargetingKeys: function(){ return []; }
  };

  var fakeSizeMapping = {
    addSize: function(){ return fakeSizeMapping; },
    build: function(){ return []; }
  };

  if (!window.googletag || !window.googletag._asdFaked) {
    window.googletag = {
      _asdFaked: true,
      cmd: [],
      defineSlot: function(){ return fakeSlot; },
      defineOutOfPageSlot: function(){ return fakeSlot; },
      pubads: function(){ return fakePubads; },
      enableServices: function(){},
      display: function(){},
      destroySlots: function(){ return true; },
      sizeMapping: function(){ return fakeSizeMapping; },
      companionAds: function(){ return { enableSyncLoading: function(){}, setRefreshUnfilledSlots: function(){} }; }
    };
    window.googletag.cmd.push = function(fn){
      try { if (typeof fn === 'function') fn(); } catch(e) {}
    };
  }

  if (!window.adsbygoogle) { window.adsbygoogle = []; }
  window.adsbygoogle.loaded = true;
  window.adsbygoogle.push = function(cfg){ Array.prototype.push.call(window.adsbygoogle, cfg); };

  window._taboola = window._taboola || [];
  window._taboola.push = function(){};
  window.OBR = window.OBR || { extern: { renderST: function(){} } };
  window.OutbrainPerf = window.OutbrainPerf || { mark: function(){} };
  window.ExoLoader = window.ExoLoader || { serve: function(){}, load: function(){} };
  window.propellerads = window.propellerads || { push: function(){} };
  window.popns = window.popns || function(){};
  window.IABConsent_CMPPresent = true;
  window.__tcfapi = window.__tcfapi || function(cmd, ver, cb){ try { cb({}, true); } catch(e) {} };
  window.__cmp = window.__cmp || function(cmd, arg, cb){ try { cb({}, true); } catch(e) {} };

  var _adDomains = [
    'pagead2','googlesyndication','doubleclick.net',
    'adnxs','exoclick','juicyads','adsterra',
    'propellerads','popcash','popads','trafficjunky',
    'hilltopads','adcash','zeropark','richpush',
    'revcontent','mgid','rubiconproject','openx','criteo',
    'bvtpk','b7510','oyo4d','omoonsih','jnbhi','sourshaped',
    'tfnvuckb','rtmark','fundingchoicesmessages','imasdk',
    'popunder','clickunder','trafficshop','plugrush'
  ];

  function _isAdDomain(url) {
    if (!url) return false;
    var s = (url + '').toLowerCase();
    return _adDomains.some(function(d){ return s.indexOf(d) !== -1; });
  }

  // ✅ FIX 1: Block location.href navigation to ad domains from inside iframes
  try {
    if (window !== window.top) {
      var _origAssign = window.location.assign.bind(window.location);
      var _origReplace = window.location.replace.bind(window.location);
      
      window.location.assign = function(url) {
        if (_isAdDomain(url ? url.toString() : '')) return;
        _origAssign(url);
      };
      window.location.replace = function(url) {
        if (_isAdDomain(url ? url.toString() : '')) return;
        _origReplace(url);
      };
      
      // Block top-frame navigation from iframe
      try {
        Object.defineProperty(window, 'top', {
          configurable: true,
          get: function() {
            return new Proxy(window.parent, {
              get: function(target, prop) {
                if (prop === 'location') {
                  return new Proxy({href: ''}, {
                    set: function(t, p, v) {
                      if (p === 'href' && _isAdDomain(v ? v.toString() : '')) return true;
                      return true; // silently block all top.location.href assignments
                    },
                    get: function(t, p) {
                      try { return target.location[p]; } catch(e) { return t[p]; }
                    }
                  });
                }
                try { return target[prop]; } catch(e) { return undefined; }
              }
            });
          }
        });
      } catch(e) {}
    }
  } catch(e) {}

  var _origCreateElement = document.createElement.bind(document);
  document.createElement = function(tagName) {
    var el = _origCreateElement(tagName);
    var tag = (tagName + '').toLowerCase();
    if (tag === 'script' || tag === 'iframe') {
      var _origSetAttr = el.setAttribute.bind(el);
      el.setAttribute = function(attr, val) {
        if ((attr === 'src' || attr === 'data-src') && _isAdDomain(val)) {
          el._asdBlocked = true; return;
        }
        _origSetAttr(attr, val);
      };
      try {
        Object.defineProperty(el, 'src', {
          configurable: true,
          set: function(val) {
            if (_isAdDomain(val)) { el._asdBlocked = true; return; }
            _origSetAttr('src', val);
          },
          get: function() { return el.getAttribute('src') || ''; }
        });
      } catch(e) {}
    }
    return el;
  };

  var _origFetch = window.fetch;
  if (_origFetch && !window.__asdSABFetch) {
    window.__asdSABFetch = true;
    window.fetch = function(input, init) {
      var url = (typeof input === 'string' ? input : (input && input.url) || '').toString();
      if (_isAdDomain(url)) {
        return Promise.resolve(new Response('/* ok */', {
          status: 200, headers: { 'Content-Type': 'text/javascript' }
        }));
      }
      return _origFetch.apply(window, arguments);
    };
  }

  var _origGCS = window.getComputedStyle;
  window.getComputedStyle = function(el, pseudo) {
    var style = _origGCS.call(window, el, pseudo);
    try {
      var cls = ((el.className || '') + ' ' + (el.id || '')).toString().toLowerCase();
      if (/adsbox|ad-placement|ads-placeholder|adsbygoogle|ad_unit|ad-slot|adnxs/i.test(cls)) {
        return new Proxy(style, {
          get: function(t, p) {
            if (p === 'height')     return '90px';
            if (p === 'display')    return 'block';
            if (p === 'visibility') return 'visible';
            if (p === 'opacity')    return '1';
            var v = t[p];
            return typeof v === 'function' ? v.bind(t) : v;
          }
        });
      }
    } catch(e) {}
    return style;
  };

  var _antiPhrases = [
    'adblock', 'ad block', 'adblocker', 'ad blocker',
    'disable your ad', 'turn off your ad', 'whitelist',
    'please allow ads', 'please disable', 'detected ad',
    'يرجى إيقاف', 'إيقاف مانع', 'تعطيل مانع'
  ];

  function _hasAntiPhrase(text) {
    var t = text.toLowerCase();
    return _antiPhrases.some(function(p){ return t.indexOf(p) !== -1; });
  }

  function _nukeAntiAdblock() {
    var sel = [
      '[class*="adblock"],[id*="adblock"]',
      '[class*="ad-block"],[id*="ad-block"]',
      '[class*="adblocker"],[id*="adblocker"]',
      '[class*="anti-ad"],[id*="anti-ad"]',
      '[class*="blockad"],[id*="blockad"]',
      '.ab-modal,.ab-overlay,.adblock-notice,.adBlockNotice',
      '#adblock-warning,#ab-warning,#adblock-overlay'
    ].join(',');
    try { document.querySelectorAll(sel).forEach(function(el){ try { el.remove(); } catch(e) {} }); } catch(e) {}
    try {
      var all = document.querySelectorAll('div,section,aside,dialog,article,span');
      for (var i = 0; i < all.length; i++) {
        var el = all[i];
        try {
          var cs = _origGCS.call(window, el);
          var zIdx = parseInt(cs.zIndex || '0');
          var isOverlay = (cs.position === 'fixed' || cs.position === 'absolute') &&
                          zIdx > 999 && cs.display !== 'none';
          if (!isOverlay) continue;
          var txt = (el.textContent || '');
          if (txt.length > 10 && txt.length < 2000 && _hasAntiPhrase(txt)) { el.remove(); }
        } catch(e) {}
      }
    } catch(e) {}
    try {
      if (document.body && !window.__asdForcedFs && !document.fullscreenElement) {
        var bs = _origGCS.call(window, document.body);
        if (bs.overflow === 'hidden') { document.body.style.removeProperty('overflow'); }
      }
    } catch(e) {}
  }

  function _bakeBaits() {
    try {
      document.querySelectorAll('.adsbox,#adsbox,.ad-placement,#ad-placement,.ads,.ad-unit,ins.adsbygoogle').forEach(function(el){
        if (el.offsetHeight === 0) {
          el.style.cssText += ';height:1px!important;display:block!important;visibility:visible!important;';
        }
      });
    } catch(e) {}
  }

  [300, 800, 1500, 3000, 6000].forEach(function(ms){ setTimeout(_nukeAntiAdblock, ms); });
  setTimeout(_bakeBaits, 600);
  setTimeout(_bakeBaits, 2000);

  try {
    new MutationObserver(function(muts) {
      var hasNew = muts.some(function(m){ return m.addedNodes.length > 0; });
      if (hasNew) { setTimeout(_nukeAntiAdblock, 50); setTimeout(_nukeAntiAdblock, 200); }
    }).observe(document.documentElement, { childList: true, subtree: true });
  } catch(e) {}
})();
""";

  // ══════════════════════════════════════════════════════════
  
  
  
  
  // ══════════════════════════════════════════════════════════
  // ══════════════════════════════════════════════════════════════════
  
  //
  
  
  
  //
  
  
  
  
  
  // ══════════════════════════════════════════════════════════════════
  // ══════════════════════════════════════════════════════════════════
  
  
  
  //
  
  
  
  
  
  // ══════════════════════════════════════════════════════════════════
  static const String _cloudflareChallengeProbe = r"""
(function(){
  try {
    var title = (document.title || '').toLowerCase();
    var body = ((document.body && document.body.innerText) || '').toLowerCase();
    var href = (location.href || '').toLowerCase();

    if (href.indexOf('/cdn-cgi/challenge-platform/') !== -1) return true;
    if (href.indexOf('/cdn-cgi/challenge-platform') !== -1) return true;
    if (title.indexOf('just a moment') !== -1) return true;
    if (title.indexOf('checking your browser') !== -1) return true;
    if (body.indexOf('checking your browser') !== -1) return true;
    if (body.indexOf('just a moment') !== -1 && body.indexOf('cloudflare') !== -1) return true;
    if (body.indexOf('verify you are human') !== -1 && body.indexOf('cloudflare') !== -1) return true;
    if (body.indexOf('تأكد من أنك إنسان') !== -1) return true;
    if (body.indexOf('تحقق من أنك إنسان') !== -1) return true;

    var selectors = [
      '#challenge-running',
      '#cf-challenge-running',
      '#cf-please-wait',
      '#turnstile-wrapper',
      '.cf-browser-verification',
      '.cf-challenge',
      '.cf-turnstile',
      'iframe[src*="challenges.cloudflare.com"]',
      'script[src*="/cdn-cgi/challenge-platform/"]'
    ];

    for (var i = 0; i < selectors.length; i++) {
      if (document.querySelector(selectors[i])) return true;
    }

    return false;
  } catch(e) {
    return false;
  }
})();
""";

  static const String _desktopViewport = r"""
(function(){
  var existing = document.querySelector('meta[name=\"viewport\"]');
  if (existing) existing.remove();
  var m = document.createElement('meta');
  m.name = 'viewport';
  m.content = 'width=device-width, initial-scale=1.0, maximum-scale=5.0, user-scalable=yes';
  (document.head || document.documentElement).appendChild(m);
})();
""";

  // ✅ FIX 3: _hideServers — now skips download pages entirely
  static const String _hideServers = r"""
(function(){
  // ✅ FIX: Don't run on download pages — they need to show file hosting links
  var href = window.location.href.toLowerCase();
  var path = window.location.pathname.toLowerCase();
  if (href.indexOf('category/download') !== -1 ||
      href.indexOf('/downloadz') !== -1 ||
      path.indexOf('/downloadz') !== -1 ||
      path.indexOf('download') !== -1) {
    return;
  }

  var removedServers = [
    'mediafire','4shared','zippyshare','uploadrar','uptobox',
    'usersdrive','filerio','clicknupload','hexupload','sendcm',
    'dailyuploads','turbobit','nitroflare','rapidgator','katfile','filefox',
    'uploaded','mega.nz','google drive'
  ];

  function hideServerLinks() {
    // ✅ FIX: Narrowed selector — don't match [class*="download"] which hides everything
    var links = document.querySelectorAll('a, button, [class*="server"], [class*="link-server"]');
    links.forEach(function(el) {
      var text = (el.textContent || el.innerText || '').toLowerCase();
      var href = (el.href || el.getAttribute('data-link') || el.getAttribute('data-url') || '').toLowerCase();
      var matched = removedServers.some(function(s) { return text.includes(s) || href.includes(s); });
      if (matched) el.style.setProperty('display','none','important');
    });
  }

  hideServerLinks();
  setInterval(hideServerLinks, 1000);
})();
""";

  static const String _css = r"""
(function(){
  var s=document.createElement('style');
  s.textContent=`
    .jw-dialog,.jw-dialog-overlay,
    [class*="ad-dialog"],[id*="ad-dialog"],
    [class*="popup"]:not([class*="player"]):not([class*="video"]):not([class*="jw"]):not([class*="vjs"]):not([class*="plyr"]),
    [id*="popup"]:not([id*="player"]):not([id*="video"]):not([id*="jw"]):not([id*="vjs"]),
    .play-overlay-ad,.ad-overlay,
    [class*="ad-overlay"],[class*="adOverlay"],
    .uq-ad,.uq-overlay,#outbrain_widget,.OUTBRAIN,
    [id*="taboola"],[class*="taboola"],
    [id*="adnxs"],[class*="adnxs"],
    [id*="exo_"],[class*="exo-"],
    [id*="pop_"],[class*="pop-up"],
    [id*="overlay_ad"],[class*="overlay_ad"],
    .content-locker,.link-locker,
    [class*="locker"],[id*="locker"]{
      display:none!important;visibility:hidden!important;
      opacity:0!important;pointer-events:none!important;}
  `;
  (document.head||document.documentElement).appendChild(s);
})();
""";




  static const String _forceAnime3rbNightMode = r"""
(function(){
  'use strict';

  function saveDarkPrefs() {
    try { localStorage.setItem('theme', 'dark'); } catch(e) {}
    try { localStorage.setItem('darkMode', 'true'); } catch(e) {}
    try { localStorage.setItem('nightMode', 'true'); } catch(e) {}
    try { localStorage.setItem('anime3rb-theme', 'dark'); } catch(e) {}
    try { localStorage.setItem('color-theme', 'dark'); } catch(e) {}
    try { localStorage.setItem('mode', 'dark'); } catch(e) {}
    try { document.cookie = 'theme=dark; path=/; max-age=31536000'; } catch(e) {}
    try { document.cookie = 'darkMode=true; path=/; max-age=31536000'; } catch(e) {}
  }

  function installDarkCss() {
    try {
      if (document.getElementById('__asd_force_anime3rb_dark')) return;

      var st = document.createElement('style');
      st.id = '__asd_force_anime3rb_dark';
      st.textContent = `
        html, body {
          background: #0f1720 !important;
          color: #e5e7eb !important;
        }

        body,
        body > div,
        main,
        section,
        article,
        aside,
        header,
        nav,
        footer,
        .container,
        .content,
        .page,
        .site,
        .app,
        .wrapper,
        [class*="bg-white"],
        [class*="bg-light"],
        [class*="background"],
        [class*="surface"],
        [class*="card"],
        [class*="box"],
        [class*="section"] {
          background-color: #0f1720 !important;
          color: #e5e7eb !important;
        }

        .bg-white,
        .bg-light,
        .text-dark,
        [style*="background: white"],
        [style*="background-color: white"],
        [style*="background:#fff"],
        [style*="background-color:#fff"],
        [style*="background: #fff"],
        [style*="background-color: #fff"] {
          background-color: #111827 !important;
          color: #e5e7eb !important;
        }

        h1,h2,h3,h4,h5,h6,p,span,div,a,li,label,small,strong {
          color: inherit;
        }

        a {
          color: #93c5fd !important;
        }

        input,
        textarea,
        select {
          background: #111827 !important;
          color: #ffffff !important;
          border-color: #374151 !important;
        }

        button,
        [role="button"] {
          color: inherit;
        }

        img,
        video,
        iframe {
          background-color: transparent !important;
        }
      `;

      (document.head || document.documentElement).appendChild(st);
    } catch(e) {}
  }

  function applyDark() {
    try {
      saveDarkPrefs();
      document.documentElement.classList.add('dark');
      document.documentElement.classList.add('dark-mode');
      document.documentElement.classList.add('night-mode');
      if (document.body) {
        document.body.classList.add('dark');
        document.body.classList.add('dark-mode');
        document.body.classList.add('night-mode');
      }
      installDarkCss();
    } catch(e) {}
  }

  applyDark();

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', applyDark, {once:false});
  }

  [50, 150, 350, 700, 1200, 2200, 4000].forEach(function(ms){
    setTimeout(applyDark, ms);
  });

  window.__asdForceAnime3rbNightMode = applyDark;
})();
""";

  static const String _ads = r"""
(function(){
  'use strict';

  var adDomains = [
    'popads','popcash','adcash','doubleclick','googlesyndication',
    'adnxs','exoclick','juicyads','adsterra','propellerads',
    'trafficjunky','hilltopads','richpush','zeropark','revcontent',
    'taboola','outbrain','mgid','rubiconproject','openx','criteo',
    'b7510','oyo4d','bvtpk','omoonsih','jnbhi','sourshaped',
    'tfnvuckb','waust','whacmoltibsay','rtmark','fundingchoices',
    'popunder','clickunder','trafficshop','plugrush','imasdk'
  ];

  function isAdUrl(url) {
    if (!url) return true;
    return adDomains.some(function(d){ return url.indexOf(d) !== -1; });
  }

  var _origOpen = window.open;
  window.open = function(url, target, features) {
    if (isAdUrl(url ? url.toString() : '')) return null;
    return _origOpen ? _origOpen.call(window, url, target, features) : null;
  };

  // ✅ FIX 1: Also block location navigation to ad URLs
  try {
    var _origAssign = window.location.assign.bind(window.location);
    window.location.assign = function(url) {
      if (isAdUrl(url ? url.toString() : '')) return;
      _origAssign(url);
    };
  } catch(e) {}

  window.alert = function(){};
  window.confirm = function(){ return false; };
  window.prompt = function(){ return null; };
})();
""";

  static const String _forcePhoneFullscreen = r"""
(function(){
  if (window.__asdForceFsInstalled) return;
  window.__asdForceFsInstalled = true;
  window.__asdForcedFs = false;

  var style = document.createElement('style');
  style.textContent = `
    html.asd-phone-fs,
    body.asd-phone-fs{
      width:100%!important;height:100%!important;
      overflow:hidden!important;background:#000!important;
      margin:0!important;padding:0!important;
    }
    .asd-fs-parent{
      position:fixed!important;inset:0!important;
      width:100vw!important;height:100vh!important;
      max-width:100vw!important;max-height:100vh!important;
      margin:0!important;padding:0!important;transform:none!important;
      z-index:2147483645!important;overflow:hidden!important;
      background:#000!important;border:none!important;border-radius:0!important;
    }
    .asd-fs-target,
    .asd-fs-target iframe,
    .asd-fs-target video,
    .asd-fs-target .jwplayer,
    .asd-fs-target .jw-video,
    .asd-fs-target .jw-media,
    .asd-fs-target .video-js,
    .asd-fs-target .vjs-tech,
    .asd-fs-target .plyr,
    .asd-fs-target .plyr__video-wrapper,
    .asd-fs-target .dplayer,
    .asd-fs-target .mejs-container{
      position:fixed!important;inset:0!important;
      width:100vw!important;height:100vh!important;
      max-width:100vw!important;max-height:100vh!important;
      min-width:100vw!important;min-height:100vh!important;
      margin:0!important;padding:0!important;transform:none!important;
      z-index:2147483647!important;background:#000!important;
      border:none!important;border-radius:0!important;
      aspect-ratio:auto!important;box-sizing:border-box!important;
    }
    .asd-fs-target video,
    .asd-fs-target .jw-video,
    .asd-fs-target .vjs-tech{
      object-fit:contain!important;background:#000!important;
    }
    .asd-fs-target .jw-controlbar,
    .asd-fs-target .jw-controls,
    .asd-fs-target .jw-button-container,
    .asd-fs-target .jw-icon,
    .asd-fs-target .jw-slider-container,
    .asd-fs-target .jw-display-icon-container,
    .asd-fs-target .jw-display,
    .asd-fs-target .jw-display-container,
    .asd-fs-target .vjs-control-bar,
    .asd-fs-target .vjs-big-play-button,
    .asd-fs-target .vjs-control,
    .asd-fs-target .vjs-slider,
    .asd-fs-target .plyr__controls,
    .asd-fs-target .plyr__control,
    .asd-fs-target .dplayer-controller,
    .asd-fs-target .dplayer-bar,
    .asd-fs-target .dplayer-icons,
    .asd-fs-target .mejs__controls,
    .asd-fs-target [class*="controlbar"],
    .asd-fs-target [class*="control-bar"],
    .asd-fs-target [class*="controls"] {
      pointer-events: auto !important;
      z-index: 2147483647 !important;
    }
    .asd-phone-fs .jwplayer.jw-flag-user-inactive .jw-controlbar,
    .asd-phone-fs .jwplayer.jw-flag-user-inactive .jw-controls {
      opacity: 0;
      visibility: hidden;
      transition: opacity 0.3s ease, visibility 0.3s ease;
    }
    .asd-fs-hide{
      opacity:0!important;visibility:hidden!important;
      pointer-events:none!important;
    }
  `;
  (document.head || document.documentElement).appendChild(style);

  var currentTarget = null;
  var _stickyWanted = false;
  var _explicitExit = false;
  var _reenterTimer = null;

  function fl(name, value) {
    try { window.flutter_inappwebview.callHandler(name, value); } catch(e) {}
  }

  function nativeFsActive() {
    return !!(document.fullscreenElement || document.webkitFullscreenElement);
  }

  function isVisible(el) {
    if (!el || !el.getBoundingClientRect) return false;
    var r = el.getBoundingClientRect();
    return r.width > 120 && r.height > 80;
  }

  function hasActiveTarget() {
    return !!(currentTarget && document.contains(currentTarget) && isVisible(currentTarget));
  }

  function pickTarget() {
    var selectors = [
      '.jwplayer','.video-js','.plyr','.dplayer','.mejs-container',
      '#player','[id*="player"]','[class*="player"]','iframe[src]','video'
    ];
    for (var i = 0; i < selectors.length; i++) {
      var els = document.querySelectorAll(selectors[i]);
      for (var j = 0; j < els.length; j++) {
        var el = els[j];
        if (!isVisible(el)) continue;
        if (el.tagName === 'IFRAME' || el.tagName === 'VIDEO' ||
            el.querySelector('video') || el.querySelector('iframe') ||
            selectors[i] === '.jwplayer' || selectors[i] === '.video-js' ||
            selectors[i] === '.plyr' || selectors[i] === '.dplayer') {
          return el;
        }
      }
    }
    var biggest = null, biggestArea = 0;
    var all = document.querySelectorAll('div,section,article,iframe,video');
    for (var k = 0; k < all.length; k++) {
      var node = all[k];
      var rect = node.getBoundingClientRect ? node.getBoundingClientRect() : null;
      if (!rect) continue;
      var area = rect.width * rect.height;
      if (rect.width > 180 && rect.height > 120 && area > biggestArea) {
        if (node.tagName === 'VIDEO' || node.tagName === 'IFRAME' ||
            node.querySelector('video') || node.querySelector('iframe') ||
            /player|video|embed|jw|plyr|vjs/i.test((node.id||'')+' '+(node.className||''))) {
          biggest = node; biggestArea = area;
        }
      }
    }
    return biggest;
  }

  function markParents(el) {
    var p = el && el.parentElement, count = 0;
    while (p && p !== document.body && count < 6) {
      p.classList.add('asd-fs-parent'); count++; p = p.parentElement;
    }
  }

  function unmarkParents(el) {
    var p = el && el.parentElement, count = 0;
    while (p && p !== document.body && count < 6) {
      p.classList.remove('asd-fs-parent'); count++; p = p.parentElement;
    }
  }

  function hidePageNoise(enable) {
    var blocks = document.querySelectorAll(
      'header:not([class*="player"]):not([class*="jw"]):not([class*="vjs"]), ' +
      'footer:not([class*="player"]):not([class*="jw"]), ' +
      'nav.navbar, nav.nav, .site-header, .site-footer, ' +
      '.sidebar:not([class*="player"]), ' +
      '.social-share, .share-buttons, ' +
      '.cookie-banner, .gdpr-banner'
    );
    blocks.forEach(function(el){
      if (enable) el.classList.add('asd-fs-hide');
      else el.classList.remove('asd-fs-hide');
    });
  }

  function applyForcedState() {
    if (!currentTarget) return false;
    window.__asdForcedFs = true;
    document.documentElement.classList.add('asd-phone-fs');
    if (document.body) document.body.classList.add('asd-phone-fs');
    currentTarget.classList.add('asd-fs-target');
    markParents(currentTarget);
    hidePageNoise(true);
    fl('onForcePhoneFs', true);
    return true;
  }

  function clearForcedState() {
    window.__asdForcedFs = false;
    document.documentElement.classList.remove('asd-phone-fs');
    if (document.body) document.body.classList.remove('asd-phone-fs');
    hidePageNoise(false);
    if (currentTarget) {
      currentTarget.classList.remove('asd-fs-target');
      unmarkParents(currentTarget);
    }
    currentTarget = null;
    fl('onForcePhoneFs', false);
  }

  function scheduleReenter(delay) {
    if (_explicitExit || !_stickyWanted) return;
    if (_reenterTimer) clearTimeout(_reenterTimer);
    _reenterTimer = setTimeout(function() {
      _reenterTimer = null;
      if (_explicitExit || !_stickyWanted) return;
      if (!hasActiveTarget()) currentTarget = pickTarget() || currentTarget;
      if (currentTarget) applyForcedState();
    }, delay || 60);
  }

  function enterForcedPhoneFs() {
    currentTarget = pickTarget() || currentTarget;
    if (!currentTarget) return false;
    _stickyWanted = true; _explicitExit = false;
    return applyForcedState();
  }

  function exitForcedPhoneFs(force) {
    if (force !== true && _stickyWanted) { scheduleReenter(60); return false; }
    _stickyWanted = false; _explicitExit = true;
    if (_reenterTimer) { clearTimeout(_reenterTimer); _reenterTimer = null; }
    clearForcedState();
    return true;
  }

  window.__asdForceFullscreenNow = function() {
    _stickyWanted = true; _explicitExit = false; return enterForcedPhoneFs();
  };
  window.__asdExitForcedFullscreen = function() { return exitForcedPhoneFs(true); };

  document.addEventListener('fullscreenchange', function() {
    var active = nativeFsActive();
    if (active) { enterForcedPhoneFs(); return; }
    if (_explicitExit) { exitForcedPhoneFs(true); return; }
    if (_stickyWanted) { scheduleReenter(30); setTimeout(function(){ scheduleReenter(180); }, 0); return; }
    exitForcedPhoneFs(true);
  }, true);

  document.addEventListener('webkitfullscreenchange', function() {
    var active = nativeFsActive();
    if (active) { enterForcedPhoneFs(); return; }
    if (_explicitExit) { exitForcedPhoneFs(true); return; }
    if (_stickyWanted) { scheduleReenter(30); setTimeout(function(){ scheduleReenter(180); }, 0); return; }
    exitForcedPhoneFs(true);
  }, true);

  document.addEventListener('click', function(e) {
    var el = e.target && e.target.closest ? e.target.closest(
      '.jw-icon-fullscreen, .vjs-fullscreen-control, [data-plyr="fullscreen"], ' +
      '.plyr__control--overlaid, .plyr__control--fullscreen, ' +
      '[class*="fullscreen"], [id*="fullscreen"], ' +
      '[aria-label*="full"], [title*="Full"], [title*="fullscreen"]'
    ) : null;
    if (!el) return;
    var txt = ((el.textContent||'')+' '+(el.getAttribute('aria-label')||'')+' '+(el.getAttribute('title')||'')).toLowerCase();
    var cls = (el.className||'').toString().toLowerCase();
    var dataPlyr = ((el.getAttribute&&el.getAttribute('data-plyr'))||'').toLowerCase();
    var pressed = ((el.getAttribute&&el.getAttribute('aria-pressed'))||'').toLowerCase();
    var isExit = txt.indexOf('exit')!==-1||cls.indexOf('exit-fullscreen')!==-1||pressed==='true';
    var isFull = txt.indexOf('full')!==-1||cls.indexOf('fullscreen')!==-1||dataPlyr==='fullscreen';
    if (!isFull && !isExit) return;
    if (isExit) {
      _stickyWanted = false; _explicitExit = true;
      setTimeout(function(){ exitForcedPhoneFs(true); }, 60);
      return;
    }
    _stickyWanted = true; _explicitExit = false;
    setTimeout(function(){ enterForcedPhoneFs(); }, 60);
    setTimeout(function(){ enterForcedPhoneFs(); }, 400);
  }, true);
})();
""";

  static const String _fsVid = r"""
(function injectAll(doc, win) {
  'use strict';

  function fl(n, v) {
    try { win.flutter_inappwebview.callHandler(n, v); } catch(e) {
      try { win.top.flutter_inappwebview.callHandler(n, v); } catch(e2) {}
    }
  }

  win.__asdLastUserGesture = win.__asdLastUserGesture || 0;
  ['pointerdown','touchstart','mousedown','keydown'].forEach(function(evt){
    doc.addEventListener(evt, function(e){
      // ✅ ROOT FIX 3: تجاهل أحداث البوت الاصطناعية حتى لا تُحسب كـ user gesture حقيقي
      if (e && e.isTrusted === false) return;
      win.__asdLastUserGesture = Date.now();
    }, true);
  });

  function maybeUrl(url) {
    if (!url || typeof url !== 'string') return null;
    var s = url.trim();
    if (!s || s.indexOf('blob:') === 0) return null;
    var lower = s.toLowerCase();
    if (lower.indexOf('.m3u8')!==-1||lower.indexOf('.mp4')!==-1||
        lower.indexOf('.mkv')!==-1||lower.indexOf('.webm')!==-1||
        lower.indexOf('.m4v')!==-1||lower.indexOf('.ts')!==-1||
        lower.indexOf('.mov')!==-1||lower.indexOf('.mpd')!==-1||
        lower.indexOf('mime=video')!==-1||lower.indexOf('/playlist')!==-1||
        lower.indexOf('/manifest')!==-1||lower.indexOf('/hls/')!==-1) {
      return s;
    }
    return null;
  }

  function sendCandidate(url, extra) {
    var clean = maybeUrl(url);
    if (!clean) return;
    var payload = { url: clean, pageUrl: win.location.href, currentTime: 0, mimeType: null };
    if (extra) { for (var k in extra) payload[k] = extra[k]; }
    fl('onVideoFound', payload);
  }

  function qualityLabelFromText(text) {
    text = (text || '').replace(/\s+/g, ' ').trim();
    var m = text.match(/(2160|1440|1080|720|540|480|360|240)\s*p?/i);
    return m ? (m[1] + 'p') : null;
  }

  function isAnimeQualityPageUrl(url) {
    try {
      if (!url) return false;
      var u = new URL(url, win.location.href);
      return /anime3rb\.com$/i.test(u.hostname) &&
             /\/(2160|1440|1080|720|540|480|360|240)\/?$/i.test(u.pathname);
    } catch(e) { return false; }
  }

  function insideRealPlayer(el) {
    try {
      return !!(el && el.closest && el.closest('.video-js,.jwplayer,.plyr,.dplayer,.mejs-container,#player,[class*="player"],.vjs-control-bar,.vjs-menu,.vjs-menu-content'));
    } catch(e) { return false; }
  }

  function clickEl(el) {
    if (!el) return false;
    try { el.dispatchEvent(new MouseEvent('pointerdown', {bubbles:true,cancelable:true})); } catch(e) {}
    try { el.dispatchEvent(new MouseEvent('mousedown', {bubbles:true,cancelable:true})); } catch(e) {}
    try { el.dispatchEvent(new MouseEvent('mouseup', {bubbles:true,cancelable:true})); } catch(e) {}
    try { el.click(); return true; } catch(e) {}
    return false;
  }

  function collectQualityOptions() {
    var out = [];
    var seen = {};
    try {
      var nodes = doc.querySelectorAll('a,button,li,div,span');
      for (var i = 0; i < nodes.length; i++) {
        var el = nodes[i];
        if (!el || !el.textContent) continue;
        var label = qualityLabelFromText((el.textContent || '') + ' ' + (el.getAttribute && (el.getAttribute('title') || el.getAttribute('aria-label')) || ''));
        if (!label) continue;
        var href = (el.href || (el.getAttribute && (el.getAttribute('data-url') || el.getAttribute('data-link') || el.getAttribute('href'))) || '').trim();
        if (isAnimeQualityPageUrl(href)) continue;
        if (href && /anime3rb\.com/i.test(href) && !insideRealPlayer(el)) continue;
        var key = (href || label + '_' + i).replace(/[^a-zA-Z0-9_:\/.\-]/g, '_');
        var selected = /active|current|selected|checked/.test(((el.className || '') + ' ' + (el.parentElement && el.parentElement.className || '')).toLowerCase()) ||
          (el.getAttribute && (el.getAttribute('aria-current') === 'true' || el.getAttribute('aria-selected') === 'true' || el.getAttribute('aria-pressed') === 'true'));
        try { el.setAttribute('data-asd-quality-key', key); } catch(e) {}
        var uniq = (label + '|' + href).toLowerCase();
        if (seen[uniq]) continue;
        seen[uniq] = true;
        out.push({ label: label, key: key, url: href || '', selected: selected });
      }
    } catch(e) {}
    if (out.length) {
      var current = null;
      for (var j = 0; j < out.length; j++) { if (out[j].selected) { current = out[j].label; break; } }
      if (!current) {
        var head = doc.body ? doc.body.innerText || '' : '';
        current = qualityLabelFromText(head) || out[0].label;
      }
      fl('onQualityOptions', { options: out, current: current });
    }
    return out;
  }

  win.__asdSelectQualityOption = function(key, label, url) {
    try {
      collectQualityOptions();
      var byKey = key ? doc.querySelector('[data-asd-quality-key="' + String(key).replace(/"/g,'\"') + '"]') : null;
      if (byKey) return clickEl(byKey);
      var nodes = doc.querySelectorAll('a,button,li,div,span');
      for (var i = 0; i < nodes.length; i++) {
        var el = nodes[i];
        var txt = qualityLabelFromText((el.textContent || '') + ' ' + (el.getAttribute && (el.getAttribute('title') || el.getAttribute('aria-label')) || ''));
        var href = (el.href || (el.getAttribute && (el.getAttribute('data-url') || el.getAttribute('data-link') || el.getAttribute('href'))) || '').trim();
        if (isAnimeQualityPageUrl(href) || isAnimeQualityPageUrl(url)) continue;
        if (href && /anime3rb\.com/i.test(href) && !insideRealPlayer(el)) continue;
        if ((label && txt === label) || (url && href === url)) {
          return clickEl(el);
        }
      }
    } catch(e) {}
    return false;
  };

  function getVideoInfo(v) {
    var url = maybeUrl(v.currentSrc) || maybeUrl(v.src);
    if (!url) {
      var srcs = v.querySelectorAll('source');
      for (var i = 0; i < srcs.length; i++) {
        var s = maybeUrl(srcs[i].src || srcs[i].getAttribute('src'));
        if (s) { url = s; break; }
      }
    }
    return {
      url: url, pageUrl: win.location.href,
      currentTime: isFinite(v.currentTime) ? v.currentTime : 0,
      duration: isFinite(v.duration) ? v.duration : 0,
      paused: v.paused, isBlob: !url,
      videoWidth: v.videoWidth || 0,
      videoHeight: v.videoHeight || 0,
      mimeType: v.currentSrc && v.currentSrc.toLowerCase().indexOf('.m3u8')!==-1
        ? 'application/x-mpegURL'
        : (v.currentSrc && v.currentSrc.toLowerCase().indexOf('.mp4')!==-1
            ? 'video/mp4' : (v.getAttribute('type') || null))
    };
  }

  try {
    var proto = win.HTMLVideoElement ? win.HTMLVideoElement.prototype : null;
    if (proto && !proto._asd_pip_patched) {
      proto._asd_pip_patched = true;
      var _origPlay = proto.play;
      proto.play = function() {
        var self = this;
        var info = getVideoInfo(self);
        var recentGesture = Date.now() - (win.__asdLastUserGesture || 0) < 1600;
        if (win.__asdNativePlayerActive) {
          try { self.pause(); self.muted = true; self.volume = 0; } catch(e) {}
          return Promise.resolve();
        }
        if (recentGesture && info.url) {
          try { self.pause(); self.muted = true; self.volume = 0; } catch(e) {}
          fl('onPlayIntent', info);
          return Promise.resolve();
        }
        return _origPlay ? _origPlay.apply(this, arguments) : Promise.resolve();
      };
      proto.requestPictureInPicture = function() {
        var self = this;
        var info = getVideoInfo(self);
        if (info.url) sendCandidate(info.url, info);
        fl('onPip', info);
        return Promise.resolve({
          addEventListener: function(){}, removeEventListener: function(){},
          dispatchEvent: function(){ return true; }, width: 0, height: 0
        });
      };
    }
  } catch(e) {}

  try {
    if (win.Hls && win.Hls.prototype && !win.Hls.prototype._asd_patched) {
      win.Hls.prototype._asd_patched = true;
      var _origLoadSource = win.Hls.prototype.loadSource;
      win.Hls.prototype.loadSource = function(url) {
        sendCandidate(url, { mimeType: 'application/x-mpegURL' });
        return _origLoadSource ? _origLoadSource.apply(this, arguments) : undefined;
      };
    }
  } catch(e) {}

  function probeJwPlayer() {
    try {
      if (!win.jwplayer) return;
      var jw = win.jwplayer();
      if (!jw) return;
      var item = jw.getPlaylistItem && jw.getPlaylistItem();
      if (item) {
        if (item.file) sendCandidate(item.file, { currentTime: jw.getPosition ? (jw.getPosition()||0) : 0 });
        if (Array.isArray(item.sources)) {
          item.sources.forEach(function(src){
            if (!src) return;
            sendCandidate(src.file||src.src, { currentTime: jw.getPosition?(jw.getPosition()||0):0, mimeType: src.type||null });
          });
        }
      }
    } catch(e) {}
  }

  function probeVideoJs() {
    try {
      if (!win.videojs || !win.videojs.getPlayers) return;
      var players = win.videojs.getPlayers();
      Object.keys(players||{}).forEach(function(key){
        try {
          var p = players[key];
          if (!p) return;
          var src = p.currentSource && p.currentSource();
          sendCandidate(src&&(src.src||src.file), { currentTime: p.currentTime?(p.currentTime()||0):0, mimeType: src&&(src.type||null) });
        } catch(e) {}
      });
    } catch(e) {}
  }

  var _fs = false;
  function onFsChange() {
    var now = !!(doc.fullscreenElement || doc.webkitFullscreenElement);
    if (now != _fs) { _fs = now; fl('onFS', now); }
  }
  doc.addEventListener('fullscreenchange', onFsChange);
  doc.addEventListener('webkitfullscreenchange', onFsChange);

  function setupVideo(v) {
    if (v._asd_vid) return;
    v._asd_vid = true;
    function pushInfo() {
      var info = getVideoInfo(v);
      if (info.url) sendCandidate(info.url, info);
      fl('onVid', { playing: !v.paused && !v.ended, info: info });
    }
    v.addEventListener('play', pushInfo);
    v.addEventListener('playing', pushInfo);
    v.addEventListener('pause', function(){ fl('onVid', { playing: false, info: getVideoInfo(v) }); });
    v.addEventListener('ended', function(){ fl('onVid', { playing: false, info: getVideoInfo(v) }); });
    v.addEventListener('loadedmetadata', pushInfo);
    v.addEventListener('loadeddata', pushInfo);
    pushInfo();
    setInterval(function() {
      if (!v.paused && !v.ended && isFinite(v.currentTime)) {
        var info = getVideoInfo(v);
        if (info.url) sendCandidate(info.url, info);
        fl('onTime', v.currentTime);
        if (v.videoWidth > 0 && v.videoHeight > 0) {
          fl('onVideoDimensions', { width: v.videoWidth, height: v.videoHeight });
        }
      }
    }, 1000);
  }

  function scanVideos(root) {
    try { (root||doc).querySelectorAll('video').forEach(setupVideo); } catch(e) {}
  }

  win.__asdCollectMediaNow = function() {
    scanVideos(doc); probeJwPlayer(); probeVideoJs(); collectQualityOptions();
  };

  scanVideos(doc); probeJwPlayer(); probeVideoJs(); collectQualityOptions();
  setInterval(win.__asdCollectMediaNow, 1500);

  new MutationObserver(function(muts) {
    muts.forEach(function(m) {
      m.addedNodes.forEach(function(node) {
        if (node.tagName === 'VIDEO') setupVideo(node);
        if (node.querySelectorAll) node.querySelectorAll('video').forEach(setupVideo);
      });
    });
  }).observe(doc.body || doc.documentElement, { childList: true, subtree: true });

})(document, window);
""";

  static const String _touchFix = r"""
(function(){
  'use strict';
  if (window.__asdTouchFixInstalled) return;
  window.__asdTouchFixInstalled = true;

  var HOLD_MS = 7000;
  var _hideTimer = null;
  var _styleInjected = false;

  var CONTROL_SELS = [
    '.jw-controlbar','.jw-controls','.jw-button-container',
    '.jw-icon','.jw-slider-container','.jw-text-elapsed','.jw-text-duration',
    '.jw-display-icon-container','.jw-slider-time','.jw-knob',
    '.jw-icon-display','.jw-icon-rewind','.jw-icon-playback',
    '.jw-icon-forward','.jw-icon-fullscreen','.jw-icon-volume',
    '.jw-icon-cast','.jw-icon-settings','.jw-icon-cc',
    '.jw-display','.jw-display-container','.jw-display-icon-next',
    '.vjs-control-bar','.vjs-big-play-button','.vjs-control',
    '.vjs-slider','.vjs-progress-control','.vjs-play-control',
    '.vjs-volume-panel','.vjs-fullscreen-control','.vjs-menu',
    '.plyr__controls','.plyr__control','.plyr__progress',
    '.plyr__time','.plyr__volume','.plyr__menu',
    '.dplayer-controller','.dplayer-bar','.dplayer-icons',
    '.mejs__controls',
    '[class*="controlbar"]','[class*="control-bar"]',
    '[class*="controls"]','[class*="progress"]',
    '[class*="seek"]','[class*="playback"]','[class*="toolbar"]',
    '[role="button"]','[role="slider"]',
    'button','input[type="range"]'
  ];

  function inFs() {
    try {
      if (window !== window.top) {
        return !!(window.top.__asdForcedFs) ||
               !!(window.top.document &&
                  window.top.document.documentElement &&
                  window.top.document.documentElement.classList.contains('asd-phone-fs'));
      }
    } catch(e) {}
    return !!(
      window.__asdForcedFs ||
      document.fullscreenElement ||
      document.webkitFullscreenElement ||
      (document.documentElement &&
       document.documentElement.classList.contains('asd-phone-fs'))
    );
  }

  function injectStyle() {
    if (_styleInjected) return;
    _styleInjected = true;
    var s = document.createElement('style');
    s.id = 'asd-touch-fix-style';
    s.textContent = `
      html.asd-controls-force-visible .jw-controlbar,
      html.asd-controls-force-visible .jw-controls,
      html.asd-controls-force-visible .jw-button-container,
      html.asd-controls-force-visible .jw-icon,
      html.asd-controls-force-visible .jw-slider-container,
      html.asd-controls-force-visible .jw-text-elapsed,
      html.asd-controls-force-visible .jw-text-duration,
      html.asd-controls-force-visible .jw-display-icon-container,
      html.asd-controls-force-visible .jw-display,
      html.asd-controls-force-visible .jw-display-container,
      html.asd-controls-force-visible .jw-slider-time,
      html.asd-controls-force-visible .jw-knob,
      html.asd-controls-force-visible .vjs-control-bar,
      html.asd-controls-force-visible .vjs-big-play-button,
      html.asd-controls-force-visible .vjs-control,
      html.asd-controls-force-visible .vjs-slider,
      html.asd-controls-force-visible .vjs-progress-control,
      html.asd-controls-force-visible .plyr__controls,
      html.asd-controls-force-visible .plyr__control,
      html.asd-controls-force-visible .plyr__progress,
      html.asd-controls-force-visible .dplayer-controller,
      html.asd-controls-force-visible .dplayer-bar,
      html.asd-controls-force-visible .dplayer-icons,
      html.asd-controls-force-visible .mejs__controls,
      html.asd-controls-force-visible [class*="controlbar"],
      html.asd-controls-force-visible [class*="control-bar"],
      html.asd-controls-force-visible [class*="controls"],
      html.asd-controls-force-visible [class*="progress"],
      html.asd-controls-force-visible [class*="seek"] {
        opacity: 1 !important;
        visibility: visible !important;
        pointer-events: auto !important;
        transition-delay: 0s !important;
      }
      html.asd-controls-force-visible .jwplayer.jw-flag-user-inactive .jw-controlbar,
      html.asd-controls-force-visible .jwplayer.jw-flag-user-inactive .jw-controls {
        opacity: 1 !important;
        visibility: visible !important;
        pointer-events: auto !important;
      }
    `;
    (document.head || document.documentElement).appendChild(s);
  }

  function wakePlayer() {
    try {
      var mv = new MouseEvent('mousemove', { bubbles: true, cancelable: true, view: window });
      document.dispatchEvent(mv);
      document.querySelectorAll('video, iframe, .jwplayer, .video-js, .plyr, .dplayer').forEach(function(el){
        try { el.dispatchEvent(mv); } catch(e) {}
      });
    } catch(e) {}
    try {
      if (window.jwplayer) {
        var jw = window.jwplayer();
        if (jw && jw.getState && jw.getState() !== 'idle') {
          var jwEl = document.querySelector('.jwplayer');
          if (jwEl) {
            var evt = new MouseEvent('mousemove', { bubbles: true, view: window });
            jwEl.dispatchEvent(evt);
          }
        }
      }
    } catch(e) {}
    try {
      document.querySelectorAll('.jwplayer.jw-flag-user-inactive').forEach(function(el){
        el.classList.remove('jw-flag-user-inactive');
      });
    } catch(e) {}
  }

  function forceShowNow() {
    injectStyle();
    document.documentElement.classList.add('asd-controls-force-visible');
    if (document.body) document.body.classList.add('asd-controls-force-visible');
    CONTROL_SELS.forEach(function(sel) {
      try {
        document.querySelectorAll(sel).forEach(function(el) {
          el.style.setProperty('opacity', '1', 'important');
          el.style.setProperty('visibility', 'visible', 'important');
          el.style.setProperty('pointer-events', 'auto', 'important');
          if (el.style.display === 'none') el.style.removeProperty('display');
        });
      } catch(e) {}
    });
    try {
      document.querySelectorAll('.jwplayer.jw-flag-user-inactive').forEach(function(el){
        el.classList.remove('jw-flag-user-inactive');
      });
    } catch(e) {}
    wakePlayer();
  }

  function releaseControls() {
    document.documentElement.classList.remove('asd-controls-force-visible');
    if (document.body) document.body.classList.remove('asd-controls-force-visible');
    CONTROL_SELS.forEach(function(sel) {
      try {
        document.querySelectorAll(sel).forEach(function(el) {
          el.style.removeProperty('opacity');
          el.style.removeProperty('visibility');
          el.style.removeProperty('pointer-events');
        });
      } catch(e) {}
    });
  }

  function armHideTimer() {
    if (_hideTimer) clearTimeout(_hideTimer);
    _hideTimer = setTimeout(function() { _hideTimer = null; releaseControls(); }, HOLD_MS);
  }

  function hasInteractiveHints(target) {
    if (!target || !target.getAttribute) return false;
    var role = (target.getAttribute('role') || '').toLowerCase();
    var aria = (target.getAttribute('aria-label') || '').toLowerCase();
    var title = (target.getAttribute('title') || '').toLowerCase();
    return role === 'button' || role === 'slider' ||
      aria.indexOf('play') !== -1 || aria.indexOf('pause') !== -1 ||
      aria.indexOf('seek') !== -1 || aria.indexOf('full') !== -1 ||
      aria.indexOf('volume') !== -1 || aria.indexOf('mute') !== -1 ||
      title.indexOf('play') !== -1 || title.indexOf('pause') !== -1 ||
      title.indexOf('seek') !== -1 || title.indexOf('full') !== -1;
  }

  function isControlElement(node) {
    var target = node;
    while (target && target !== document.documentElement) {
      var cls = (target.className || '').toString();
      var tag = (target.tagName || '').toUpperCase();
      var id  = (target.id || '').toString();
      if (
        /jw-icon|jw-button|jw-controlbar|jw-controls|jw-slider|jw-knob|jw-display|jw-display-icon|jw-display-container|jw-icon-display|jw-icon-rewind|jw-icon-playback|jw-icon-forward|jw-icon-fullscreen|jw-icon-volume|jw-icon-settings|jw-icon-cc|jw-icon-cast/i.test(cls) ||
        /vjs-control|vjs-slider|vjs-big-play|vjs-play-control|vjs-volume|vjs-fullscreen|vjs-menu|vjs-time|vjs-progress/i.test(cls) ||
        /plyr__control|plyr__controls|plyr__progress|plyr__time|plyr__volume|plyr__menu/i.test(cls) ||
        /dplayer-controller|dplayer-bar|dplayer-icons|dplayer-setting|dplayer-volume/i.test(cls) ||
        /mejs__controls|mejs__button|mejs__playpause|mejs__time|mejs__volume/i.test(cls) ||
        /controlbar|control-bar|controls|progress-bar|seekbar|seek-bar|playback|toolbar/i.test(cls) ||
        /jw-|vjs-|plyr/i.test(id) ||
        tag === 'BUTTON' || tag === 'INPUT' || tag === 'A' ||
        tag === 'SELECT' || tag === 'TEXTAREA' || tag === 'LABEL' ||
        tag === 'SUMMARY' || tag === 'SVG' || tag === 'PATH' ||
        tag === 'USE' || tag === 'G' || tag === 'CIRCLE' ||
        tag === 'RECT' || tag === 'POLYGON' || tag === 'POLYLINE' ||
        hasInteractiveHints(target)
      ) { return true; }
      target = target.parentElement;
    }
    return false;
  }

  function handleInteraction(e) {
    if (!inFs()) return;
    if (isControlElement(e.target)) {
      forceShowNow();
      armHideTimer();
      return;
    }
    var tag = e.target ? (e.target.tagName || '').toUpperCase() : '';
    if (tag !== 'VIDEO') return;
    forceShowNow();
    armHideTimer();
  }

  document.addEventListener('touchstart',  handleInteraction, { passive: true,  capture: true });
  document.addEventListener('touchend',    handleInteraction, { passive: true,  capture: true });
  document.addEventListener('pointerdown', handleInteraction, { passive: true,  capture: true });
  document.addEventListener('pointerup',   handleInteraction, { passive: true,  capture: true });
  document.addEventListener('mousedown',   handleInteraction, { passive: true,  capture: true });
  document.addEventListener('click',       handleInteraction, { passive: true,  capture: true });

  document.addEventListener('fullscreenchange', function() {
    if (!inFs()) { if (_hideTimer) { clearTimeout(_hideTimer); _hideTimer = null; } releaseControls(); }
  }, true);
  document.addEventListener('webkitfullscreenchange', function() {
    if (!inFs()) { if (_hideTimer) { clearTimeout(_hideTimer); _hideTimer = null; } releaseControls(); }
  }, true);

  window.__asdShowControls = function() { if (!inFs()) return; forceShowNow(); armHideTimer(); };
  window.__asdStopControls = function() { if (_hideTimer) { clearTimeout(_hideTimer); _hideTimer = null; } releaseControls(); };

  function startJwWatchdog() {
    try {
      var jwEl = document.querySelector('.jwplayer');
      if (!jwEl || jwEl._asdWatchdog) return;
      jwEl._asdWatchdog = true;
      new MutationObserver(function(muts) {
        if (!inFs()) return;
        muts.forEach(function(m) {
          if (m.attributeName === 'class') {
            var el = m.target;
            if (el.classList.contains('jw-flag-user-inactive')) {
              setTimeout(function() {
                if (inFs() && _hideTimer) {
                  el.classList.remove('jw-flag-user-inactive');
                }
              }, 20);
            }
          }
        });
      }).observe(jwEl, { attributes: true, subtree: false });
    } catch(e) {}
  }

  function startVjsWatchdog() {
    try {
      if (!window.videojs || !window.videojs.getPlayers) return;
      var players = window.videojs.getPlayers();
      Object.keys(players || {}).forEach(function(key) {
        try {
          var p = players[key];
          if (!p || p._asdWatchdog) return;
          p._asdWatchdog = true;
          p.on('userinactive', function() {
            if (inFs() && _hideTimer) {
              setTimeout(function() { try { p.userActive(true); } catch(e) {} }, 20);
            }
          });
        } catch(e) {}
      });
    } catch(e) {}
  }

  setTimeout(startJwWatchdog, 1000);
  setTimeout(startJwWatchdog, 3000);
  setTimeout(startVjsWatchdog, 1000);
  setTimeout(startVjsWatchdog, 3000);

  try {
    new MutationObserver(function(muts) {
      var hasNew = muts.some(function(m){ return m.addedNodes.length > 0; });
      if (hasNew) { setTimeout(startJwWatchdog, 500); setTimeout(startVjsWatchdog, 500); }
    }).observe(document.body || document.documentElement, { childList: true, subtree: true });
  } catch(e) {}
})();
""";

  static const String _iframeVideoFix = r"""
(function(){
  'use strict';
  if (window.__asdIframeVideoFixInstalled) return;
  window.__asdIframeVideoFixInstalled = true;

  var _lastTouchTime = 0;
  var _touchPauseBlocked = false;
  var _lastTouchKind = 'other';

  function isInForcedFs() {
    try {
      if (window !== window.top) {
        return !!(window.top.__asdForcedFs) ||
               !!(window.top.document &&
                  window.top.document.documentElement &&
                  window.top.document.documentElement.classList.contains('asd-phone-fs'));
      }
    } catch(e) {}
    return !!(
      window.__asdForcedFs ||
      (document.documentElement && document.documentElement.classList.contains('asd-phone-fs')) ||
      document.fullscreenElement || document.webkitFullscreenElement
    );
  }

  function hasInteractiveHints(target) {
    if (!target || !target.getAttribute) return false;
    var role = (target.getAttribute('role') || '').toLowerCase();
    var aria = (target.getAttribute('aria-label') || '').toLowerCase();
    var title = (target.getAttribute('title') || '').toLowerCase();
    return role === 'button' || role === 'slider' ||
      aria.indexOf('play') !== -1 || aria.indexOf('pause') !== -1 ||
      aria.indexOf('seek') !== -1 || aria.indexOf('full') !== -1 ||
      aria.indexOf('volume') !== -1 || aria.indexOf('mute') !== -1 ||
      title.indexOf('play') !== -1 || title.indexOf('pause') !== -1 ||
      title.indexOf('seek') !== -1 || title.indexOf('full') !== -1;
  }

  function isControlElement(node) {
    var target = node;
    while (target && target !== document.documentElement) {
      var cls = (target.className || '').toString();
      var tag = (target.tagName || '').toUpperCase();
      var id  = (target.id || '').toString();
      if (
        /jw-icon|jw-button|jw-controlbar|jw-controls|jw-slider|jw-knob|jw-display|jw-display-icon|jw-display-container|jw-icon-display|jw-icon-rewind|jw-icon-playback|jw-icon-forward|jw-icon-fullscreen|jw-icon-volume|jw-icon-settings|jw-icon-cc|jw-icon-cast/i.test(cls) ||
        /vjs-control|vjs-slider|vjs-big-play|vjs-play-control|vjs-volume|vjs-fullscreen|vjs-menu|vjs-time|vjs-progress/i.test(cls) ||
        /plyr__control|plyr__controls|plyr__progress|plyr__time|plyr__volume|plyr__menu/i.test(cls) ||
        /dplayer-controller|dplayer-bar|dplayer-icons|dplayer-setting|dplayer-volume/i.test(cls) ||
        /mejs__controls|mejs__button|mejs__playpause|mejs__time|mejs__volume/i.test(cls) ||
        /controlbar|control-bar|controls|progress-bar|seekbar|seek-bar|playback|toolbar/i.test(cls) ||
        /jw-|vjs-|plyr/i.test(id) ||
        tag === 'BUTTON' || tag === 'INPUT' || tag === 'A' ||
        tag === 'SELECT' || tag === 'TEXTAREA' || tag === 'LABEL' ||
        tag === 'SUMMARY' || tag === 'SVG' || tag === 'PATH' ||
        tag === 'USE' || tag === 'G' || tag === 'CIRCLE' ||
        tag === 'RECT' || tag === 'POLYGON' || tag === 'POLYLINE' ||
        hasInteractiveHints(target)
      ) { return true; }
      target = target.parentElement;
    }
    return false;
  }

  function askShowControls() {
    try { if (window.__asdShowControls) window.__asdShowControls(); } catch(e) {}
    try { if (window.top && window.top.__asdShowControls) window.top.__asdShowControls(); } catch(e) {}
  }

  function askKeepFullscreen() {
    try { if (window.__asdForceFullscreenNow) window.__asdForceFullscreenNow(); } catch(e) {}
    try { if (window.top && window.top.__asdForceFullscreenNow) window.top.__asdForceFullscreenNow(); } catch(e) {}
  }

  function syncTapKind(kind) {
    _lastTouchKind = kind;
    try { window.__asdLastTapKind = kind; if (window.top) window.top.__asdLastTapKind = kind; } catch(e) {}
  }

  document.addEventListener('touchstart', function(e) {
    _lastTouchTime = Date.now();
    _touchPauseBlocked = false;
    if (!isInForcedFs()) return;
    if (isControlElement(e.target)) { syncTapKind('control'); askShowControls(); return; }
    var tag = e.target ? (e.target.tagName || '').toUpperCase() : '';
    if (tag === 'VIDEO') { syncTapKind('surface'); askShowControls(); return; }
    syncTapKind('other');
  }, { passive: true, capture: true });

  document.addEventListener('pointerdown', function(e) {
    _lastTouchTime = Date.now();
    _touchPauseBlocked = false;
    if (!isInForcedFs()) return;
    if (isControlElement(e.target)) { syncTapKind('control'); askShowControls(); return; }
    var tag = e.target ? (e.target.tagName || '').toUpperCase() : '';
    if (tag === 'VIDEO') { syncTapKind('surface'); askShowControls(); return; }
    syncTapKind('other');
  }, { passive: true, capture: true });

  try {
    var proto = window.HTMLMediaElement && window.HTMLMediaElement.prototype;
    if (proto && !proto._asdAutoResumePatch) {
      proto._asdAutoResumePatch = true;
      var _origPause = proto.pause;
      proto.pause = function() {
        var self = this;
        var result;
        try { result = _origPause ? _origPause.apply(self, arguments) : undefined; } catch(e) {}
        if (isInForcedFs()) {
          var timeSinceTouch = Date.now() - _lastTouchTime;
          if (timeSinceTouch < 450 && !_touchPauseBlocked && _lastTouchKind === 'surface') {
            _touchPauseBlocked = true;
            setTimeout(function() {
              try {
                if (self.paused && isInForcedFs()) {
                  self.play();
                  askShowControls();
                  askKeepFullscreen();
                }
              } catch(e) {}
              _touchPauseBlocked = false;
            }, 90);
          }
        }
        return result;
      };
    }
  } catch(e) {}

  function blockVideoTap(e) {
    if (!isInForcedFs()) return;
    if (isControlElement(e.target)) {
      syncTapKind('control');
      askShowControls();
      return;
    }
    var tag = e.target ? (e.target.tagName || '').toUpperCase() : '';
    if (tag !== 'VIDEO') { syncTapKind('other'); return; }
    syncTapKind('surface');
    askShowControls();
    askKeepFullscreen();
  }

  document.addEventListener('click',      blockVideoTap, { passive: true, capture: true });
  document.addEventListener('touchend',   blockVideoTap, { passive: true, capture: true });
  document.addEventListener('pointerup',  blockVideoTap, { passive: true, capture: true });
})();
""";

  static const String _dlCapture = r"""
(function(){
  'use strict';

  var dlExts = ['.mp4','.mkv','.avi','.mov','.webm','.m4v'];

  function maybeMedia(url) {
    if (!url || typeof url !== 'string') return null;
    var s = url.trim();
    if (!s || s.indexOf('blob:') === 0) return null;
    var lower = s.toLowerCase();
    if (lower.indexOf('.m3u8')!==-1||lower.indexOf('.mp4')!==-1||
        lower.indexOf('.mkv')!==-1||lower.indexOf('.webm')!==-1||
        lower.indexOf('.m4v')!==-1||lower.indexOf('.ts')!==-1||
        lower.indexOf('.mov')!==-1||lower.indexOf('.mpd')!==-1||
        lower.indexOf('mime=video')!==-1||lower.indexOf('/playlist')!==-1||
        lower.indexOf('/manifest')!==-1||lower.indexOf('/hls/')!==-1) {
      return s;
    }
    return null;
  }

  function isDlUrl(url) {
    var clean = maybeMedia(url);
    if (!clean) return false;
    var lower = clean.toLowerCase().split('?')[0].split('#')[0];
    return dlExts.some(function(e){ return lower.endsWith(e); });
  }

  function extractName(url) {
    if (!url) return 'video.mp4';
    var parts = url.split('?')[0].split('/');
    var name = parts[parts.length - 1];
    return name && name.length > 0 ? name : 'video.mp4';
  }

  function sendDl(url, name) {
    if (!url || url.length < 5) return;
    try { window.flutter_inappwebview.callHandler('onDownload', { url: url, name: name || extractName(url) }); } catch(e) {}
  }

  function sendVideo(url, mimeType) {
    var clean = maybeMedia(url);
    if (!clean) return;
    try { window.flutter_inappwebview.callHandler('onVideoFound', { url: clean, pageUrl: window.location.href, currentTime: 0, mimeType: mimeType || null }); } catch(e) {}
  }

  document.addEventListener('click', function(e) {
    var el = e.target;
    while (el && el !== document) {
      if (el.tagName === 'A' || el.tagName === 'BUTTON') break;
      el = el.parentElement;
    }
    if (!el || el === document) return;
    var href = el.href || el.getAttribute('data-url') || el.getAttribute('data-link') ||
               el.getAttribute('data-src') || el.getAttribute('data-file') || '';
    if (href && isDlUrl(href)) {
      e.preventDefault(); e.stopPropagation();
      sendDl(href, el.getAttribute('download') || extractName(href));
      return;
    }
    sendVideo(href, null);
  }, true);

  var origFetch = window.fetch;
  if (origFetch && !window.__asdFetchPatched) {
    window.__asdFetchPatched = true;
    window.fetch = function(input, init) {
      var url = '';
      if (typeof input === 'string') url = input;
      else if (input && input.url) url = input.url;
      sendVideo(url, null);
      if (isDlUrl(url)) sendDl(url, extractName(url));
      return origFetch.call(window, input, init).then(function(response) {
        var resUrl = response.url || url;
        var mime = null;
        try { mime = response.headers && response.headers.get ? response.headers.get('content-type') : null; } catch(e) {}
        sendVideo(resUrl, mime);
        if (isDlUrl(resUrl)) sendDl(resUrl, extractName(resUrl));
        return response;
      });
    };
  }

  try {
    if (!XMLHttpRequest.prototype._asdPatched) {
      XMLHttpRequest.prototype._asdPatched = true;
      var _open = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function(method, url) {
        this._asdUrl = url;
        sendVideo(url, null);
        return _open.apply(this, arguments);
      };
      var _send = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.send = function() {
        this.addEventListener('readystatechange', function() {
          if (this.readyState === 2 || this.readyState === 4) {
            var mime = null;
            try { mime = this.getResponseHeader('content-type'); } catch(e) {}
            sendVideo(this.responseURL || this._asdUrl, mime);
          }
        });
        return _send.apply(this, arguments);
      };
    }
  } catch(e) {}
})();
""";

  static const String _networkMediaProbe = r"""
(function(){
  'use strict';
  if (window.__asdNetProbeInstalled) return;
  window.__asdNetProbeInstalled = true;

  function isMedia(url) {
    if (!url || typeof url !== 'string') return false;
    var s = url.toLowerCase();
    if (s.indexOf('blob:') === 0) return false;
    return s.indexOf('.m3u8') !== -1 ||
           s.indexOf('.mpd') !== -1 ||
           s.indexOf('.mp4') !== -1 ||
           s.indexOf('.mkv') !== -1 ||
           s.indexOf('.webm') !== -1 ||
           s.indexOf('.m4v') !== -1 ||
           s.indexOf('.mov') !== -1 ||
           s.indexOf('.avi') !== -1 ||
           s.indexOf('/manifest') !== -1 ||
           s.indexOf('/playlist') !== -1 ||
           s.indexOf('/hls/') !== -1 ||
           s.indexOf('mime=video') !== -1;
  }

  function notify(url, mime) {
    if (!isMedia(url)) return;
    try {
      window.flutter_inappwebview.callHandler('onVideoFound', {
        url: url,
        pageUrl: window.location.href,
        currentTime: 0,
        mimeType: mime || null
      });
    } catch(e) {}
  }

  try {
    var origFetch = window.fetch;
    if (origFetch && !window.__asdFetchMediaProbe) {
      window.__asdFetchMediaProbe = true;
      window.fetch = function(input, init) {
        var url = '';
        if (typeof input === 'string') url = input;
        else if (input && input.url) url = input.url;
        notify(url, null);
        return origFetch.call(this, input, init).then(function(res){
          var resUrl = res && res.url ? res.url : url;
          var mime = null;
          try { mime = res.headers.get('content-type'); } catch(e) {}
          notify(resUrl, mime);
          return res;
        });
      };
    }
  } catch(e) {}

  try {
    if (!XMLHttpRequest.prototype.__asdMediaPatched) {
      XMLHttpRequest.prototype.__asdMediaPatched = true;
      var origOpen = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function(method, url) {
        this.__asdUrl = url;
        notify(url, null);
        return origOpen.apply(this, arguments);
      };

      var origSend = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.send = function() {
        this.addEventListener('readystatechange', function() {
          if (this.readyState === 2 || this.readyState === 4) {
            var mime = null;
            try { mime = this.getResponseHeader('content-type'); } catch(e) {}
            notify(this.responseURL || this.__asdUrl, mime);
          }
        });
        return origSend.apply(this, arguments);
      };
    }
  } catch(e) {}
})();
""";

  static const String _vid3rbDeepCapture = r"""
(function(){
  'use strict';
  if (window.__asdVid3rbDeepInstalled) return;
  window.__asdVid3rbDeepInstalled = true;

  function fl(name, value) {
    try { window.flutter_inappwebview.callHandler(name, value); } catch(e) {
      try { window.top.flutter_inappwebview.callHandler(name, value); } catch(e2) {
        try { window.parent.flutter_inappwebview.callHandler(name, value); } catch(e3) {}
      }
    }
  }

  function qualityFromUrl(url) {
    if (!url) return null;
    var m = url.match(/\/(2160|1440|1080|720|540|480|360|240)p\./i);
    if (m) return m[1] + 'p';
    m = url.match(/(2160|1440|1080|720|540|480|360|240)p/i);
    return m ? m[1] + 'p' : null;
  }

  function sendQualityMap(sourcesArr, currentLabel) {
    if (!sourcesArr || !sourcesArr.length) return;
    var opts = [];
    var seen = {};
    sourcesArr.forEach(function(src) {
      var url = (src.file || src.src || '').trim();
      if (!url) return;
      var q = qualityFromUrl(url) || (src.label ? (src.label + 'p').replace(/pp$/, 'p') : null);
      if (!q) return;
      if (seen[q]) return;
      seen[q] = true;
      opts.push({ label: q, key: q.toLowerCase() + '_direct', url: url, selected: q === currentLabel });
    });
    if (opts.length < 1) return;
    var cur = currentLabel || (opts.find(function(o){return o.selected;}) || opts[0]).label;
    fl('onQualityOptions', { options: opts, current: cur });
    opts.forEach(function(opt) {
      if (opt.url) {
        fl('onVideoFound', {
          url: opt.url,
          pageUrl: window.location.href,
          currentTime: 0,
          mimeType: 'video/mp4',
          qualityLabel: opt.label
        });
      }
    });
  }

  function hookJwPlayer() {
    if (!window.jwplayer || window.__asdJwHooked) return false;
    window.__asdJwHooked = true;

    var origJw = window.jwplayer;

    function tryHookInstance(jw) {
      if (!jw || jw._asdHooked) return;
      jw._asdHooked = true;

      try {
        jw.on('ready', function() {
          try {
            var levels = jw.getQualityLevels ? jw.getQualityLevels() : [];
            var curLevel = jw.getCurrentQuality ? jw.getCurrentQuality() : 0;
            var curLabel = levels[curLevel] ? (levels[curLevel].label || '') : '';
            var sources = levels.map(function(lvl) {
              return { file: lvl.file || lvl.src || '', label: lvl.label || '', src: lvl.file || '' };
            });
            sendQualityMap(sources, qualityFromUrl(curLabel) || curLabel);

            jw.on('levelsChanged', function(e) {
              try {
                var newLevels = jw.getQualityLevels();
                var newCur = jw.getCurrentQuality();
                var newLabel = newLevels[newCur] ? (qualityFromUrl(newLevels[newCur].label || '') || newLevels[newCur].label) : '';
                var sources2 = newLevels.map(function(lvl) {
                  return { file: lvl.file || '', label: lvl.label || '' };
                });
                sendQualityMap(sources2, newLabel);
              } catch(ex) {}
            });

            jw.on('complete', function() {});
          } catch(ex) {}
        });

        jw.on('playlist', function(e) {
          try {
            if (!e || !e.playlist) return;
            var item = e.playlist[0] || {};
            var sources = item.sources || [];
            sendQualityMap(sources, null);
          } catch(ex) {}
        });
      } catch(ex) {}
    }

    window.jwplayer = function(id) {
      var instance = origJw.apply(this, arguments);
      if (instance) {
        setTimeout(function() { tryHookInstance(instance); }, 100);
      }
      return instance;
    };
    Object.keys(origJw).forEach(function(k) {
      try { window.jwplayer[k] = origJw[k]; } catch(e) {}
    });

    try {
      var existingJw = origJw();
      if (existingJw) tryHookInstance(existingJw);
    } catch(e) {}

    return true;
  }

  function hookVideoJs() {
    if (!window.videojs || window.__asdVjsDeepHooked) return false;
    window.__asdVjsDeepHooked = true;

    try {
      var players = window.videojs.getPlayers ? window.videojs.getPlayers() : {};
      Object.keys(players || {}).forEach(function(key) {
        try {
          var p = players[key];
          if (!p || p._asdDeepHooked) return;
          p._asdDeepHooked = true;

          var srcs = [];
          try { srcs = p.currentSources ? p.currentSources() : []; } catch(e) {}
          if (!srcs.length) { try { srcs = p.sources ? p.sources() : []; } catch(e) {} }

          var curSrc = '';
          try { curSrc = p.currentSrc ? p.currentSrc() : ''; } catch(e) {}
          var curQ = qualityFromUrl(curSrc);

          if (srcs.length >= 1) {
            sendQualityMap(srcs.map(function(s) {
              return { file: s.src || s.file || '', label: s.label || qualityFromUrl(s.src) || '' };
            }), curQ);
          }

          p.on('sourcechanged', function() {
            try {
              var newSrc = p.currentSrc ? p.currentSrc() : '';
              var newQ = qualityFromUrl(newSrc);
              if (newQ) fl('onQualityChanged', { quality: newQ, url: newSrc });
            } catch(ex) {}
          });
        } catch(e) {}
      });
    } catch(e) {}
    return true;
  }

  function hookNetwork() {
    if (window.__asdNetQualHooked) return;
    window.__asdNetQualHooked = true;

    var origXhrOpen = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function(method, url) {
      var q = qualityFromUrl(url);
      if (q && url.indexOf('vid3rb.com') !== -1) {
        fl('onVideoFound', {
          url: url,
          pageUrl: window.location.href,
          currentTime: 0,
          mimeType: 'video/mp4',
          qualityLabel: q
        });
      }
      return origXhrOpen.apply(this, arguments);
    };

    if (window.fetch && !window.__asdFetchQualHooked) {
      window.__asdFetchQualHooked = true;
      var origFetch = window.fetch;
      window.fetch = function(input) {
        var url = typeof input === 'string' ? input : (input && input.url ? input.url : '');
        var q = qualityFromUrl(url);
        if (q && url.indexOf('vid3rb.com') !== -1) {
          fl('onVideoFound', {
            url: url,
            pageUrl: window.location.href,
            currentTime: 0,
            mimeType: 'video/mp4',
            qualityLabel: q
          });
        }
        return origFetch.apply(this, arguments);
      };
    }
  }

  window.__asdSelectQualityOption = function(key, label, url) {
    if (url && url.indexOf('.mp4') !== -1) {
      try {
        var vids = document.querySelectorAll('video');
        if (vids.length > 0) {
          var ct = vids[0].currentTime;
          var paused = vids[0].paused;
          vids[0].src = url;
          vids[0].load();
          vids[0].addEventListener('loadedmetadata', function onL() {
            vids[0].removeEventListener('loadedmetadata', onL);
            vids[0].currentTime = ct;
            if (!paused) vids[0].play();
          });
          fl('onQualityChanged', { quality: label, url: url });
          return true;
        }
      } catch(e) {}
    }

    try {
      var jw = window.jwplayer ? window.jwplayer() : null;
      if (jw && jw.getQualityLevels) {
        var levels = jw.getQualityLevels();
        var norm = (label || '').toString().toLowerCase().replace(/\s/g, '');
        for (var i = 0; i < levels.length; i++) {
          var lvlLabel = (levels[i].label || '').toString().toLowerCase().replace(/\s/g, '');
          if (lvlLabel.includes(norm) || norm.includes(lvlLabel)) {
            jw.setCurrentQuality(i);
            return true;
          }
        }
        var digits = norm.match(/\d+/);
        if (digits) {
          for (var j = 0; j < levels.length; j++) {
            var ld = (levels[j].label || '').match(/\d+/);
            if (ld && ld[0] === digits[0]) {
              jw.setCurrentQuality(j);
              return true;
            }
          }
        }
      }
    } catch(e) {}

    try {
      var items = document.querySelectorAll('[class*="quality"], [class*="Quality"], .jw-option, .vjs-menu-item');
      for (var k = 0; k < items.length; k++) {
        var el = items[k];
        var txt = (el.textContent || el.innerText || '').trim();
        if (txt.includes(label) || label.includes(txt)) {
          el.click();
          return true;
        }
      }
    } catch(e) {}

    return false;
  };

  function runAll() {
    hookJwPlayer();
    hookVideoJs();
    hookNetwork();
  }

  runAll();
  [500, 1000, 2000, 3500, 6000].forEach(function(ms) { setTimeout(runAll, ms); });

  try {
    new MutationObserver(function(muts) {
      if (muts.some(function(m) { return m.addedNodes.length > 0; })) {
        setTimeout(runAll, 300);
      }
    }).observe(document.body || document.documentElement, { childList: true, subtree: true });
  } catch(e) {}
})();
""";



  static const String _srvCapture = r"""
(function(){
  'use strict';
  if (window.__asdSrvInstalled) return;
  window.__asdSrvInstalled = true;

  function fl(name, value) {
    try { window.flutter_inappwebview.callHandler(name, value); } catch(e) {}
  }




  function getEmbedUrl(el) {
    return (
      el.getAttribute('data-embed') ||
      el.getAttribute('data-link')  ||
      el.getAttribute('data-url')   ||
      el.getAttribute('data-src')   ||
      el.getAttribute('data-iframe') ||
      el.getAttribute('href')       ||
      ''
    ).trim();
  }

  function isActiveEl(el) {
    var cls = ((el.className || '') + ' ' +
               ((el.parentElement && el.parentElement.className) || '')).toLowerCase();
    return /\bactive\b|\bcurrent\b|\bselected\b/.test(cls) ||
      el.getAttribute('aria-selected') === 'true' ||
      el.getAttribute('aria-current')  === 'true' ||
      el.getAttribute('aria-pressed')  === 'true';
  }


  function currentIframe() {
    var iframes = document.querySelectorAll(
      '.server-content.active iframe, .tab-content.active iframe, ' +
      '.player-content iframe, #player iframe, .embed-responsive iframe'
    );
    for (var i = 0; i < iframes.length; i++) {
      var src = (iframes[i].src || iframes[i].getAttribute('src') || '').trim();
      if (src && src.length > 4 && src.indexOf('about:') === -1) return src;
    }

    var all = document.querySelectorAll('iframe');
    for (var j = 0; j < all.length; j++) {
      var s = (all[j].src || all[j].getAttribute('src') || '').trim();
      if (s && s.length > 4 && s.indexOf('about:') === -1 &&
          s.indexOf('googlesyndication') === -1 && s.indexOf('doubleclick') === -1) {
        return s;
      }
    }
    return null;
  }

  function collectServers() {
    var out   = [];
    var seen  = {};
    var idx   = 0;


    var candidates = Array.from(document.querySelectorAll(
      '[class*="server-link"], [class*="link-server"], [class*="srv-link"],' +
      '[class*="server-btn"], [class*="server-tab"], [class*="server-item"],' +
      '[class*="tab-link"][data-link], [class*="tab-link"][data-embed],' +
      'a[data-embed], a[data-link], button[data-embed], button[data-link],' +
      'li[data-link], li[data-embed], span[data-embed], div[data-embed],' +
      '[data-server]'
    ));

    candidates.forEach(function(el) {
      var rawLabel = ((el.textContent || el.innerText || '') +
                      ' ' + (el.getAttribute('title') || '')).replace(/\s+/g,' ').trim();


      var low = rawLabel.toLowerCase();
      var isServer = /سيرفر|server|srv|\bstream\b|dood|stape|voe|vidtube|uqload|mixdrop|fembed/i.test(low);
      if (!isServer) return;
      if (rawLabel.length > 60 || rawLabel.length < 1) return;

      var embedUrl = getEmbedUrl(el);
      var key = (embedUrl || rawLabel + '_' + idx).replace(/[^a-zA-Z0-9_:\/.\-]/g,'_').substring(0,120);
      var uniq = (rawLabel + '|' + embedUrl).toLowerCase();
      if (seen[uniq]) return;
      seen[uniq] = true;
      idx++;

      try { el.setAttribute('data-asd-srv-key', key); } catch(e) {}

      out.push({
        label:    rawLabel,
        key:      key,
        embedUrl: embedUrl,
        selected: isActiveEl(el)
      });
    });

    if (out.length < 2) return;

    var currentLabel = null;
    var curIframe    = currentIframe();

    out.forEach(function(o) {
      if (o.selected) { currentLabel = o.label; }

      if (!o.selected && curIframe && o.embedUrl &&
          curIframe.indexOf(o.embedUrl.split('?')[0]) !== -1) {
        o.selected   = true;
        currentLabel = o.label;
      }
    });
    if (!currentLabel && out.length > 0) currentLabel = out[0].label;

    fl('onServerOptions', { options: out, current: currentLabel });
  }


  window.__asdSelectServer = function(key, label, embedUrl) {
    try {

      var byKey = key
        ? document.querySelector('[data-asd-srv-key="' + String(key).replace(/"/g,'\\"') + '"]')
        : null;
      if (byKey) { byKey.click(); collectServers(); return true; }


      var nodes = document.querySelectorAll(
        '[class*="server-link"],[class*="link-server"],[data-embed],[data-link],a,button,li,span,div'
      );
      for (var i = 0; i < nodes.length; i++) {
        var el   = nodes[i];
        var txt  = ((el.textContent || el.innerText || '')).replace(/\s+/g,' ').trim();
        var eUrl = getEmbedUrl(el);
        if ((label && txt === label) ||
            (embedUrl && embedUrl.length > 4 && eUrl === embedUrl)) {
          el.click();
          setTimeout(collectServers, 600);
          return true;
        }
      }
    } catch(e) {}
    return false;
  };


  setTimeout(collectServers, 800);
  setInterval(collectServers, 3000);

  try {
    new MutationObserver(function(muts) {
      if (muts.some(function(m){ return m.addedNodes.length > 0; })) {
        setTimeout(collectServers, 500);
      }
    }).observe(document.body || document.documentElement, { childList: true, subtree: true });
  } catch(e) {}
})();
""";


  static const String _qualityAutoBot = r"""
(function(){
  'use strict';
  if (window.__asdPPBotInstalled) return;
  window.__asdPPBotInstalled = true;

  var _href = (window.location.href || '').toLowerCase();
  var _inVid3rb = _href.indexOf('video.vid3rb.com') !== -1 ||
                  _href.indexOf('vid3rb.com/player/') !== -1 ||
                  _href.indexOf('/player/') !== -1;
  var _done = false;
  var _step = 0;
  var _runId = 0;
  var _suppressed = !!window.__asdPreciseBotSuppressed;
  var _targetQuality = '';

  function botBlocked() {
    try {
      return _suppressed === true || window.__asdPreciseBotSuppressed === true;
    } catch(e) {
      return _suppressed === true;
    }
  }

  window.__asdSetPreciseBotSuppressed = function(value, reset) {
    _suppressed = !!value;
    try { window.__asdPreciseBotSuppressed = _suppressed; } catch(e) {}
    if (_suppressed || reset) {
      _done = true;
      _step = 99;
      _runId++;
    }
    log('suppressed=' + _suppressed, 'reset=' + (!!reset));
    return _suppressed;
  };

  function log() {
    try {
      var args = Array.prototype.slice.call(arguments || []);
      args.unshift('[ASD-PreciseBot]');
      console.log.apply(console, args);
    } catch(e) {}
  }

  function fl(name, value) {
    try { window.flutter_inappwebview.callHandler(name, value); return; } catch(e) {}
    try { window.top.flutter_inappwebview.callHandler(name, value); return; } catch(e2) {}
    try { window.parent.flutter_inappwebview.callHandler(name, value); } catch(e3) {}
  }


  function getVid3rbIframe() {
    try {
      var frames = document.querySelectorAll('iframe');
      for (var i = 0; i < frames.length; i++) {
        var fr = frames[i];
        var src = (fr.src || fr.getAttribute('src') || '').toLowerCase();
        if (src.indexOf('vid3rb.com') !== -1 || src.indexOf('video.vid3rb') !== -1) return fr;
      }

      var best = null, bestArea = 0;
      for (var j = 0; j < frames.length; j++) {
        try {
          var r = frames[j].getBoundingClientRect();
          var area = r.width * r.height;
          if (r.width > 200 && r.height > 150 && area > bestArea) { best = frames[j]; bestArea = area; }
        } catch(e) {}
      }
      return best;
    } catch(e) { return null; }
  }


  function getTargetDoc() {
    if (_inVid3rb) return document;
    try {
      var fr = getVid3rbIframe();
      if (fr && fr.contentDocument && fr.contentDocument.readyState !== 'loading') return fr.contentDocument;
      if (fr && fr.contentWindow && fr.contentWindow.document) return fr.contentWindow.document;
    } catch(e) {}
    return document;
  }

  function getTargetWin() {
    if (_inVid3rb) return window;
    try {
      var fr = getVid3rbIframe();
      if (fr && fr.contentWindow) return fr.contentWindow;
    } catch(e) {}
    return window;
  }

  function isWatchCtx() {
    try {
      var href = (window.location.href || '').toLowerCase();
      return href.indexOf('/episode/') !== -1 ||
             href.indexOf('/watch/') !== -1 ||
             href.indexOf('/movie/') !== -1 ||
             href.indexOf('vid3rb.com') !== -1 ||
             href.indexOf('/player/') !== -1;
    } catch(e) { return false; }
  }


  function getPlayerRect() {
    if (!_inVid3rb) {
      try {
        var fr = getVid3rbIframe();
        if (fr) {
          var r = fr.getBoundingClientRect();
          if (r.width > 100 && r.height > 80) return r;
        }
      } catch(e) {}
    }
    var doc = getTargetDoc();
    var sels = ['.video-js','.jwplayer','.plyr','.dplayer','#player','video'];
    for (var i = 0; i < sels.length; i++) {
      try {
        var els = doc.querySelectorAll(sels[i]);
        for (var j = 0; j < els.length; j++) {
          var r2 = els[j].getBoundingClientRect();
          if (r2.width > 120 && r2.height > 80) return r2;
        }
      } catch(e) {}
    }


    return null;
  }

  function vis(el) {
    if (!el) return false;
    try {
      var r = el.getBoundingClientRect();
      var ow = el.ownerDocument && el.ownerDocument.defaultView;
      var s = ow ? ow.getComputedStyle(el) : window.getComputedStyle(el);
      return r.width > 4 && r.height > 4 &&
             s.display !== 'none' && s.visibility !== 'hidden' &&
             parseFloat(s.opacity || '1') > 0;
    } catch(e) { return false; }
  }

  function textOf(el) {
    try { return ((el && (el.textContent || el.innerText)) || '').replace(/\s+/g, ' ').trim(); } catch(e) { return ''; }
  }

  function qualityFromText(txt) {
    var m = String(txt || '').match(/(2160|1440|1080|720|540|480|360|240)\s*p?/i);
    return m ? (m[1] + 'p') : '';
  }

  function isAnimeQualityPageUrl(url) {
    try {
      if (!url) return false;
      var u = new URL(url, window.location.href);
      return /anime3rb\.com$/i.test(u.hostname) &&
             /\/(2160|1440|1080|720|540|480|360|240)\/?$/i.test(u.pathname);
    } catch(e) { return false; }
  }

  function elementUrl(el) {
    try { return (el && (el.href || (el.getAttribute && (el.getAttribute('data-url') || el.getAttribute('data-link') || el.getAttribute('href'))))) || ''; } catch(e) { return ''; }
  }

  function insidePlayerUi(el) {
    try {
      return !!(el && el.closest && el.closest('.video-js,.jwplayer,.plyr,.dplayer,.mejs-container,#player,video,.vjs-control-bar,.vjs-menu,.vjs-menu-content,.vjs-quality-selector'));
    } catch(e) { return false; }
  }


  function dispatchAll(el, x, y) {
    if (!el) return false;
    var tw = (el.ownerDocument && el.ownerDocument.defaultView) ? el.ownerDocument.defaultView : window;
    var opts = { bubbles:true, cancelable:true, view:tw, clientX:x, clientY:y };
    ['pointerover','mouseover','mouseenter','pointerdown','mousedown','pointerup','mouseup','click'].forEach(function(type){
      try { el.dispatchEvent(new MouseEvent(type, opts)); } catch(e) {}
    });
    try {
      var touch = new Touch({ identifier:Date.now(), target:el, clientX:x, clientY:y, radiusX:2, radiusY:2, rotationAngle:0, force:1 });
      el.dispatchEvent(new TouchEvent('touchstart',{bubbles:true,cancelable:true,touches:[touch],targetTouches:[touch],changedTouches:[touch]}));
      el.dispatchEvent(new TouchEvent('touchend',{bubbles:true,cancelable:true,touches:[],targetTouches:[],changedTouches:[touch]}));
    } catch(e) {}
    try { el.focus && el.focus(); } catch(e) {}
    try { el.click(); } catch(e) {}
    return true;
  }

  function tap(el) {
    if (!el) return false;
    try { el.scrollIntoView({ block:'center', inline:'center' }); } catch(e) {}
    var r;
    try { r = el.getBoundingClientRect(); } catch(e) {}
    var x = r ? Math.round((r.left + r.right) / 2) : 0;
    var y = r ? Math.round((r.top + r.bottom) / 2) : 0;
    return dispatchAll(el, x, y);
  }


  function isFullscreenEl(el) {
    if (!el) return false;
    var cls = (el.className || '').toString().toLowerCase();
    var id  = (el.id || '').toString().toLowerCase();
    var lbl = ((el.getAttribute && (el.getAttribute('aria-label') || el.getAttribute('title'))) || '').toLowerCase();
    return /fullscreen|full-screen|jw-icon-fullscreen|vjs-fullscreen/.test(cls + ' ' + id + ' ' + lbl);
  }

  function isCrossOriginIframe() {
    if (_inVid3rb) return false;
    try {
      var fr = getVid3rbIframe();
      if (!fr) return false;
      var test = fr.contentDocument;
      return !test;
    } catch(e) {
      return true;
    }
  }

  function tapInPlayer(px, py) {
    // ✅ ROOT FIX 2: لا تلمس الصفحة الأم إذا كان iframe cross-origin؛ هذا كان يضغط خارج المشغل
    if (!_inVid3rb && isCrossOriginIframe()) {
      log('tapInPlayer blocked: cross-origin iframe, cannot safely tap');
      return false;
    }

    var doc = getTargetDoc();
    var pr = getPlayerRect();
    if (!pr) {
      log('tapInPlayer skipped: no real player rect');
      return false;
    }
    var x = Math.round(pr.left + pr.width  * px);
    var y = Math.round(pr.top  + pr.height * py);
    try {
      var el = doc.elementFromPoint(x, y);
      if (!el) return false;
      // يبقى إصلاح fullscreen السابق فعالاً: لا تضغط زر fullscreen بالغلط
      if (isFullscreenEl(el)) {
        log('tapInPlayer: skipped fullscreen btn at px=' + px + ', retrying at px-0.1');
        var x2 = Math.round(pr.left + pr.width * Math.max(0.5, px - 0.12));
        var el2 = doc.elementFromPoint(x2, y);
        if (!el2 || isFullscreenEl(el2)) return false;
        return dispatchAll(el2, x2, y);
      }
      return dispatchAll(el, x, y);
    } catch(e) { return false; }
  }


  function activatePlayerUi() {
    var doc = getTargetDoc();
    var tw  = getTargetWin();
    try {
      var p = getVjsPlayer();
      if (p) {
        try { p.userActive(true); } catch(e) {}
        try {
          var pel = p.el && p.el();
          if (pel) { pel.classList.remove('vjs-user-inactive'); pel.classList.add('vjs-user-active'); }
        } catch(e) {}
      }
    } catch(e) {}
    try {
      var pr = getPlayerRect();
      if (pr) {
        var cx = !_inVid3rb ? Math.round(pr.width * 0.5) : Math.round(pr.left + pr.width * 0.5);
        var cy = !_inVid3rb ? Math.round(pr.height * 0.5) : Math.round(pr.top + pr.height * 0.5);
        ['mousemove','mouseover','mouseenter'].forEach(function(type){
          try { doc.dispatchEvent(new MouseEvent(type,{bubbles:true,cancelable:true,view:tw,clientX:cx,clientY:cy})); } catch(e) {}
        });
      }
    } catch(e) {}
    try {
      doc.querySelectorAll(
        '.video-js,.jwplayer,.plyr,video,.vjs-control-bar,.vjs-big-play-button,.vjs-menu-button,.vjs-quality-selector,.vjs-menu,.vjs-menu-content'
      ).forEach(function(el){
        try {
          el.style.setProperty('visibility','visible','important');
          el.style.setProperty('opacity','1','important');
          el.style.setProperty('pointer-events','auto','important');
          if (el.classList.contains('vjs-control-bar')) el.style.setProperty('display','flex','important');
        } catch(e) {}
      });
    } catch(e) {}
  }

  // ── videojs player instance ───────────────────────────────────────────
  function getVjsPlayer() {
    var tw = getTargetWin();
    try {
      if (!tw.videojs || !tw.videojs.getPlayers) return null;
      var players = tw.videojs.getPlayers();
      var keys = Object.keys(players || {});
      for (var i = 0; i < keys.length; i++) {
        var p = players[keys[i]];
        if (!p) continue;
        try { if (p.isDisposed && p.isDisposed()) continue; } catch(e) {}
        return p;
      }
    } catch(e) {}
    return null;
  }

  function isPlaying() {
    var doc = getTargetDoc();
    var tw  = getTargetWin();
    try {
      var p = getVjsPlayer();
      if (p) { try { if (!p.paused()) return true; } catch(e) {} }
      if (doc.querySelector('.video-js.vjs-playing,.jw-state-playing,.plyr--playing')) return true;
      var vids = doc.querySelectorAll('video');
      for (var i = 0; i < vids.length; i++) {
        var v = vids[i];
        if (!v.paused && !v.ended && (v.readyState >= 2 || v.currentTime > 0.35)) return true;
      }
    } catch(e) {}
    return false;
  }

  function getCurrentQuality() {
    var doc = getTargetDoc();
    try {
      var sel = doc.querySelector('.vjs-menu-item.vjs-selected,.vjs-selected[role="menuitemradio"]');
      var q = qualityFromText(textOf(sel));
      if (q) return q;
    } catch(e) {}
    try {
      var p = getVjsPlayer();
      if (p && p.currentSrc) { var q2 = qualityFromText(p.currentSrc()); if (q2) return q2; }
    } catch(e) {}
    return '';
  }

  function findPlay() {
    if (isPlaying()) return null;
    if (!getPlayerRect()) return null;
    var doc = getTargetDoc();
    var sels = [
      '.video-js .vjs-big-play-button','.vjs-big-play-button',
      '.video-js .vjs-play-control.vjs-paused',
      '.video-js button[title*="Play" i]','.video-js button[aria-label*="Play" i]',
      '.jw-icon-display','.jw-display-icon-container','.jw-icon-playback',
      '.plyr__control--overlaid',
      'button[aria-label*="play" i]:not([aria-label*="pause" i])',
      'button[title*="play" i]:not([title*="pause" i])',
      'video'
    ];
    for (var i = 0; i < sels.length; i++) {
      try {
        var els = doc.querySelectorAll(sels[i]);
        for (var j = 0; j < els.length; j++) { if (vis(els[j])) return els[j]; }
      } catch(e) {}
    }
    return null;
  }

  function findQualityButton() {
    if (!getPlayerRect()) return null;
    var doc = getTargetDoc();
    var tw  = getTargetWin();
    var directSels = [
      '.vjs-quality-selector .vjs-menu-button',
      '.vjs-quality-selector button','.vjs-quality-selector',
      '.vjs-quality-selector-button','.vjs-quality-button',
      'button[title="Quality"]','button[aria-label="Quality"]',
      'button[title="الجودة"]','button[aria-label="الجودة"]',
      '.vjs-settings-button button','.vjs-settings button',
      'button.vjs-settings','.vjs-icon-cog',
      'button[title="Settings"]','button[title="الإعدادات"]',
    ];
    for (var i = 0; i < directSels.length; i++) {
      try {
        var els = doc.querySelectorAll(directSels[i]);
        for (var j = 0; j < els.length; j++) {
          if (vis(els[j])) { log('findQualityButton: found via', directSels[i]); return els[j]; }
        }
      } catch(e) {}
    }
    try {
      var p = getVjsPlayer();
      if (p && p.controlBar && p.controlBar.children) {
        var kids = p.controlBar.children();
        for (var k = 0; k < kids.length; k++) {
          var el = kids[k] && kids[k].el ? kids[k].el() : null;
          if (!el || !vis(el)) continue;
          var cls = String(el.className||'').toLowerCase();
          if (cls.indexOf('quality') !== -1) {
            var btn = el.querySelector('button') || el;
            if (vis(btn)) { log('findQualityButton: vjs API quality'); return btn; }
          }
        }
        for (var m = kids.length-1; m >= 0; m--) {
          var cel = kids[m] && kids[m].el ? kids[m].el() : null;
          if (!cel || !vis(cel)) continue;
          var ccls = String(cel.className||'').toLowerCase();
          if (/fullscreen|volume|subs|caption|picture|audio/.test(ccls)) continue;
          if (/menu-button|quality|settings|cog/.test(ccls)) {
            var cBtn = cel.querySelector('button') || cel;
            if (vis(cBtn)) { log('findQualityButton: vjs last menu-button'); return cBtn; }
          }
        }
      }
    } catch(e) {}
    try {
      var allBtns = doc.querySelectorAll('.vjs-control-bar button,.vjs-control-bar .vjs-menu-button');
      for (var n = allBtns.length-1; n >= 0; n--) {
        var b = allBtns[n];
        if (!vis(b)) continue;
        var btxt = (textOf(b)+' '+(b.getAttribute('title')||'')+' '+(b.getAttribute('aria-label')||'')).toLowerCase();
        var bcls = String(b.className||'').toLowerCase();
        if (/fullscreen|volume|subs|caption|picture|audio|closed|captions/.test(btxt+' '+bcls)) continue;
        if (/quality|settings|إعداد|جودة|cog/.test(btxt+' '+bcls)) { log('findQualityButton: control-bar scan'); return b; }
      }
      for (var nn = allBtns.length-1; nn >= 0; nn--) {
        var bb = allBtns[nn];
        if (!vis(bb)) continue;
        var bbc = String(bb.className||'').toLowerCase();
        if (/fullscreen/.test(bbc)) continue;
        if (/menu-button|settings|quality|cog/.test(bbc)) { log('findQualityButton: last non-fullscreen'); return bb; }
      }
    } catch(e) {}
    return null;
  }

  function settingsOpen() {
    var doc = getTargetDoc();
    try {
      var items = doc.querySelectorAll(
        '.vjs-quality-selector .vjs-menu-item,.vjs-menu.vjs-lock-showing .vjs-menu-item,.vjs-menu-content .vjs-menu-item,li[role="menuitemradio"]:not([hidden])'
      );
      for (var i = 0; i < items.length; i++) { if (vis(items[i])) return true; }
    } catch(e) {}
    try {
      var btn = findQualityButton();
      if (btn && btn.getAttribute('aria-expanded') === 'true') return true;
    } catch(e) {}
    return false;
  }

  function getQualityOpts() {
    if (!getPlayerRect()) return [];
    var doc = getTargetDoc();
    var out = [], seen = {};
    var sels = [
      '.vjs-quality-selector .vjs-menu-item',
      '.vjs-menu.vjs-lock-showing .vjs-menu-item',
      '.vjs-menu-content .vjs-menu-item',
      'li[role="menuitemradio"]','button[role="menuitemradio"]','[data-quality]'
    ];
    for (var s = 0; s < sels.length; s++) {
      try {
        var els = doc.querySelectorAll(sels[s]);
        for (var i = 0; i < els.length; i++) {
          var el = els[i];
          if (!vis(el)) continue;
          var txt = textOf(el);
          var q = qualityFromText(txt);
          if (!q) continue;
          var href = elementUrl(el);
          if (isAnimeQualityPageUrl(href)) continue;
          if (href && /anime3rb\.com/i.test(href) && !insidePlayerUi(el)) continue;
          if (!insidePlayerUi(el) && !_inVid3rb) continue;
          var key = q+'|'+s+'|'+i;
          if (seen[key]) continue;
          seen[key] = true;
          out.push({
            el:el, q:q,
            premium:/premium|vip|بريميوم/i.test(txt),
            selected:/selected|checked/i.test(String(el.className||'')) || el.getAttribute('aria-checked')==='true',
            txt:txt
          });
        }
      } catch(e) {}
    }
    out.sort(function(a,b){
      var o={'2160p':2160,'1440p':1440,'1080p':1080,'720p':720,'540p':540,'480p':480,'360p':360,'240p':240};
      return (o[b.q]||0)-(o[a.q]||0);
    });
    return out;
  }

  function clickQualityButton() {
    // ✅ ROOT FIX 4: لا تحاول تشغيل البوت من الصفحة الرئيسية مع iframe cross-origin
    if (!_inVid3rb && isCrossOriginIframe()) {
      log('clickQualityButton blocked: cross-origin, bot only works inside iframe');
      return false;
    }
    activatePlayerUi();
    var btn = findQualityButton();
    if (btn) { log('clickQualityButton: tapping', String(btn.className||btn.tagName).substring(0,60)); tap(btn); return true; }
    log('clickQualityButton: fallback tapInPlayer');
    tapInPlayer(0.82, 0.88);
    return false;
  }

  function isBotAcceptedFinalQuality(quality) {
    var q = qualityFromText(quality || getCurrentQuality() || '');
    if (!q) return false;
    if (_targetQuality) return q === _targetQuality;
    return q === '1080p';
  }

  function finish(id, success, quality) {
    if (botBlocked() || _done || id !== _runId) return;
    var confirmedQuality = qualityFromText(quality || getCurrentQuality() || '');
    success = !!success && isBotAcceptedFinalQuality(confirmedQuality);
    quality = confirmedQuality || quality || '';
    _done = true; _step = 5;
    log('complete', 'success='+success, 'quality='+(quality||''), 'playing='+isPlaying());


    if (success) {
      try {
        var doc = getTargetDoc();
        doc.querySelectorAll('video,audio').forEach(function(v){
          try { v.pause(); v.muted = true; v.volume = 0; } catch(e) {}
        });

        var p = getVjsPlayer();
        if (p) {
          try { p.pause(); } catch(e) {}
          try { p.muted(true); } catch(e) {}
        }

        var tw = getTargetWin();
        if (tw && tw.HTMLMediaElement && !tw.__asdBotPaused) {
          tw.__asdBotPaused = true;
          var origPlay = tw.HTMLMediaElement.prototype.play;
          tw.HTMLMediaElement.prototype.play = function() {
            if (tw.__asdBotPaused) {
              try { this.pause(); this.muted = true; this.volume = 0; } catch(ex) {}
              return Promise.resolve();
            }
            return origPlay ? origPlay.apply(this, arguments) : Promise.resolve();
          };
        }
      } catch(e) {}
    }

    fl('onBotComplete', { success:!!success, quality:quality||'', playing:false });
  }

  function step1_play(id, tries) {
    if (botBlocked() || _done || id !== _runId) return;
    tries = tries || 0;
    if (tries > 5) { finish(id, false, ''); return; }
    _step = 1;
    activatePlayerUi();
    if (isPlaying()) { log('step1: already playing'); step2_settings(id, 0); return; }
    var play = findPlay();
    if (play) { log('step1: tap play', String(play.className||play.tagName).substring(0,40)); tap(play); }
    else {

      log('step1: tapInPlayer center');
      tapInPlayer(0.5, 0.5);
    }
    setTimeout(function(){
      if (botBlocked() || _done || id !== _runId) return;
      if (isPlaying()) step2_settings(id, 0);
      else step1_play(id, tries+1);
    }, 900);
  }

  function step2_settings(id, tries) {
    if (botBlocked() || _done || id !== _runId) return;
    tries = tries || 0;
    if (tries > 8) { var cur=getCurrentQuality(); finish(id,isBotAcceptedFinalQuality(cur)&&isPlaying(),cur); return; }
    _step = 2;
    activatePlayerUi();
    if (settingsOpen()) { log('step2: menu already open at try', tries); step3_quality(id, 0); return; }
    var clickDelay = 750;
    if (tries === 0) {
      clickQualityButton(); clickDelay = 800;
    } else if (tries === 1) {
      try {
        var tw = getTargetWin();
        var p = getVjsPlayer();
        if (p && p.controlBar) {
          var qs = p.controlBar.getChild('QualitySelector') || p.controlBar.getChild('qualitySelector');
          if (qs) { var qsEl = qs.el&&qs.el(); if (qsEl) tap(qsEl.querySelector('button')||qsEl); }
        }
      } catch(e) {}
      clickDelay = 900;
    } else if (tries === 2) {
      activatePlayerUi();
      setTimeout(function(){ clickQualityButton(); }, 120);
      clickDelay = 900;
    } else {
      // ابعد اللمس عن الزاوية السفلية اليمنى حتى لا يضغط fullscreen ويطلق reload/onLoadStop.
      var pxOffsets = [0.82, 0.86, 0.78, 0.90];
      tapInPlayer(pxOffsets[tries % pxOffsets.length], 0.88);
      clickDelay = 700;
    }
    setTimeout(function(){
      if (botBlocked() || _done || id !== _runId) return;
      if (settingsOpen()) { log('step2: menu opened at try', tries); step3_quality(id, 0); }
      else { log('step2: retry', tries+1); step2_settings(id, tries+1); }
    }, clickDelay);
  }

  function step3_quality(id, tries) {
    if (botBlocked() || _done || id !== _runId) return;
    tries = tries || 0;
    if (tries > 6) { var cur=getCurrentQuality(); finish(id,isBotAcceptedFinalQuality(cur),cur); return; }
    _step = 3;
    var opts = getQualityOpts();
    log('step3: opts=', opts.map(function(o){return o.q+':'+o.txt;}).join(' | '));
    if (!opts.length) { activatePlayerUi(); clickQualityButton(); setTimeout(function(){ if(_done||id!==_runId)return; step3_quality(id,tries+1); }, 650); return; }
    var preferred = ['1080p','720p','480p','360p','240p'];
    var target = null;
    for (var p = 0; p < preferred.length && !target; p++) {
      for (var i = 0; i < opts.length; i++) { if (opts[i].q === preferred[p] && !opts[i].premium) { target = opts[i]; break; } }
    }
    if (!target) { finish(id, false, getCurrentQuality()); return; }
    _targetQuality = target.q;
    if (target.selected && target.q === _targetQuality) { log('step3: target already selected', _targetQuality); step4_ensurePlaying(id, target.q, 0); return; }
    var targetHref = elementUrl(target.el);
    if (isAnimeQualityPageUrl(targetHref)) { log('step3: blocked page quality link', targetHref); finish(id, false, getCurrentQuality()); return; }
    log('step3: tap quality', target.q, target.txt);
    var safeToClick = true;
    try {
      var tHref = (target.el.href || (target.el.getAttribute && (target.el.getAttribute('href') || target.el.getAttribute('data-url') || '')) || '').trim();
      if (tHref && isAnimeQualityPageUrl(tHref)) {
        log('step3: blocked navigation link', tHref);
        finish(id, false, getCurrentQuality());
        return;
      }
      if (tHref && tHref.startsWith('http') && !insideRealPlayer(target.el)) {
        log('step3: external href detected, using safe click');
        try { target.el.click(); } catch(e) {}
        safeToClick = false;
      }
    } catch(e) {}
    if (safeToClick) tap(target.el);
    setTimeout(function(){ if(_done||id!==_runId)return; step4_ensurePlaying(id, target.q, 0); }, 950);
  }

  function step4_ensurePlaying(id, quality, tries) {
    if (botBlocked() || _done || id !== _runId) return;
    tries = tries || 0;
    if (tries > 4) { var cur=getCurrentQuality()||quality; finish(id,isBotAcceptedFinalQuality(cur)&&isPlaying(),cur); return; }
    _step = 4;
    activatePlayerUi();
    var currentQ = getCurrentQuality() || quality;
    if (isPlaying() && currentQ) { finish(id,isBotAcceptedFinalQuality(currentQ),currentQ); return; }
    var play = findPlay();
    if (play) { log('step4: tap play again'); tap(play); }
    else { tapInPlayer(0.5, 0.5); }
    setTimeout(function(){ if(_done||id!==_runId)return; step4_ensurePlaying(id, quality, tries+1); }, 850);
  }

  window.__asdRunPreciseBot = function() {
    if (botBlocked()) { log('run skipped: suppressed'); return; }
    if (!isWatchCtx()) return;
    _done = false; _step = 0; _targetQuality = ''; _runId++;
    log('run', 'vid3rb='+_inVid3rb, 'url='+window.location.href);
    step1_play(_runId, 0);
  };

  window.__asdResetPreciseBot = function() { _done = botBlocked(); _step = 0; _targetQuality = ''; _runId++; };

  if (_inVid3rb) {
    [1200, 2600, 4200].forEach(function(delay) {
      setTimeout(function() {
        if (botBlocked() || _done || !isWatchCtx()) return;
        _done = false; _step = 0; _targetQuality = ''; _runId++;
        log('auto-run', 'delay='+delay);
        step1_play(_runId, 0);
      }, delay);
    });
  }

  log('Installed on:', window.location.href, '| vid3rb:', _inVid3rb);
})();
""";

  // ─────────────────────────────────────────────────────────────────────────

  String _normalizeQualityLabel(String input) {
    final m = RegExp(r'(2160|1440|1080|720|540|480|360|240)\s*p?', caseSensitive: false)
        .firstMatch(input);
    if (m != null) return '${m.group(1)}p';
    return input.trim();
  }

  void _updatePageQualityOptions(
      List<PageQualityOption> options, [String? currentLabel]) {
    final seen = <String>{};
    final list = <PageQualityOption>[];
    for (final opt in options) {
      final norm = _normalizeQualityLabel(opt.label.trim());
      if (norm.isEmpty) continue;
      if (!seen.add(norm.toLowerCase())) continue;
      list.add(PageQualityOption(
        label: norm.isNotEmpty ? norm : opt.label,
        key: opt.key.isNotEmpty ? opt.key : norm.toLowerCase(),
        url: opt.url,
        selected: opt.selected,
      ));
    }
    _pageQualityOptions = list;
    _currentPageQualityLabel = currentLabel?.trim().isNotEmpty == true
        ? _normalizeQualityLabel(currentLabel!)
        : (list.firstWhere(
                (e) => e.selected,
                orElse: () => list.isNotEmpty
                    ? list.first
                    : const PageQualityOption(label: '', key: ''),
              )
            .label);
    if (_currentPageQualityLabel?.isEmpty ?? true) {
      _currentPageQualityLabel = null;
    }
  }


  Future<void> _switchPageQuality(PageQualityOption option) async {
    if (_wc == null) return;
    final normalizedLabel = _normalizeQualityLabel(option.label);

    if (mounted) {
      setState(() => _currentPageQualityLabel = normalizedLabel);
    } else {
      _currentPageQualityLabel = normalizedLabel;
    }

    _pendingNativeStartTime = _capturedVideoTime;

    final directOptionUrl = (option.url ?? '').trim();
    if (_looksLikePlayableMediaUrl(directOptionUrl)) {
      _qualitySwitchPending = false;
      _manualPlayAfterQualitySwitchPending = false;
      await _openNativePlayer(
        force: true,
        replace: true,
        startTimeOverride: _pendingNativeStartTime,
        forcedUrl: directOptionUrl,
        forcedPageUrl: _capturedVideoPageUrl ?? _currentPageUrl,
        forcedMimeType: _inferMimeType(directOptionUrl),
      );
      return;
    }

    final cachedUrl = (_qualityDirectUrls[normalizedLabel] ?? '').trim();
    if (cachedUrl.isNotEmpty && _looksLikePlayableMediaUrl(cachedUrl)) {
      _qualitySwitchPending = false;
      _manualPlayAfterQualitySwitchPending = false;
      await _openNativePlayer(
        force: true,
        replace: true,
        startTimeOverride: _pendingNativeStartTime,
        forcedUrl: cachedUrl,
        forcedPageUrl: _capturedVideoPageUrl ?? _currentPageUrl,
        forcedMimeType: _inferMimeType(cachedUrl),
      );
      return;
    }

    _qualitySwitchPending = true;
    _manualPlayAfterQualitySwitchPending = _nativePlayerActive || _nativePlayerOpening;
    _qualityDirectUrls.remove(normalizedLabel);

    debugPrint('🔄 Switching quality to: $normalizedLabel (fresh token)');

    final optionUrl = (option.url ?? '').trim();
    if (_isAnimeQualityPageUrl(optionUrl)) {
      
      _qualitySwitchPending = false;
      _manualPlayAfterQualitySwitchPending = false;
      await _forcePreferred1080();
      await _primeWatchPageCapture();
      _showSnack('تم فرض الجودة داخل المشغل بدون إعادة تحميل الصفحة');
      return;
    }

    bool clicked = false;
    try {
      final raw = await _wc!.evaluateJavascript(source: '''
        (function(){
          var frames = document.querySelectorAll('iframe');
          for (var i = 0; i < frames.length; i++) {
            try {
              var fw = frames[i].contentWindow;
              if (!fw) continue;
              if (fw.jwplayer) {
                var jw = fw.jwplayer();
                if (!jw || !jw.getQualityLevels) continue;
                var levels = jw.getQualityLevels();
                var norm = ${jsonEncode(normalizedLabel)}.toLowerCase().replace('p','');
                for (var j = 0; j < levels.length; j++) {
                  var lbl = (levels[j].label || '').toLowerCase().replace(/s/g,'').replace('p','');
                  if (lbl === norm) {
                    jw.setCurrentQuality(j);
                    return true;
                  }
                }
              }
              if (fw.__asdSelectQualityOption) {
                var res = fw.__asdSelectQualityOption(
                  ${jsonEncode(option.key)}, ${jsonEncode(option.label)}, ${jsonEncode(optionUrl)}
                );
                if (res) return true;
              }
            } catch(e) {}
          }
          try {
            if (window.__asdSelectQualityOption) {
              return !!window.__asdSelectQualityOption(
                ${jsonEncode(option.key)}, ${jsonEncode(option.label)}, ${jsonEncode(optionUrl)}
              );
            }
          } catch(e) {}
          return false;
        })();
      ''');
      clicked = raw == true || raw?.toString() == 'true';
    } catch (_) {}

    if (!clicked) {
      _qualitySwitchPending = false;
      _manualPlayAfterQualitySwitchPending = false;
      _showSnack('⚠️ تعذّر تغيير الجودة إلى: $normalizedLabel');
      return;
    }

    Future.delayed(const Duration(seconds: 10), () {
      if (_qualitySwitchPending) {
        _qualitySwitchPending = false;
        _manualPlayAfterQualitySwitchPending = false;
        _showSnack('⚠️ لم يُلتقط رابط الجودة الجديد: $normalizedLabel');
      }
    });

    if (_nativePlayerActive) {
      try {
        await _pip.invokeMethod('updateQualityOptions', {
          'qualityOptions': _pageQualityOptions.map((e) => e.toMap()).toList(),
          'currentQualityLabel': normalizedLabel,
        });
      } catch (_) {}
    }
  }

  void _updateServerOptions(List<PageServerOption> options, [String? currentLabel]) {
    final seen = <String>{};
    final list = <PageServerOption>[];
    for (final opt in options) {
      final label = opt.label.trim();
      if (label.isEmpty) continue;
      final key   = opt.key.isNotEmpty ? opt.key : '${label}_${list.length}';
      final dedupe = '${label.toLowerCase()}|${(opt.embedUrl ?? '').toLowerCase()}';
      if (seen.contains(dedupe)) continue;
      seen.add(dedupe);
      list.add(PageServerOption(label: label, key: key, embedUrl: opt.embedUrl, selected: opt.selected));
    }
    _pageServerOptions = list;
    _currentServerLabel = (currentLabel?.trim().isNotEmpty == true)
        ? currentLabel
        : list.firstWhere((e) => e.selected,
              orElse: () => list.isNotEmpty ? list.first : const PageServerOption(label:'',key:'')).label;
  }

  Future<void> _switchServer(PageServerOption option) async {
    if (_wc == null) return;
    if (mounted) {
      setState(() => _currentServerLabel = option.label);
    } else {
      _currentServerLabel = option.label;
    }

    
    _capturedVideoUrl       = null;
    _capturedVideoTime      = 0;
    _capturedVideoMimeType  = null;
    _serverSwitchPending    = true;

    
    if (_looksLikePlayableMediaUrl(option.embedUrl)) {
      _serverSwitchPending = false;
      await _openNativePlayer(
        force: true,
        replace: true,
        forcedUrl: option.embedUrl,
        forcedPageUrl: _capturedVideoPageUrl,
        forcedMimeType: _inferMimeType(option.embedUrl),
      );
      return;
    }

    
    bool clicked = false;
    try {
      final raw = await _wc!.evaluateJavascript(source: '''
        (function(){
          try {
            if (!window.__asdSelectServer) return false;
            return !!window.__asdSelectServer(
              ${jsonEncode(option.key)},
              ${jsonEncode(option.label)},
              ${jsonEncode(option.embedUrl ?? '')}
            );
          } catch(e) { return false; }
        })();
      ''');
      clicked = raw == true || raw?.toString() == 'true';
    } catch (_) {}

    if (!clicked) {
      _serverSwitchPending = false;
      _showSnack('⚠️ تعذّر تغيير السيرفر');
      return;
    }

    
    Future.delayed(const Duration(seconds: 4), () {
      if (_serverSwitchPending) {
        _serverSwitchPending = false;
        _showSnack('⚠️ لم ألتقط رابط السيرفر الجديد');
      }
    });
  }

  // ✅ FIX 2: _safePipAspectRatio — fixed math, safe clamping
  //    Old bug: fallback 5:12 = 0.4166 < minRatio 0.418410 → still caused error
  //    New: any out-of-range ratio falls back to safe 16:9 directly
  // ─────────────────────────────────────────────────────────────────────────
  Map<String, int> _safePipAspectRatio() {
    // Android PiP requires: 0.418410 ≤ w/h ≤ 2.390000
    // Use slightly stricter bounds to avoid edge cases
    const double minRatio = 0.42;
    const double maxRatio = 2.38;

    int w = _videoAspectW > 0 ? _videoAspectW : 16;
    int h = _videoAspectH > 0 ? _videoAspectH : 9;

    // Validate inputs
    if (w <= 0 || h <= 0) return {'w': 16, 'h': 9};

    final double ratio = w / h;

    // If ratio is outside safe range, always return 16:9 — never risk it
    if (ratio < minRatio || ratio > maxRatio) {
      return {'w': 16, 'h': 9};
    }

    // Reduce to smallest integers via GCD
    int gcd(int a, int b) => b == 0 ? a : gcd(b, a % b);
    final g = gcd(w.abs(), h.abs());
    final rw = w ~/ g;
    final rh = h ~/ g;

    // If reduced values are too large for Android Rational, fall back to 16:9
    if (rw > 239 || rh > 239 || rw <= 0 || rh <= 0) {
      return {'w': 16, 'h': 9};
    }

    // Final safety check on reduced ratio (GCD reduction can theoretically drift)
    final double reducedRatio = rw / rh;
    if (reducedRatio < minRatio || reducedRatio > maxRatio) {
      return {'w': 16, 'h': 9};
    }

    return {'w': rw, 'h': rh};
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _ptr = PullToRefreshController(
      settings: PullToRefreshSettings(color: Colors.orange),
      onRefresh: () async => await _wc?.reload(),
    );

    
    

    _pip.setMethodCallHandler((call) async {
      if (!mounted) return;
      if (call.method == 'onPipChanged') {
        final isInPip = call.arguments as bool? ?? false;
        setState(() => _inPip = isInPip);
        if (!isInPip && !_nativePlayerActive) {
          await _restoreUI();
        }
      } else if (call.method == 'onNativePlayerChanged') {
        final active = call.arguments as bool? ?? false;
        setState(() {
          _nativePlayerActive = active;
          if (!active) _lastNativePlayerUrl = null;
          _videoPlaying = active ? false : _videoPlaying;
        });
        if (active) {
          _stopSitePlayerRectTracking(clear: true);
          _suppressAutoOpenUntil = 0;
          await _pauseOriginalSitePlayer();
          _scheduleOriginalPlayerHardPause();
          await _suspendWebViewForNative();
        } else {
          _suppressAutoOpenUntil = DateTime.now().millisecondsSinceEpoch + (_preventAutoReopenAfterClose ? 15000 : 1200);
          await _releaseOriginalSitePlayerBlock();
          await _resumeWebViewAfterNative();
          await _restoreUI();
          if (_showQuickMediaButtons) {
            _startSitePlayerRectTracking();
          }
          if (_preventAutoReopenAfterClose) {
            _popRouteIfHiddenLaunch();
          }
        }
      } else if (call.method == 'onNativePipError') {
        _nativePlayerOpening = false;
        final message = call.arguments?.toString();
        if (message != null && message.isNotEmpty) _showSnack('⚠️ $message');
      } else if (call.method == 'onQualitySelected') {
        final arg = call.arguments;
        if (arg is Map) {
          final option = PageQualityOption.fromMap(Map<String, dynamic>.from(arg));
          await _switchPageQuality(option);
        }
      } else if (call.method == 'onServerSelected') {
        final arg = call.arguments;
        if (arg is Map) {
          final option = PageServerOption.fromMap(Map<String, dynamic>.from(arg));
          await _switchServer(option);
        }
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideSitePlayerActionOverlay();
    _stopSitePlayerRectTracking(clear: false);
    _restoreUI();
    _backgroundDownloadSyncTimer?.cancel();
    _backgroundDownloadSyncTimer = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      Future.microtask(_pauseNativePlayerForAppBackground);
      return;
    }

    if (state == AppLifecycleState.resumed && mounted) {
      _nativePauseSentForBackground = false;
      setState(() => _inPip = false);

      
      
      if (!_nativePlayerActive && _showQuickMediaButtons) {
        Future.microtask(_startSitePlayerRectTracking);
      }
    }
  }

  Future<void> _pauseNativePlayerForAppBackground() async {
    if (_inPip) return;
    if (!_nativePlayerActive && !_nativePlayerOpening) return;
    if (_nativePauseSentForBackground) return;

    _nativePauseSentForBackground = true;

    Future<bool> callNativePause(String method, [Map<String, dynamic>? args]) async {
      try {
        final result = await _pip.invokeMethod<bool>(method, args);
        return result != false;
      } on MissingPluginException {
        return false;
      } catch (_) {
        return false;
      }
    }

    
    
    if (await callNativePause('pauseNativePlayer', {
      'keepOpen': true,
      'reason': 'app_lifecycle',
    })) {
      return;
    }

    if (await callNativePause('setNativePlayerPaused', {
      'paused': true,
      'keepOpen': true,
      'reason': 'app_lifecycle',
    })) {
      return;
    }

    await callNativePause('pausePlayer', {
      'keepOpen': true,
      'reason': 'app_lifecycle',
    });
  }

  String? _normalizeWatchReturnUrl(String? rawUrl) {
    final value = (rawUrl ?? '').trim();
    if (value.isEmpty) return null;

    final uri = Uri.tryParse(value);
    if (uri == null) return value;

    final cleaned = uri.replace(fragment: '');
    return cleaned.toString();
  }

  bool _isSameDocumentUrl(String? a, String? b) {
    final first = _normalizeWatchReturnUrl(a);
    final second = _normalizeWatchReturnUrl(b);
    if (first == null || second == null || first.isEmpty || second.isEmpty) {
      return false;
    }

    final ua = Uri.tryParse(first);
    final ub = Uri.tryParse(second);
    if (ua == null || ub == null) return first == second;

    String cleanPath(Uri u) {
      var path = Uri.decodeComponent(u.path).trim();
      if (path.length > 1 && path.endsWith('/')) {
        path = path.substring(0, path.length - 1);
      }
      return path;
    }

    return ua.scheme.toLowerCase() == ub.scheme.toLowerCase() &&
        ua.host.toLowerCase() == ub.host.toLowerCase() &&
        cleanPath(ua) == cleanPath(ub) &&
        ua.query == ub.query;
  }

  bool _isWatchLikeUrl(String? rawUrl) {
    final value = (rawUrl ?? '').trim();
    if (value.isEmpty) return false;

    final lower = value.toLowerCase();
    if (lower == 'about:blank' ||
        lower.startsWith('data:') ||
        lower.startsWith('javascript:') ||
        lower.startsWith('blob:')) {
      return false;
    }

    final uri = Uri.tryParse(value);
    final host = uri?.host.toLowerCase() ?? '';
    final path = uri?.path.toLowerCase() ?? lower;

    if (host.contains('video.vid3rb.com') ||
        host.contains('files.vid3rb.com') ||
        host.contains('vid3rb.com')) {
      return false;
    }

    if (host.contains('anime3rb.com') || host == 'anime3rb.com') {
      if (path.contains('/download') || path.contains('/category/download')) {
        return false;
      }
      return path.contains('/watch/') ||
          path.contains('/episode/') ||
          path.contains('/movie/') ||
          path.contains('/titles/') ||
          path.contains('/anime/') ||
          lower.contains('play=true') ||
          lower.contains('%d9%85%d8%b4%d8%a7%d9%87');
    }

    return lower.contains('/watch/') ||
        lower.contains('play=true') ||
        lower.contains('%d9%85%d8%b4%d8%a7%d9%87');
  }

  void _rememberStableWatchUrl([String? rawUrl]) {
    final normalized = _normalizeWatchReturnUrl(rawUrl);
    if (normalized == null || normalized.isEmpty) return;
    if (_isWatchLikeUrl(normalized)) {
      _lastStableWatchUrl = normalized;
    }
  }

  bool _isGoodAnimePageUrl(String? rawUrl) {
    final value = (rawUrl ?? '').trim();
    if (value.isEmpty || value == 'about:blank') return false;
    final uri = Uri.tryParse(value);
    if (uri == null) return false;
    final host = uri.host.toLowerCase();
    if (!host.endsWith('anime3rb.com')) return false;
    final lower = value.toLowerCase();
    if (_isB(lower) || _isAdResourceUrl(lower)) return false;
    if (_looksLikePlayableMediaUrl(lower)) return false;
    if (lower.contains('/build/assets/') ||
        lower.contains('/livewire/') ||
        lower.contains('/cf-fonts/') ||
        lower.contains('/favicon') ||
        lower.contains('/images/')) {
      return false;
    }
    return true;
  }

  void _rememberGoodAnimePage([String? rawUrl]) {
    final normalized = _normalizeWatchReturnUrl(rawUrl);
    if (!_isGoodAnimePageUrl(normalized)) return;

    _lastGoodAnimePageUrl = normalized;

    if (_animePageHistory.isEmpty) {
      _animePageHistory.add(normalized!);
      return;
    }

    if (_safeBackInProgress) {
      
      if (_animePageHistory.length > 1 && _animePageHistory.last != normalized) {
        _animePageHistory.removeLast();
      }
      if (_animePageHistory.isEmpty || _animePageHistory.last != normalized) {
        _animePageHistory.add(normalized!);
      }
      return;
    }

    if (_animePageHistory.last == normalized) return;
    _animePageHistory.add(normalized!);
    if (_animePageHistory.length > 30) {
      _animePageHistory.removeRange(0, _animePageHistory.length - 30);
    }
  }

  String? _previousGoodAnimePage() {
    if (_animePageHistory.length >= 2) return _animePageHistory[_animePageHistory.length - 2];
    return _lastGoodAnimePageUrl ?? _normalizeWatchReturnUrl(widget.initialUrl);
  }

  Future<void> _goBackToSafeAnimePage() async {
    final controller = _wc;
    if (controller == null) {
      if (context.mounted) SystemNavigator.pop();
      return;
    }

    if (_safeBackInProgress) return;
    _safeBackInProgress = true;

    final fallback = _previousGoodAnimePage() ?? 'https://anime3rb.com/';

    try {
      final current = (await controller.getUrl())?.toString();

      
      if ((current == null || current.isEmpty || current == 'about:blank')) {
        await controller.loadUrl(
          urlRequest: URLRequest(
            url: WebUri(fallback),
            headers: const {'User-Agent': _ua},
          ),
        );
        return;
      }

      if (await controller.canGoBack()) {
        await controller.goBack();

        await Future.delayed(const Duration(milliseconds: 420));

        final after = (await controller.getUrl())?.toString();
        if (!_isGoodAnimePageUrl(after)) {
          await controller.loadUrl(
            urlRequest: URLRequest(
              url: WebUri(fallback),
              headers: const {'User-Agent': _ua},
            ),
          );
        }
        return;
      }

      if (context.mounted) SystemNavigator.pop();
    } catch (_) {
      try {
        await controller.loadUrl(
          urlRequest: URLRequest(
            url: WebUri(fallback),
            headers: const {'User-Agent': _ua},
          ),
        );
      } catch (_) {
        if (context.mounted) SystemNavigator.pop();
      }
    } finally {
      Future.delayed(const Duration(milliseconds: 650), () {
        _safeBackInProgress = false;
      });
    }
  }

  Future<void> _returnToWatchPage() async {
    
    
    
    return;
  }

  Future<String?> _createVideoThumbnail(String videoPath) async {
    if (!Platform.isAndroid && !Platform.isIOS) return null;
    try {
      final tempDir = await getTemporaryDirectory();
      return await VideoThumbnail.thumbnailFile(
        video: videoPath,
        thumbnailPath: tempDir.path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 420,
        quality: 85,
      );
    } catch (_) {
      return null;
    }
  }


  Future<void> _startDownload(String url, String fileName) async {
    if (_discoveredDownloadUrls.contains(url)) return;
    _discoveredDownloadUrls.add(url);

    final safeName = _sanitizeFileName(fileName);
    final dir = await _downloadsBaseDir();
    final fullPath = '${dir.path}/$safeName';
    final tempPath = '$fullPath.downloading';
    final item = DownloadItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      url: url,
      fileName: safeName,
      savedPath: tempPath,
      tempPath: tempPath,
      finalPath: fullPath,
      status: 'preparing',
    );

    if (mounted) setState(() { _downloads.insert(0, item); });
    _openDownloadsPanel();

    final ok = await _enqueueBackgroundDirectDownload(
      item,
      headers: _downloadHeaders(url),
      pageUrl: _capturedVideoPageUrl ?? _currentPageUrl ?? _lastTrusted,
    );
    if (!ok) _discoveredDownloadUrls.remove(url);
  }


  Future<void> _cancelDownload(DownloadItem item) async {
    await BackgroundDownloadBridge.cancel(item.id);
    item.cancelToken?.cancel('cancelled by user');
    if (!mounted) return;
    setState(() { item.status = 'cancelled'; item.progress = 0; });
    _discoveredDownloadUrls.remove(item.url);
    if (item.savedPath != null) {
      final file = File(item.savedPath!);
      if (await file.exists()) { try { await file.delete(); } catch (_) {} }
    }
    _showSnack('⛔ تم إلغاء التحميل: ${item.fileName}');
  }

  Future<void> _playVideo(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      _showSnack('⚠️ ملف الفيديو غير موجود');
      return;
    }

    final fileUrl = Uri.file(file.path).toString();
    await _openNativePlayer(
      force: true,
      replace: true,
      allowInDownloadOnlyMode: true,
      startTimeOverride: 0,
      forcedUrl: fileUrl,
      forcedPageUrl: fileUrl,
      forcedMimeType: _inferMimeType(fileUrl) ?? 'video/mp4',
    );
  }

  Future<void> _confirmDelete(DownloadItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF18212C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('حذف التحميل', style: TextStyle(color: Colors.white)),
        content: Text('هل تريد حذف "${item.fileName}" ؟', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await BackgroundDownloadBridge.delete(item.id);
      item.cancelToken?.cancel('deleted by user');
      if (item.resumeCompleter != null && !item.resumeCompleter!.isCompleted) {
        item.resumeCompleter!.complete();
      }
      final pathsToDelete = <String>{
        if (item.savedPath != null && item.savedPath!.isNotEmpty) item.savedPath!,
        if (item.tempPath != null && item.tempPath!.isNotEmpty) item.tempPath!,
        if (item.finalPath != null && item.finalPath!.isNotEmpty) item.finalPath!,
        if (item.thumbnailPath != null && item.thumbnailPath!.isNotEmpty) item.thumbnailPath!,
      };
      for (final path in pathsToDelete) {
        try {
          final file = File(path);
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
      _discoveredDownloadUrls.remove(item.url);
      setState(() { _downloads.remove(item); });
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: const Color(0xFF18212C),
      behavior: SnackBarBehavior.floating,
    ));
  }



  
  static const String _backgroundDownloadSource = 'Anime';

  void _ensureBackgroundDownloadPolling() {
    _backgroundDownloadSyncTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) unawaited(_syncBackgroundDownloads());
    });
    unawaited(_syncBackgroundDownloads());
  }

  Future<void> _syncBackgroundDownloads() async {
    final snapshots = await BackgroundDownloadBridge.list(source: _backgroundDownloadSource);
    if (!mounted) return;
    final existingById = <String, DownloadItem>{for (final item in _downloads) item.id: item};
    var changed = false;
    for (final snap in snapshots) {
      var item = existingById[snap.id];
      if (item == null) {
        item = DownloadItem(
          id: snap.id,
          url: snap.url,
          fileName: snap.fileName,
          progress: snap.progress,
          status: snap.status,
          savedPath: snap.status == 'done' ? snap.finalPath : snap.tempPath,
          tempPath: snap.tempPath,
          finalPath: snap.finalPath,
          errorMessage: snap.errorMessage,
        );
        _downloads.insert(0, item);
        existingById[snap.id] = item;
        changed = true;
      }
      final nextSavedPath = snap.status == 'done' ? snap.finalPath : snap.tempPath;
      if (item.progress != snap.progress ||
          item.status != snap.status ||
          item.savedPath != nextSavedPath ||
          item.errorMessage != snap.errorMessage) {
        item.progress = snap.progress;
        item.status = snap.status;
        item.savedPath = nextSavedPath;
        item.tempPath = snap.tempPath;
        item.finalPath = snap.finalPath;
        item.errorMessage = snap.errorMessage;
        changed = true;
      }
    }
    if (changed && mounted) setState(() {});
  }

  Future<bool> _enqueueBackgroundDirectDownload(
    DownloadItem item, {
    Map<String, dynamic> headers = const <String, dynamic>{},
    String? pageUrl,
    String? qualityLabel,
  }) async {
    final normalizedHeaders = <String, String>{
      for (final entry in headers.entries)
        if (entry.key.toString().trim().isNotEmpty && entry.value.toString().trim().isNotEmpty)
          entry.key.toString(): entry.value.toString(),
    };
    try {
      await BackgroundDownloadBridge.enqueue(
        id: item.id,
        source: _backgroundDownloadSource,
        type: 'direct',
        url: item.url,
        fileName: item.fileName,
        tempPath: item.tempPath ?? item.savedPath ?? '',
        finalPath: item.finalPath ?? item.savedPath ?? '',
        headers: normalizedHeaders,
        pageUrl: pageUrl,
        qualityLabel: qualityLabel,
      );
      item.status = 'downloading';
      if (mounted) setState(() {});
      _ensureBackgroundDownloadPolling();
      _showSnack('⬇️ التحميل مستمر في الخلفية ويمكن إيقافه/استئنافه من الإشعار');
      return true;
    } catch (e) {
      item.status = 'error';
      item.errorMessage = e.toString();
      if (mounted) setState(() {});
      _showSnack('❌ تعذّر بدء تحميل الخلفية');
      return false;
    }
  }

  Future<bool> _enqueueBackgroundHlsDownload(
    DownloadItem item, {
    Map<String, dynamic> headers = const <String, dynamic>{},
    String? pageUrl,
    String? qualityLabel,
  }) async {
    final normalizedHeaders = <String, String>{
      for (final entry in headers.entries)
        if (entry.key.toString().trim().isNotEmpty && entry.value.toString().trim().isNotEmpty)
          entry.key.toString(): entry.value.toString(),
    };
    try {
      await BackgroundDownloadBridge.enqueue(
        id: item.id,
        source: _backgroundDownloadSource,
        type: 'hls',
        url: item.url,
        fileName: item.fileName,
        tempPath: item.tempPath ?? item.savedPath ?? '',
        finalPath: item.finalPath ?? item.savedPath ?? '',
        headers: normalizedHeaders,
        pageUrl: pageUrl,
        qualityLabel: qualityLabel,
      );
      item.status = 'downloading';
      if (mounted) setState(() {});
      _ensureBackgroundDownloadPolling();
      _showSnack('⬇️ تحميل HLS مستمر في الخلفية ويمكن إيقافه/استئنافه من الإشعار');
      return true;
    } catch (e) {
      item.status = 'error';
      item.errorMessage = e.toString();
      if (mounted) setState(() {});
      _showSnack('❌ تعذّر بدء تحميل HLS بالخلفية');
      return false;
    }
  }

Future<void> _waitIfDownloadPaused(DownloadItem item) async {
    if (!item.pauseRequested) return;
    if (item.status != 'paused') {
      item.status = 'paused';
      if (mounted) setState(() {});
    }
    item.resumeCompleter ??= Completer<void>();
    await item.resumeCompleter!.future;
    item.resumeCompleter = null;
    item.pauseRequested = false;
    item.status = 'downloading';
    if (mounted) setState(() {});
  }

  Future<void> _pauseDownload(DownloadItem item) async {
    if (item.status != 'downloading' && item.status != 'preparing') return;
    item.pauseRequested = true;
    await BackgroundDownloadBridge.pause(item.id);
    item.status = 'paused';
    if (mounted) setState(() {});
    _showSnack('⏸️ تم إيقاف التحميل مؤقتًا: ${item.fileName}');
  }

  Future<void> _resumeDownload(DownloadItem item) async {
    if (item.status != 'paused') return;
    if (item.resumeCompleter != null && !item.resumeCompleter!.isCompleted) {
      item.resumeCompleter!.complete();
    }
    await BackgroundDownloadBridge.resume(item.id);
    item.pauseRequested = false;
    item.status = 'downloading';
    if (mounted) setState(() {});
    _showSnack('▶️ تم استئناف التحميل: ${item.fileName}');
  }

  void _openDownloadsPanel() { if (!mounted) return; setState(() { _showDownloads = true; }); }
  void _closeDownloadsPanel() { if (!mounted) return; setState(() { _showDownloads = false; }); }

  Future<bool> _isPipSupported() async {
    if (!Platform.isAndroid) return true;
    try { return await _pip.invokeMethod<bool>('isPipSupported') ?? false; }
    on MissingPluginException { return false; }
    catch (_) { return false; }
  }

  void _popRouteIfHiddenLaunch() {
    if (!widget.launchHidden || widget.downloadOnlyMode || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final nav = Navigator.of(context, rootNavigator: true);
      if (nav.canPop()) {
        nav.pop();
      }
    });
  }

  bool get _allowNativeAutoOpen =>
      widget.launchHidden &&
      !widget.downloadOnlyMode &&
      !widget.autoDownloadPrompt &&
      !_preventAutoReopenAfterClose;

  bool _isPremiumQualityLabel(String? raw) {
    final compact = (raw ?? '').toLowerCase().replaceAll(RegExp(r'\s+'), '');
    if (compact.isEmpty) return false;
    return compact.contains('premium') || compact.contains('vip');
  }

  bool _isBotRelevantWatchPage() {
    return _isWatchLikeUrl(_currentPageUrl) ||
        _isWatchLikeUrl(_capturedVideoPageUrl) ||
        _isWatchLikeUrl(_lastStableWatchUrl);
  }

  bool _isBotAcceptedQuality(String? raw) {
    if (_isPremiumQualityLabel(raw)) return false;
    final norm = _normalizeQualityLabel(raw ?? '');
    const preferred = ['1080p', '720p', '480p', '360p', '240p'];
    return preferred.contains(norm);
  }

  String _botTargetQualityFromOptions([Iterable<PageQualityOption>? source]) {
    const preferred = ['1080p', '720p', '480p', '360p', '240p'];
    final options = (source ?? _pageQualityOptions).toList();
    for (final wanted in preferred) {
      for (final opt in options) {
        final label = _normalizeQualityLabel(opt.label);
        if (label == wanted && !_isPremiumQualityLabel(opt.label)) return wanted;
      }
    }
    final manualTarget = _normalizeQualityLabel(_botPreferredTargetQuality ?? '');
    if (preferred.contains(manualTarget)) return manualTarget;
    return '';
  }

  bool _isBotConfirmed1080([String? raw]) {
    bool acceptedAgainstTarget(String? value) {
      final direct = (value ?? '').trim();
      if (direct.isEmpty || _isPremiumQualityLabel(direct)) return false;
      final norm = _normalizeQualityLabel(direct);
      if (!_isBotAcceptedQuality(norm)) return false;
      final target = _botTargetQualityFromOptions();
      if (target.isNotEmpty) return norm == target;
      return norm == '1080p';
    }

    if (acceptedAgainstTarget(raw)) return true;
    if (_currentQualityIsPremium) return false;
    final candidates = <String?>[
      _botConfirmedQuality,
      _currentPageQualityLabel,
    ];
    for (final candidate in candidates) {
      if (acceptedAgainstTarget(candidate)) return true;
    }
    return false;
  }

  void _finishPreferredQualityBotGate([String reason = '']) {
    if (_preferredQualityBotReady) return;
    if (widget.launchHidden && !widget.downloadOnlyMode && !_isBotConfirmed1080()) {
      _preferredQualityBotPending = false;
      _preferredQualityBotReady = false;
      debugPrint('🤖 Bot gate blocked native open until preferred quality is confirmed: $reason');
      return;
    }
    _preferredQualityBotPending = false;
    _preferredQualityBotReady = true;
    if (_allowNativeAutoOpen && !_nativePlayerActive && !_nativePlayerOpening) {
      Future.microtask(_tryAutoOpenBestQuickMedia);
    }
  }

  void _markBotGateReady(String reason, {String? quality}) {
    final normalized = _normalizeQualityLabel(quality ?? _currentPageQualityLabel ?? '');
    if (!_isBotConfirmed1080(normalized)) {
      debugPrint('🤖 Bot gate ignored non-target quality: $normalized reason=$reason');
      _preferredQualityBotReady = false;
      return;
    }
    _botPreferredTargetQuality = normalized;
    _botConfirmedQuality = normalized;
    _currentPageQualityLabel = normalized;
    _currentQualityIsPremium = false;
    if (!_botCompleted && mounted) {
      setState(() => _botCompleted = true);
    } else {
      _botCompleted = true;
    }
    _finishPreferredQualityBotGate('bot_gate:$reason');
    if (_allowNativeAutoOpen && !_nativePlayerActive && !_nativePlayerOpening) {
      Future.microtask(_tryAutoOpenBestQuickMedia);
    }
  }

  void _startPreferredQualityBotGate([String reason = 'auto']) {
    if (!_allowNativeAutoOpen || !_isBotRelevantWatchPage()) return;
    if (_preferredQualityBotPending || _preferredQualityBotReady) return;
    _preferredQualityBotPending = true;
    _preferredQualityBotStartedAt = DateTime.now().millisecondsSinceEpoch;

    Future.microtask(_forcePreferred1080);
    Future.delayed(const Duration(milliseconds: 900), () {
      if (!_preferredQualityBotPending || _preferredQualityBotReady) return;
      _forcePreferred1080();
    });
    Future.delayed(const Duration(milliseconds: 2200), () {
      if (!_preferredQualityBotPending || _preferredQualityBotReady) return;
      if (_isBotConfirmed1080()) {
        _finishPreferredQualityBotGate('confirmed_preferred_delay');
        return;
      }
      _forcePreferred1080();
    });
    Future.delayed(const Duration(milliseconds: 5200), () {
      if (!_preferredQualityBotPending || _preferredQualityBotReady) return;
      if (_isBotConfirmed1080()) {
        _finishPreferredQualityBotGate('confirmed_preferred_final');
        return;
      }
      debugPrint('🤖 Bot did not confirm preferred quality; native player will stay closed');
      _preferredQualityBotPending = false;
      _preferredQualityBotReady = false;
    });
  }

  bool _shouldHoldForPreferredQuality([String? currentQuality]) {
    if (!_allowNativeAutoOpen || !_isBotRelevantWatchPage()) return false;
    if (_preferredQualityBotReady) return false;
    if (_isBotAcceptedQuality(currentQuality ?? _currentPageQualityLabel)) return false;
    return true;
  }

  void _ensurePreferredQualityBeforeAutoOpen() {
    _startPreferredQualityBotGate('hold');
  }

void _tryAutoOpenBestQuickMedia() {
  if (!_allowNativeAutoOpen || widget.downloadOnlyMode) return;
  if (_nativePlayerActive || _nativePlayerOpening) return;
  if (_preventAutoReopenAfterClose) return;
  if (DateTime.now().millisecondsSinceEpoch < _suppressAutoOpenUntil) return;

  if (widget.launchHidden && !_isBotConfirmed1080()) {
    _startPreferredQualityBotGate('auto_open_wait_preferred_quality');
    return;
  }

  final targetQuality = _botTargetQualityFromOptions();
  final preferredItem = targetQuality.isNotEmpty ? _bestQuickMediaForQuality(targetQuality) : null;
  final item1080 = _bestQuickMediaForQuality('1080p');
  final item720 = _bestQuickMediaForQuality('720p');
  final item = preferredItem ?? item1080 ?? item720 ?? (_isBotConfirmed1080() ? _bestQuickMedia : null);
  if (item != null) {
    Future.microtask(() => _openNativePlayer(
          force: true,
          replace: true,
          forcedUrl: item.url,
          forcedPageUrl: item.pageUrl,
          forcedMimeType: item.mimeType,
        ));
    return;
  }

  final url = (_capturedVideoUrl ?? '').trim();
  if (url.isNotEmpty && !url.startsWith('blob:') && _isBotConfirmed1080()) {
    Future.microtask(() => _openNativePlayer(
          force: true,
          replace: true,
          forcedUrl: url,
          forcedPageUrl: _capturedVideoPageUrl,
          forcedMimeType: _capturedVideoMimeType,
        ));
  }
}

  void _scheduleOriginalPlayerHardPause() {
    for (final ms in const [0, 120, 260, 520, 900, 1400, 2000]) {
      Future.delayed(Duration(milliseconds: ms), () async {
        await _pauseOriginalSitePlayer();
      });
    }
  }

  bool _isAnimeQualityPageUrl(String? rawUrl) {
    final url = (rawUrl ?? '').trim();
    if (url.isEmpty || !url.startsWith('http')) return false;
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final host = uri.host.toLowerCase();
    if (!host.contains('anime3rb.com')) return false;
    final path = uri.path.toLowerCase();
    return RegExp(r'/(2160|1440|1080|720|540|480|360|240)(/)?$').hasMatch(path);
  }

  bool _isBlockingAnimeQualityPageNavigation() {
    return DateTime.now().millisecondsSinceEpoch < _blockAnimeQualityPageNavigationUntil;
  }

  void _temporarilyBlockAnimeQualityPageNavigation([int milliseconds = 6500]) {
    _blockAnimeQualityPageNavigationUntil =
        DateTime.now().millisecondsSinceEpoch + milliseconds;
  }

  List<PageQualityOption> _animeQualityPageOptions([Iterable<PageQualityOption>? source]) {
    final input = (source ?? _pageQualityOptions).toList();
    final byLabel = <String, PageQualityOption>{};
    for (final opt in input) {
      final label = _normalizeQualityLabel(opt.label);
      if (label.isEmpty) continue;
      final url = (opt.url ?? '').trim();
      if (!_isAnimeQualityPageUrl(url)) continue;
      byLabel[label] = PageQualityOption(
        label: label,
        key: opt.key.isNotEmpty ? opt.key : label.toLowerCase(),
        url: url,
        selected: opt.selected,
      );
    }
    final out = byLabel.values.toList();
    out.sort((a, b) => _qualityRankLabel(b.label).compareTo(_qualityRankLabel(a.label)));
    return out;
  }

  void _scheduleQualityHarvestIfNeeded([List<PageQualityOption>? incoming]) {
    
    return;
  }

  Future<void> _allowSitePlayerForSwitchCapture() async {
    try {
      await _wc?.evaluateJavascript(source: r'''
        (function(){
          try {
            window.__asdNativePlayerActive = false;
            try { clearInterval(window.__asdNativePauseLoop); } catch(e) {}
            window.__asdNativePauseLoop = null;
            document.querySelectorAll('video,audio').forEach(function(v){
              try {
                v.muted = true;
                v.volume = 0;
              } catch(e) {}
            });
            try {
              if (window.jwplayer) {
                var jw = window.jwplayer();
                if (jw && jw.setMute) jw.setMute(true);
              }
            } catch(e) {}
            try {
              if (window.videojs && window.videojs.getPlayers) {
                var players = window.videojs.getPlayers();
                Object.keys(players || {}).forEach(function(key) {
                  try {
                    var p = players[key];
                    if (p && p.muted) p.muted(true);
                  } catch(e) {}
                });
              }
            } catch(e) {}
          } catch(e) {}
        })();
      ''');
    } catch (_) {}
  }


  Future<void> _pauseOriginalSitePlayer() async {
    try {
      await _wc?.evaluateJavascript(source: r'''
        (function(){
          try {
            window.__asdNativePlayerActive = true;


            function stopAll(doc) {
              try {
                if (!doc) return;
                doc.querySelectorAll('video,audio').forEach(function(v){
                  try {
                    v.pause();
                    v.muted = true;
                    v.volume = 0;
                    v.autoplay = false;
                    v.removeAttribute('autoplay');
                  } catch(e) {}
                });
                try {
                  var win = doc.defaultView;
                  if (win && win.jwplayer) {
                    var jw = win.jwplayer();
                    if (jw) {
                      try { jw.setMute(true); } catch(e) {}
                      try { jw.pause(true); } catch(e) {}
                      try { jw.stop(); } catch(e) {}
                      try { jw.setVolume(0); } catch(e) {}
                    }
                  }
                } catch(e) {}
                try {
                  var win2 = doc.defaultView;
                  if (win2 && win2.videojs && win2.videojs.getPlayers) {
                    var players = win2.videojs.getPlayers();
                    Object.keys(players || {}).forEach(function(k) {
                      try {
                        var p = players[k];
                        if (p) {
                          try { p.muted(true); } catch(e) {}
                          try { p.pause(); } catch(e) {}
                        }
                      } catch(e) {}
                    });
                  }
                } catch(e) {}
              } catch(e) {}
            }

            stopAll(document);

            try {
              document.querySelectorAll('iframe').forEach(function(fr) {
                try {
                  var fd = fr.contentDocument || (fr.contentWindow && fr.contentWindow.document);
                  stopAll(fd);
                } catch(e) {}
              });
            } catch(e) {}


            if (!window.__asdOrigMediaPlay) {
              try {
                window.__asdOrigMediaPlay = HTMLMediaElement.prototype.play;
                HTMLMediaElement.prototype.play = function() {
                  if (window.__asdNativePlayerActive) {
                    try { this.pause(); this.muted = true; this.volume = 0; } catch(e) {}
                    return Promise.resolve();
                  }
                  return window.__asdOrigMediaPlay.apply(this, arguments);
                };
              } catch(e) {}
            }

            try { clearInterval(window.__asdNativePauseLoop); } catch(e) {}
            window.__asdNativePauseLoop = setInterval(function(){
              if (!window.__asdNativePlayerActive) {
                clearInterval(window.__asdNativePauseLoop);
                return;
              }
              stopAll(document);
              try {
                document.querySelectorAll('iframe').forEach(function(fr){
                  try {
                    var fd = fr.contentDocument || (fr.contentWindow && fr.contentWindow.document);
                    stopAll(fd);
                  } catch(e) {}
                });
              } catch(e) {}
            }, 300);

          } catch(e) {}
        })();
      ''');
    } catch (_) {}
  }



  Future<void> _releaseOriginalSitePlayerBlock() async {
    try {
      await _wc?.evaluateJavascript(source: r'''
        (function(){
          try {
            window.__asdNativePlayerActive = false;
            try { clearInterval(window.__asdNativePauseLoop); window.__asdNativePauseLoop = null; } catch(e) {}
            if (window.__asdOrigMediaPlay) {
              try { HTMLMediaElement.prototype.play = window.__asdOrigMediaPlay; window.__asdOrigMediaPlay = null; } catch(e) {}
            }
            function restoreAll(doc) {
              if (!doc) return;
              try {
                doc.querySelectorAll('video,audio').forEach(function(v){
                  try { v.pause(); v.muted = false; v.volume = 1; } catch(e) {}
                });
              } catch(e) {}
              try {
                var win = doc.defaultView;
                if (win && win.jwplayer) {
                  var jw = win.jwplayer();
                  if (jw) {
                    try { jw.setMute(false); } catch(e) {}
                    try { jw.pause(true); } catch(e) {}
                  }
                }
              } catch(e) {}
            }
            restoreAll(document);
            try {
              document.querySelectorAll('iframe').forEach(function(fr){
                try {
                  restoreAll(fr.contentDocument || (fr.contentWindow && fr.contentWindow.document));
                } catch(e) {}
              });
            } catch(e) {}
          } catch(e) {}
        })();
      ''');
    } catch (_) {}
  }


  Future<void> _suspendWebViewForNative({String? pageUrl}) async {
    if (_wc == null || _webViewSuspendedForNative) return;

    _rememberStableWatchUrl(pageUrl);
    try {
      final current = (await _wc!.getUrl())?.toString();
      _rememberStableWatchUrl(current);
      await _wc!.stopLoading();
    } catch (_) {}

    try {
      await _pauseOriginalSitePlayer();
    } catch (_) {}

    if (mounted) {
      setState(() => _webViewSuspendedForNative = true);
    } else {
      _webViewSuspendedForNative = true;
    }

    
    
  }

  Future<void> _resumeWebViewAfterNative() async {
    if (!_webViewSuspendedForNative) return;
    if (mounted) {
      setState(() => _webViewSuspendedForNative = false);
    } else {
      _webViewSuspendedForNative = false;
    }
    
  }


  Future<void> _closeNativePlayer() async {
    _preventAutoReopenAfterClose = true;
    _suppressAutoOpenUntil = DateTime.now().millisecondsSinceEpoch + 15000;
    _nativeAutoOpenQueued = false;
    _qualitySwitchPending = false;
    _manualPlayAfterQualitySwitchPending = false;
    try {
      await _pip.invokeMethod<bool>('closeNativePlayer');
    } catch (_) {}
    await _releaseOriginalSitePlayerBlock();
  }

  Future<void> _openNativePlayer({bool force = false, bool enterPipAfter = false, bool replace = false, double? startTimeOverride, String? forcedUrl, String? forcedPageUrl, String? forcedMimeType, bool allowInDownloadOnlyMode = false}) async {
    if (widget.downloadOnlyMode && !allowInDownloadOnlyMode) return;
    if (!replace && (_nativePlayerActive || _nativePlayerOpening)) return;
    if (widget.launchHidden && !widget.downloadOnlyMode && !_isBotConfirmed1080()) {
      debugPrint('🤖 Native player blocked until bot confirms preferred quality');
      _startPreferredQualityBotGate('open_native_player_guard');
      return;
    }

    if (_capturedVideoUrl == null || _capturedVideoUrl!.startsWith('blob:')) {
      try {
        await _wc?.evaluateJavascript(source: 'window.__asdCollectMediaNow && window.__asdCollectMediaNow();');
        await Future.delayed(const Duration(milliseconds: 180));
      } catch (_) {}
    }

    final mediaUrl = forcedUrl ?? _capturedVideoUrl;
    if (mediaUrl == null || mediaUrl.isEmpty || mediaUrl.startsWith('blob:')) {
      if (force) {
        _showSnack('⚠️ لم ألتقط رابط الفيديو الحقيقي بعد. شغّل الفيديو مرة ثانية');
      }
      return;
    }
    if (_isYouTubeUrl(mediaUrl)) {
      if (force) _showSnack('⚠️ روابط يوتيوب لا تُشغَّل داخل المشغل الأصلي');
      return;
    }

    if (!force && !_videoPlaying) return;

    _preventAutoReopenAfterClose = false;
    _nativePlayerOpening = true;
    final ticket = ++_nativeOpenTicket;

    try {
      await _pauseOriginalSitePlayer();
      final currentPage = (await _wc?.getUrl())?.toString();
      final pageUrl = forcedPageUrl ?? _capturedVideoPageUrl ?? currentPage ?? _lastTrusted;
      _rememberStableWatchUrl(pageUrl);
      _rememberStableWatchUrl(currentPage);
      _rememberStableWatchUrl(_capturedVideoPageUrl);
      final headers = await _buildPipHeaders(mediaUrl, pageUrl: pageUrl);
      final preparedMediaUrl = await _prepareBestNativeMediaUrl(mediaUrl, headers);
      final aspectRatio = _safePipAspectRatio();

      if (!Platform.isAndroid) {
        if (ticket != _nativeOpenTicket) return;
        if (mounted) {
          setState(() {
            _nativePlayerActive = true;
            _lastNativePlayerUrl = preparedMediaUrl;
          });
        }
        await _suspendWebViewForNative(pageUrl: pageUrl);
        await openUniversalMediaPlayer(
          context,
          url: preparedMediaUrl,
          title: widget.headerTitle ?? 'Anime3rb',
          pageUrl: pageUrl,
          mimeType: forcedMimeType ?? _capturedVideoMimeType ?? _inferMimeType(preparedMediaUrl),
          headers: headers,
          currentTime: startTimeOverride ?? _capturedVideoTime,
          qualityOptions: _pageQualityOptions.map((e) => Map<String, dynamic>.from(e.toMap())).toList(growable: false),
          currentQualityLabel: _currentPageQualityLabel,
          serverOptions: _pageServerOptions.map((e) => Map<String, dynamic>.from(e.toMap())).toList(growable: false),
          currentServerLabel: _currentServerLabel,
        );
        if (ticket != _nativeOpenTicket) return;
        if (mounted) {
          setState(() {
            _nativePlayerActive = false;
            _lastNativePlayerUrl = null;
          });
        } else {
          _nativePlayerActive = false;
          _lastNativePlayerUrl = null;
        }
        await _releaseOriginalSitePlayerBlock();
        await _resumeWebViewAfterNative();
        await _restoreUI();
        return;
      }

      final ok = await _pip.invokeMethod<bool>('openNativePlayer', {
        'url': preparedMediaUrl,
        'currentTime': startTimeOverride ?? _capturedVideoTime,
        'pageUrl': pageUrl,
        'mimeType': forcedMimeType ?? _capturedVideoMimeType ?? _inferMimeType(preparedMediaUrl),
        'headers': headers,
        'aspectRatioNumerator': aspectRatio['w'],
        'aspectRatioDenominator': aspectRatio['h'],
        'subtitleTracks': const <Map<String, String>>[],
        'qualityOptions': _pageQualityOptions.map((e) => e.toMap()).toList(),
        'currentQualityLabel': _currentPageQualityLabel,
        'serverOptions': _pageServerOptions.map((e) => e.toMap()).toList(),
        'currentServerLabel': _currentServerLabel,
      });

      if (ticket != _nativeOpenTicket) return;
      if (ok == true && mounted) {
        setState(() {
          _nativePlayerActive = true;
          _lastNativePlayerUrl = preparedMediaUrl;
        });
        await _suspendWebViewForNative(pageUrl: pageUrl);
        if (enterPipAfter) {
          await Future.delayed(const Duration(milliseconds: 140));
          await _enterPip();
        }
      } else if (force) {
        _showSnack('⚠️ تعذّر فتح مشغلك الأصلي');
      }
    } on MissingPluginException {
      if (force) _showSnack('⚠️ المشغل الأصلي غير مفعّل Native داخل Android للمشروع');
    } catch (_) {
      if (force) _showSnack('⚠️ تعذّر فتح المشغل الأصلي');
    } finally {
      if (ticket == _nativeOpenTicket) {
        _nativePlayerOpening = false;
        _nativeAutoOpenQueued = false;
      }
    }
  }

  Future<void> _enterPip() async {
    if (_inPip) return;
    final supported = await _isPipSupported();
    if (!supported) {
      _showSnack('⚠️ PiP غير مفعّل Native داخل Android للمشروع');
      return;
    }

    if (!_nativePlayerActive) {
      await _openNativePlayer(force: true, enterPipAfter: true);
      return;
    }

    try {
      final ok = await _pip.invokeMethod<bool>('enterPip') ?? false;
      if (ok == true && mounted) {
        setState(() => _inPip = true);
      } else {
        _showSnack('⚠️ تعذّر إدخال المشغل إلى PiP');
      }
    } on MissingPluginException {
      _showSnack('⚠️ PiP غير مفعّل Native داخل Android للمشروع');
    } catch (_) {
      _showSnack('⚠️ تعذّر تفعيل PiP');
    }
  }

  Future<void> _applyPageFullscreenForce() async {
    try { await _wc?.evaluateJavascript(source: 'window.__asdForceFullscreenNow && window.__asdForceFullscreenNow();'); } catch (_) {}
  }

  Future<void> _removePageFullscreenForce() async {
    try { await _wc?.evaluateJavascript(source: 'window.__asdExitForcedFullscreen && window.__asdExitForcedFullscreen();'); } catch (_) {}
  }

  Future<void> _enterFullscreen() async {
    if (!mounted || _fullscreen || _fullscreenBusy) return;
    _fullscreenBusy = true;
    try {
      setState(() => _fullscreen = true);
      await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await Future.delayed(const Duration(milliseconds: 80));
      await _applyPageFullscreenForce();
    } finally {
      await Future.delayed(const Duration(milliseconds: 250));
      _fullscreenBusy = false;
    }
  }

  Future<void> _exitFullscreen() async {
    if (!mounted || !_fullscreen || _fullscreenBusy) return;
    _fullscreenBusy = true;
    try {
      setState(() => _fullscreen = false);
      await _removePageFullscreenForce();
      await _restoreUI();
    } finally {
      await Future.delayed(const Duration(milliseconds: 250));
      _fullscreenBusy = false;
    }
  }

  Future<void> _restoreUI() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp, DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  Future<bool> _pageLooksLikeCloudflareCheck() async {
    final controller = _wc;
    if (controller == null) return false;
    try {
      final result = await controller.evaluateJavascript(source: _cloudflareChallengeProbe);
      if (result == true) return true;
      final value = result?.toString().toLowerCase().trim();
      return value == 'true' || value == '1';
    } catch (_) {
      return false;
    }
  }

  void _scheduleDeferredAdBlockInjection() {
    if (_deferredAdBlockInjected || _deferredAdBlockScheduleActive) return;
    _deferredAdBlockScheduleActive = true;
    final ticket = _cloudflareSafeInjectTicket;
    final delays = <Duration>[
      const Duration(milliseconds: 900),
      const Duration(milliseconds: 1800),
      const Duration(milliseconds: 3200),
      const Duration(milliseconds: 5200),
      const Duration(milliseconds: 8500),
    ];

    for (var i = 0; i < delays.length; i++) {
      final delay = delays[i];
      final isLastAttempt = i == delays.length - 1;
      Future.delayed(delay, () async {
        if (!mounted) return;
        if (ticket != _cloudflareSafeInjectTicket) return;
        if (_deferredAdBlockInjected) return;
        if (isLastAttempt) {
          _deferredAdBlockScheduleActive = false;
        }
        await _injectAdBlockScriptsAfterCloudflareCheck(scheduleIfBlocked: false);
      });
    }
  }

  Future<void> _injectAdBlockScriptsAfterCloudflareCheck({bool scheduleIfBlocked = true}) async {
    final controller = _wc;
    if (controller == null || _deferredAdBlockInjected) return;

    final blockedByCloudflareCheck = await _pageLooksLikeCloudflareCheck();
    if (blockedByCloudflareCheck) {
      if (scheduleIfBlocked) _scheduleDeferredAdBlockInjection();
      return;
    }

    _deferredAdBlockInjected = true;
    _deferredAdBlockScheduleActive = false;

    try { await controller.evaluateJavascript(source: _stealthAdBlock); } catch (_) {}
    try { await controller.evaluateJavascript(source: _ads); } catch (_) {}
    try { await controller.evaluateJavascript(source: _css); } catch (_) {}
  }

  Future<void> _reinjectScripts() async {
    if (_wc == null) return;
    await _wc!.evaluateJavascript(source: _desktopViewport);
    await _wc!.evaluateJavascript(source: _forceAnime3rbNightMode);
    await _wc!.evaluateJavascript(source: _hideServers);
    await _wc!.evaluateJavascript(source: _dlCapture);
    await _wc!.evaluateJavascript(source: _srvCapture);
    await _wc!.evaluateJavascript(source: _vid3rbDeepCapture);
    await _wc!.evaluateJavascript(source: _qualityAutoBot);
    await _injectAdBlockScriptsAfterCloudflareCheck();
  }


Future<void> _forcePreferred1080() async {
  if (_wc == null) return;
  if (_preventAutoReopenAfterClose) return;
  _temporarilyBlockAnimeQualityPageNavigation();
  
  try {
    await _wc!.evaluateJavascript(source: r'''(function(){
      try {
        // ✅ ROOT FIX 1: لا نشغّل البوت على الصفحة الرئيسية أبداً
        // إذا كان iframe cross-origin، تشغيل البوت من الصفحة الأم كان يضغط خارج المشغل.
        document.querySelectorAll('iframe').forEach(function(fr){
          try {
            var fw = fr.contentWindow;
            if (!fw) return;

            var hasBotAccess = false;
            try {
              hasBotAccess = typeof fw.__asdRunPreciseBot === 'function';
            } catch(e) {
              return;
            }
            if (!hasBotAccess) return;

            if (fw.__asdSetPreciseBotSuppressed) fw.__asdSetPreciseBotSuppressed(false, true);
            if (fw.__asdResetPreciseBot) fw.__asdResetPreciseBot();
            if (fw.__asdRunPreciseBot) fw.__asdRunPreciseBot();
          } catch(e) {}
        });
      } catch(e) {}
    })();''');
  } catch (_) {}
}

  // ─────────────────────────────────────────────────────────────────────────
  // ✅ FIX 1: _isAllowedNavigation — closed the canRedir loophole
  //    Old bug: if _lastTrusted was doodstream/anime3rb (in _redirectOk),
  //    ANY URL was allowed through — including ad redirects triggered by clicking.
  //    New: canRedir path ALSO requires destination to be in _white.
  //    CDN/cloud URLs still pass because they ARE in _white (cloudfront, akamaized, etc.)
  // ─────────────────────────────────────────────────────────────────────────
  bool _isAllowedNavigation(String url, bool isMainFrame) {
    if (!url.startsWith('http://') && !url.startsWith('https://')) return false;

    // ✅ FIX 1a: Always block known ad/tracking domains first, before any whitelist logic
    if (_isB(url) || _isAdResourceUrl(url)) return false;

    final decodedTarget = _decodeArabseedRedirect(url);
    if (decodedTarget != null) {
      if (_isB(decodedTarget) || _isAdResourceUrl(decodedTarget)) return false;
      _rememberAllowedHost(decodedTarget);
      _lastTrusted = url;
      _currentHost = Uri.tryParse(decodedTarget)?.host;
      return true;
    }

    if (!isMainFrame) return true;

    if (_isRuntimeAllowed(url)) {
      _lastTrusted = url;
      _currentHost = Uri.tryParse(url)?.host;
      return true;
    }

    // Direct anime3rb — always allowed
    if (url.contains('anime3rb.com')) {
      _lastTrusted = url;
      _currentHost = Uri.tryParse(url)?.host;
      return true;
    }

    // Known whitelisted domain — allowed
    if (_isW(url)) {
      _lastTrusted = url;
      _currentHost = Uri.tryParse(url)?.host;
      return true;
    }

    // Download landing pages opened from ArabSeed should be allowed when they are not ads.
    if (_isLikelyDownloadLandingUrl(url)) {
      _rememberAllowedHost(url);
      _lastTrusted = url;
      _currentHost = Uri.tryParse(url)?.host;
      return true;
    }

    // ✅ FIX 1b: canRedir path — destination MUST also be whitelisted or runtime-approved
    if (_lastTrusted != null && _canRedir(_lastTrusted!) && (_isW(url) || _isRuntimeAllowed(url))) {
      _lastTrusted = url;
      _currentHost = Uri.tryParse(url)?.host;
      return true;
    }

    if (_currentHost != null && _canRedir(_currentHost!) && (_isW(url) || _isRuntimeAllowed(url))) {
      _currentHost = Uri.tryParse(url)?.host;
      return true;
    }

    return false;
  }

  Widget _buildDownloadsPanel() {
    final panelHeight = MediaQuery.of(context).size.height * 0.75;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      top: _showDownloads ? 0 : -(panelHeight + 24),
      left: 0, right: 0,
      child: SafeArea(
        bottom: false,
        child: Container(
          height: panelHeight,
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF203040), Color(0xFF0F1720)],
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white10),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.45), blurRadius: 24, offset: const Offset(0, 10))],
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
                child: Row(
                  children: [
                    Container(
                      width: 38, height: 38,
                      decoration: BoxDecoration(color: Colors.orange.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.download_rounded, color: Colors.orange),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('التحميلات', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
                        ],
                      ),
                    ),
                    IconButton(onPressed: _closeDownloadsPanel, icon: const Icon(Icons.keyboard_arrow_up, color: Colors.white70)),
                  ],
                ),
              ),
              const Divider(color: Colors.white12, height: 1),
              Expanded(
                child: _downloads.isEmpty
                    ? const Center(child: Text('لا توجد تحميلات', style: TextStyle(color: Colors.white38, fontSize: 15)))
                    : ListView.builder(
                        padding: const EdgeInsets.all(10),
                        itemCount: _downloads.length,
                        itemBuilder: (context, i) => _buildDownloadCard(_downloads[i]),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDownloadCard(DownloadItem d) {
    final isDone = d.status == 'done';
    final isErr = d.status == 'error';
    final isCancelled = d.status == 'cancelled';
    final isPaused = d.status == 'paused';
    final isDownloading = d.status == 'downloading' || d.status == 'preparing';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: 108, height: 72, color: Colors.black26,
              child: d.thumbnailPath != null && File(d.thumbnailPath!).existsSync()
                  ? pwaImageFile(d.thumbnailPath!, fit: BoxFit.cover)
                  : Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.orange.withOpacity(0.25), Colors.deepOrange.withOpacity(0.15)],
                          begin: Alignment.topLeft, end: Alignment.bottomRight,
                        ),
                      ),
                      child: Icon(
                        isDone ? Icons.movie_creation_outlined
                          : isErr ? Icons.error_outline
                          : isCancelled ? Icons.remove_circle_outline
                          : isPaused ? Icons.pause_circle_outline_rounded
                          : Icons.downloading_rounded,
                        color: Colors.white70, size: 30,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 72,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    d.fileName, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isCancelled ? Colors.white38 : Colors.white,
                      fontWeight: FontWeight.w600, fontSize: 13.5, height: 1.2,
                    ),
                  ),
                  const Spacer(),
                  if (isDownloading || isPaused) Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.all(Radius.circular(99)),
                        child: LinearProgressIndicator(
                          value: d.progress <= 0 ? null : d.progress,
                          minHeight: 6,
                          backgroundColor: const Color(0x332196F3),
                          valueColor: const AlwaysStoppedAnimation<Color>(Colors.orange),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isPaused
                            ? 'متوقف مؤقتًا... ${(d.progress * 100).clamp(0, 100).toStringAsFixed(0)}%'
                            : (d.progress > 0 ? 'جاري التحميل... ${(d.progress * 100).clamp(0, 100).toStringAsFixed(0)}%' : 'جاري التحميل...'),
                        style: TextStyle(color: isPaused ? Colors.white : Colors.orange, fontSize: 11.5),
                      ),
                    ],
                  )
                  else if (isDone) Text(
                    d.savedPath != null ? 'اكتمل التحميل - اضغط تشغيل' : 'اكتمل التحميل',
                    style: const TextStyle(color: Colors.green, fontSize: 11.5),
                  )
                  else if (isErr) const Text('فشل التحميل', style: TextStyle(color: Colors.redAccent, fontSize: 11.5))
                  else if (isCancelled) const Text('تم إلغاء التحميل', style: TextStyle(color: Colors.white38, fontSize: 11.5)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isDownloading) _actionBtn(icon: Icons.pause_circle_outline_rounded, color: Colors.white, onTap: () => _pauseDownload(d)),
              if (isPaused) _actionBtn(icon: Icons.play_circle_outline_rounded, color: Colors.white, onTap: () => _resumeDownload(d)),
              if (isDone && d.savedPath != null) _actionBtn(icon: Icons.play_circle_fill_rounded, color: Colors.green, onTap: () => _playVideo(d.savedPath!)),
              _actionBtn(icon: Icons.delete_outline, color: Colors.white70, onTap: () => _confirmDelete(d)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionBtn({required IconData icon, required Color color, required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: color.withOpacity(0.12), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }


  bool _looksLikeWatchPage([String? rawUrl]) {
    final url = (rawUrl ?? _currentPageUrl ?? _capturedVideoPageUrl ?? _lastTrusted ?? '').toLowerCase();
    if (url.isEmpty) return false;
    return url.contains('play=true') ||
        url.contains('/watch/') ||
        url.contains('%d9%85%d8%b4%d8%a7%d9%87') ||
        url.contains('/episode/') ||
        url.contains('/movie/');
  }

  CapturedMediaItem? get _bestQuickMedia {
    final preferred = _bestPreferredQualityOption();
    final byPreferred = _bestQuickMediaForQuality(preferred?.label);
    if (byPreferred != null) return byPreferred;
    final bestCaptured = _bestQuickMediaForQuality();
    if (bestCaptured != null) return bestCaptured;
    final url = _capturedVideoUrl;
    if (url == null || url.isEmpty) return null;
    return CapturedMediaItem(
      id: 'fallback',
      url: url,
      pageUrl: _capturedVideoPageUrl ?? _currentPageUrl ?? _lastTrusted ?? 'https://anime3rb.com/',
      fileName: _contextualFileName(url, qualityLabel: _currentPageQualityLabel),
      foundAt: DateTime.now(),
      isDirectFile: _isDirectMediaFile(url),
      isStream: _isStreamUrl(url),
      mimeType: _capturedVideoMimeType ?? _inferMimeType(url),
      qualityLabel: _normalizeQualityLabel(_currentPageQualityLabel ?? '').isEmpty ? null : _normalizeQualityLabel(_currentPageQualityLabel ?? ''),
      headers: {
        'User-Agent': _ua,
        'Referer': _capturedVideoPageUrl ?? _currentPageUrl ?? _lastTrusted ?? 'https://anime3rb.com/',
      },
    );
  }

  bool get _showQuickMediaButtons =>
      !widget.downloadOnlyMode &&
      _looksLikeWatchPage() &&
      (_bestQuickMedia != null ||
          _pageQualityOptions.isNotEmpty ||
          _pageServerOptions.isNotEmpty) &&
      !_fullscreen &&
      !_nativePlayerActive &&
      !_showDownloads;

  bool get _hideSiteDuringDirectLaunch =>
      widget.launchHidden &&
      _looksLikeWatchPage(widget.initialUrl) &&
      !_revealHiddenLaunchUi &&
      !_nativePlayerActive &&
      !_nativePlayerOpening;

  void _clearSitePlayerOverlayRect({bool notify = true}) {
    if (_sitePlayerOverlayRect == null) {
      _hideSitePlayerActionOverlay();
      return;
    }
    if (notify && mounted) {
      setState(() => _sitePlayerOverlayRect = null);
    } else {
      _sitePlayerOverlayRect = null;
    }
    _hideSitePlayerActionOverlay();
  }

  Future<void> _hideSitePlayerActionOverlay() async {
    if (_wc == null) return;
    try {
      await _wc!.evaluateJavascript(source: r'''(function(){
        try {
          var root = document.getElementById('__asd_site_player_actions');
          if (root) {
            root.style.display = 'none';
            root.setAttribute('aria-hidden', 'true');
          }
        } catch(e) {}
      })();''');
    } catch (_) {}
  }


  Future<void> _setPreciseBotSuppressed(bool suppressed, {bool reset = true}) async {
    if (_wc == null) return;
    try {
      await _wc!.evaluateJavascript(source: '''(function(s, reset){
        function apply(win) {
          try {
            if (!win) return;
            try { win.__asdPreciseBotSuppressed = !!s; } catch(e) {}
            if (typeof win.__asdSetPreciseBotSuppressed === 'function') {
              try { win.__asdSetPreciseBotSuppressed(!!s, !!reset); } catch(e) {}
            } else if (reset && typeof win.__asdResetPreciseBot === 'function') {
              try { win.__asdResetPreciseBot(); } catch(e) {}
            }
          } catch(e) {}
        }
        apply(window);
        try {
          document.querySelectorAll('iframe').forEach(function(fr){
            try { apply(fr.contentWindow); } catch(e) {}
          });
        } catch(e) {}
        return true;
      })(${suppressed ? 'true' : 'false'}, ${reset ? 'true' : 'false'});''');
    } catch (_) {}
  }

  void _stopSitePlayerRectTracking({bool clear = false}) {
    _sitePlayerRectTrackToken++;
    _sitePlayerRectTracking = false;
    if (clear) {
      _clearSitePlayerOverlayRect(notify: mounted);
    }
  }

  void _startSitePlayerRectTracking() {
    if (_wc == null || _sitePlayerRectTracking) return;
    final token = ++_sitePlayerRectTrackToken;
    _sitePlayerRectTracking = true;
    Future.microtask(() => _sitePlayerRectTrackingLoop(token));
  }

  Future<void> _sitePlayerRectTrackingLoop(int token) async {
    while (mounted && token == _sitePlayerRectTrackToken) {
      final shouldKeepTracking =
          _showQuickMediaButtons &&
          !_hideSiteDuringDirectLaunch &&
          !_webViewSuspendedForNative &&
          !_nativePlayerActive &&
          !_nativePlayerOpening;

      if (!shouldKeepTracking) {
        _sitePlayerRectTracking = false;
        _clearSitePlayerOverlayRect(notify: mounted);
        return;
      }

      await _syncSitePlayerOverlayRect();
      await Future.delayed(const Duration(milliseconds: 180));
    }
    if (token == _sitePlayerRectTrackToken) {
      _sitePlayerRectTracking = false;
    }
  }

  Future<void> _syncSitePlayerOverlayRect() async {
    if (_wc == null || !_showQuickMediaButtons || !mounted) {
      await _hideSitePlayerActionOverlay();
      if (_sitePlayerOverlayRect != null) {
        if (mounted) {
          setState(() => _sitePlayerOverlayRect = null);
        } else {
          _sitePlayerOverlayRect = null;
        }
      }
      return;
    }

    try {
      final showDownloadIcon = _pageQualityOptions.length > 1 || (_bestQuickMedia?.isDirectFile ?? false);
      final config = {
        'playLabel': 'مشاهدة',
        'downloadLabel': 'تحميل',
        'downloadIcon': 'download',
        'disableInteractions': _preferredQualityBotPending,
      };

      await _wc!.evaluateJavascript(source: '''(function(cfg){
        function visibleRect(el) {
          if (!el || !el.getBoundingClientRect) return null;
          try {
            var style = window.getComputedStyle(el);
            if (style.display === 'none' || style.visibility === 'hidden' || Number(style.opacity || '1') <= 0) {
              return null;
            }
          } catch(e) {}
          var r = el.getBoundingClientRect();
          if (!r || r.width < 140 || r.height < 90) return null;
          return r;
        }

        function biggestIframeRect() {
          try {
            var frames = document.querySelectorAll('iframe');
            var best = null;
            var bestArea = 0;
            for (var i = 0; i < frames.length; i++) {
              var frame = frames[i];
              var r = visibleRect(frame);
              if (!r) continue;
              var src = (frame.src || frame.getAttribute('src') || '').toLowerCase();
              var area = r.width * r.height;
              if (src.indexOf('vid3rb.com') !== -1 || src.indexOf('video.vid3rb') !== -1) {
                return r;
              }
              if (area > bestArea) {
                best = r;
                bestArea = area;
              }
            }
            return best;
          } catch(e) {
            return null;
          }
        }

        function directPlayerRect() {
          var selectors = [
            '.video-js','.jwplayer','.plyr','.dplayer','.mejs-container',
            '#player','[id="player"]','[class*="player"]','video'
          ];
          for (var i = 0; i < selectors.length; i++) {
            try {
              var els = document.querySelectorAll(selectors[i]);
              for (var j = 0; j < els.length; j++) {
                var r = visibleRect(els[j]);
                if (r) return r;
              }
            } catch(e) {}
          }
          return null;
        }

        function hasVisibleMenu() {
          var selectors = [
            '.jw-settings-menu',
            '.jw-settings-submenu',
            '.jw-menu',
            '.jw-tooltip',
            '.jw-dialog:not(.jw-dialog-overlay)',
            '.vjs-menu',
            '.vjs-lock-showing',
            '.plyr__menu__container',
            '[role="menu"]',
            '[class*="settings-menu"]',
            '[class*="quality-menu"]',
            '[class*="submenu"]'
          ];
          for (var i = 0; i < selectors.length; i++) {
            try {
              var nodes = document.querySelectorAll(selectors[i]);
              for (var j = 0; j < nodes.length; j++) {
                var node = nodes[j];
                var r = visibleRect(node);
                if (!r) continue;
                if (r.width >= 90 && r.height >= 40) return true;
              }
            } catch(e) {}
          }
          try {
            if (document.body && document.body.classList && document.body.classList.contains('jw-flag-menu-open')) {
              return true;
            }
          } catch(e) {}
          return false;
        }

        function installInteractionHideHooks() {
          if (window.__asdSitePlayerOverlayHooksInstalled) return;
          window.__asdSitePlayerOverlayHooksInstalled = true;
          window.__asdSitePlayerOverlayHideUntil = 0;

          function shouldBump(target) {
            try {
              if (!target) return false;
              if (target.closest && target.closest('#__asd_site_player_actions')) return false;
              if (target.closest && target.closest('.jw-settings-menu,.jw-settings-submenu,.jw-menu,.jw-tooltip,.jw-dialog,.jw-controlbar,.jw-controls,.jw-button-container,.jw-icon,.vjs-control-bar,.vjs-menu,.plyr__controls,.plyr__menu__container,[role="menu"],[class*="settings"],[class*="quality"],[class*="control"]')) {
                return true;
              }
            } catch(e) {}
            return false;
          }

          function bump(ev) {
            try {
              if (!shouldBump(ev && ev.target)) return;
              window.__asdSitePlayerOverlayHideUntil = Date.now() + 1800;
            } catch(e) {}
          }

          document.addEventListener('pointerdown', bump, true);
          document.addEventListener('mousedown', bump, true);
          document.addEventListener('touchstart', bump, true);
        }

        function ensureButton(id, label, bg, onTap, iconSvg) {
          var btn = document.getElementById(id);
          if (!btn) {
            btn = document.createElement('button');
            btn.id = id;
            btn.type = 'button';
            btn.style.cssText = [
              'pointer-events:auto',
              'height:52px',
              'border:none',
              'outline:none',
              'border-radius:16px',
              'padding:0 16px',
              'display:flex',
              'align-items:center',
              'justify-content:center',
              'gap:8px',
              'font-size:15px',
              'font-weight:800',
              'color:#fff',
              'box-shadow:0 5px 14px rgba(0,0,0,.28)',
              'backdrop-filter:blur(8px)',
              '-webkit-backdrop-filter:blur(8px)',
              'cursor:pointer',
              'touch-action:manipulation'
            ].join(';');
            btn.addEventListener('click', function(ev){
              ev.preventDefault();
              ev.stopPropagation();
              try { onTap(); } catch(e) {}
            }, true);
          }
          btn.style.background = bg;
          btn.innerHTML = '<span style="display:inline-flex;width:20px;height:20px">' + iconSvg + '</span><span style="display:inline-block;line-height:1">' + label + '</span>';
          return btn;
        }

        function ensureRoot() {
          var root = document.getElementById('__asd_site_player_actions');
          if (root) return root;

          root = document.createElement('div');
          root.id = '__asd_site_player_actions';
          root.style.cssText = [
            'position:absolute',
            'left:0',
            'top:0',
            'width:0',
            'height:0',
            'z-index:2147483646',
            'display:none',
            'pointer-events:none',
            'contain:layout style paint'
          ].join(';');

          var veil = document.createElement('div');
          veil.id = '__asd_site_player_veil';
          veil.style.cssText = [
            'position:absolute',
            'left:0',
            'top:0',
            'width:100%',
            'height:0',
            'background:rgba(0,0,0,1)',
            'pointer-events:none',
            'border-radius:0',
            'box-shadow:none'
          ].join(';');

          var row = document.createElement('div');
          row.id = '__asd_site_player_actions_row';
          row.style.cssText = [
            'position:absolute',
            'left:0',
            'top:0',
            'right:0',
            'width:100%',
            'display:flex',
            'flex-direction:row',
            'align-items:stretch',
            'justify-content:stretch',
            'gap:0',
            'pointer-events:none'
          ].join(';');

          var playIcon = '<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M8 6.5v11l9-5.5-9-5.5Z" fill="currentColor"/></svg>';
          var dlIcon = '<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M12 4v9m0 0 3.5-3.5M12 13 8.5 9.5M5 18h14" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>';
          var linkIcon = '<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M10 13a5 5 0 0 1 0-7l1.5-1.5a5 5 0 1 1 7 7L17 13M14 11a5 5 0 0 1 0 7L12.5 19.5a5 5 0 1 1-7-7L7 11" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>';

          var playBtn = ensureButton(
            '__asd_site_player_play_btn',
            cfg.playLabel || 'مشاهدة',
            'rgba(76,175,80,.98)',
            function(){ try { window.flutter_inappwebview.callHandler('onOverlayPlayTap'); } catch(e) {} },
            playIcon
          );
          var downloadBtn = ensureButton(
            '__asd_site_player_download_btn',
            cfg.downloadLabel || 'تحميل',
            'rgba(76,175,80,.98)',
            function(){ try { window.flutter_inappwebview.callHandler('onOverlayDownloadTap'); } catch(e) {} },
            (cfg.downloadIcon === 'link') ? linkIcon : dlIcon
          );

          playBtn.style.flex = '1 1 0';
          downloadBtn.style.flex = '1 1 0';
          row.appendChild(playBtn);
          row.appendChild(downloadBtn);
          root.appendChild(veil);
          root.appendChild(row);
          (document.body || document.documentElement).appendChild(root);
          return root;
        }

        installInteractionHideHooks();

        var rect = biggestIframeRect() || directPlayerRect();
        var root = ensureRoot();
        var veil = document.getElementById('__asd_site_player_veil');
        var row = document.getElementById('__asd_site_player_actions_row');
        var playBtn = document.getElementById('__asd_site_player_play_btn');
        var downloadBtn = document.getElementById('__asd_site_player_download_btn');
        var disableInteractions = cfg && cfg.disableInteractions === true;

        if (!rect || rect.width < 140 || rect.height < 90) {
          root.style.display = 'none';
          root.setAttribute('aria-hidden', 'true');
          return '';
        }

        root.style.display = 'block';
        root.setAttribute('aria-hidden', 'false');
        root.style.left = Math.max(0, rect.left + (window.scrollX || window.pageXOffset || 0)) + 'px';
        root.style.top = Math.max(0, rect.top + (window.scrollY || window.pageYOffset || 0)) + 'px';
        root.style.width = Math.max(140, rect.width) + 'px';

        var rowHeight = Math.max(52, Math.min(72, rect.height * 0.18));
        var rowGap = 0;
        var rowWidth = Math.max(140, rect.width);
        var iconSize = Math.max(18, Math.min(24, rowHeight * 0.42));
        var fontSize = Math.max(14, Math.min(18, rowHeight * 0.31));

        root.style.height = Math.max(90, rect.height + rowGap + rowHeight) + 'px';

        veil.style.width = '100%';
        veil.style.height = Math.max(90, rect.height) + 'px';
        veil.style.background = 'rgba(0,0,0,1)';
        veil.style.pointerEvents = 'none';
        veil.style.borderRadius = '0';

        row.style.width = rowWidth + 'px';
        row.style.maxWidth = '100%';
        row.style.left = '0';
        row.style.right = '0';
        row.style.top = Math.max(0, rect.height + rowGap) + 'px';
        row.style.bottom = 'auto';
        row.style.transform = 'none';

        [playBtn, downloadBtn].forEach(function(btn) {
          btn.style.width = 'auto';
          btn.style.flex = '1 1 0';
          btn.style.height = rowHeight + 'px';
          btn.style.minHeight = rowHeight + 'px';
          btn.style.padding = '0 12px';
          btn.style.margin = '0';
          btn.style.borderRadius = '0';
          btn.style.fontSize = fontSize + 'px';
          btn.style.boxShadow = 'none';
          btn.style.pointerEvents = disableInteractions ? 'none' : 'auto';
          btn.style.opacity = disableInteractions ? '0.28' : '1';
          btn.style.filter = disableInteractions ? 'grayscale(0.2)' : 'none';
          btn.setAttribute('aria-disabled', disableInteractions ? 'true' : 'false');
        });
        playBtn.style.background = 'rgba(76,175,80,.98)';
        downloadBtn.style.background = 'rgba(76,175,80,.98)';
        playBtn.innerHTML = '<span style="display:inline-flex;width:' + iconSize + 'px;height:' + iconSize + 'px"><svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M8 6.5v11l9-5.5-9-5.5Z" fill="currentColor"/></svg></span><span style="display:inline-block;line-height:1">' + (cfg.playLabel || 'مشاهدة') + '</span>';
        downloadBtn.innerHTML = '<span style="display:inline-flex;width:' + iconSize + 'px;height:' + iconSize + 'px">' + ((cfg.downloadIcon === 'link')
          ? '<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M10 13a5 5 0 0 1 0-7l1.5-1.5a5 5 0 1 1 7 7L17 13M14 11a5 5 0 0 1 0 7L12.5 19.5a5 5 0 1 1-7-7L7 11" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>'
          : '<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M12 4v9m0 0 3.5-3.5M12 13 8.5 9.5M5 18h14" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>') + '</span><span style="display:inline-block;line-height:1">' + (cfg.downloadLabel || 'تحميل') + '</span>';

        return JSON.stringify({
          left: Number(rect.left || 0),
          top: Number(rect.top || 0),
          width: Number(rect.width || 0),
          height: Number(rect.height || 0)
        });
      })(${jsonEncode(config)});''');
    } catch (_) {
      await _hideSitePlayerActionOverlay();
      if (_sitePlayerOverlayRect != null) {
        if (mounted) {
          setState(() => _sitePlayerOverlayRect = null);
        } else {
          _sitePlayerOverlayRect = null;
        }
      }
    }
  }


  bool get _hasAnyCapturedPlayableMedia =>
      _bestQuickMedia != null ||
      ((_capturedVideoUrl ?? '').isNotEmpty &&
          !(_capturedVideoUrl ?? '').startsWith('blob:'));

  bool get _hasAnyDirectDownloadMedia {
    if (_bestQuickMedia?.isDirectFile == true) return true;
    return _capturedMedia.any((item) =>
        _sameWatchPage(item.pageUrl) && item.isDirectFile);
  }

  void _clearQuickActionCaptureWaiters() {
    _watchButtonWaitingForCapture = false;
    _downloadButtonWaitingForCapture = false;
  }

  Future<void> _scheduleQuickActionCapture({required bool forDownload}) async {
    if (_wc == null) {
      _showSnack(forDownload
          ? '⚠️ لا يمكن تجهيز التحميل الآن'
          : '⚠️ لا يمكن تجهيز المشاهدة الآن');
      return;
    }

    final ticket = ++_quickActionCaptureTicket;
    _watchButtonWaitingForCapture = !forDownload;
    _downloadButtonWaitingForCapture = forDownload;
    _suppressAutoOpenUntil = DateTime.now().millisecondsSinceEpoch + 15000;

    await _setPreciseBotSuppressed(false);
    await _refreshCurrentMediaTitle();
    await _forcePreferred1080();
    await _primeWatchPageCapture();

    if (!mounted) return;
    _showSnack(forDownload
        ? 'جاري سحب رابط التحميل...'
        : 'جاري التقاط رابط المشاهدة...');

    Future.delayed(const Duration(seconds: 8), () {
      if (!mounted) return;
      if (ticket != _quickActionCaptureTicket) return;
      if (_watchButtonWaitingForCapture || _downloadButtonWaitingForCapture) {
        _clearQuickActionCaptureWaiters();
        _showSnack(forDownload
            ? '⚠️ لم يتم التقاط رابط تحميل مباشر بعد'
            : '⚠️ لم يتم التقاط رابط المشاهدة بعد');
      }
    });
  }

  Future<void> _tryCompletePendingQuickAction() async {
    if (_nativePlayerActive || _nativePlayerOpening) return;

    if (_watchButtonWaitingForCapture && _hasAnyCapturedPlayableMedia) {
      _watchButtonWaitingForCapture = false;
      _downloadButtonWaitingForCapture = false;
      await _playBestCapturedMedia();
      return;
    }

    if (_downloadButtonWaitingForCapture && _hasAnyCapturedPlayableMedia) {
      _watchButtonWaitingForCapture = false;
      _downloadButtonWaitingForCapture = false;
      await _downloadBestCapturedMedia();
    }
  }

  Future<void> _handleWatchButtonTap() async {
    await _setPreciseBotSuppressed(false);
    if (_hasAnyCapturedPlayableMedia) {
      _clearQuickActionCaptureWaiters();
      await _playBestCapturedMedia();
      return;
    }
    await _scheduleQuickActionCapture(forDownload: false);
  }

  Future<void> _handleDownloadButtonTap() async {
    await _setPreciseBotSuppressed(false);
    if (_hasAnyCapturedPlayableMedia) {
      _clearQuickActionCaptureWaiters();
      await _downloadBestCapturedMedia();
      return;
    }
    await _scheduleQuickActionCapture(forDownload: true);
  }

  Future<void> _playBestCapturedMedia() async {
    _watchButtonWaitingForCapture = false;
    _downloadButtonWaitingForCapture = false;
    final item = _bestQuickMedia;

    if (item != null) {
      await _openNativePlayer(
        force: true,
        replace: true,
        forcedUrl: item.url,
        forcedPageUrl: item.pageUrl,
        forcedMimeType: item.mimeType,
      );
      return;
    }

    if (_capturedVideoUrl != null && _capturedVideoUrl!.isNotEmpty) {
      await _openNativePlayer(
        force: true,
        replace: true,
        forcedUrl: _capturedVideoUrl,
        forcedPageUrl: _capturedVideoPageUrl,
        forcedMimeType: _capturedVideoMimeType,
      );
      return;
    }

    _showSnack('⚠️ لم ألتقط رابط الفيديو الحقيقي بعد');
  }

  Future<void> _startDownloadForQuality(PageQualityOption option) async {
    final normalizedLabel = _normalizeQualityLabel(option.label);
    final cached = _bestQuickMediaForQuality(normalizedLabel);
    if (cached != null && cached.isDirectFile) {
      await _startDownload(cached.url, cached.fileName);
      return;
    }
    if (_looksLikePlayableMediaUrl(option.url)) {
      if (_isDirectMediaFile(option.url)) {
        await _startDownload(
          option.url!,
          _contextualFileName(option.url!, qualityLabel: normalizedLabel),
        );
      } else {
        _showSnack('رابط ${normalizedLabel.isEmpty ? 'البث' : normalizedLabel} جاهز للتشغيل فقط');
      }
      return;
    }
    if (_wc == null) return;

    _qualityDownloadSwitchPending = true;
    _pendingDownloadQualityLabel = normalizedLabel;
    _currentPageQualityLabel = normalizedLabel;
    _suppressAutoOpenUntil = DateTime.now().millisecondsSinceEpoch + 7000;
    await _pauseOriginalSitePlayer();

    bool clicked = false;
    try {
      final raw = await _wc!.evaluateJavascript(source: '''
        (function(){
          try {
            if (!window.__asdSelectQualityOption) return false;
            return !!window.__asdSelectQualityOption(${jsonEncode(option.key)}, ${jsonEncode(option.label)}, ${jsonEncode(option.url ?? '')});
          } catch(e) { return false; }
        })();
      ''');
      clicked = raw == true || raw?.toString() == 'true';
    } catch (_) {}

    if (!clicked) {
      _qualityDownloadSwitchPending = false;
      _pendingDownloadQualityLabel = null;
      _showSnack('⚠️ تعذّر التقاط جودة ${normalizedLabel.isEmpty ? option.label : normalizedLabel}');
      return;
    }

    Future.delayed(const Duration(seconds: 5), () {
      if (_qualityDownloadSwitchPending && _pendingDownloadQualityLabel == normalizedLabel) {
        _qualityDownloadSwitchPending = false;
        _pendingDownloadQualityLabel = null;
        _showSnack('⚠️ لم ألتقط رابط ${normalizedLabel.isEmpty ? option.label : normalizedLabel}');
      }
    });
  }

  Future<void> _downloadBestCapturedMedia() async {
    _watchButtonWaitingForCapture = false;
    _downloadButtonWaitingForCapture = false;

    final item = _bestQuickMedia;

    if (item != null) {
      await _startDownload(
        item.url,
        item.fileName,
      );
      return;
    }

    if (_capturedVideoUrl != null && _capturedVideoUrl!.isNotEmpty) {
      final url = _capturedVideoUrl!;
      await _startDownload(
        url,
        _contextualFileName(
          url,
          qualityLabel: _currentPageQualityLabel,
          fallbackExt: _isStreamUrl(url) ? 'm3u8' : 'mp4',
        ),
      );
      return;
    }

    _showSnack('⚠️ لم ألتقط رابط الفيديو الحقيقي بعد');
  }

  Future<void> _showQualityDownloadSheet() async {
    await _ensureDownloadQualityChoicesReady();
    final options = _sortedQualityOptions;
    if (options.isEmpty) {
      final item = _bestQuickMedia;
      if (item != null && item.isDirectFile) {
        await _startDownload(item.url, item.fileName);
      }
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF151A21),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'اختر الجودة للتحميل',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                ...options.map((option) {
                  final normalized = _normalizeQualityLabel(option.label);
                  final cached = _bestQuickMediaForQuality(normalized);
                  final readyDirect = cached?.isDirectFile == true || _isDirectMediaFile(option.url);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      tileColor: const Color(0xFF1D2430),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFFF59E0B),
                        child: Text(
                          normalized.isEmpty ? option.label : normalized.replaceAll('p', ''),
                          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w700, fontSize: 11),
                        ),
                      ),
                      title: Text(
                        normalized.isEmpty ? option.label : normalized,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        readyDirect ? 'تحميل مباشر' : 'التقاط الرابط ثم التحميل',
                        style: const TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                      trailing: const Icon(Icons.download_rounded, color: Colors.white),
                      onTap: () async {
                        Navigator.of(ctx).pop();
                        await _startDownloadForQuality(option);
                      },
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _startHiddenQualityHarvest() async {
    
    
    return;
  }

  void _maybePromptDownloadChoices() {
    if (!widget.autoDownloadPrompt || _autoDownloadPromptShown || !_looksLikeWatchPage()) {
      return;
    }
    final hasPlayable = _bestQuickMedia != null;
    final hasQualities = _pageQualityOptions.isNotEmpty;
    if (!hasPlayable && !hasQualities) return;
    _autoDownloadPromptShown = true;
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted || _nativePlayerActive || _nativePlayerOpening) return;
      _downloadBestCapturedMedia();
    });
  }

  String? _lastPrimedUrl;

  Future<void> _primeWatchPageCapture() async {
    if (_wc == null || !_looksLikeWatchPage()) return;
    final currentUrl = _currentPageUrl ?? '';
    if (currentUrl.isNotEmpty && currentUrl == _lastPrimedUrl) return;
    _lastPrimedUrl = currentUrl;

    Future<void> runProbe() async {
      try {
        await _wc!.evaluateJavascript(source: r'''(function(){
          try { if (window.__asdCollectMediaNow) window.__asdCollectMediaNow(); } catch(e) {}

          try {
            document.querySelectorAll('video,audio').forEach(function(v){
              try { v.pause(); v.muted = true; v.volume = 0; } catch(e) {}
            });
          } catch(e) {}

          try {
            var frames = document.querySelectorAll('iframe');
            frames.forEach(function(fr){
              try {
                var fw = fr.contentWindow;
                if (!fw) return;
                if (fw.jwplayer) {
                  var jw = fw.jwplayer();
                  if (!jw || !jw.getQualityLevels) return;
                  var levels = jw.getQualityLevels();
                  if (!levels || levels.length === 0) return;

                  var PREFERRED = ['1080','720','480','360','240'];
                  var opts = [];
                  var seen = {};
                  levels.forEach(function(lvl, i) {
                    var url = lvl.file || lvl.src || '';
                    var mLabel = (lvl.label || '').match(/(2160|1440|1080|720|540|480|360|240)/);
                    var mUrl   = url.match(/(2160|1440|1080|720|540|480|360|240)p/i);
                    var q = (mLabel && mLabel[1]) || (mUrl && mUrl[1]);
                    if (!q || !url) return;
                    if (seen[q]) return;
                    seen[q] = true;
                    opts.push({ label: q+'p', key: q+'p_direct', url: url, selected: false });
                    try {
                      window.flutter_inappwebview.callHandler('onVideoFound', {
                        url: url, pageUrl: window.location.href,
                        currentTime: 0, mimeType: 'video/mp4', qualityLabel: q+'p'
                      });
                    } catch(ex) {}
                  });

                  var bestIdx = 0;
                  outer: for (var p = 0; p < PREFERRED.length; p++) {
                    for (var k = 0; k < levels.length; k++) {
                      var lbl  = (levels[k].label || '');
                      var file = (levels[k].file || levels[k].src || '');
                      var has  = lbl.indexOf(PREFERRED[p]) !== -1 || file.indexOf('/'+PREFERRED[p]+'p.') !== -1;
                      if (has) { bestIdx = k; break outer; }
                    }
                  }

                  if (opts.length > 0) {
                    opts.forEach(function(o){ o.selected = false; });
                    opts[Math.min(bestIdx, opts.length-1)].selected = true;
                    var cur = opts.find(function(o){ return o.selected; });
                    try {
                      window.flutter_inappwebview.callHandler('onQualityOptions', {
                        options: opts,
                        current: cur ? cur.label : opts[0].label
                      });
                    } catch(ex) {}
                  }

                  try {
                    ['preferredQuality','defaultQuality','quality','jwplayer.qualityLabel'].forEach(function(k){
                      try { localStorage.setItem(k, (cur ? cur.label : '1080p')); } catch(ex) {}
                      try { sessionStorage.setItem(k, (cur ? cur.label : '1080p')); } catch(ex) {}
                    });
                  } catch(ex) {}

                  if (!window.__asdQualitySet) {
                    window.__asdQualitySet = true;
                    try { jw.setCurrentQuality(bestIdx); } catch(e) {}
                    setTimeout(function(){
                      try { jw.setCurrentQuality(bestIdx); } catch(ex) {}
                      setTimeout(function(){ window.__asdQualitySet = false; }, 5000);
                    }, 250);
                  }
                }
              } catch(e) {}
            });
          } catch(e) {}
        })();''');
      } catch (_) {}
    }

    for (final ms in const [200, 600, 1200, 2200, 3500, 5000]) {
      Future.delayed(Duration(milliseconds: ms), runProbe);
    }
    Future.delayed(const Duration(milliseconds: 2200), _pauseOriginalSitePlayer);
    // Future.delayed(const Duration(milliseconds: 3200), _startHiddenQualityHarvest);
    
  }

  Widget _buildQuickMediaButtons() {
    if (!_showQuickMediaButtons) {
      _stopSitePlayerRectTracking(clear: false);
      return const SizedBox.shrink();
    }

    if (!_sitePlayerRectTracking) {
      _startSitePlayerRectTracking();
      Future.microtask(_syncSitePlayerOverlayRect);
    }

    return const SizedBox.shrink();
  }

  Widget _buildMediaGrabberPanel() {
    if (!_showMediaGrabber) return const SizedBox.shrink();

    return Positioned(
      top: 10,
      left: 10,
      right: 10,
      bottom: 10,
      child: Material(
        color: const Color(0xFF11161D),
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: const BoxDecoration(color: Color(0xFF18212C)),
              child: Row(
                children: [
                  const Icon(Icons.video_collection_outlined, color: Colors.orange),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'أداة جلب الفيديو (${_capturedMedia.length})',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _capturedMedia.clear();
                        _capturedMediaSeen.clear();
                      });
                    },
                    icon: const Icon(Icons.cleaning_services_outlined),
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() => _showMediaGrabber = false);
                    },
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _capturedMedia.isEmpty
                  ? const Center(
                      child: Text(
                        'لا يوجد أي رابط ملتقط بعد',
                        style: TextStyle(color: Colors.white70),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(10),
                      itemCount: _capturedMedia.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final item = _capturedMedia[i];
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A2431),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.fileName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                item.url,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(30),
                                    ),
                                    child: Text(
                                      _mediaKindLabel(item),
                                      style: const TextStyle(color: Colors.orange, fontSize: 12),
                                    ),
                                  ),
                                  if (item.mimeType != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(30),
                                      ),
                                      child: Text(
                                        item.mimeType!,
                                        style: const TextStyle(color: Colors.lightBlueAccent, fontSize: 12),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.orange,
                                        foregroundColor: Colors.black,
                                      ),
                                      onPressed: () async {
                                        await _openNativePlayer(
                                          force: true,
                                          replace: true,
                                          forcedUrl: item.url,
                                          forcedPageUrl: item.pageUrl,
                                          forcedMimeType: item.mimeType,
                                        );
                                      },
                                      icon: const Icon(Icons.play_arrow),
                                      label: const Text('تشغيل'),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF243142),
                                        foregroundColor: Colors.white,
                                      ),
                                      onPressed: () async {
                                        if (item.isDirectFile) {
                                          await _startDownload(
                                            item.url,
                                            item.fileName,
                                          );
                                        } else {
                                          
                                        }
                                      },
                                      icon: const Icon(Icons.download_rounded),
                                      label: const Text('تحميل'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStopBackgroundButton() {
    if (!_nativePlayerActive) return const SizedBox.shrink();
    return Positioned(
      bottom: 24,
      left: 0,
      right: 0,
      child: Center(
        child: SafeArea(
          top: false,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(30),
              onTap: () async {
                await _pauseOriginalSitePlayer();
                _showSnack('⏹ تم إيقاف الفيديو في الخلفية');
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xDD1A2430),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.white24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.stop_circle_outlined, color: Colors.orangeAccent, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'إيقاف الخلفية',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeDownloads = _downloads.where((d) => d.status == 'downloading' || d.status == 'preparing' || d.status == 'paused').length;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_nativePlayerActive) { await _closeNativePlayer(); return; }
        if (_fullscreen) { await _exitFullscreen(); return; }
        if (_showMediaGrabber) { setState(() => _showMediaGrabber = false); return; }
        if (_showDownloads) { _closeDownloadsPanel(); return; }
        await _goBackToSafeAnimePage();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: (_fullscreen || _hideSiteDuringDirectLaunch) ? null : PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: AppBar(
            toolbarHeight: 56,
            backgroundColor: const Color(0xFF18212C),
            foregroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            centerTitle: false,
            titleSpacing: 16,
            iconTheme: const IconThemeData(color: Colors.white),
            actionsIconTheme: const IconThemeData(color: Colors.white),
            title: Text(
              widget.headerTitle ?? 'Anime3rb',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 10),
                child: Center(
                  child: SizedBox(
                    width: 56,
                    height: 44,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.white, width: 1.5),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              color: Colors.white,
                              onPressed: () {
                                setState(() {
                                  _showDownloads = !_showDownloads;
                                  if (_showDownloads) _showMediaGrabber = false;
                                });
                                if (_showDownloads) {
                                  _stopSitePlayerRectTracking(clear: true);
                                } else if (_showQuickMediaButtons) {
                                  _startSitePlayerRectTracking();
                                }
                              },
                              icon: const Icon(Icons.download_rounded, color: Colors.white),
                            ),
                          ),
                        ),
                        if (activeDownloads > 0)
                          Positioned(
                            right: -2,
                            top: -4,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle),
                              child: Text(
                                '$activeDownloads',
                                style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        body: Stack(
          children: [
            Opacity(
              opacity: (_hideSiteDuringDirectLaunch || _webViewSuspendedForNative || _nativePlayerActive || _nativePlayerOpening) ? 0.0 : 1.0,
              child: IgnorePointer(
                ignoring: _hideSiteDuringDirectLaunch || _webViewSuspendedForNative || _nativePlayerActive || _nativePlayerOpening,
                child: InAppWebView(
                  initialUrlRequest: URLRequest(
                url: WebUri(widget.initialUrl),
                headers: {'User-Agent': _ua},
              ),
              pullToRefreshController: _ptr,
              initialUserScripts: UnmodifiableListView([
                UserScript(
                  source: _desktopViewport,
                  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                ),
                UserScript(
                  source: _forceAnime3rbNightMode,
                  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                  forMainFrameOnly: false,
                ),
                UserScript(
                  source: _forcePhoneFullscreen,
                  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                  forMainFrameOnly: false,
                ),
                UserScript(
                  source: _fsVid,
                  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                  forMainFrameOnly: false,
                ),
                UserScript(
                  source: _touchFix,
                  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                  forMainFrameOnly: false,
                ),
                UserScript(
                  source: _iframeVideoFix,
                  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                  forMainFrameOnly: false,
                ),
                UserScript(
                  source: _hideServers,
                  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
                ),
                UserScript(
                  source: _dlCapture,
                  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
                ),
                UserScript(
                  source: _networkMediaProbe,
                  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                  forMainFrameOnly: false,
                ),
                UserScript(
                  source: _vid3rbDeepCapture,
                  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                  forMainFrameOnly: false,
                ),
                UserScript(
                  source: _qualityAutoBot,
                  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                  forMainFrameOnly: false,
                ),
                UserScript(
                  source: _srvCapture,
                  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
                ),
              ]),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                useShouldInterceptRequest: true,
                useShouldOverrideUrlLoading: true,
                useOnDownloadStart: true,
                allowsInlineMediaPlayback: true,
                mediaPlaybackRequiresUserGesture: false,
                supportMultipleWindows: true,
                javaScriptCanOpenWindowsAutomatically: true,
                useHybridComposition: true,
                disableContextMenu: true,
                userAgent: _ua,
                preferredContentMode: UserPreferredContentMode.MOBILE,
                useWideViewPort: false,
                loadWithOverviewMode: true,
                allowsPictureInPictureMediaPlayback: true,
                isFraudulentWebsiteWarningEnabled: false,
                allowFileAccess: true,
                allowUniversalAccessFromFileURLs: true,
                  ),
                  onWebViewCreated: (controller) {
                _wc = controller;


                controller.addJavaScriptHandler(
                  handlerName: 'onVid',
                  callback: (args) {
                    if (!mounted) return;
                    if (args.isNotEmpty && args[0] is Map) {
                      final data = Map<String, dynamic>.from(args[0] as Map);
                      final playing = data['playing'] == true;
                      final info = data['info'];

                      if (info is Map) {
                        final map = Map<String, dynamic>.from(info);
                        final vw = (map['videoWidth'] as num?)?.toInt() ?? 0;
                        final vh = (map['videoHeight'] as num?)?.toInt() ?? 0;
                        if (vw > 0 && vh > 0) {
                          _videoAspectW = vw;
                          _videoAspectH = vh;
                        }
                        final ct = (map['currentTime'] as num?)?.toDouble();
                        if (ct != null && ct > 0) _capturedVideoTime = ct;
                        
                        final urlStr = map['url']?.toString();
                        if (urlStr != null && urlStr.isNotEmpty && !urlStr.startsWith('blob:')) {
                          _capturePlayableUrl(
                            urlStr,
                            pageUrl: map['pageUrl']?.toString(),
                            currentTime: ct,
                            mimeType: map['mimeType']?.toString(),
                          );
                        }
                      }

                      
                      if (_nativePlayerActive || _nativePlayerOpening) {
                        if (playing) {
                          _pauseOriginalSitePlayer();
                          _scheduleOriginalPlayerHardPause();
                        }
                        return;
                      }

                      setState(() {
                        _videoPlaying = playing;
                        if (playing) _videoDetected = true;
                      });

                      final now = DateTime.now().millisecondsSinceEpoch;
                      if (playing && _allowNativeAutoOpen &&
                          now > _suppressAutoOpenUntil &&
                          (!widget.launchHidden || _botCompleted)) {
                        _tryAutoOpenBestQuickMedia();
                      }
                    }
                  },
                );


                controller.addJavaScriptHandler(
                  handlerName: 'onTime',
                  callback: (args) {
                    if (args.isNotEmpty && args[0] != null) {
                      _capturedVideoTime = (args[0] as num).toDouble();
                    }
                  },
                );

                controller.addJavaScriptHandler(
                  handlerName: 'onVideoDimensions',
                  callback: (args) {
                    if (args.isNotEmpty && args[0] is Map) {
                      final map = Map<String, dynamic>.from(args[0] as Map);
                      final vw = (map['width'] as num?)?.toInt() ?? 0;
                      final vh = (map['height'] as num?)?.toInt() ?? 0;
                      if (vw > 0 && vh > 0) {
                        _videoAspectW = vw;
                        _videoAspectH = vh;
                      }
                    }
                  },
                );

                controller.addJavaScriptHandler(
                  handlerName: 'onPip',
                  callback: (args) {
                    if (args.isNotEmpty && args[0] is Map) {
                      final info = Map<String, dynamic>.from(args[0] as Map);
                      _capturePlayableUrl(info['url']?.toString(),
                        pageUrl: info['pageUrl']?.toString(),
                        currentTime: (info['currentTime'] as num?)?.toDouble(),
                        mimeType: info['mimeType']?.toString());
                      final vw = (info['videoWidth'] as num?)?.toInt() ?? 0;
                      final vh = (info['videoHeight'] as num?)?.toInt() ?? 0;
                      if (vw > 0 && vh > 0) { _videoAspectW = vw; _videoAspectH = vh; }
                    }
                  },
                );

                controller.addJavaScriptHandler(
                  handlerName: 'onPlayIntent',
                  callback: (args) {
                    if (args.isNotEmpty && args[0] is Map) {
                      final info = Map<String, dynamic>.from(args[0] as Map);
                      _capturePlayableUrl(info['url']?.toString(),
                        pageUrl: info['pageUrl']?.toString(),
                        currentTime: (info['currentTime'] as num?)?.toDouble(),
                        mimeType: info['mimeType']?.toString());
                      final vw = (info['videoWidth'] as num?)?.toInt() ?? 0;
                      final vh = (info['videoHeight'] as num?)?.toInt() ?? 0;
                      if (vw > 0 && vh > 0) { _videoAspectW = vw; _videoAspectH = vh; }
                    }
                  },
                );

                controller.addJavaScriptHandler(
                  handlerName: 'onQualityChanged',
                  callback: (args) {
                    if (args.isEmpty || args[0] is! Map) return;
                    final data = Map<String, dynamic>.from(args[0] as Map);
                    final quality = _normalizeQualityLabel(data['quality']?.toString() ?? '');
                    final url = data['url']?.toString() ?? '';
                    if (quality.isEmpty || url.isEmpty) return;

                    debugPrint('🎬 Quality changed: $quality → $url');
                    _qualityDirectUrls[quality] = url;

                    _capturePlayableUrl(
                      url,
                      pageUrl: _capturedVideoPageUrl,
                      mimeType: 'video/mp4',
                      qualityLabel: quality,
                    );

                    if (_qualitySwitchPending &&
                        _normalizeQualityLabel(_currentPageQualityLabel ?? '') == quality) {
                      _qualitySwitchPending = false;
                      final shouldReopen = _manualPlayAfterQualitySwitchPending || _nativePlayerActive;
                      _manualPlayAfterQualitySwitchPending = false;
                      if (shouldReopen) {
                        Future.microtask(() => _openNativePlayer(
                              force: true,
                              replace: true,
                              startTimeOverride: _pendingNativeStartTime,
                              forcedUrl: url,
                              forcedPageUrl: _capturedVideoPageUrl,
                              forcedMimeType: 'video/mp4',
                            ));
                      }
                    }
                  },
                );


                controller.addJavaScriptHandler(
                  handlerName: 'onQualityOptions',
                  callback: (args) {
                    if (args.isEmpty || args[0] is! Map) return;
                    final data = Map<String, dynamic>.from(args[0] as Map);
                    final rawOpts = (data['options'] as List?)
                            ?.whereType<Map>()
                            .map((e) => PageQualityOption.fromMap(
                                Map<String, dynamic>.from(e)))
                            .where((opt) => !_isAnimeQualityPageUrl(opt.url))
                            .toList() ??
                        const <PageQualityOption>[];
                    final currentLabel = data['current']?.toString();

                    if (rawOpts.length < 2) return;

                    bool currentPremium = (currentLabel != null && currentLabel.isNotEmpty)
                        ? _isPremiumQualityLabel(currentLabel)
                        : false;
                    String? detectedCurrent = (currentLabel != null && currentLabel.isNotEmpty)
                        ? _normalizeQualityLabel(currentLabel)
                        : null;
                    if (detectedCurrent == null || detectedCurrent.isEmpty) {
                      for (final opt in rawOpts) {
                        if (opt.selected) {
                          detectedCurrent = _normalizeQualityLabel(opt.label);
                          currentPremium = _isPremiumQualityLabel(opt.label);
                          break;
                        }
                      }
                    }
                    detectedCurrent ??= _normalizeQualityLabel(rawOpts.first.label);
                    _currentQualityIsPremium = currentPremium;

                    final merged = <String, PageQualityOption>{};
                    for (final opt in rawOpts) {
                      final norm = _normalizeQualityLabel(opt.label);
                      if (norm.isEmpty) continue;
                      final directUrl = (_qualityDirectUrls[norm] ?? '').trim();
                      final originalUrl = (opt.url ?? '').trim();
                      final effectiveUrl = directUrl.isNotEmpty
                          ? directUrl
                          : (originalUrl.isNotEmpty ? originalUrl : null);
                      merged[norm] = PageQualityOption(
                        label: norm,
                        key: opt.key.isNotEmpty ? opt.key : norm.toLowerCase(),
                        url: effectiveUrl,
                        selected: norm == detectedCurrent,
                      );
                    }

                    for (final entry in _qualityDirectUrls.entries) {
                      final norm = _normalizeQualityLabel(entry.key);
                      if (norm.isEmpty || merged.containsKey(norm)) continue;
                      merged[norm] = PageQualityOption(
                        label: norm,
                        key: 'captured_${norm.toLowerCase()}',
                        url: entry.value,
                        selected: norm == detectedCurrent,
                      );
                    }

                    final fixedOpts = merged.values.toList()
                      ..sort((a, b) => _qualityRankLabel(b.label).compareTo(_qualityRankLabel(a.label)));

                    debugPrint('🎬 Quality options received: ${fixedOpts.map((e) => '${e.label}:${e.url ?? ''}').toList()}');
                    debugPrint('🎬 Current quality: $detectedCurrent');

                    if (mounted) {
                      setState(() => _updatePageQualityOptions(fixedOpts, detectedCurrent));
                    } else {
                      _updatePageQualityOptions(fixedOpts, detectedCurrent);
                    }

                    _scheduleQualityHarvestIfNeeded(fixedOpts);

                    PageQualityOption? readyOption;
                    for (final opt in fixedOpts) {
                      final q = _normalizeQualityLabel(opt.label);
                      final readyUrl = (opt.url ?? '').trim();
                      if (_isBotAcceptedQuality(q) && readyUrl.isNotEmpty &&
                          (_isVid3rbDirectVideoUrl(readyUrl) || _isDirectMediaFile(readyUrl))) {
                        readyOption = opt;
                        break;
                      }
                    }
                    if (readyOption != null && widget.launchHidden) {
                      _botPreferredTargetQuality = _normalizeQualityLabel(readyOption.label);
                      _markBotGateReady('quality_options', quality: readyOption.label);
                    } else if (_preferredQualityBotPending && _isBotAcceptedQuality(currentPremium ? '' : detectedCurrent)) {
                      _finishPreferredQualityBotGate('quality_options');
                    }

                    if (!_preventAutoReopenAfterClose && !_autoQualityApplied && fixedOpts.isNotEmpty) {
                      _autoQualityApplied = true;
                      const preferredQualities = ['1080p', '720p', '480p', '360p', '240p'];
                      PageQualityOption? autoOption;
                      for (final pq in preferredQualities) {
                        for (final opt in fixedOpts) {
                          if (_normalizeQualityLabel(opt.label) == pq) {
                            autoOption = opt;
                            break;
                          }
                        }
                        if (autoOption != null) break;
                      }
                      autoOption ??= fixedOpts.first;

                      final currentNorm = _normalizeQualityLabel(detectedCurrent);
                      final targetNorm = _normalizeQualityLabel(autoOption.label);
                      if (targetNorm.isNotEmpty && targetNorm != currentNorm) {
                        debugPrint('🎯 Forcing preferred quality in-page only: ${autoOption.label}');
                        Future.delayed(const Duration(milliseconds: 200), () async {
                          if (!mounted || _nativePlayerActive || _nativePlayerOpening) return;
                          await _forcePreferred1080();
                          await _primeWatchPageCapture();
                        });
                      }
                    }

                    if (_nativePlayerActive) {
                      _pip.invokeMethod('updateQualityOptions', {
                        'qualityOptions': _pageQualityOptions.map((e) => e.toMap()).toList(),
                        'currentQualityLabel': _currentPageQualityLabel,
                      }).catchError((_) {});
                    }
                  },
                );

controller.addJavaScriptHandler(
  handlerName: 'onBotComplete',
  callback: (args) async {
    if (!mounted) return;
    if (args.isEmpty || args[0] is! Map) return;
    final data = Map<String, dynamic>.from(args[0] as Map);

    final success = data['success'] == true;
    final qualityRaw = data['quality']?.toString() ?? '';
    final playing = data['playing'] == true;
    final quality = _normalizeQualityLabel(qualityRaw);

    debugPrint('🤖 Bot complete: success=$success '
        'quality=$quality playing=$playing');

    if (!success) {
      debugPrint('🤖 Bot failed, skipping native player');
      return;
    }

    if (quality.isNotEmpty) {
      _botPreferredTargetQuality = quality;
      _botConfirmedQuality = quality;
      _currentPageQualityLabel = quality;
    }

    final qualityOk = _isBotAcceptedQuality(quality) && _isBotConfirmed1080(quality);
    if (!qualityOk) {
      debugPrint('🤖 Bot quality is not the preferred fallback target, native player stays closed: $quality');
      return;
    }

    if (!playing) {
      debugPrint('🤖 Bot: video not playing yet, wait 600ms');
      await Future.delayed(const Duration(milliseconds: 600));
    }

    final bestItem = _bestQuickMediaForQuality(quality) ?? _bestQuickMedia;
    if (bestItem == null && _capturedVideoUrl == null) {
      debugPrint('🤖 Bot complete but no URL captured yet, waiting 800ms more');
      await Future.delayed(const Duration(milliseconds: 800));
    }

    if (!mounted || _nativePlayerActive || _nativePlayerOpening) return;
    if (_preventAutoReopenAfterClose) return;

    _markBotGateReady('bot_complete', quality: quality);

    final item = _bestQuickMediaForQuality(quality) ?? _bestQuickMedia;
    final hasPlayable = item != null ||
        (_capturedVideoUrl != null && !(_capturedVideoUrl!.startsWith('blob:')));

    if (hasPlayable) {
      _videoDetected = true;
      
      await _pauseOriginalSitePlayer();
      _scheduleOriginalPlayerHardPause();
      if (_watchButtonWaitingForCapture || _downloadButtonWaitingForCapture) {
        await _tryCompletePendingQuickAction();
      } else if (mounted) {
        _tryAutoOpenBestQuickMedia();
      }
    } else {
      debugPrint('🤖 Bot done but no URL available yet');
    }
  },
);

                controller.addJavaScriptHandler(
                  handlerName: 'onOverlayPlayTap',
                  callback: (args) async {
                    await _handleWatchButtonTap();
                  },
                );

                controller.addJavaScriptHandler(
                  handlerName: 'onOverlayDownloadTap',
                  callback: (args) async {
                    await _handleDownloadButtonTap();
                  },
                );

                controller.addJavaScriptHandler(
                  handlerName: 'onPreferredQualityBotState',
                  callback: (args) {
                    if (args.isEmpty || args[0] is! Map) return;
                    final data = Map<String, dynamic>.from(args[0] as Map);
                    final state = data['state']?.toString() ?? '';
                    final qualityRaw = data['quality']?.toString();
                    final premium = data['premium'] == true;
                    if (qualityRaw != null && qualityRaw.isNotEmpty && !premium) {
                      final normalized = _normalizeQualityLabel(qualityRaw);
                      if (normalized.isNotEmpty) {
                        _currentPageQualityLabel = normalized;
                        _currentQualityIsPremium = false;
                        if (_preferredQualityBotPending && _isBotAcceptedQuality(normalized)) {
                          if (normalized == '1080p' || _botTargetQualityFromOptions().isEmpty) {
                            _botPreferredTargetQuality = normalized;
                          }
                          _markBotGateReady('bot_state:$normalized', quality: normalized);
                        }
                        if (normalized == '1080p') {
                          
                        }
                      }
                    } else if (state == 'player_started' && _preferredQualityBotPending) {
                      
                    }
                  },
                );

                controller.addJavaScriptHandler(
                  handlerName: 'onServerOptions',
                  callback: (args) {
                    if (args.isEmpty || args[0] is! Map) return;
                    final data = Map<String, dynamic>.from(args[0] as Map);
                    final rawOpts = (data['options'] as List?)
                            ?.whereType<Map>()
                            .map((e) => PageServerOption.fromMap(
                                Map<String, dynamic>.from(e)))
                            .toList() ??
                        const <PageServerOption>[];
                    final current = data['current']?.toString();
                    if (rawOpts.length < 2) return;
                    if (mounted) {
                      setState(() => _updateServerOptions(rawOpts, current));
                    } else {
                      _updateServerOptions(rawOpts, current);
                    }
                    if (_nativePlayerActive) {
                      _pip.invokeMethod('updateServerOptions', {
                        'serverOptions': _pageServerOptions.map((e) => e.toMap()).toList(),
                        'currentServerLabel': _currentServerLabel,
                      }).catchError((_) {});
                    }
                  },
                );

                controller.addJavaScriptHandler(
                  handlerName: 'onDebugLog',
                  callback: (args) {
                    if (args.isNotEmpty) {
                      debugPrint('🌐 [WebView Debug] ${args[0]}');
                    }
                  },
                );

                controller.addJavaScriptHandler(
                  handlerName: 'onDownload',
                  callback: (args) {
                    if (args.isNotEmpty && args[0] is Map) {
                      final info = Map<String, dynamic>.from(args[0] as Map);
                      final url = info['url']?.toString() ?? '';
                      final label = _normalizeQualityLabel(
                        _pendingDownloadQualityLabel ?? _hiddenHarvestCurrentQuality ?? _currentPageQualityLabel ?? '',
                      );
                      final name = _contextualFileName(url, qualityLabel: label);
                      if (url.isNotEmpty) {
                        _addCapturedMedia(
                          url,
                          pageUrl: _currentPageUrl ?? _capturedVideoPageUrl ?? _lastTrusted,
                          mimeType: _inferMimeType(url),
                          qualityLabel: label,
                          headers: {
                            'User-Agent': _ua,
                            'Referer': _currentPageUrl ?? _capturedVideoPageUrl ?? _lastTrusted ?? 'https://anime3rb.com/',
                          },
                        );
                      }
                      if (url.isNotEmpty && !_discoveredDownloadUrls.contains(url)) {
                        _startDownload(url, name);
                      }
                    }
                  },
                );

                controller.addJavaScriptHandler(
                  handlerName: 'onVideoFound',
                  callback: (args) {
                    if (!mounted) return;
                    if (args.isNotEmpty && args[0] is Map) {
                      final info = Map<String, dynamic>.from(args[0] as Map);
                      final foundUrl = info['url']?.toString();

                      String foundQuality = _normalizeQualityLabel(
                        info['qualityLabel']?.toString() ??
                            _pendingDownloadQualityLabel ??
                            _hiddenHarvestCurrentQuality ??
                            _currentPageQualityLabel ??
                            '',
                      );

                      if (foundQuality.isEmpty && foundUrl != null) {
                        final qMatch = RegExp(r'/(2160|1440|1080|720|540|480|360|240)p\.', caseSensitive: false)
                            .firstMatch(foundUrl);
                        if (qMatch != null) foundQuality = '${qMatch.group(1)}p';
                      }

                      if (foundQuality.isNotEmpty && foundUrl != null && foundUrl.isNotEmpty) {
                        if (foundUrl.contains('vid3rb.com') || foundUrl.contains('.mp4')) {
                          _qualityDirectUrls[foundQuality] = foundUrl;
                          debugPrint('📦 Stored quality URL: $foundQuality');
                        }
                      }

                      _capturePlayableUrl(foundUrl,
                        pageUrl: info['pageUrl']?.toString(),
                        currentTime: (info['currentTime'] as num?)?.toDouble(),
                        mimeType: info['mimeType']?.toString(),
                        qualityLabel: foundQuality);
                      if (_serverSwitchPending &&
                          foundUrl != null &&
                          foundUrl.isNotEmpty &&
                          foundUrl != _lastNativePlayerUrl) {
                        _serverSwitchPending = false;
                        Future.microtask(() => _openNativePlayer(
                          force: true,
                          replace: true,
                          forcedUrl: foundUrl,
                          forcedPageUrl: info['pageUrl']?.toString(),
                          forcedMimeType: info['mimeType']?.toString(),
                        ));
                        return;
                      }
                      if (_qualityDownloadSwitchPending && foundUrl != null && foundUrl.isNotEmpty) {
                        final pendingLabel = _normalizeQualityLabel(_pendingDownloadQualityLabel ?? foundQuality);
                        _qualityDownloadSwitchPending = false;
                        _pendingDownloadQualityLabel = null;
                        if (_isDirectMediaFile(foundUrl)) {
                          final downloadName = _contextualFileName(foundUrl, qualityLabel: pendingLabel);
                          Future.microtask(() => _startDownload(foundUrl, downloadName));
                        } else {
                          
                        }
                        return;
                      }
                      if (_qualitySwitchPending && foundUrl != null && foundUrl.isNotEmpty && foundUrl != _lastNativePlayerUrl) {
                        _qualitySwitchPending = false;
                        final shouldReopenPlayer = _manualPlayAfterQualitySwitchPending || _nativePlayerActive || _nativePlayerOpening;
                        _manualPlayAfterQualitySwitchPending = false;
                        if (shouldReopenPlayer) {
                          Future.microtask(() => _openNativePlayer(
                            force: true,
                            replace: true,
                            startTimeOverride: _pendingNativeStartTime,
                            forcedUrl: foundUrl,
                            forcedPageUrl: info['pageUrl']?.toString(),
                            forcedMimeType: info['mimeType']?.toString(),
                          ));
                        }
                        return;
                      }
                      if (_videoPlaying && _allowNativeAutoOpen &&
                          !_nativePlayerActive && !_nativePlayerOpening &&
                          (!widget.launchHidden || _botCompleted)) {
                        _tryAutoOpenBestQuickMedia();
                      }
                      _maybePromptDownloadChoices();
                    }
                  },
                );

                controller.addJavaScriptHandler(
                  handlerName: 'onFS',
                  callback: (args) {
                    if (!mounted || _nativePlayerActive || _nativePlayerOpening) return;
                    if (args.isNotEmpty) {
                      final isFullscreen = args[0] == true;
                      if (isFullscreen && !_fullscreen) {
                        _enterFullscreen();
                      } else if (!isFullscreen && _fullscreen) _exitFullscreen();
                    }
                  },
                );

                controller.addJavaScriptHandler(
                  handlerName: 'onForcePhoneFs',
                  callback: (args) {},
                );
              },
              onEnterFullscreen: (_) => _enterFullscreen(),
              onExitFullscreen: (_) => _exitFullscreen(),
              onCreateWindow: (controller, action) async {
                final rawUrl = action.request.url?.toString() ?? '';
                if (rawUrl.isEmpty) return false;

                final currentUrl = (await controller.getUrl())?.toString();
                if (_isBlockingAnimeQualityPageNavigation() && _isAnimeQualityPageUrl(rawUrl)) {
                  return false;
                }
                
                
                if (action.hasGesture != true && _isSameDocumentUrl(rawUrl, currentUrl)) {
                  return false;
                }

                final decodedTarget = _decodeArabseedRedirect(rawUrl);
                if (decodedTarget != null) {
                  if (_isB(decodedTarget) || _isAdResourceUrl(decodedTarget)) {
                    return false;
                  }
                  _rememberAllowedHost(decodedTarget);
                }

                final checkUrl = decodedTarget ?? rawUrl;
                if (_isB(checkUrl) || _isAdResourceUrl(checkUrl)) {
                  return false;
                }

                if (_isDownloadUrl(checkUrl)) {
                  final name = _contextualFileName(checkUrl);
                  if (!_discoveredDownloadUrls.contains(checkUrl)) {
                    _startDownload(checkUrl, name);
                  }
                  return true;
                }

                if (_isAllowedNavigation(rawUrl, true) || _isAllowedNavigation(checkUrl, true)) {
                  await controller.loadUrl(
                    urlRequest: URLRequest(
                      url: WebUri(rawUrl),
                      headers: {
                        'User-Agent': _ua,
                        if ((_lastTrusted ?? '').isNotEmpty) 'Referer': _lastTrusted!,
                      },
                    ),
                  );
                  return true;
                }

                return false;
              },
              onDownloadStartRequest: (controller, req) async {
                final url = req.url.toString();
                final suggested = req.suggestedFilename?.trim();
                final name = _contextualFileName(
                  url,
                  qualityLabel: _pendingDownloadQualityLabel ?? _hiddenHarvestCurrentQuality ?? _currentPageQualityLabel,
                  fallbackExt: (suggested != null && suggested.contains('.')) ? suggested.split('.').last : 'mp4',
                );

                _addCapturedMedia(
                  url,
                  pageUrl: _lastTrusted,
                  mimeType: req.mimeType,
                  headers: {
                    'User-Agent': _ua,
                    'Referer': _lastTrusted ?? 'https://anime3rb.com/',
                  },
                );

                if (_isDirectMediaFile(url)) {
                  if (!_discoveredDownloadUrls.contains(url)) {
                    await _startDownload(url, name);
                  }
                } else {
                  
                }
              },
              shouldOverrideUrlLoading: (controller, nav) async {
                final url = nav.request.url?.toString() ?? '';
                final isMain = nav.isForMainFrame == true;
                if (!url.startsWith('http://') && !url.startsWith('https://')) {
                  return NavigationActionPolicy.CANCEL;
                }

                if (isMain && _isBlockingAnimeQualityPageNavigation() && _isAnimeQualityPageUrl(url)) {
                  return NavigationActionPolicy.CANCEL;
                }

                if (isMain && nav.hasGesture != true) {
                  final currentUrl = (await controller.getUrl())?.toString();
                  
                  if (_isSameDocumentUrl(url, currentUrl) && _isWatchLikeUrl(url)) {
                    return NavigationActionPolicy.CANCEL;
                  }
                }

                // ✅ FIX 1c: Block ads in ALL frames (main and iframe)
                if (_isB(url) || _isAdResourceUrl(url)) {
                  return NavigationActionPolicy.CANCEL;
                }

                final decodedTarget = _decodeArabseedRedirect(url);
                if (decodedTarget != null) {
                  if (_isB(decodedTarget) || _isAdResourceUrl(decodedTarget)) {
                    return NavigationActionPolicy.CANCEL;
                  }
                  _rememberAllowedHost(decodedTarget);
                  if (_isDownloadUrl(decodedTarget)) {
                    final name = _contextualFileName(decodedTarget);
                    if (!_discoveredDownloadUrls.contains(decodedTarget)) {
                      _startDownload(decodedTarget, name);
                    }
                    return NavigationActionPolicy.CANCEL;
                  }
                  return NavigationActionPolicy.ALLOW;
                }

                if (!isMain) return NavigationActionPolicy.ALLOW;

                if (_isDownloadUrl(url)) {
                  final name = _contextualFileName(url);
                  if (!_discoveredDownloadUrls.contains(url)) _startDownload(url, name);
                  return NavigationActionPolicy.CANCEL;
                }

                if (_isLikelyDownloadLandingUrl(url)) {
                  _rememberAllowedHost(url);
                  return NavigationActionPolicy.ALLOW;
                }

                if (_isAllowedNavigation(url, isMain)) return NavigationActionPolicy.ALLOW;
                return NavigationActionPolicy.CANCEL;
              },
              shouldInterceptRequest: (controller, req) async {
                final url = req.url.toString();
                if (url.isEmpty) return null;

                if (_isAdResourceUrl(url)) {
                  return WebResourceResponse(data: Uint8List(0));
                }

                final headers = <String, String>{};
                req.headers?.forEach((k, v) {
                  headers[k.toString()] = v.toString();
                });

                final interceptedQuality = _inferInterceptedQualityLabel(
                  url,
                  headers: headers,
                );
                final interceptedMime = headers['content-type'] ?? _inferMimeType(url);
                final interceptedPageUrl = _capturedVideoPageUrl ?? _currentPageUrl ?? _lastTrusted;

                if ((_looksLikePlayableMediaUrl(url) || _isVid3rbDirectVideoUrl(url)) && !_isYouTubeUrl(url)) {
                  _capturePlayableUrl(
                    url,
                    pageUrl: interceptedPageUrl,
                    mimeType: interceptedMime,
                    qualityLabel: interceptedQuality,
                  );
                  _addCapturedMedia(
                    url,
                    pageUrl: interceptedPageUrl,
                    mimeType: interceptedMime,
                    qualityLabel: interceptedQuality,
                    headers: headers,
                  );
                }

                if (url.contains('vid3rb.com') || url.contains('video.vid3rb') || url.contains('files.vid3rb')) {
                  if (_isVid3rbDirectVideoUrl(url) || url.contains('.mp4')) {
                    final qualityLabel = interceptedQuality;
                    if (qualityLabel.isNotEmpty) {
                      _qualityDirectUrls[qualityLabel] = url;
                      debugPrint('✅ [intercept] Quality URL captured: $qualityLabel → $url');
                    } else {
                      debugPrint('✅ [intercept] Direct Vid3rb URL captured: $url');
                    }

                    final now2 = DateTime.now().millisecondsSinceEpoch;
                    if (!_nativePlayerActive &&
                        !_nativePlayerOpening &&
                        now2 > _suppressAutoOpenUntil &&
                        !_qualitySwitchPending &&
                        !_qualityDownloadSwitchPending &&
                        (!widget.launchHidden || _botCompleted)) {
                      _capturedVideoUrl = url;
                      _capturedVideoMimeType = interceptedMime ?? 'video/mp4';
                      if (qualityLabel.isNotEmpty) {
                        _currentPageQualityLabel = qualityLabel;
                      }
                      _tryAutoOpenBestQuickMedia();
                    }

                    final uuidMatch = RegExp(r'/files/([^/]+)/([a-f0-9\-]{36})/').firstMatch(url);
                    if (uuidMatch != null) {
                      _currentVideoFolder = uuidMatch.group(1);
                      _currentVideoUuid = uuidMatch.group(2);
                    }
                    final tokenMatch = RegExp(r'[?&](?:t|token)=([^&]+)').firstMatch(url);
                    if (tokenMatch != null) {
                      _currentVideoBaseToken = tokenMatch.group(1);
                    }

                    _capturePlayableUrl(
                      url,
                      pageUrl: interceptedPageUrl,
                      mimeType: interceptedMime ?? 'video/mp4',
                      qualityLabel: qualityLabel,
                    );

                    if (_qualityDownloadSwitchPending) {
                      final pendingLabel = _normalizeQualityLabel(
                        _pendingDownloadQualityLabel ?? qualityLabel,
                      );
                      if (pendingLabel.isEmpty || pendingLabel == qualityLabel) {
                        _qualityDownloadSwitchPending = false;
                        _pendingDownloadQualityLabel = null;
                        final dlName = _contextualFileName(url, qualityLabel: pendingLabel);
                        Future.microtask(() => _startDownload(url, dlName));
                      }
                    }

                    if (_qualitySwitchPending) {
                      final wantedLabel = _normalizeQualityLabel(_currentPageQualityLabel ?? '');
                      if (wantedLabel.isEmpty || qualityLabel.isEmpty || wantedLabel == qualityLabel) {
                        _qualitySwitchPending = false;
                        final shouldReopen = _manualPlayAfterQualitySwitchPending || _nativePlayerActive;
                        _manualPlayAfterQualitySwitchPending = false;
                        if (shouldReopen) {
                          final freshUrl = url;
                          Future.microtask(() => _openNativePlayer(
                                force: true,
                                replace: true,
                                startTimeOverride: _pendingNativeStartTime,
                                forcedUrl: freshUrl,
                                forcedPageUrl: interceptedPageUrl,
                                forcedMimeType: interceptedMime ?? 'video/mp4',
                              ));
                        }
                      }
                    }
                  }
                }
                return null;
              },
              onLoadStart: (controller, url) {
                if (widget.launchHidden && !widget.downloadOnlyMode) {
                  _suppressAutoOpenUntil = DateTime.now().millisecondsSinceEpoch + 2400;
                }
                _cloudflareSafeInjectTicket++;
                _deferredAdBlockInjected = false;
                _deferredAdBlockScheduleActive = false;
                final preserveQualityState = _hiddenQualityHarvesting || _qualitySwitchPending || _qualityDownloadSwitchPending;
                _currentPageUrl = url?.toString();
                _rememberStableWatchUrl(url?.toString());
                _rememberGoodAnimePage(url?.toString());
                _stopSitePlayerRectTracking(clear: true);
                _currentPageTitle = null;
                _currentMediaTitle = null;
                _capturedVideoUrl = null;
                _capturedVideoTime = 0;
                _capturedVideoPageUrl = url?.toString();
                _capturedVideoMimeType = null;
                _videoAspectW = 16;
                _videoAspectH = 9;
                if (!preserveQualityState) {
                  _capturedMedia.clear();
                  _qualityDirectUrls.clear();
                  _currentVideoUuid = null;
                  _currentVideoFolder = null;
                  _currentVideoBaseToken = null;
                  _capturedMediaSeen.clear();
                  _harvestedQualityLabels.clear();
                  _hiddenHarvestCurrentQuality = null;
                  _qualityDownloadSwitchPending = false;
                  _pendingDownloadQualityLabel = null;
                  _autoDownloadPromptShown = false;
                }
                _nativeAutoOpenQueued = false;
                _botCompleted = false;
                _botConfirmedQuality = null;
                _preferredQualityBotPending = false;
                _preferredQualityBotReady = false;
                _preferredQualityBotStartedAt = 0;
                _currentQualityIsPremium = false;
                if (mounted) {
                  setState(() {
                    _videoDetected = false;
                    _videoPlaying = false;
                    if (!preserveQualityState) {
                      _pageQualityOptions = const [];
                      _pageServerOptions = const [];
                      _currentPageQualityLabel = null;
                      _currentServerLabel = null;
                      _serverSwitchPending = false;
                      _autoQualityApplied = false;
                    }
                  });
                }
              },
              onUpdateVisitedHistory: (controller, url, _) {
                _currentPageUrl = url?.toString();
                _rememberStableWatchUrl(url?.toString());
                _rememberGoodAnimePage(url?.toString());
              },
              onLoadStop: (controller, url) async {
                _ptr?.endRefreshing();
                if (widget.launchHidden && !widget.downloadOnlyMode) {
                  _suppressAutoOpenUntil = DateTime.now().millisecondsSinceEpoch + 1600;
                }
                final preserveQualityState = _hiddenQualityHarvesting || _qualitySwitchPending || _qualityDownloadSwitchPending;
                _currentHost = url?.host;
                _currentPageUrl = url?.toString();
                _rememberStableWatchUrl(url?.toString());
                _rememberGoodAnimePage(url?.toString());
                _rememberAllowedHost(url?.toString());
                _capturedVideoUrl = null;
                _capturedVideoTime = 0;
                _capturedVideoPageUrl = url?.toString();
                _capturedVideoMimeType = null;
                _videoAspectW = 16;
                _videoAspectH = 9;
                if (!preserveQualityState) {
                  _autoDownloadPromptShown = false;
                }
                _nativeAutoOpenQueued = false;
                _botCompleted = false;
                _botConfirmedQuality = null;
                if (mounted) {
                  setState(() {
                  _videoDetected = false;
                  _videoPlaying = false;
                  if (!preserveQualityState) {
                    _pageQualityOptions = const [];
                    _pageServerOptions = const [];
                    _currentPageQualityLabel = null;
                    _currentServerLabel = null;
                    _serverSwitchPending = false;
                    _autoQualityApplied = false;
                  }
                });
                }
                await _reinjectScripts();
                if (!_botCompleted && !_nativePlayerActive) {
                  await _forcePreferred1080();
                }
                await _refreshCurrentMediaTitle();
                await _primeWatchPageCapture();
                if (_showQuickMediaButtons) {
                  _startSitePlayerRectTracking();
                  Future.delayed(const Duration(milliseconds: 220), _syncSitePlayerOverlayRect);
                }
                Future.delayed(const Duration(milliseconds: 700), () {
                  if (!_botCompleted && !_nativePlayerActive && mounted) {
                    _forcePreferred1080();
                  }
                });
              },
              onProgressChanged: (controller, p) {
                if (mounted) setState(() => _progress = p / 100);
                if (p >= 35 && _showQuickMediaButtons) {
                  _startSitePlayerRectTracking();
                }
                if (p >= 80 && !_deferredAdBlockInjected) {
                  unawaited(_injectAdBlockScriptsAfterCloudflareCheck());
                }
              },
              onTitleChanged: (controller, title) {
                final clean = _cleanMediaTitle(title ?? '');
                if (clean.isNotEmpty) {
                  _currentPageTitle = clean;
                  if (mounted) setState(() {});
                }
              },
              onReceivedServerTrustAuthRequest: (controller, challenge) async {
                return ServerTrustAuthResponse(action: ServerTrustAuthResponseAction.CANCEL);
              },
            ),
              ),
            ),
            if (_hideSiteDuringDirectLaunch)
              Positioned.fill(
                child: Container(
                  color: Colors.black,
                  child: SafeArea(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if ((widget.loadingPosterUrl ?? '').isNotEmpty)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: Image.network(
                                  widget.loadingPosterUrl!,
                                  width: 170,
                                  height: 240,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    width: 170,
                                    height: 240,
                                    color: const Color(0xFF171B22),
                                    child: const Icon(Icons.movie_outlined, color: Colors.white54, size: 42),
                                  ),
                                ),
                              )
                            else
                              Container(
                                width: 170,
                                height: 240,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF171B22),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(Icons.movie_outlined, color: Colors.white54, size: 42),
                              ),
                            const SizedBox(height: 22),
                            Text(
                              widget.headerTitle ??
                                  (widget.downloadOnlyMode ? 'جاري تجهيز التحميل...' : 'جاري فتح المشغل...'),
                              maxLines: 2,
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              widget.downloadOnlyMode
                                  ? 'جاري فتح صفحة المشاهدة والتقاط الجودات وروابط السيرفرات للتحميل...'
                                  : 'جاري فتح صفحة المشاهدة والتقاط مشغل الموقع...',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
                            ),
                            const SizedBox(height: 20),
                            const CircularProgressIndicator(color: Color(0xFF7FBF3F)),
                            const SizedBox(height: 14),
                            TextButton.icon(
                              onPressed: () {
                                if (!mounted) return;
                                setState(() => _revealHiddenLaunchUi = true);
                              },
                              icon: const Icon(Icons.visibility_rounded, size: 18),
                              label: const Text('إظهار الصفحة يدويًا'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (_progress < 1.0)
              LinearProgressIndicator(value: _progress, color: Colors.orange, backgroundColor: Colors.transparent),
            _buildDownloadsPanel(),
            _buildQuickMediaButtons(),
            _buildStopBackgroundButton(),
          ],
        ),
      ),
    );
  }
}

class ArabPlexApp extends StatelessWidget {
  const ArabPlexApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0E1117),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF7FBF3F),
          secondary: Color(0xFF7FBF3F),
          surface: Color(0xFF171B22),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        useMaterial3: true,
      ),
      home: const PlexCatalogHome(),
    );
  }
}

enum PlexFilter { all, movies, series }

class CatalogEntry {
  final String title;
  final String url;
  final String imageUrl;
  final String type;
  final String subtitle;
  final String badge;
  final String quality;
  final String rating;
  final String year;

  const CatalogEntry({
    required this.title,
    required this.url,
    required this.imageUrl,
    required this.type,
    this.subtitle = '',
    this.badge = '',
    this.quality = '',
    this.rating = '',
    this.year = '',
  });
}

class CatalogPayload {
  final List<CatalogEntry> featured;
  final List<CatalogEntry> items;
  final List<CatalogEntry> movies;
  final List<CatalogEntry> series;

  const CatalogPayload({
    required this.featured,
    required this.items,
    required this.movies,
    required this.series,
  });
}

class MediaDetailsData {
  final String title;
  final String description;
  final String posterUrl;
  final String watchUrl;
  final String downloadUrl;
  final String rating;
  final String year;
  final String duration;
  final String quality;
  final String country;
  final String language;
  final String category;
  final List<String> genres;
  final List<CatalogEntry> episodes;

  const MediaDetailsData({
    required this.title,
    required this.description,
    required this.posterUrl,
    required this.watchUrl,
    required this.downloadUrl,
    required this.rating,
    required this.year,
    required this.duration,
    required this.quality,
    required this.country,
    required this.language,
    required this.category,
    required this.genres,
    required this.episodes,
  });
}

class PlexCatalogHome extends StatefulWidget {
  const PlexCatalogHome({super.key});

  @override
  State<PlexCatalogHome> createState() => _PlexCatalogHomeState();
}

class _PlexCatalogHomeState extends State<PlexCatalogHome> {
  InAppWebViewController? _bridge;
  CatalogPayload? _payload;
  bool _loading = true;
  bool _catalogWebViewReady = false;
  String? _error;
  PlexFilter _filter = PlexFilter.all;
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
      setState(() => _catalogWebViewReady = true);
    });
  }

  List<CatalogEntry> get _visibleItems {
    final payload = _payload;
    if (payload == null) return const [];
    List<CatalogEntry> base;
    switch (_filter) {
      case PlexFilter.movies:
        base = payload.movies;
        break;
      case PlexFilter.series:
        base = payload.series;
        break;
      case PlexFilter.all:
        base = payload.items;
        break;
    }
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return base;
    return base.where((e) {
      final hay = '${e.title} ${e.subtitle} ${e.badge}'.toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final featured = _payload?.featured ?? const <CatalogEntry>[];
    final visible = _visibleItems;

    return Scaffold(
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: 92,
                titleSpacing: 20,
                flexibleSpace: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xAA0E1117), Color(0xFF0E1117)],
                    ),
                  ),
                ),
                title: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: Color(0xFF7FBF3F),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'KR Plex',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'الموقع الأصلي',
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const AsdPicsPlayer(
                              initialUrl: 'https://anime3rb.com/',
                              headerTitle: 'Anime3rb',
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.language_rounded),
                    ),
                  ],
                ),
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(74),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    child: Column(
                      children: [
                        _buildSearchBar(),
                        const SizedBox(height: 12),
                        _buildFilterRow(),
                      ],
                    ),
                  ),
                ),
              ),
              if (_loading)
                const SliverToBoxAdapter(child: _PlexLoadingView())
              else if (_error != null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _PlexErrorView(
                    message: _error!,
                    onRetry: _reload,
                  ),
                )
              else ...[
                if (featured.isNotEmpty)
                  SliverToBoxAdapter(child: _buildHeroCarousel(featured)),
                SliverToBoxAdapter(
                  child: _buildSection(
                    title: 'أضيف حديثًا',
                    subtitle: 'واجهة قريبة من Plex مع نفس مصدر الموقع',
                    items: visible.take(18).toList(),
                    large: false,
                  ),
                ),
                SliverToBoxAdapter(
                  child: _buildSection(
                    title: 'أفلام أنمي',
                    subtitle: 'مجمعة من المصدر الحالي',
                    items: (_payload?.movies ?? const <CatalogEntry>[]).take(14).toList(),
                    large: false,
                  ),
                ),
                SliverToBoxAdapter(
                  child: _buildSection(
                    title: 'أنميات وحلقات',
                    subtitle: 'الحلقات والعناوين كما تظهر في الموقع',
                    items: (_payload?.series ?? const <CatalogEntry>[]).take(14).toList(),
                    large: false,
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 40)),
              ],
            ],
          ),
          if (_catalogWebViewReady)
            Positioned(
              width: 0.1,
              height: 0.1,
            left: -20,
            top: -20,
            child: IgnorePointer(
              ignoring: true,
              child: Opacity(
                opacity: 0.0,
                child: InAppWebView(
                  initialUrlRequest: URLRequest(
                    url: WebUri(kCatalogHomeUrl),
                    headers: const {'User-Agent': kScraperUserAgent},
                  ),
                  initialSettings: InAppWebViewSettings(
                    javaScriptEnabled: true,
                    transparentBackground: true,
                    supportZoom: false,
                    mediaPlaybackRequiresUserGesture: false,
                  ),
                  onWebViewCreated: (controller) {
                    _bridge = controller;
                  },
                  onLoadStop: (controller, url) async {
                    await _extractCatalogWithRetry();
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: const Color(0xFF171B22),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: TextField(
        onChanged: (value) => setState(() => _query = value),
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          border: InputBorder.none,
          prefixIcon: const Icon(Icons.search_rounded, color: Colors.white70),
          hintText: 'ابحث داخل النتائج الحالية',
          hintStyle: const TextStyle(color: Colors.white54),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  onPressed: () => setState(() => _query = ''),
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                ),
        ),
      ),
    );
  }

  Widget _buildFilterRow() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _filterChip('الكل', PlexFilter.all),
          const SizedBox(width: 10),
          _filterChip('أفلام', PlexFilter.movies),
          const SizedBox(width: 10),
          _filterChip('مسلسلات', PlexFilter.series),
        ],
      ),
    );
  }

  Widget _filterChip(String label, PlexFilter value) {
    final selected = _filter == value;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => setState(() => _filter = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF7FBF3F) : const Color(0xFF171B22),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? const Color(0xFF7FBF3F)
                : Colors.white.withOpacity(0.06),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.black : Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildHeroCarousel(List<CatalogEntry> items) {
    return SizedBox(
      height: 244,
      child: PageView.builder(
        controller: PageController(viewportFraction: 0.9),
        itemCount: items.length.clamp(0, 6),
        itemBuilder: (context, index) {
          final item = items[index];
          return GestureDetector(
            onTap: () => _openDetails(item),
            child: Container(
              margin: EdgeInsets.only(
                left: index == 0 ? 16 : 8,
                right: index == items.length - 1 ? 16 : 8,
                top: 10,
                bottom: 14,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                image: DecorationImage(
                  image: ResizeImage(NetworkImage(item.imageUrl), width: 900),
                  fit: BoxFit.cover,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x66000000),
                    blurRadius: 24,
                    offset: Offset(0, 14),
                  ),
                ],
              ),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x11000000), Color(0xD9000000)],
                  ),
                ),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (item.badge.isNotEmpty) _heroTag(item.badge),
                        if (item.quality.isNotEmpty) _heroTag(item.quality),
                        if (item.rating.isNotEmpty) _heroTag(item.rating),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (item.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        item.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _heroAction(
                          icon: Icons.play_arrow_rounded,
                          label: 'التفاصيل',
                          filled: true,
                          onTap: () => _openDetails(item),
                        ),
                        _heroAction(
                          icon: Icons.movie_filter_outlined,
                          label: item.type == 'movie' ? 'فيلم' : 'مسلسل',
                          filled: false,
                          onTap: () {},
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _heroTag(String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.36),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Text(
        value,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _heroAction({
    required IconData icon,
    required String label,
    required bool filled,
    required VoidCallback onTap,
  }) {
    return Material(
      color: filled ? const Color(0xFF7FBF3F) : Colors.white.withOpacity(0.08),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(icon, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required String subtitle,
    required List<CatalogEntry> items,
    required bool large,
  }) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: large ? 300 : 246,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemBuilder: (context, index) => _posterCard(items[index]),
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemCount: items.length,
            ),
          ),
        ],
      ),
    );
  }

  Widget _posterCard(CatalogEntry item) {
    return GestureDetector(
      onTap: () => _openDetails(item),
      child: SizedBox(
        width: 146,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: Image.network(
                        item.imageUrl,
                        fit: BoxFit.cover,
                        cacheWidth: 320,
                        errorBuilder: (_, __, ___) => Container(
                          color: const Color(0xFF1B2029),
                          child: const Icon(Icons.movie_creation_outlined, color: Colors.white54, size: 36),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xCC0E1117),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        item.quality.isNotEmpty ? item.quality : (item.badge.isNotEmpty ? item.badge : 'جاهز'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xFF7FBF3F),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.play_arrow_rounded, color: Colors.black),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                height: 1.15,
              ),
            ),
            if (item.subtitle.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                item.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
      _payload = null;
    });
    await _bridge?.loadUrl(
      urlRequest: URLRequest(
        url: WebUri(kCatalogHomeUrl),
        headers: const {'User-Agent': kScraperUserAgent},
      ),
    );
  }

  Future<void> _extractCatalogWithRetry([int attempt = 0]) async {
    if (_bridge == null) return;
    try {
      final raw = await _bridge!.evaluateJavascript(source: _homeExtractorJs);
      final decoded = await _decodeJsonValueAsync(raw);
      final payload = _parseCatalogPayload(decoded);
      if (payload.items.length < 8 && attempt < 5) {
        await Future.delayed(Duration(milliseconds: 350 + (attempt * 250)));
        return _extractCatalogWithRetry(attempt + 1);
      }
      if (!mounted) return;
      setState(() {
        _payload = payload;
        _loading = false;
        _error = payload.items.isEmpty ? 'لم أتمكن من التقاط عناصر الصفحة.' : null;
      });
    } catch (e) {
      if (attempt < 5) {
        await Future.delayed(Duration(milliseconds: 350 + (attempt * 250)));
        return _extractCatalogWithRetry(attempt + 1);
      }
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذر جلب بيانات الواجهة من الموقع.';
      });
    }
  }

  void _openDetails(CatalogEntry item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlexDetailsScreen(entry: item),
      ),
    );
  }
}

class PlexDetailsScreen extends StatefulWidget {
  final CatalogEntry entry;

  const PlexDetailsScreen({super.key, required this.entry});

  @override
  State<PlexDetailsScreen> createState() => _PlexDetailsScreenState();
}

class _PlexDetailsScreenState extends State<PlexDetailsScreen> {
  InAppWebViewController? _bridge;
  MediaDetailsData? _details;
  bool _loading = true;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final details = _details;
    return Scaffold(
      body: Stack(
        children: [
          if (_loading)
            const _PlexLoadingView()
          else if (_error != null)
            _PlexErrorView(message: _error!, onRetry: _reload)
          else if (details != null)
            CustomScrollView(
              slivers: [
                SliverAppBar(
                  pinned: true,
                  expandedHeight: 350,
                  backgroundColor: const Color(0xFF0E1117),
                  leading: IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  flexibleSpace: FlexibleSpaceBar(
                    background: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          details.posterUrl.isNotEmpty ? details.posterUrl : widget.entry.imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(color: const Color(0xFF131820)),
                        ),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0x33000000), Color(0xFF0E1117)],
                            ),
                          ),
                        ),
                        Positioned(
                          left: 18,
                          right: 18,
                          bottom: 18,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(20),
                                child: Image.network(
                                  details.posterUrl.isNotEmpty ? details.posterUrl : widget.entry.imageUrl,
                                  width: 104,
                                  height: 148,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    width: 104,
                                    height: 148,
                                    color: const Color(0xFF171B22),
                                    child: const Icon(Icons.movie_outlined, color: Colors.white54, size: 34),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        if (details.year.isNotEmpty) _detailsChip(details.year),
                                        if (details.quality.isNotEmpty) _detailsChip(details.quality),
                                        if (details.rating.isNotEmpty) _detailsChip(details.rating),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      details.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 24,
                                        fontWeight: FontWeight.w800,
                                        height: 1.08,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 20, 18, 30),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            SizedBox(
                              width: MediaQuery.of(context).size.width > 440
                                  ? (MediaQuery.of(context).size.width - 48) / 2
                                  : MediaQuery.of(context).size.width - 36,
                              child: _actionButton(
                                label: 'مشاهدة الآن',
                                icon: Icons.play_arrow_rounded,
                                filled: true,
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => AsdPicsPlayer(
                                        initialUrl: details.watchUrl,
                                        headerTitle: details.title,
                                        launchHidden: true,
                                        loadingPosterUrl: details.posterUrl.isNotEmpty ? details.posterUrl : widget.entry.imageUrl,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            SizedBox(
                              width: MediaQuery.of(context).size.width > 440
                                  ? (MediaQuery.of(context).size.width - 48) / 2
                                  : MediaQuery.of(context).size.width - 36,
                              child: _actionButton(
                                label: 'تحميل',
                                icon: Icons.download_rounded,
                                filled: false,
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => AsdPicsPlayer(
                                        initialUrl: details.watchUrl,
                                        headerTitle: details.title,
                                        autoDownloadPrompt: true,
                                        launchHidden: true,
                                        downloadOnlyMode: true,
                                        loadingPosterUrl: details.posterUrl.isNotEmpty ? details.posterUrl : widget.entry.imageUrl,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            if (details.duration.isNotEmpty) _factPill(Icons.schedule_rounded, details.duration),
                            if (details.country.isNotEmpty) _factPill(Icons.public_rounded, details.country),
                            if (details.language.isNotEmpty) _factPill(Icons.translate_rounded, details.language),
                            if (details.category.isNotEmpty) _factPill(Icons.local_movies_outlined, details.category),
                          ],
                        ),
                        if (details.description.isNotEmpty) ...[
                          const SizedBox(height: 26),
                          const Text(
                            'قصة العرض',
                            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            details.description,
                            style: const TextStyle(color: Colors.white70, height: 1.6, fontSize: 14),
                          ),
                        ],
                        if (details.genres.isNotEmpty) ...[
                          const SizedBox(height: 26),
                          const Text(
                            'الأنواع',
                            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: details.genres.map((g) => _genreChip(g)).toList(),
                          ),
                        ],
                        if (details.episodes.isNotEmpty) ...[
                          const SizedBox(height: 28),
                          const Text(
                            'الحلقات',
                            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 14),
                          ...details.episodes.take(30).map(
                            (ep) => Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF171B22),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: Colors.white.withOpacity(0.06)),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                title: Text(ep.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                                subtitle: Text(ep.subtitle.isNotEmpty ? ep.subtitle : 'افتح الحلقة بالمشغل الحالي', style: const TextStyle(color: Colors.white54)),
                                trailing: const Icon(Icons.play_circle_fill_rounded, color: Color(0xFF7FBF3F)),
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => AsdPicsPlayer(
                                        initialUrl: _buildWatchUrl(ep.url),
                                        headerTitle: ep.title,
                                        launchHidden: true,
                                        loadingPosterUrl: details.posterUrl.isNotEmpty ? details.posterUrl : widget.entry.imageUrl,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          Positioned(
            width: 1,
            height: 1,
            left: -20,
            top: -20,
            child: IgnorePointer(
              ignoring: true,
              child: Opacity(
                opacity: 0.0,
                child: InAppWebView(
                  initialUrlRequest: URLRequest(
                    url: WebUri(widget.entry.url),
                    headers: const {'User-Agent': kScraperUserAgent},
                  ),
                  initialSettings: InAppWebViewSettings(
                    javaScriptEnabled: true,
                    transparentBackground: true,
                    supportZoom: false,
                    mediaPlaybackRequiresUserGesture: false,
                  ),
                  onWebViewCreated: (controller) {
                    _bridge = controller;
                  },
                  onLoadStop: (controller, url) async {
                    await _extractDetailsWithRetry();
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailsChip(String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.28),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Text(
        value,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _genreChip(String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFF171B22),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(value, style: const TextStyle(color: Colors.white)),
    );
  }

  Widget _factPill(IconData icon, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF171B22),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: const Color(0xFF7FBF3F)),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.62),
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required bool filled,
    required VoidCallback onTap,
  }) {
    return Material(
      color: filled ? const Color(0xFF1F80E0) : const Color(0xFF1A2430),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
      _details = null;
    });
    await _bridge?.loadUrl(
      urlRequest: URLRequest(
        url: WebUri(widget.entry.url),
        headers: const {'User-Agent': kScraperUserAgent},
      ),
    );
  }

  Future<void> _extractDetailsWithRetry([int attempt = 0]) async {
    if (_bridge == null) return;
    try {
      final raw = await _bridge!.evaluateJavascript(source: _detailsExtractorJs);
      final decoded = _decodeJsonValue(raw);
      final details = _parseDetailsPayload(decoded, widget.entry);
      final strongEnough = details.title.isNotEmpty &&
          (details.posterUrl.isNotEmpty || widget.entry.imageUrl.isNotEmpty) &&
          (details.watchUrl.isNotEmpty || details.downloadUrl.isNotEmpty);
      if (!strongEnough && attempt < 5) {
        await Future.delayed(Duration(milliseconds: 350 + (attempt * 250)));
        return _extractDetailsWithRetry(attempt + 1);
      }
      if (!mounted) return;
      setState(() {
        _details = details;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (attempt < 5) {
        await Future.delayed(Duration(milliseconds: 350 + (attempt * 250)));
        return _extractDetailsWithRetry(attempt + 1);
      }
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذر قراءة تفاصيل المادة من الصفحة.';
      });
    }
  }
}

class _PlexLoadingView extends StatelessWidget {
  const _PlexLoadingView();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: List.generate(
        5,
        (index) => Container(
          height: index == 0 ? 230 : 120,
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF171B22),
            borderRadius: BorderRadius.circular(24),
          ),
        ),
      ),
    );
  }
}

class _PlexErrorView extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _PlexErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 46, color: Colors.white54),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7FBF3F),
                foregroundColor: Colors.black,
              ),
              onPressed: () { onRetry(); },
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}

Object? _decodeJsonValue(dynamic raw) {
  if (raw == null) return null;
  if (raw is Map || raw is List) return raw;
  final str = raw.toString().trim();
  if (str.isEmpty || str == 'null') return null;
  try {
    return jsonDecode(str);
  } catch (_) {
    return null;
  }
}

Future<Object?> _decodeJsonValueAsync(dynamic raw) async {
  if (raw == null) return null;
  if (raw is Map || raw is List) return raw;
  final str = raw.toString().trim();
  if (str.isEmpty || str == 'null') return null;
  if (str.length < 16000) return _decodeJsonValue(str);
  try {
    return await Isolate.run<Object?>(() => _decodeJsonValue(str));
  } catch (_) {
    return _decodeJsonValue(str);
  }
}

CatalogPayload _parseCatalogPayload(Object? decoded) {
  final map = decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
  List<CatalogEntry> parseList(String key) {
    final raw = map[key];
    if (raw is! List) return const [];
    final out = <CatalogEntry>[];
    final seen = <String>{};
    for (final item in raw) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(item);
      final url = (m['url'] ?? '').toString().trim();
      final title = (m['title'] ?? '').toString().trim();
      final imageUrl = (m['imageUrl'] ?? '').toString().trim();
      if (url.isEmpty || title.isEmpty || imageUrl.isEmpty) continue;
      if (!seen.add(url)) continue;
      out.add(CatalogEntry(
        title: title,
        url: url,
        imageUrl: imageUrl,
        type: ((m['type'] ?? 'movie').toString().trim().isEmpty ? 'movie' : m['type'].toString().trim()),
        subtitle: (m['subtitle'] ?? '').toString().trim(),
        badge: (m['badge'] ?? '').toString().trim(),
        quality: (m['quality'] ?? '').toString().trim(),
        rating: (m['rating'] ?? '').toString().trim(),
        year: (m['year'] ?? '').toString().trim(),
      ));
    }
    return out;
  }

  final items = parseList('items');
  final movies = parseList('movies');
  final series = parseList('series');
  final featured = parseList('featured');
  return CatalogPayload(
    featured: featured.isNotEmpty ? featured : items.take(6).toList(),
    items: items,
    movies: movies.isNotEmpty ? movies : items.where((e) => e.type == 'movie').toList(),
    series: series.isNotEmpty ? series : items.where((e) => e.type != 'movie').toList(),
  );
}

MediaDetailsData _parseDetailsPayload(Object? decoded, CatalogEntry fallback) {
  final map = decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
  final genresRaw = map['genres'];
  final episodesRaw = map['episodes'];
  return MediaDetailsData(
    title: ((map['title'] ?? '').toString().trim().isNotEmpty ? map['title'].toString().trim() : fallback.title),
    description: (map['description'] ?? '').toString().trim(),
    posterUrl: ((map['posterUrl'] ?? '').toString().trim().isNotEmpty ? map['posterUrl'].toString().trim() : fallback.imageUrl),
    watchUrl: _buildWatchUrl((map['watchUrl'] ?? '').toString().trim().isNotEmpty ? map['watchUrl'].toString().trim() : fallback.url),
    downloadUrl: _buildDownloadUrl((map['downloadUrl'] ?? '').toString().trim().isNotEmpty ? map['downloadUrl'].toString().trim() : fallback.url),
    rating: (map['rating'] ?? fallback.rating).toString().trim(),
    year: (map['year'] ?? fallback.year).toString().trim(),
    duration: (map['duration'] ?? '').toString().trim(),
    quality: (map['quality'] ?? fallback.quality).toString().trim(),
    country: (map['country'] ?? '').toString().trim(),
    language: (map['language'] ?? '').toString().trim(),
    category: (map['category'] ?? fallback.badge).toString().trim(),
    genres: genresRaw is List ? genresRaw.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toSet().toList() : const [],
    episodes: episodesRaw is List
        ? episodesRaw.whereType<Map>().map((e) {
            final m = Map<String, dynamic>.from(e);
            return CatalogEntry(
              title: (m['title'] ?? '').toString().trim(),
              url: (m['url'] ?? '').toString().trim(),
              imageUrl: fallback.imageUrl,
              type: 'series',
              subtitle: (m['subtitle'] ?? '').toString().trim(),
              quality: (m['quality'] ?? '').toString().trim(),
              rating: '',
              year: fallback.year,
              badge: 'حلقة',
            );
          }).where((e) => e.title.isNotEmpty && e.url.isNotEmpty).toList()
        : const [],
  );
}

String _buildWatchUrl(String url) {
  final clean = url.trim();
  if (clean.isEmpty) return clean;
  final lower = clean.toLowerCase();
  if (lower.contains('anime3rb.com')) {
    return clean;
  }
  if (clean.contains('/watch/')) return clean;
  if (clean.endsWith('/')) return '${clean}watch/';
  return '$clean/watch/';
}

String _buildDownloadUrl(String url) {
  final clean = url.trim();
  if (clean.isEmpty) return clean;
  final lower = clean.toLowerCase();
  if (lower.contains('anime3rb.com')) {
    if (lower.contains('/download')) return clean;
    if (lower.contains('/episode/')) return clean;
    if (lower.contains('/titles/')) {
      if (clean.endsWith('/')) return '${clean}download';
      return '$clean/download';
    }
    return clean;
  }
  if (clean.contains('/download')) return clean;
  if (clean.endsWith('/')) return '${clean}download/';
  return '$clean/download/';
}

const String _homeExtractorJs = r'''(function(){
  function clean(t){ return (t || '').replace(/\s+/g, ' ').trim(); }
  function attr(el, name){ return el ? clean(el.getAttribute(name) || '') : ''; }
  function text(el){ return el ? clean(el.innerText || el.textContent || '') : ''; }
  function abs(url){
    try { return new URL(url, location.href).href; } catch(e) { return clean(url || ''); }
  }
  function imgOf(root){
    if (!root || !root.querySelector) return '';
    var img = root.querySelector('img[src], img[data-src], img[data-lazy-src], img[data-original], [style*="background-image"]');
    if (!img) return '';
    var src = attr(img, 'src') || attr(img, 'data-src') || attr(img, 'data-lazy-src') || attr(img, 'data-original');
    if (!src) {
      var bg = clean((img.style && img.style.backgroundImage) || '');
      var m = bg.match(/url\(["']?(.*?)["']?\)/i);
      if (m) src = clean(m[1]);
    }
    if (!src) {
      var srcset = attr(img, 'srcset');
      if (srcset) src = clean(srcset.split(',')[0].trim().split(' ')[0]);
    }
    return abs(src);
  }
  function inferTitle(root, a){
    var sels = ['h1','h2','h3','h4','.title','.Title','.name','[class*="title"]','[class*="name"]','strong'];
    for (var i = 0; i < sels.length; i++) {
      var node = root && root.querySelector ? root.querySelector(sels[i]) : null;
      var t = text(node);
      if (t && t.length >= 2 && t.length <= 180) return t;
    }
    var direct = attr(a, 'title') || attr(a, 'aria-label');
    if (direct) return direct;
    var raw = text(root || a);
    var parts = raw.split(/\n|\r/).map(clean).filter(Boolean);
    for (var j = 0; j < parts.length; j++) {
      var p = parts[j];
      if (p.length < 2 || p.length > 180) continue;
      if (/التالي|السابق|بحث|تسجيل الدخول|حساب جديد|إغلاق|الإشتراك|العضوية|اعرف المزيد|قائمة/.test(p)) continue;
      return p;
    }
    return '';
  }
  function qualityOf(txt){
    var s = clean(txt || '');
    var m = s.match(/(2160|1440|1080|720|540|480|360)\s*p/i);
    if (m) return m[1] + 'p';
    var q = s.match(/HEVC|WEB-DL|BluRay|HDRip|HDTS|HD|FHD/i);
    return q ? q[0] : '';
  }
  function ratingOf(txt){
    var s = clean(txt || '');
    var m = s.match(/(?:التقييم\s*)?([0-9]+(?:\.[0-9]+)?)(?:\s*\/\s*10)?/);
    if (!m) return '';
    var v = parseFloat(m[1]);
    if (isNaN(v) || v > 10) return '';
    return m[1];
  }
  function yearOf(txt){
    var s = clean(txt || '');
    var m = s.match(/(19|20)\d{2}/);
    return m ? m[0] : '';
  }
  function inferType(title, href, rawText){
    var s = (title + ' ' + href + ' ' + rawText).toLowerCase();
    if (/فيلم|movie|anime movie/.test(s)) return 'movie';
    return 'series';
  }
  function cardFromAnchor(a){
    if (!a || !a.href) return null;
    var href = abs(a.href);
    if (!href || href.indexOf('anime3rb.com') === -1) return null;
    if (!(/\/episode\//.test(href) || /\/titles\//.test(href))) return null;
    if (/\/titles\/list\//.test(href) || /\/genre\//.test(href) || /\/c\//.test(href) || /\/search/.test(href) || /\/account/.test(href) || /\/login/.test(href) || /\/register/.test(href)) return null;
    var root = a.closest ? (a.closest('article, li, .swiper-slide, .splide__slide, .card, .item, [class*="card"], [class*="item"]') || a.parentElement || a) : (a.parentElement || a);
    var rawText = text(root || a);
    var imageUrl = imgOf(root || a);
    if (!imageUrl) imageUrl = imgOf(a);
    var title = inferTitle(root || a, a);
    if (!title || title.length < 2) return null;
    return {
      title: title,
      url: href,
      imageUrl: imageUrl,
      type: inferType(title, href, rawText),
      subtitle: rawText && rawText !== title ? clean(rawText.replace(title, '')).slice(0, 180) : '',
      badge: /\/episode\
      quality: qualityOf(rawText),
      rating: ratingOf(rawText),
      year: yearOf(rawText)
    };
  }
  var out = [];
  var seen = {};
  Array.from(document.querySelectorAll('a[href*="/episode/"], a[href*="/titles/"]')).forEach(function(a){
    var card = cardFromAnchor(a);
    if (!card) return;
    if (seen[card.url]) return;
    seen[card.url] = true;
    out.push(card);
  });
  var featured = out.slice(0, 8);
  var movies = out.filter(function(c){ return c.type === 'movie'; });
  var series = out.filter(function(c){ return c.type !== 'movie'; });
  return JSON.stringify({ featured: featured, items: out, movies: movies, series: series });
})();''';

const String _detailsExtractorJs = r'''(function(){
  function clean(t){ return (t || '').replace(/\s+/g, ' ').trim(); }
  function attr(el, name){ return el ? clean(el.getAttribute(name) || '') : ''; }
  function text(el){ return el ? clean(el.innerText || el.textContent || '') : ''; }
  function abs(url){
    try { return new URL(url, location.href).href; } catch(e) { return clean(url || ''); }
  }
  function firstMatch(nodes, fn){
    for (var i = 0; i < nodes.length; i++) {
      var v = fn(nodes[i]);
      if (v) return v;
    }
    return '';
  }
  function bestPoster(){
    var imgs = Array.from(document.querySelectorAll('img[src], img[data-src], img[data-lazy-src]'));
    var scored = imgs.map(function(img){
      var src = abs(attr(img, 'src') || attr(img, 'data-src') || attr(img, 'data-lazy-src') || '');
      var score = 0;
      if (/anime3rb|cdn|image/i.test(src)) score += 4;
      var w = img.naturalWidth || img.width || 0;
      var h = img.naturalHeight || img.height || 0;
      score += Math.min(10, Math.round((w * h) / 50000));
      var alt = clean(attr(img, 'alt'));
      if (alt) score += 1;
      return { src: src, score: score };
    }).filter(function(v){ return !!v.src; }).sort(function(a,b){ return b.score - a.score; });
    return scored.length ? scored[0].src : '';
  }
  var pageText = clean(document.body ? document.body.innerText || '' : '');
  function match(re){ var m = pageText.match(re); return m ? clean(m[1]) : ''; }
  function genres(){
    var arr = [];
    Array.from(document.querySelectorAll('a[href]')).forEach(function(a){
      var href = abs(a.href || '');
      var t = text(a);
      if (!t || t.length > 40) return;
      if (/\/genre\
        arr.push(t);
      }
    });
    return Array.from(new Set(arr)).slice(0, 12);
  }
  function episodeLinks(){
    var out = [];
    var seen = {};
    Array.from(document.querySelectorAll('a[href*="/episode/"]')).forEach(function(a){
      var href = abs(a.href || '');
      var t = text(a) || attr(a, 'title') || attr(a, 'aria-label');
      if (!href || !t) return;
      if (seen[href]) return;
      seen[href] = true;
      out.push({ title: clean(t), url: href, subtitle: '' });
    });
    return out.slice(0, 80);
  }
  function backToTitle(){
    return firstMatch(Array.from(document.querySelectorAll('a[href*="/titles/"]')), function(a){
      var href = abs(a.href || '');
      if (!href) return '';
      var t = text(a);
      if (/العودة لصفحة العمل|صفحة العمل/.test(t) || /\/titles\//.test(href)) return href;
      return '';
    });
  }
  function firstEpisodeUrl(){
    return firstMatch(Array.from(document.querySelectorAll('a[href*="/episode/"]')), function(a){
      return abs(a.href || '');
    });
  }
  function directDownloadUrl(){
    return firstMatch(Array.from(document.querySelectorAll('a[href]')), function(a){
      var href = abs(a.href || '');
      var t = text(a);
      if (!href) return '';
      if (/تحميل مباشر|download/i.test(t) && href.indexOf('anime3rb.com') !== -1) return href;
      return '';
    });
  }
  var isEpisodePage = /\/episode\//.test(location.pathname);
  var isTitlePage = /\/titles\//.test(location.pathname);
  var h1 = text(document.querySelector('h1')) || text(document.querySelector('#app h1')) || clean((document.title || '').replace(/\s*-.*$/, ''));
  var title = h1.replace(/\(\s*(مسلسل|فيلم|اوفا|أوفا|أونا)\s*\)/g, '').trim();
  var descCandidates = [];
  Array.from(document.querySelectorAll('p, .description, [class*="description"], [class*="summary"]')).forEach(function(el){
    var t = text(el);
    if (t && t.length > 80 && descCandidates.indexOf(t) === -1) descCandidates.push(t);
  });
  var description = descCandidates.slice(0, 3).join(' ');
  if (!description) description = attr(document.querySelector('meta[name="description"]'), 'content');

  var watchUrl = '';
  if (isEpisodePage) {
    watchUrl = location.href;
  } else {
    watchUrl = firstEpisodeUrl() || backToTitle() || location.href;
  }
  var downloadUrl = directDownloadUrl();
  if (!downloadUrl && isTitlePage) {
    downloadUrl = /\/download$/.test(location.pathname) ? location.href : location.href.replace(/\/$/, '') + '/download';
  }
  if (!downloadUrl && isEpisodePage) downloadUrl = location.href;

  var rating = match(/(?:^|\n)التقييم\s*\n\s*([0-9]+(?:\.[0-9]+)?)/);
  if (!rating) {
    var m = pageText.match(/(?:^|\s)([0-9]+(?:\.[0-9]+)?)(?:\s|$)/);
    if (m) {
      var v = parseFloat(m[1]);
      if (!isNaN(v) && v <= 10) rating = m[1];
    }
  }
  var year = match(/(?:إصدار|سنة العرض)\s*:?\s*[^\n]*?((?:19|20)\d{2})/);
  if (!year) year = match(/((?:19|20)\d{2})/);

  return JSON.stringify({
    title: title,
    description: description,
    posterUrl: bestPoster(),
    watchUrl: watchUrl,
    downloadUrl: downloadUrl,
    rating: rating,
    year: year,
    duration: match(/مدة العرض\s*:?\s*([^\n]+)/),
    quality: match(/جودة(?:\s+العرض)?\s*:?\s*([^\n]+)/),
    country: match(/بلد(?:\s+العرض)?\s*:?\s*([^\n]+)/) || 'اليابان',
    language: match(/لغة(?:\s+العرض)?\s*:?\s*([^\n]+)/) || 'ياباني',
    category: match(/\(([^\)]+)\)/) || (isEpisodePage ? 'حلقة' : 'أنمي'),
    genres: genres(),
    episodes: episodeLinks()
  });
})();''';
