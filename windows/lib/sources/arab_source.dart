import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import '../pwa/io_compat.dart';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../pwa/path_provider_compat.dart';
import '../pwa/video_thumbnail_compat.dart';

import '../background_download_bridge.dart';
import '../secure_strings.dart';
import '../native_security_guard.dart';
import '../universal_media_player.dart';
import '../pwa/file_image_compat.dart';

final String kCatalogHomeUrl = AppSecureText.s('HDk3V7IuSrjLKtGAQYi2TCsNYb6_kF7zK5TDlyLF');
const String kScraperUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

@pragma('vm:entry-point')
void arabSourceMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(NativeSecurityGuard.ensureClean());

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  await SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: SystemUiOverlay.values,
  );
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.black,
    systemNavigationBarDividerColor: Colors.black,
    systemNavigationBarIconBrightness: Brightness.light,
    statusBarIconBrightness: Brightness.light,
  ));

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
    this.initialUrl = 'https://asd.pics/main6/',
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
  bool _revealHiddenLaunchUi = false;
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
  bool _hiddenQualityHarvesting = false;
  double _pendingNativeStartTime = 0;
  String? _pendingDownloadQualityLabel;
  String? _hiddenHarvestCurrentQuality;
  final Set<String> _harvestedQualityLabels = <String>{};

  String? _lastTrusted;
  String? _currentHost;
  String? _currentPageUrl;
  String? _currentPageTitle;
  String? _currentMediaTitle;
  String? _lastStableWatchUrl;

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
  final Map<String, String> _debugLastDownloadUrlByQuality = <String, String>{};
  final Map<String, int> _debugLastDownloadBytesByQuality = <String, int>{};

  bool _showDownloads = false;
  bool _showMediaGrabber = false;
  bool _fullscreenBusy = false;
  String? _lastDetectedMediaUrl;
  String? _lastDetectedMediaType;
  bool _autoDownloadPromptShown = false;
  double _bestScreenRefreshRate = 60.0;
  int _frameBoostTicket = 0;

  static final MethodChannel _pip = MethodChannel(AppSecureText.s('C5sitUl1gPZlhlkI'));

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
    "asd.pics", "hglink", "vibuxer", "audinifer", "huntrexus", "hanerix",
    "dood", "doods", "dooood", "ds2play", "d0o0d", "doodstream", "dood.li",
    "uqload", "uqloads", "minochinos", "minomax", "pixibay", "streamtape",
    "stape", "voe.sx", "voeunblok", "voe", "jwplatform", "jwpcdn",
    "akamaized", "cloudfront", "cdnjs.cloudflare", "fonts.googleapis",
    "fonts.gstatic", "kit-pro.fontawesome", "kit-free.fontawesome",
    "static.cloudflareinsights", "vidtube", "1cloudfile", "masukestin",
    "cdn.vidtube", "s3.amazonaws", "googleapis", "gstatic", "bunnycdn",
    "b-cdn", "storage.googleapis", "cdn-tube", "stellarcrestcreative",
    "server-hls2-stream", "server-hls", "cdn-stream", "arabseed",
    "m.arabseed.show", "arabseed.show",
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
    "insertillegimateillegimatepack.com", "skinnycrawlinglax.com",
    "highperformancecpmgate.com", "highperformancedformats.com",
    "profitableratecpm.com", "onclickalgo.com", "onclickperformance.com",
  ];

  final _redirectOk = const [
    "asd.pics", "hglink", "vibuxer", "audinifer", "huntrexus", "hanerix",
    "dood", "doods", "ds2play", "d0o0d", "doodstream", "uqload", "uqloads",
    "minochinos", "minomax", "streamtape", "stape", "voe.sx", "voeunblok",
    "voe", "jwplatform", "jwpcdn", "vidtube", "1cloudfile", "masukestin",
    "cdn.vidtube", "s3.amazonaws", "googleapis", "bunnycdn", "b-cdn",
    "cdn-tube", "stellarcrestcreative", "server-hls2-stream", "server-hls",
    "arabseed", "m.arabseed.show", "arabseed.show",
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
    if (!(host.contains('asd.pics') || host.contains('arabseed'))) return null;
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
    value = value.replaceAll(RegExp(r'\s*[|｜\-–—]\s*(arabseed|asd\s*pics|عرب\s*سيد).*$', caseSensitive: false), ' ');
    value = value.replaceAll(RegExp(r'\b(ArabSeed|ASD\s*Pics)\b', caseSensitive: false), ' ');
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
        final dir = Directory('${ext.path}/Videos/Arab');
        if (!await dir.exists()) await dir.create(recursive: true);
        return dir;
      }
    }
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/Videos/Arab');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  String _buildReferer(String downloadUrl) {
    try {
      final host = Uri.parse(downloadUrl).host.toLowerCase();
      if (host.contains('cdn-tube') || host.contains('server-hls') || host.contains('cdn-stream')) {
        return _currentHost != null ? 'https://$_currentHost/' : 'https://asd.pics/';
      }
      if (host.contains('1cloudfile')) return 'https://1cloudfile.com/';
      if (host.contains('vidtube')) return 'https://vidtube.one/';
    } catch (_) {}
    if (_currentHost != null) return 'https://$_currentHost/';
    return 'https://asd.pics/';
  }

  Map<String, dynamic> _downloadHeaders(String url) {
    return {
      'User-Agent': _ua,
      'Accept': '*/*',
      'Connection': 'keep-alive',
      'Referer': _buildReferer(url),
      'Origin': 'https://${_currentHost ?? 'asd.pics'}',
    };
  }

  bool _looksLikePlayableMediaUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    final lower = url.toLowerCase();
    if (lower.startsWith('blob:')) return false;
    return lower.contains('.m3u8') || lower.contains('.mp4') ||
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
    return u.endsWith('.mp4') ||
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
    final options = _sortedQualityOptions;
    if (options.isEmpty) return null;
    for (final wanted in const ['1080p', '720p', '480p']) {
      for (final opt in options) {
        if (_normalizeQualityLabel(opt.label) == wanted) return opt;
      }
    }
    return options.first;
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

  String _capturedQualityForUrl(String? url) {
    final target = (url ?? '').trim();
    if (target.isEmpty) return '';
    for (final item in _capturedMedia) {
      if (item.url == target) {
        return _normalizeQualityLabel(item.qualityLabel ?? '');
      }
    }
    return '';
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
        : (_lastTrusted ?? 'https://asd.pics/');
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
      'insertillegimateillegimatepack.com', 'skinnycrawlinglax.com',
      'protrafficinspector.com', 'sourshaped.com', 'preferencenail.com',
      'highperformancecpmgate.com', 'highperformancedformats.com',
      'profitableratecpm.com', 'onclickalgo.com', 'onclickperformance.com',
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
        'Referer': pageUrl ?? (_lastTrusted ?? 'https://asd.pics/'),
      },
    );

    final isHls = url.toLowerCase().contains('.m3u8');
    final current = _capturedVideoUrl?.toLowerCase() ?? '';
    final currentIsHls = current.contains('.m3u8');
    final activePageQuality = _normalizeQualityLabel(_currentPageQualityLabel ?? '');
    final currentCapturedQuality = _capturedQualityForUrl(_capturedVideoUrl);
    final currentRank = _qualityRankLabel(
      currentCapturedQuality.isNotEmpty ? currentCapturedQuality : activePageQuality,
    );
    final newRank = _qualityRankLabel(normalizedQuality);
    final shouldReplaceSelectedUrl =
        _capturedVideoUrl == null ||
        (isHls && !currentIsHls) ||
        (_capturedVideoUrl?.startsWith('blob:') ?? false) ||
        newRank > currentRank ||
        (normalizedQuality.isNotEmpty &&
            normalizedQuality == activePageQuality &&
            (currentCapturedQuality != normalizedQuality || url != _capturedVideoUrl));
    if (shouldReplaceSelectedUrl) {
      _capturedVideoUrl = url;
      if (normalizedQuality.isNotEmpty) {
        _currentPageQualityLabel = normalizedQuality;
      }
    }

    _capturedVideoMimeType = _inferMimeType(url, mimeType);
    if (pageUrl != null && pageUrl.isNotEmpty) _capturedVideoPageUrl = pageUrl;
    if (currentTime != null && currentTime >= 0) _capturedVideoTime = currentTime;
    if (mounted && !_videoDetected) setState(() => _videoDetected = true);
  }

  Future<Map<String, String>> _buildPipHeaders(String mediaUrl, {String? pageUrl}) async {
    final referer = (pageUrl != null && pageUrl.isNotEmpty) ? pageUrl : (_lastTrusted ?? 'https://asd.pics/');
    String origin = 'https://asd.pics';
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

      // ✅ Block ALL window.open inside iframes too
      window.open = function(){ return null; };

      window.location.assign = function(url) {
        if (_isAdDomain(url ? url.toString() : '')) return;
        _origAssign(url);
      };
      window.location.replace = function(url) {
        if (_isAdDomain(url ? url.toString() : '')) return;
        _origReplace(url);
      };

      // ✅ Block location.href setter inside iframe
      try {
        var _hrefDesc = Object.getOwnPropertyDescriptor(Location.prototype, 'href');
        if (_hrefDesc && _hrefDesc.set) {
          Object.defineProperty(window.location, 'href', {
            configurable: true,
            get: function() { return window.location.toString(); },
            set: function(val) {
              if (_isAdDomain(val ? val.toString() : '')) return;
              _hrefDesc.set.call(window.location, val);
            }
          });
        }
      } catch(e) {}

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
  static const String _webViewFrameBoost = r"""
(function(){
  'use strict';
  if (window.__asdFrameBoostInstalled) return;
  window.__asdFrameBoostInstalled = true;

  window.__asdPreferredRefreshRate = window.__asdPreferredRefreshRate || 60;
  window.__asdApplyRefreshRate = function(rate){
    var parsed = parseFloat(rate || 60);
    if (!isFinite(parsed) || parsed < 30) parsed = 60;
    window.__asdPreferredRefreshRate = parsed;
    try { document.documentElement.style.setProperty('--asd-refresh-rate', String(parsed)); } catch(e) {}
    return parsed;
  };

  function installStyle(){
    if (document.getElementById('asd-frame-boost-style')) return;
    var s = document.createElement('style');
    s.id = 'asd-frame-boost-style';
    s.textContent = `
      html, body {
        scroll-behavior: auto !important;
        -webkit-font-smoothing: antialiased !important;
      }
      video, iframe,
      .jwplayer, .jw-video, .jw-media,
      .video-js, .vjs-tech,
      .plyr, .dplayer {
        transform: translateZ(0) !important;
        -webkit-transform: translateZ(0) !important;
        backface-visibility: hidden !important;
        -webkit-backface-visibility: hidden !important;
      }
      video, .jw-video, .vjs-tech {
        will-change: transform !important;
      }
    `;
    (document.head || document.documentElement).appendChild(s);
  }

  function boostVideo(v){
    if (!v || v.__asdFrameBoosted) return;
    v.__asdFrameBoosted = true;
    try {
      v.style.transform = 'translateZ(0)';
      v.style.webkitTransform = 'translateZ(0)';
      v.style.backfaceVisibility = 'hidden';
      v.style.willChange = 'transform';
      v.playsInline = true;
      v.setAttribute('playsinline', '');
      v.setAttribute('webkit-playsinline', '');
    } catch(e) {}
  }

  function scan(root){
    installStyle();
    try {
      var base = root || document;
      if (base.tagName && String(base.tagName).toLowerCase() === 'video') boostVideo(base);
      base.querySelectorAll && base.querySelectorAll('video').forEach(boostVideo);
    } catch(e) {}
  }

  var scanTimer = 0;
  function scheduleScan(root){
    if (scanTimer) return;
    scanTimer = setTimeout(function(){
      scanTimer = 0;
      scan(root || document);
    }, 220);
  }

  scan(document);
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function(){ scan(document); }, {once:true});
  }
  try {
    new MutationObserver(function(muts){
      for (var i = 0; i < muts.length; i++) {
        if (muts[i].addedNodes && muts[i].addedNodes.length) { scheduleScan(document); break; }
      }
    }).observe(document.documentElement, {childList:true, subtree:true});
  } catch(e) {}
})();
""";

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

  static const String _ads = r"""
(function(){
  'use strict';

  window.__asdAdsInstalled = true;
  window.__asdStableUrl = window.__asdStableUrl || location.href;

  var adDomains = [
    'popads','popcash','adcash','doubleclick','googlesyndication',
    'adnxs','exoclick','juicyads','adsterra','propellerads',
    'trafficjunky','hilltopads','richpush','zeropark','revcontent',
    'taboola','outbrain','mgid','rubiconproject','openx','criteo',
    'b7510','oyo4d','bvtpk','omoonsih','jnbhi','sourshaped',
    'tfnvuckb','waust','whacmoltibsay','rtmark','fundingchoices',
    'popunder','clickunder','trafficshop','plugrush','imasdk',
    'pyppo','pop.pro','trffk','g2afse','llvpn','onclickads',
    'onclickmega','popmyads','ad-maven','adspyglass',
    'push','pushads','push-notifications','redirect','prplads',
    'hilltop','adclick','adserver','adform','adskeeper','profitablerate',
    'highperformanceformat','xmlppcbuzz','trk','traff'
  ];

  function lower(v){ return (v || '').toString().toLowerCase(); }

  function hostOf(url) {
    try { return new URL((url || '').toString(), location.href).host.toLowerCase(); }
    catch(e) { return ''; }
  }

  function isAdUrl(url) {
    if (!url) return false;
    var s = lower(url);
    return adDomains.some(function(d){ return s.indexOf(d) !== -1; }) ||
      /(^|[.\/_-])(ads?|adserver|popunder|popads|pushads?|clickunder|trk|track|traffic|redirect)([.\/_-]|$)/i.test(s);
  }

  function stableHost() { return hostOf(window.__asdStableUrl || location.href); }

  function allowedExternalHost(host) {
    return /(^|\.)((asd\.pics)|(arabseed\.show)|(m\.arabseed\.show)|(reviewrate\.net)|(fredl\.ru)|(filespayouts\.com)|(up-4ever\.net))$/i.test(host);
  }

  function isBadNavigation(url) {
    if (!url) return false;
    var s = (url || '').toString();
    if (s.indexOf('javascript:') === 0 || s.indexOf('intent:') === 0 || s.indexOf('market:') === 0) return true;
    if (isAdUrl(s)) return true;
    var h = hostOf(s);
    var sh = stableHost();
    if (h && sh && h !== sh && !allowedExternalHost(h)) return true;
    return false;
  }

  function rememberStable() {
    try {
      if (!isBadNavigation(location.href)) {
        window.__asdStableUrl = location.href;
      }
    } catch(e) {}
  }

  function restoreStable() {
    try {
      var target = window.__asdStableUrl;
      if (!target) return;
      if (location.href !== target && hostOf(location.href) !== stableHost()) {
        history.replaceState(null, document.title, target);
      }
    } catch(e) {}
  }

  function isPlayerNode(el) {
    var d = 0;
    while (el && d < 10) {
      try {
        var blob = lower((el.className || '') + ' ' + (el.id || '') + ' ' + (el.tagName || ''));
        if (blob.indexOf('jw') !== -1 || blob.indexOf('vjs') !== -1 ||
            blob.indexOf('plyr') !== -1 || blob.indexOf('player') !== -1 ||
            blob.indexOf('video') !== -1 || blob.indexOf('media') !== -1 ||
            (el.tagName && lower(el.tagName) === 'video')) {
          return true;
        }
      } catch(e) {}
      el = el.parentElement;
      d++;
    }
    return false;
  }

  function visible(el) {
    try {
      var r = el.getBoundingClientRect();
      var cs = getComputedStyle(el);
      return r.width > 8 && r.height > 8 && cs.display !== 'none' && cs.visibility !== 'hidden' && parseFloat(cs.opacity || '1') > 0.05;
    } catch(e) { return false; }
  }

  function isBigPopupLayer(el) {
    if (!el || isPlayerNode(el) || !visible(el)) return false;
    try {
      var cs = getComputedStyle(el);
      var r = el.getBoundingClientRect();
      var area = r.width * r.height;
      var screen = Math.max(1, innerWidth * innerHeight);
      var z = parseInt(cs.zIndex || '0', 10) || 0;
      var blob = lower((el.className || '') + ' ' + (el.id || '') + ' ' + (el.getAttribute('role') || ''));
      var fixed = cs.position === 'fixed' || cs.position === 'absolute' || cs.position === 'sticky';
      var looksPopup = /popup|pop|modal|overlay|advert|ads?|banner|interstitial|promo|sponsor|lightbox|backdrop/.test(blob);
      var hasBadLink = false;
      try {
        el.querySelectorAll('a[href],iframe[src]').forEach(function(a){
          var u = (a.href || a.src || '').toString();
          if (isBadNavigation(u)) hasBadLink = true;
        });
      } catch(e) {}
      return fixed && (z > 50 || looksPopup) && (area > screen * 0.18 || looksPopup || hasBadLink);
    } catch(e) {
      return false;
    }
  }

  function fireClick(el) {
    if (!el || !visible(el) || isPlayerNode(el)) return false;
    try {
      rememberStable();
      ['pointerdown','mousedown','mouseup','click'].forEach(function(type){
        el.dispatchEvent(new MouseEvent(type, {bubbles:true, cancelable:true, view:window}));
      });
      setTimeout(restoreStable, 20);
      setTimeout(restoreStable, 120);
      return true;
    } catch(e) { return false; }
  }

  function closeText(el) {
    var txt = lower((el.textContent || el.innerText || '').trim());
    var aria = lower(el.getAttribute && (el.getAttribute('aria-label') || el.getAttribute('title') || ''));
    var blob = txt + ' ' + aria + ' ' + lower((el.className || '') + ' ' + (el.id || ''));
    return blob === 'x' || blob === '×' || blob.indexOf('close') !== -1 ||
      blob.indexOf('dismiss') !== -1 || blob.indexOf('skip') !== -1 ||
      blob.indexOf('اغلاق') !== -1 || blob.indexOf('إغلاق') !== -1 ||
      blob.indexOf('تخطي') !== -1 || blob.indexOf('لا شكرا') !== -1 ||
      blob.indexOf('no thanks') !== -1;
  }

  function autoClosePopups(root) {
    root = root || document;
    rememberStable();

    try {
      var closeCandidates = root.querySelectorAll(
        '[aria-label*="close" i],[title*="close" i],[class*="close" i],[id*="close" i],' +
        '[data-dismiss],[data-bs-dismiss],.mfp-close,.modal-close,.btn-close,' +
        'button,a,[role="button"]'
      );
      for (var i = 0; i < closeCandidates.length; i++) {
        var el = closeCandidates[i];
        if (isPlayerNode(el)) continue;
        if (closeText(el)) {
          fireClick(el);
        }
      }
    } catch(e) {}

    try {
      var nodes = root.querySelectorAll('div,section,aside,dialog,iframe');
      for (var j = 0; j < nodes.length; j++) {
        var n = nodes[j];
        if (isBigPopupLayer(n)) {
          n.style.setProperty('display','none','important');
          n.style.setProperty('visibility','hidden','important');
          n.style.setProperty('pointer-events','none','important');
          n.style.setProperty('opacity','0','important');
          try { if (n.parentElement) n.parentElement.removeChild(n); } catch(ee) {}
        }
      }
    } catch(e) {}

    restoreStable();
  }

  window.open = function(){ restoreStable(); return null; };

  try {
    var _reload = window.location.reload.bind(window.location);
    window.location.reload = function(){ restoreStable(); return; };
  } catch(e) {}

  try {
    var _origAssign = window.location.assign.bind(window.location);
    window.location.assign = function(url) {
      if (isBadNavigation(url)) { restoreStable(); return; }
      rememberStable();
      _origAssign(url);
    };
    var _origReplace = window.location.replace.bind(window.location);
    window.location.replace = function(url) {
      if (isBadNavigation(url)) { restoreStable(); return; }
      rememberStable();
      _origReplace(url);
    };
  } catch(e) {}

  try {
    var _hrefDesc = Object.getOwnPropertyDescriptor(Location.prototype, 'href');
    if (_hrefDesc && _hrefDesc.set) {
      Object.defineProperty(window.location, 'href', {
        configurable: true,
        get: function() { return window.location.toString(); },
        set: function(val) {
          if (isBadNavigation(val)) { restoreStable(); return; }
          rememberStable();
          _hrefDesc.set.call(window.location, val);
        }
      });
    }
  } catch(e) {}

  try {
    var _push = history.pushState.bind(history);
    history.pushState = function(state, title, url) {
      if (url && isBadNavigation(url)) { restoreStable(); return; }
      var r = _push.apply(history, arguments);
      rememberStable();
      return r;
    };
    var _replace = history.replaceState.bind(history);
    history.replaceState = function(state, title, url) {
      if (url && isBadNavigation(url)) { restoreStable(); return; }
      var r = _replace.apply(history, arguments);
      rememberStable();
      return r;
    };
  } catch(e) {}

  function stripInlinePopups(root) {
    try {
      var nodes = (root || document).querySelectorAll('[onclick],[onmousedown],[onpointerdown],a[href]');
      nodes.forEach(function(el) {
        if (isPlayerNode(el)) return;
        var oc = lower(
          (el.getAttribute('onclick') || '') + ' ' +
          (el.getAttribute('onmousedown') || '') + ' ' +
          (el.getAttribute('onpointerdown') || '')
        );
        var href = (el.href || el.getAttribute('href') || el.getAttribute('data-href') || '').toString();
        if (oc.indexOf('window.open') !== -1 || oc.indexOf('location') !== -1 || isBadNavigation(href) || isAdUrl(oc)) {
          el.removeAttribute('onclick');
          el.removeAttribute('onmousedown');
          el.removeAttribute('onpointerdown');
          if (isBadNavigation(href)) {
            el.removeAttribute('href');
            el.style.setProperty('pointer-events','none','important');
          }
        }
      });
    } catch(e) {}
  }

  function captureClick(e) {
    var el = e.target;
    var depth = 0;
    while (el && el !== document.documentElement && depth < 12) {
      try {
        var href = (el.href || (el.getAttribute && (el.getAttribute('href') || el.getAttribute('data-href') || el.getAttribute('data-url'))) || '').toString();
        if (!isPlayerNode(el) && (isBadNavigation(href) || isBigPopupLayer(el))) {
          e.preventDefault();
          e.stopImmediatePropagation();
          autoClosePopups(document);
          restoreStable();
          return false;
        }
      } catch(ee) {}
      el = el.parentElement;
      depth++;
    }
    setTimeout(restoreStable, 30);
    setTimeout(function(){ autoClosePopups(document); }, 80);
  }

  ['pointerdown','mousedown','touchstart','click'].forEach(function(evt) {
    document.addEventListener(evt, captureClick, true);
  });

  [80, 180, 400, 800, 1400, 2500, 4000].forEach(function(ms) {
    setTimeout(function() {
      stripInlinePopups(document);
      autoClosePopups(document);
    }, ms);
  });

  try {
    new MutationObserver(function(muts) {
      var changed = false;
      muts.forEach(function(m) {
        m.addedNodes.forEach(function(node) {
          if (node.nodeType === 1) {
            changed = true;
            stripInlinePopups(node);
          }
        });
      });
      if (changed) {
        setTimeout(function(){ autoClosePopups(document); }, 30);
        setTimeout(function(){ autoClosePopups(document); }, 180);
      }
    }).observe(document.documentElement, { childList: true, subtree: true });
  } catch(e) {}

  window.__asdAutoClosePopups = function(){
    stripInlinePopups(document);
    autoClosePopups(document);
    restoreStable();
    return true;
  };

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
    doc.addEventListener(evt, function(){ win.__asdLastUserGesture = Date.now(); }, true);
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

  // ─────────────────────────────────────────────────────────────────────────

  String _normalizeQualityLabel(String input) {
    final m = RegExp(r'(2160|1440|1080|720|540|480|360|240)\s*p?', caseSensitive: false)
        .firstMatch(input);
    if (m != null) return '${m.group(1)}p';
    return input.trim();
  }

  void _updatePageQualityOptions(List<PageQualityOption> options, [String? currentLabel]) {
    final seen = <String>{};
    final normalized = <PageQualityOption>[];
    for (final opt in options) {
      final label = _normalizeQualityLabel(opt.label);
      final key = opt.key.isNotEmpty ? opt.key : '${label}_${normalized.length}';
      final dedupe = '${label.toLowerCase()}|${(opt.url ?? '').toLowerCase()}';
      if (seen.contains(dedupe)) continue;
      seen.add(dedupe);
      normalized.add(PageQualityOption(
        label: label,
        key: key,
        url: opt.url,
        selected: opt.selected,
      ));
    }
    _pageQualityOptions = normalized;
    _currentPageQualityLabel = currentLabel != null && currentLabel.trim().isNotEmpty
        ? _normalizeQualityLabel(currentLabel)
        : normalized.firstWhere(
            (e) => e.selected,
            orElse: () => normalized.isNotEmpty ? normalized.first : const PageQualityOption(label: '', key: ''),
          ).label;
  }

  Future<void> _switchPageQuality(PageQualityOption option) async {
    if (_wc == null) return;
    final startTime = (() async {
      try {
        final pos = await _pip.invokeMethod<num>('getCurrentPosition');
        return pos?.toDouble() ?? _capturedVideoTime;
      } catch (_) {
        return _capturedVideoTime;
      }
    })();

    final seekSeconds = await startTime;
    if (mounted) {
      setState(() {
        _currentPageQualityLabel = option.label;
      });
    } else {
      _currentPageQualityLabel = option.label;
    }

    await _pauseOriginalSitePlayer();

    if (_looksLikePlayableMediaUrl(option.url)) {
      _qualitySwitchPending = false;
      _manualPlayAfterQualitySwitchPending = false;
      await _openNativePlayer(
        force: true,
        replace: true,
        startTimeOverride: seekSeconds,
        forcedUrl: option.url,
        forcedPageUrl: _capturedVideoPageUrl,
        forcedMimeType: _inferMimeType(option.url),
      );
      return;
    }

    _qualitySwitchPending = true;
    _pendingNativeStartTime = seekSeconds;

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
      _qualitySwitchPending = false;
      _manualPlayAfterQualitySwitchPending = false;
      _showSnack('⚠️ تعذّر تغيير الجودة من الصفحة');
      return;
    }

    Future.delayed(const Duration(seconds: 4), () {
      if (_qualitySwitchPending) {
        _qualitySwitchPending = false;
        _manualPlayAfterQualitySwitchPending = false;
        _showSnack('⚠️ لم ألتقط رابط الجودة الجديدة');
      }
    });
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

  double _readBestScreenRefreshRate() {
    double best = 60.0;
    try {
      for (final view in ui.PlatformDispatcher.instance.views) {
        final rate = view.display.refreshRate;
        if (rate.isFinite && rate > best) best = rate;
      }
    } catch (_) {}
    return best.clamp(60.0, 240.0).toDouble();
  }

  Future<void> _applyBestScreenRefreshRate() async {
    final rate = _readBestScreenRefreshRate();
    _bestScreenRefreshRate = rate;
    final ticket = ++_frameBoostTicket;

    try {
      await _pip.invokeMethod('setPreferredRefreshRate', <String, dynamic>{
        'refreshRate': rate,
        'fps': rate,
      });
    } catch (_) {
    }

    Future<void> inject() async {
      if (ticket != _frameBoostTicket) return;
      try {
        await _wc?.evaluateJavascript(source: '''
          (function(){
            try {
              if (window.__asdApplyRefreshRate) {
                window.__asdApplyRefreshRate(${rate.toStringAsFixed(2)});
              }
            } catch(e) {}
          })();
        ''');
      } catch (_) {}
    }

    await inject();
    Future.delayed(const Duration(milliseconds: 700), inject);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(_applyBestScreenRefreshRate);

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
          _suppressAutoOpenUntil = 0;
          await _pauseOriginalSitePlayer();
          _scheduleOriginalPlayerHardPause();
        } else {
          _suppressAutoOpenUntil = DateTime.now().millisecondsSinceEpoch + 1200;
          await _releaseOriginalSitePlayerBlock();
          await _returnToWatchPage();
          await _restoreUI();
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
      Future.microtask(_applyBestScreenRefreshRate);

      if (!_nativePlayerActive) {
        Future.microtask(() async {
          await _returnToWatchPage();
        });
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

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    Future.delayed(const Duration(milliseconds: 120), _applyBestScreenRefreshRate);
  }

  String? _normalizeWatchReturnUrl(String? rawUrl) {
    final value = (rawUrl ?? '').trim();
    if (value.isEmpty) return null;

    final uri = Uri.tryParse(value);
    if (uri == null) return value;

    final cleaned = uri.replace(fragment: '');
    return cleaned.toString();
  }

  bool _isWatchLikeUrl(String? rawUrl) {
    final url = (rawUrl ?? '').toLowerCase();
    if (url.isEmpty) return false;
    return url.contains('/watch/') ||
        url.contains('play=true') ||
        url.contains('%d9%85%d8%b4%d8%a7%d9%87');
  }

  void _rememberStableWatchUrl([String? rawUrl]) {
    final normalized = _normalizeWatchReturnUrl(rawUrl);
    if (normalized == null || normalized.isEmpty) return;
    if (_isWatchLikeUrl(normalized)) {
      _lastStableWatchUrl = normalized;
    }
  }

  Future<void> _returnToWatchPage() async {
    if (_wc == null) return;

    final target = _lastStableWatchUrl ??
        _normalizeWatchReturnUrl(_capturedVideoPageUrl) ??
        _normalizeWatchReturnUrl(_currentPageUrl) ??
        _normalizeWatchReturnUrl(_lastTrusted);

    if (target == null || target.isEmpty) return;

    final current = (await _wc!.getUrl())?.toString();
    final currentNormalized = _normalizeWatchReturnUrl(current);

    if (currentNormalized == target) {
      try {
        await _wc!.evaluateJavascript(source: """
          (function(){
            try {
              if (window.location.hash) {
                history.replaceState(null, '', window.location.pathname + window.location.search);
              }
            } catch(e) {}
          })();
        """);
      } catch (_) {}
      return;
    }

    try {
      await _wc!.loadUrl(
        urlRequest: URLRequest(
          url: WebUri(target),
          headers: const {'User-Agent': _ua},
        ),
      );
    } catch (_) {}
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

  void _downloadDebug(String message) {
    debugPrint('🎯 [ASD-DL-DEBUG] $message');
  }

  String _bytesLabel(int? value) {
    if (value == null || value <= 0) return 'unknown';
    const kb = 1024.0;
    const mb = kb * 1024.0;
    const gb = mb * 1024.0;
    if (value >= gb) return '${(value / gb).toStringAsFixed(2)} GB ($value bytes)';
    if (value >= mb) return '${(value / mb).toStringAsFixed(2)} MB ($value bytes)';
    if (value >= kb) return '${(value / kb).toStringAsFixed(2)} KB ($value bytes)';
    return '$value bytes';
  }

  Future<int?> _probeDownloadContentLength(
    String url, {
    String? qualityLabel,
  }) async {
    try {
      final response = await _dio.head<dynamic>(
        url,
        options: Options(
          headers: _downloadHeaders(url),
          followRedirects: true,
          receiveTimeout: const Duration(seconds: 20),
          validateStatus: (status) => status != null && status >= 200 && status < 500,
        ),
      );
      final rawLength = response.headers.value(Headers.contentLengthHeader) ??
          response.headers.value('content-length');
      final parsed = int.tryParse((rawLength ?? '').trim());
      _downloadDebug(
        'HEAD quality=${qualityLabel?.isNotEmpty == true ? qualityLabel : 'unknown'} '
        'status=${response.statusCode} contentLength=${_bytesLabel(parsed)} url=$url',
      );
      return parsed;
    } catch (e) {
      _downloadDebug(
        'HEAD FAILED quality=${qualityLabel?.isNotEmpty == true ? qualityLabel : 'unknown'} '
        'error=$e url=$url',
      );
      return null;
    }
  }

  void _rememberAndCompareDownloadDebug({
    required String qualityLabel,
    required String url,
    int? savedBytes,
  }) {
    final quality = _normalizeQualityLabel(qualityLabel).isNotEmpty
        ? _normalizeQualityLabel(qualityLabel)
        : 'unknown';

    for (final entry in _debugLastDownloadUrlByQuality.entries) {
      if (entry.key != quality && entry.value == url) {
        _downloadDebug(
          '⚠️ SAME_URL quality=$quality uses same url as quality=${entry.key} url=$url',
        );
      }
    }

    if (savedBytes != null && savedBytes > 0) {
      for (final entry in _debugLastDownloadBytesByQuality.entries) {
        if (entry.key != quality && entry.value == savedBytes) {
          _downloadDebug(
            '⚠️ SAME_SIZE quality=$quality size=${_bytesLabel(savedBytes)} '
            'matches quality=${entry.key}',
          );
        }
      }
      _debugLastDownloadBytesByQuality[quality] = savedBytes;
    }

    _debugLastDownloadUrlByQuality[quality] = url;
  }


  Future<void> _startDownload(
    String url,
    String fileName, {
    String? qualityLabel,
    String? debugReason,
  }) async {
    final normalizedQuality = _normalizeQualityLabel(
      qualityLabel ?? _capturedQualityForUrl(url),
    );
    final debugQuality = normalizedQuality.isNotEmpty ? normalizedQuality : 'unknown';

    if (_discoveredDownloadUrls.contains(url)) {
      _downloadDebug(
        'SKIP_DUPLICATE quality=$debugQuality reason=${debugReason ?? 'none'} url=$url',
      );
      return;
    }
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

    _downloadDebug('BACKGROUND_START quality=$debugQuality reason=${debugReason ?? 'none'}');
    _downloadDebug('URL quality=$debugQuality $url');
    _downloadDebug('FILE quality=$debugQuality path=$fullPath');

    if (mounted) setState(() { _downloads.insert(0, item); });
    _openDownloadsPanel();

    final ok = await _enqueueBackgroundDirectDownload(
      item,
      headers: _downloadHeaders(url),
      pageUrl: _capturedVideoPageUrl ?? _currentPageUrl ?? _lastTrusted,
      qualityLabel: debugQuality,
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



  
  static const String _backgroundDownloadSource = 'Arab';

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

  bool get _allowNativeAutoOpen => false;

  bool _shouldHoldForPreferredQuality([String? currentQuality]) {
    if (widget.downloadOnlyMode) return false;
    final preferred = _bestPreferredQualityOption();
    if (preferred == null) return false;
    final preferredNormalized = _normalizeQualityLabel(preferred.label);
    final currentNormalized = _normalizeQualityLabel(currentQuality ?? _currentPageQualityLabel ?? '');
    return preferredNormalized == '1080p' && currentNormalized != '1080p';
  }

  void _ensurePreferredQualityBeforeAutoOpen([String? currentQuality]) {
    if (!_allowNativeAutoOpen) return;
    if (_nativePlayerActive || _nativePlayerOpening || widget.downloadOnlyMode) return;
    final preferred = _bestPreferredQualityOption();
    if (preferred == null) return;
    if (_shouldHoldForPreferredQuality(currentQuality)) {
      _autoQualityApplied = true;
      Future.microtask(() => _switchPageQuality(preferred));
    }
  }

  void _tryAutoOpenBestQuickMedia() {
    if (!widget.launchHidden || widget.downloadOnlyMode) return;
    if (!_allowNativeAutoOpen || _nativePlayerActive || _nativePlayerOpening) return;
    final item = _bestQuickMedia;
    if (item == null) return;
    final activeQuality = item.qualityLabel ?? _currentPageQualityLabel;
    if (_shouldHoldForPreferredQuality(activeQuality)) {
      _ensurePreferredQualityBeforeAutoOpen(activeQuality);
      return;
    }
    Future.microtask(() => _openNativePlayer(
          force: true,
          replace: true,
          forcedUrl: item.url,
          forcedPageUrl: item.pageUrl,
          forcedMimeType: item.mimeType,
        ));
  }

  void _scheduleOriginalPlayerHardPause() {
    for (final ms in const [0, 120, 260, 520, 900, 1400, 2000]) {
      Future.delayed(Duration(milliseconds: ms), () async {
        await _pauseOriginalSitePlayer();
      });
    }
  }

  Future<void> _pauseOriginalSitePlayer() async {
    try {
      await _wc?.evaluateJavascript(source: r'''
        (function(){
          try {
            window.__asdNativePlayerActive = true;
            window.__asdPauseAllSitePlayers = window.__asdPauseAllSitePlayers || function(){
              try {
                document.querySelectorAll('video,audio').forEach(function(v){
                  try {
                    v.pause();
                    v.muted = true;
                    v.volume = 0;
                    v.autoplay = false;
                    v.removeAttribute('autoplay');
                  } catch(e) {}
                });
              } catch(e) {}
              try {
                if (window.jwplayer) {
                  var jw = window.jwplayer();
                  if (jw && jw.setMute) jw.setMute(true);
                  if (jw && jw.pause) jw.pause(true);
                  if (jw && jw.stop) jw.stop();
                }
              } catch(e) {}
              try {
                if (window.videojs && window.videojs.getPlayers) {
                  var players = window.videojs.getPlayers();
                  Object.keys(players || {}).forEach(function(key) {
                    try {
                      var p = players[key];
                      if (p && p.muted) p.muted(true);
                      if (p && p.pause) p.pause();
                      if (p && p.autoplay) p.autoplay(false);
                    } catch(e) {}
                  });
                }
              } catch(e) {}
            };
            if (!window.__asdOrigMediaPlay) {
              window.__asdOrigMediaPlay = HTMLMediaElement.prototype.play;
              HTMLMediaElement.prototype.play = function() {
                if (window.__asdNativePlayerActive) {
                  try {
                    this.pause();
                    this.muted = true;
                    this.volume = 0;
                  } catch(e) {}
                  return Promise.resolve();
                }
                return window.__asdOrigMediaPlay.apply(this, arguments);
              };
            }
            window.__asdPauseAllSitePlayers();
            try { clearInterval(window.__asdNativePauseLoop); } catch(e) {}
            window.__asdNativePauseLoop = setInterval(function(){
              if (!window.__asdNativePlayerActive) return;
              try { window.__asdPauseAllSitePlayers(); } catch(e) {}
            }, 220);
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
            try { clearInterval(window.__asdNativePauseLoop); } catch(e) {}
            window.__asdNativePauseLoop = null;
            document.querySelectorAll('video,audio').forEach(function(v){
              try {
                v.pause();
                v.muted = false;
                v.volume = 1;
              } catch(e) {}
            });
            if (window.jwplayer) {
              try {
                var jw = window.jwplayer();
                if (jw && jw.setMute) jw.setMute(false);
                if (jw && jw.pause) jw.pause(true);
              } catch(e) {}
            }
            if (window.videojs && window.videojs.getPlayers) {
              try {
                var players = window.videojs.getPlayers();
                Object.keys(players || {}).forEach(function(key) {
                  try {
                    var p = players[key];
                    if (p && p.muted) p.muted(false);
                    if (p && p.pause) p.pause();
                  } catch(e) {}
                });
              } catch(e) {}
            }
          } catch(e) {}
        })();
      ''');
    } catch (_) {}
  }

  Future<void> _closeNativePlayer() async {
    _suppressAutoOpenUntil = DateTime.now().millisecondsSinceEpoch + 1200;
    try {
      await _pip.invokeMethod<bool>('closeNativePlayer');
    } catch (_) {}
    await _releaseOriginalSitePlayerBlock();
  }

  Future<void> _openNativePlayer({bool force = false, bool enterPipAfter = false, bool replace = false, double? startTimeOverride, String? forcedUrl, String? forcedPageUrl, String? forcedMimeType, bool allowInDownloadOnlyMode = false}) async {
    if (widget.downloadOnlyMode && !allowInDownloadOnlyMode) return;
    if (!replace && (_nativePlayerActive || _nativePlayerOpening)) return;

    if (_capturedVideoUrl == null || _capturedVideoUrl!.startsWith('blob:')) {
      try {
        await _wc?.evaluateJavascript(source: 'window.__asdCollectMediaNow && window.__asdCollectMediaNow();');
        await Future.delayed(const Duration(milliseconds: 180));
      } catch (_) {}
    }

    final preferredItem = forcedUrl == null ? _bestQuickMedia : null;
    final mediaUrl = forcedUrl ?? preferredItem?.url ?? _capturedVideoUrl;
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

    _nativePlayerOpening = true;
    final ticket = ++_nativeOpenTicket;

    try {
      await _pauseOriginalSitePlayer();
      final currentPage = (await _wc?.getUrl())?.toString();
      final pageUrl = forcedPageUrl ?? preferredItem?.pageUrl ?? _capturedVideoPageUrl ?? currentPage ?? _lastTrusted;
      _rememberStableWatchUrl(pageUrl);
      _rememberStableWatchUrl(currentPage);
      _rememberStableWatchUrl(preferredItem?.pageUrl);
      _rememberStableWatchUrl(_capturedVideoPageUrl);
      final headers = await _buildPipHeaders(mediaUrl, pageUrl: pageUrl);
      final aspectRatio = _safePipAspectRatio();

      if (!Platform.isAndroid) {
        if (ticket != _nativeOpenTicket) return;
        if (mounted) {
          setState(() {
            _nativePlayerActive = true;
            _lastNativePlayerUrl = mediaUrl;
          });
        }
        await openUniversalMediaPlayer(
          context,
          url: mediaUrl,
          title: widget.headerTitle ?? 'ASD Pics',
          pageUrl: pageUrl,
          mimeType: forcedMimeType ?? preferredItem?.mimeType ?? _capturedVideoMimeType ?? _inferMimeType(mediaUrl),
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
        await _returnToWatchPage();
        await _restoreUI();
        return;
      }

      final ok = await _pip.invokeMethod<bool>('openNativePlayer', {
        'url': mediaUrl,
        'currentTime': startTimeOverride ?? _capturedVideoTime,
        'pageUrl': pageUrl,
        'mimeType': forcedMimeType ?? preferredItem?.mimeType ?? _capturedVideoMimeType ?? _inferMimeType(mediaUrl),
        'headers': headers,
        'aspectRatioNumerator': aspectRatio['w'],
        'aspectRatioDenominator': aspectRatio['h'],
        'qualityOptions': _pageQualityOptions.map((e) => e.toMap()).toList(),
        'currentQualityLabel': _currentPageQualityLabel,
        'serverOptions': _pageServerOptions.map((e) => e.toMap()).toList(),
        'currentServerLabel': _currentServerLabel,
      });

      if (ticket != _nativeOpenTicket) return;
      if (ok == true && mounted) {
        setState(() {
          _nativePlayerActive = true;
          _lastNativePlayerUrl = mediaUrl;
        });
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
      await _applyBestScreenRefreshRate();
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
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.black,
      systemNavigationBarDividerColor: Colors.black,
      systemNavigationBarIconBrightness: Brightness.light,
      statusBarIconBrightness: Brightness.light,
    ));
    await _applyBestScreenRefreshRate();
  }

  Future<void> _killPopupsAndKeepPage() async {
    final controller = _wc;
    if (controller == null) return;
    try {
      await controller.evaluateJavascript(source: r'''
(function(){
  try {
    if (window.__asdAutoClosePopups) window.__asdAutoClosePopups();
    if (window.__asdStableUrl && location.href !== window.__asdStableUrl) {
      try { history.replaceState(null, document.title, window.__asdStableUrl); } catch(e) {}
    }
  } catch(e) {}
})();
''');
    } catch (_) {}
  }

  void _restoreStableAfterBlockedPopup() {
    Future.delayed(const Duration(milliseconds: 80), () async {
      await _killPopupsAndKeepPage();
    });
    Future.delayed(const Duration(milliseconds: 280), () async {
      await _killPopupsAndKeepPage();
    });
  }

  Future<void> _reinjectScripts() async {
    if (_wc == null) return;
    await _wc!.evaluateJavascript(source: _stealthAdBlock);
    await _wc!.evaluateJavascript(source: _ads);
    await _wc!.evaluateJavascript(source: _desktopViewport);
        await _wc!.evaluateJavascript(source: _css);
    await _wc!.evaluateJavascript(source: _hideServers);
    await _wc!.evaluateJavascript(source: _dlCapture);
    await _wc!.evaluateJavascript(source: _srvCapture);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ✅ FIX 1: _isAllowedNavigation — closed the canRedir loophole
  //    Old bug: if _lastTrusted was doodstream/arabseed (in _redirectOk),
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

    // Direct asd.pics / arabseed — always allowed
    if (url.contains('asd.pics') || url.contains('arabseed.show')) {
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
    final status = d.status.toLowerCase();
    final isDone = status == 'done';
    final isErr = status == 'error';
    final isCancelled = status == 'cancelled';
    final isPaused = status == 'paused';
    final isDownloading = status == 'downloading' || status == 'preparing' || status == 'running' || status == 'active' || status == 'queued' || status == 'enqueued';

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
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isDownloading)
                _actionBtn(icon: Icons.pause_circle_outline_rounded, color: Colors.white, onTap: () => _pauseDownload(d)),
              if (isPaused)
                _actionBtn(icon: Icons.play_circle_outline_rounded, color: Colors.white, onTap: () => _resumeDownload(d)),
              if (isDone && d.savedPath != null)
                _actionBtn(icon: Icons.play_circle_fill_rounded, color: Colors.green, onTap: () => _playVideo(d.savedPath!)),
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
          width: 34, height: 34,
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
      pageUrl: _capturedVideoPageUrl ?? _currentPageUrl ?? _lastTrusted ?? 'https://asd.pics/',
      fileName: _contextualFileName(url, qualityLabel: _currentPageQualityLabel),
      foundAt: DateTime.now(),
      isDirectFile: _isDirectMediaFile(url),
      isStream: _isStreamUrl(url),
      mimeType: _capturedVideoMimeType ?? _inferMimeType(url),
      qualityLabel: _normalizeQualityLabel(_currentPageQualityLabel ?? '').isEmpty ? null : _normalizeQualityLabel(_currentPageQualityLabel ?? ''),
      headers: {
        'User-Agent': _ua,
        'Referer': _capturedVideoPageUrl ?? _currentPageUrl ?? _lastTrusted ?? 'https://asd.pics/',
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

  Future<void> _playBestCapturedMedia() async {
    // onVideoFound ← _qualitySwitchPending ← _manualPlayAfterQualitySwitchPending
    final preferred = _bestPreferredQualityOption();

    if (preferred != null) {
      _capturedVideoUrl = null;
      _manualPlayAfterQualitySwitchPending = true;
      await _switchPageQuality(preferred);
      return;
    }

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

    await _primeWatchPageCapture();
    _showSnack('⌛ انتظر قليلًا حتى يلتقط الرابط ثم اضغط تشغيل مرة أخرى');
  }

  Future<void> _startDownloadForQuality(PageQualityOption option) async {
    final normalizedLabel = _normalizeQualityLabel(option.label);
    final cached = _bestQuickMediaForQuality(normalizedLabel);
    if (cached != null && cached.isDirectFile) {
      await _startDownload(
        cached.url,
        cached.fileName,
        qualityLabel: normalizedLabel,
        debugReason: 'cached-quality',
      );
      return;
    }
    if (_looksLikePlayableMediaUrl(option.url)) {
      if (_isDirectMediaFile(option.url)) {
        await _startDownload(
          option.url!,
          _contextualFileName(option.url!, qualityLabel: normalizedLabel),
          qualityLabel: normalizedLabel,
          debugReason: 'direct-option-url',
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

    _downloadDebug(
      'QUALITY_CLICK quality=${normalizedLabel.isEmpty ? option.label : normalizedLabel} clicked=$clicked key=${option.key}',
    );

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
    await _prepareDownloadQualityChoices();
  }

  Future<void> _prepareDownloadQualityChoices() async {
    _manualPlayAfterQualitySwitchPending = false;
    _qualitySwitchPending = false;
    _qualityDownloadSwitchPending = false;
    _pendingDownloadQualityLabel = null;
    _suppressAutoOpenUntil = DateTime.now().millisecondsSinceEpoch + 10000;

    await _pauseOriginalSitePlayer();
    await _primeWatchPageCapture();

    try {
      await _wc?.evaluateJavascript(source: r'''
        (function(){
          try { if (window.__asdCollectMediaNow) window.__asdCollectMediaNow(); } catch(e) {}
        })();
      ''');
    } catch (_) {}

    await Future.delayed(const Duration(milliseconds: 550));
    if (!mounted) return;

    if (_pageQualityOptions.isNotEmpty || _bestQuickMedia != null) {
      await _showQualityDownloadSheet();
      return;
    }

    _showSnack('⌛ جاري جلب الجودات... اضغط تحميل مرة أخرى بعد لحظات');
  }

  Future<void> _showQualityDownloadSheet() async {
    final options = _sortedQualityOptions;
    if (options.isNotEmpty) {
      _downloadDebug(
        'QUALITY_SHEET options=${options.map((e) => '${_normalizeQualityLabel(e.label).isEmpty ? e.label : _normalizeQualityLabel(e.label)}:${e.key}').join(', ')}',
      );
    }
    if (options.isEmpty) {
      final item = _bestQuickMedia;
      if (item != null && item.isDirectFile) {
        await _startDownload(item.url, item.fileName);
      } else {
        _showSnack('لا توجد جودات تحميل جاهزة بعد');
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
        final bottomInset = MediaQuery.of(ctx).padding.bottom;
        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.68,
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 18 + bottomInset),
              child: SingleChildScrollView(
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
                        _downloadDebug(
                          'USER_SELECTED quality=${normalized.isEmpty ? option.label : normalized} key=${option.key} optionUrl=${option.url ?? ''}',
                        );
                        await _startDownloadForQuality(option);
                      },
                    ),
                  );
                }),
              ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _startHiddenQualityHarvest() async {
    if (_wc == null || _hiddenQualityHarvesting || _nativePlayerActive || _nativePlayerOpening) return;
    final options = _sortedQualityOptions;
    if (!_looksLikeWatchPage() || options.length < 2) return;

    _hiddenQualityHarvesting = true;
    _suppressAutoOpenUntil = DateTime.now().millisecondsSinceEpoch + 12000;
    final restore = _bestPreferredQualityOption();

    try {
      for (final option in options) {
        final label = _normalizeQualityLabel(option.label);
        if (label.isEmpty || _harvestedQualityLabels.contains(label)) continue;
        final cached = _bestQuickMediaForQuality(label);
        if (cached != null && cached.isDirectFile) {
          _harvestedQualityLabels.add(label);
          continue;
        }
        _hiddenHarvestCurrentQuality = label;
        _currentPageQualityLabel = label;
        try {
          await _wc!.evaluateJavascript(source: '''
            (function(){
              try {
                if (window.__asdSelectQualityOption) {
                  window.__asdSelectQualityOption(${jsonEncode(option.key)}, ${jsonEncode(option.label)}, ${jsonEncode(option.url ?? '')});
                }
                if (window.__asdCollectMediaNow) {
                  setTimeout(function(){ try { window.__asdCollectMediaNow(); } catch(e) {} }, 120);
                  setTimeout(function(){ try { window.__asdCollectMediaNow(); } catch(e) {} }, 700);
                }
              } catch(e) {}
            })();
          ''');
        } catch (_) {}
        await Future.delayed(const Duration(milliseconds: 1500));
        await _pauseOriginalSitePlayer();
        await Future.delayed(const Duration(milliseconds: 500));
      }

      if (restore != null) {
        _currentPageQualityLabel = _normalizeQualityLabel(restore.label);
        try {
          await _wc!.evaluateJavascript(source: '''
            (function(){
              try {
                if (window.__asdSelectQualityOption) {
                  window.__asdSelectQualityOption(${jsonEncode(restore.key)}, ${jsonEncode(restore.label)}, ${jsonEncode(restore.url ?? '')});
                }
              } catch(e) {}
            })();
          ''');
        } catch (_) {}
      }
    } finally {
      _hiddenHarvestCurrentQuality = null;
      _hiddenQualityHarvesting = false;
      await _pauseOriginalSitePlayer();
    }
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
      _prepareDownloadQualityChoices();
    });
  }

  Future<void> _primeWatchPageCapture() async {
    if (_wc == null || !_looksLikeWatchPage()) return;
    Future<void> runProbe() async {
      try {
        await _wc!.evaluateJavascript(source: r'''(function(){
          try { if (window.__asdCollectMediaNow) window.__asdCollectMediaNow(); } catch(e) {}
          try {
            document.querySelectorAll('video,audio').forEach(function(v){
              try {
                v.pause();
                v.muted = true;
                v.volume = 0;
              } catch(e) {}
            });
          } catch(e) {}
        })();''');
      } catch (_) {}
    }
    for (final ms in const [250, 800, 1600, 2800]) {
      Future.delayed(Duration(milliseconds: ms), runProbe);
    }
    Future.delayed(const Duration(milliseconds: 2200), _pauseOriginalSitePlayer);
    Future.delayed(const Duration(milliseconds: 3200), _startHiddenQualityHarvest);
  }

  Widget _buildQuickMediaButtons() {
    if (!_showQuickMediaButtons) return const SizedBox.shrink();
    Widget fullPageButton({
      required IconData icon,
      required String title,
      required String subtitle,
      required VoidCallback onTap,
      required Color accent,
    }) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          child: Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              color: accent,
              border: Border.all(
                color: Colors.white,
                width: 2,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Center(
                      child: Icon(icon, color: Colors.white, size: 132),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final downloadSubtitle = _pageQualityOptions.isNotEmpty
        ? 'اختر الجودة ثم تحميل'
        : 'جلب الجودات ثم تحميل';

    return Positioned.fill(
      child: Material(
        color: Colors.black.withValues(alpha: 0.55),
        child: Column(
          children: [
            Expanded(
              child: fullPageButton(
                icon: Icons.play_arrow_rounded,
                title: 'مشاهدة',
                subtitle: '',
                onTap: _playBestCapturedMedia,
                accent: const Color(0xFF2F8F2F),
              ),
            ),
            Container(
              width: double.infinity,
              height: 2,
              color: Colors.white.withValues(alpha: 0.08),
            ),
            Expanded(
              child: fullPageButton(
                icon: Icons.download_rounded,
                title: 'تحميل',
                subtitle: downloadSubtitle,
                onTap: _prepareDownloadQualityChoices,
                accent: const Color(0xFFB00000),
              ),
            ),
          ],
        ),
      ),
    );
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
                                          _showSnack('هذا رابط بث HLS/DASH، تم التقاطه للتشغيل وليس تنزيله المباشر');
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
        if (_wc != null && await _wc!.canGoBack()) { await _wc!.goBack(); return; }
        if (context.mounted) SystemNavigator.pop();
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
              widget.headerTitle ?? 'ASD Pics',
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
        body: SafeArea(
          top: false,
          bottom: !_fullscreen,
          child: Stack(
            children: [
            Opacity(
              opacity: _hideSiteDuringDirectLaunch ? 0.0 : 1.0,
              child: IgnorePointer(
                ignoring: _hideSiteDuringDirectLaunch,
                child: InAppWebView(
                  initialUrlRequest: URLRequest(
                url: WebUri(widget.initialUrl),
                headers: {'User-Agent': _ua},
              ),
              pullToRefreshController: _ptr,
              initialUserScripts: UnmodifiableListView([
                UserScript(
                  source: _stealthAdBlock,
                  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                  forMainFrameOnly: false,
                ),
                UserScript(
                  source: _ads,
                  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                  forMainFrameOnly: false,
                ),
                UserScript(
                  source: _desktopViewport,
                  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                ),
                UserScript(
                  source: _webViewFrameBoost,
                  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                  forMainFrameOnly: false,
                ),
                UserScript(
                  source: _css,
                  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
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
                Future.microtask(_applyBestScreenRefreshRate);

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
                        _capturePlayableUrl(map['url']?.toString(),
                          pageUrl: map['pageUrl']?.toString(),
                          currentTime: (map['currentTime'] as num?)?.toDouble(),
                          mimeType: map['mimeType']?.toString());
                        final vw = (map['videoWidth'] as num?)?.toInt() ?? 0;
                        final vh = (map['videoHeight'] as num?)?.toInt() ?? 0;
                        if (vw > 0 && vh > 0) {
                          _videoAspectW = vw;
                          _videoAspectH = vh;
                        }
                      }
                      if (playing && (_nativePlayerActive || _nativePlayerOpening)) {
                        _pauseOriginalSitePlayer();
                        _scheduleOriginalPlayerHardPause();
                        setState(() { _videoPlaying = false; _videoDetected = true; });
                        return;
                      }
                      setState(() { _videoPlaying = playing; if (playing) _videoDetected = true; });
                      if (playing && _allowNativeAutoOpen && !_nativePlayerActive && !_nativePlayerOpening) {
                        Future.delayed(const Duration(milliseconds: 60), _openNativePlayer);
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
                  handlerName: 'onQualityOptions',
                  callback: (args) {
                    if (args.isEmpty || args[0] is! Map) return;
                    final data = Map<String, dynamic>.from(args[0] as Map);
                    final rawOptions = (data['options'] as List?)
                            ?.whereType<Map>()
                            .map((e) => PageQualityOption.fromMap(Map<String, dynamic>.from(e)))
                            .toList() ??
                        const <PageQualityOption>[];
                    final current = data['current']?.toString();
                    if (mounted) {
                      setState(() {
                        _updatePageQualityOptions(rawOptions, current);
                      });
                    } else {
                      _updatePageQualityOptions(rawOptions, current);
                    }

                    final preferred = _bestPreferredQualityOption();
                    final currentNormalized = _normalizeQualityLabel(_currentPageQualityLabel ?? current ?? '');
                    if (preferred != null) {
                      final preferredNormalized = _normalizeQualityLabel(preferred.label);
                      if (!_autoQualityApplied && currentNormalized == preferredNormalized) {
                        _autoQualityApplied = true;
                      }
                      if (!_autoQualityApplied &&
                          preferredNormalized == '1080p' &&
                          currentNormalized != '1080p' &&
                          (_nativePlayerActive || _nativePlayerOpening)) {
                        _autoQualityApplied = true;
                        Future.delayed(const Duration(milliseconds: 600), () {
                          if (mounted && (_nativePlayerActive || _nativePlayerOpening)) {
                            _switchPageQuality(preferred);
                          }
                        });
                      }
                    }

                    if (_looksLikeWatchPage()) {
                      Future.delayed(const Duration(milliseconds: 900), _startHiddenQualityHarvest);
                    }
                    _maybePromptDownloadChoices();
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
                            'Referer': _currentPageUrl ?? _capturedVideoPageUrl ?? _lastTrusted ?? 'https://asd.pics/',
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
                      final foundQuality = _normalizeQualityLabel(
                        _pendingDownloadQualityLabel ?? _hiddenHarvestCurrentQuality ?? _currentPageQualityLabel ?? '',
                      );
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
                        _downloadDebug(
                          'CAPTURED_FOR_DOWNLOAD quality=${pendingLabel.isEmpty ? 'unknown' : pendingLabel} url=$foundUrl',
                        );
                        _qualityDownloadSwitchPending = false;
                        _pendingDownloadQualityLabel = null;
                        if (_isDirectMediaFile(foundUrl)) {
                          final downloadName = _contextualFileName(foundUrl, qualityLabel: pendingLabel);
                          Future.microtask(() => _startDownload(
                            foundUrl,
                            downloadName,
                            qualityLabel: pendingLabel,
                            debugReason: 'captured-after-quality-switch',
                          ));
                        } else {
                          _showSnack('تم التقاط ${pendingLabel.isEmpty ? 'الرابط' : pendingLabel} لكنه بث وليس ملفًا مباشرًا');
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
                      if (_videoPlaying && _allowNativeAutoOpen && !_nativePlayerActive && !_nativePlayerOpening) {
                        Future.delayed(const Duration(milliseconds: 60), _openNativePlayer);
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
                    'Referer': _lastTrusted ?? 'https://asd.pics/',
                  },
                );

                if (_isDirectMediaFile(url)) {
                  if (!_discoveredDownloadUrls.contains(url)) {
                    await _startDownload(url, name);
                  }
                } else {
                  _showSnack('تم التقاط الرابط داخل أداة الجلب');
                }
              },
              shouldOverrideUrlLoading: (controller, nav) async {
                final url = nav.request.url?.toString() ?? '';
                final isMain = nav.isForMainFrame == true;
                if (!url.startsWith('http://') && !url.startsWith('https://')) {
                  return NavigationActionPolicy.CANCEL;
                }

                // ✅ FIX 1c: Block ads in ALL frames (main and iframe)
                if (_isB(url) || _isAdResourceUrl(url)) {
                  if (isMain) _restoreStableAfterBlockedPopup();
                  return NavigationActionPolicy.CANCEL;
                }

                final decodedTarget = _decodeArabseedRedirect(url);
                if (decodedTarget != null) {
                  if (_isB(decodedTarget) || _isAdResourceUrl(decodedTarget)) {
                    if (isMain) _restoreStableAfterBlockedPopup();
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
                _restoreStableAfterBlockedPopup();
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

                if (_looksLikePlayableMediaUrl(url) && !_isYouTubeUrl(url)) {
                  _capturePlayableUrl(
                    url,
                    pageUrl: _capturedVideoPageUrl ?? _lastTrusted,
                    mimeType: headers['content-type'] ?? _inferMimeType(url),
                  );
                  _addCapturedMedia(
                    url,
                    pageUrl: _capturedVideoPageUrl ?? _lastTrusted,
                    mimeType: headers['content-type'] ?? _inferMimeType(url),
                    headers: headers,
                  );
                }
                return null;
              },
              onLoadStart: (controller, url) {
                final startedUrl = url?.toString() ?? '';
                if (startedUrl.isNotEmpty && (_isB(startedUrl) || _isAdResourceUrl(startedUrl))) {
                  controller.stopLoading();
                  _restoreStableAfterBlockedPopup();
                  return;
                }
                if (widget.launchHidden && !widget.downloadOnlyMode) {
                  _suppressAutoOpenUntil = DateTime.now().millisecondsSinceEpoch + 2400;
                }
                _currentPageUrl = url?.toString();
                _rememberStableWatchUrl(url?.toString());
                _currentPageTitle = null;
                _currentMediaTitle = null;
                _capturedVideoUrl = null;
                _capturedVideoTime = 0;
                _capturedVideoPageUrl = url?.toString();
                _capturedVideoMimeType = null;
                _videoAspectW = 16;
                _videoAspectH = 9;
                _capturedMedia.clear();
                _capturedMediaSeen.clear();
                _harvestedQualityLabels.clear();
                _hiddenHarvestCurrentQuality = null;
                _qualityDownloadSwitchPending = false;
                _pendingDownloadQualityLabel = null;
                _autoDownloadPromptShown = false;
                if (mounted) {
                  setState(() {
                    _videoDetected = false;
                    _videoPlaying = false;
                    _pageQualityOptions = const [];
                    _pageServerOptions = const [];
                    _currentPageQualityLabel = null;
                    _currentServerLabel = null;
                    _serverSwitchPending = false;
                    _autoQualityApplied = false;
                  });
                }
              },
              onUpdateVisitedHistory: (controller, url, _) {
                _currentPageUrl = url?.toString();
                _rememberStableWatchUrl(url?.toString());
              },
              onLoadStop: (controller, url) async {
                _ptr?.endRefreshing();
                if (widget.launchHidden && !widget.downloadOnlyMode) {
                  _suppressAutoOpenUntil = DateTime.now().millisecondsSinceEpoch + 1600;
                }
                _currentHost = url?.host;
                _currentPageUrl = url?.toString();
                _rememberStableWatchUrl(url?.toString());
                _rememberAllowedHost(url?.toString());
                _capturedVideoUrl = null;
                _capturedVideoTime = 0;
                _capturedVideoPageUrl = url?.toString();
                _capturedVideoMimeType = null;
                _videoAspectW = 16;
                _videoAspectH = 9;
                _autoDownloadPromptShown = false;
                if (mounted) setState(() { _videoDetected = false; _videoPlaying = false; _pageQualityOptions = const []; _pageServerOptions = const []; _currentPageQualityLabel = null; _currentServerLabel = null; _serverSwitchPending = false; _autoQualityApplied = false; });
                await _reinjectScripts();
                await _applyBestScreenRefreshRate();
                await _killPopupsAndKeepPage();
                await _refreshCurrentMediaTitle();
                await _primeWatchPageCapture();
              },
              onProgressChanged: (controller, p) {
                if (mounted) setState(() => _progress = p / 100);
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
            ],
          ),
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
  String? _error;
  PlexFilter _filter = PlexFilter.all;
  String _query = '';

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
                              initialUrl: 'https://asd.pics/main6/',
                              headerTitle: 'ASD Pics',
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
                    title: 'أفلام',
                    subtitle: 'مجمعة من نفس الصفحة الحالية',
                    items: (_payload?.movies ?? const <CatalogEntry>[]).take(14).toList(),
                    large: false,
                  ),
                ),
                SliverToBoxAdapter(
                  child: _buildSection(
                    title: 'مسلسلات وحلقات',
                    subtitle: 'الحلقات والمواسم كما تظهر في الموقع',
                    items: (_payload?.series ?? const <CatalogEntry>[]).take(14).toList(),
                    large: false,
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 40)),
              ],
            ],
          ),
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
                  image: NetworkImage(item.imageUrl),
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
      final decoded = _decodeJsonValue(raw);
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
  if (clean.contains('/watch/')) return clean;
  if (clean.endsWith('/')) return '${clean}watch/';
  return '$clean/watch/';
}

String _buildDownloadUrl(String url) {
  final clean = url.trim();
  if (clean.isEmpty) return clean;
  if (clean.contains('/download')) return clean;
  if (clean.endsWith('/')) return '${clean}download/';
  return '$clean/download/';
}

const String _homeExtractorJs = r'''(function(){
  function clean(t){ return (t || '').replace(/\s+/g, ' ').trim(); }
  function attr(el, name){ return el ? clean(el.getAttribute(name) || '') : ''; }
  function text(el){ return el ? clean(el.innerText || el.textContent || '') : ''; }
  function imgOf(root){
    if (!root || !root.querySelector) return '';
    var img = root.querySelector('img');
    if (!img) return '';
    var src = attr(img, 'src') || attr(img, 'data-src') || attr(img, 'data-lazy-src') || attr(img, 'data-original');
    if (!src) {
      var srcset = attr(img, 'srcset');
      if (srcset) src = clean(srcset.split(',')[0].trim().split(' ')[0]);
    }
    return src;
  }
  function titleOf(root, a, img){
    var sels = ['h1','h2','h3','h4','.Title','.title','.entry-title','.name','.BlockTitle','.movie-title','.post-title'];
    for (var i = 0; i < sels.length; i++) {
      var node = root.querySelector ? root.querySelector(sels[i]) : null;
      var t = text(node);
      if (t) return t;
    }
    var direct = attr(a, 'title') || attr(a, 'aria-label') || attr(img, 'alt');
    if (direct) return direct;
    var raw = text(root);
    var parts = raw.split(/\n|\r/).map(clean).filter(Boolean);
    for (var j = 0; j < parts.length; j++) {
      var p = parts[j];
      if (p.length < 4 || p.length > 140) continue;
      if (/اعلان|القسم|الجودة|التقييم|النوع|الدقائق|ساعة|دقيقة|تصنيف/.test(p)) continue;
      return p;
    }
    return '';
  }
  function badgeOf(txt){
    var s = clean(txt || '');
    if (/افلام/i.test(s)) return 'فيلم';
    if (/مسلسلات|الحلقة|الموسم|برنامج/i.test(s)) return 'مسلسل';
    return '';
  }
  function qualityOf(txt){
    var s = clean(txt || '');
    var m = s.match(/(2160|1440|1080|720|540|480|360)\s*p/i);
    if (m) return m[1] + 'p';
    var q = s.match(/WEB-DL|BluRay|HDRip|HDTS|HD|FHD/i);
    return q ? q[0] : '';
  }
  function ratingOf(txt){
    var s = clean(txt || '');
    var m = s.match(/([0-9]+(?:\.[0-9]+)?)\s*\/\s*10/);
    return m ? (m[1] + ' / 10') : '';
  }
  function yearOf(txt){
    var s = clean(txt || '');
    var m = s.match(/\((19|20)\d{2}\)/);
    if (m) return m[0].replace(/[()]/g, '');
    var m2 = s.match(/(19|20)\d{2}/);
    return m2 ? m2[0] : '';
  }
  function inferType(title, href){
    var s = (title + ' ' + href).toLowerCase();
    return /(الحلقة|الموسم|series|season|episode|tv|برنامج)/.test(s) ? 'series' : 'movie';
  }
  function makeCard(a, scope){
    if (!a || !a.href) return null;
    var href = clean(a.href);
    if (!href) return null;
    if (/category|privacy|dmca|actor|request|iptv|search|tag\//i.test(href)) return null;
    var img = scope ? (scope.querySelector ? scope.querySelector('img') : null) : null;
    if (!img && a.querySelector) img = a.querySelector('img');
    if (!img && a.parentElement && a.parentElement.querySelector) img = a.parentElement.querySelector('img');
    var imageUrl = imgOf(scope || a.parentElement || a);
    if (!imageUrl && img) imageUrl = attr(img,'src') || attr(img,'data-src') || attr(img,'data-lazy-src');
    if (!imageUrl || imageUrl.indexOf('wp-content/uploads') === -1) return null;
    var rawText = text(scope || a.parentElement || a);
    var title = titleOf(scope || a.parentElement || a, a, img);
    if (!title || title.length < 3) return null;
    return {
      title: title,
      url: href,
      imageUrl: imageUrl,
      type: inferType(title, href),
      subtitle: clean(rawText.replace(title, '')).slice(0, 140),
      badge: badgeOf(rawText),
      quality: qualityOf(rawText),
      rating: ratingOf(rawText),
      year: yearOf(rawText)
    };
  }
  var roots = Array.from(document.querySelectorAll('article, .BlockItem, .MovieBlock, .item, .post, .GridItem, .swiper-slide, .splide__slide, li, .Grid--MyPosts > *, .Grid--WecimaPosts > *'));
  var out = [];
  var seen = {};
  roots.forEach(function(root){
    var a = root.querySelector ? root.querySelector('a[href]') : null;
    var card = makeCard(a, root);
    if (!card) return;
    if (seen[card.url]) return;
    seen[card.url] = true;
    out.push(card);
  });
  if (out.length < 8) {
    Array.from(document.querySelectorAll('a[href]')).forEach(function(a){
      var card = makeCard(a, a.parentElement || a);
      if (!card) return;
      if (seen[card.url]) return;
      seen[card.url] = true;
      out.push(card);
    });
  }
  var featured = out.slice(0, 6);
  var movies = out.filter(function(c){ return c.type === 'movie'; });
  var series = out.filter(function(c){ return c.type !== 'movie'; });
  return JSON.stringify({ featured: featured, items: out, movies: movies, series: series });
})();''';

const String _detailsExtractorJs = r'''(function(){
  function clean(t){ return (t || '').replace(/\s+/g, ' ').trim(); }
  function attr(el, name){ return el ? clean(el.getAttribute(name) || '') : ''; }
  function text(el){ return el ? clean(el.innerText || el.textContent || '') : ''; }
  function bestPoster(){
    var imgs = Array.from(document.querySelectorAll('img[src], img[data-src], img[data-lazy-src]'));
    var scored = imgs.map(function(img){
      var src = attr(img, 'src') || attr(img, 'data-src') || attr(img, 'data-lazy-src') || '';
      var score = 0;
      if (src.indexOf('wp-content/uploads') !== -1) score += 5;
      var w = img.naturalWidth || img.width || 0;
      var h = img.naturalHeight || img.height || 0;
      score += Math.min(10, Math.round((w * h) / 50000));
      return { src: src, score: score };
    }).filter(function(v){ return !!v.src; }).sort(function(a,b){ return b.score - a.score; });
    return scored.length ? scored[0].src : '';
  }
  function sectionText(label){
    var headings = Array.from(document.querySelectorAll('h1,h2,h3,h4,strong,div,p,span'));
    for (var i = 0; i < headings.length; i++) {
      var node = headings[i];
      var t = text(node);
      if (!t) continue;
      if (t === label || t.indexOf(label) !== -1) {
        var collected = [];
        var next = node.nextElementSibling;
        var guard = 0;
        while (next && guard < 6) {
          var nt = text(next);
          if (nt && nt.length > 15) collected.push(nt);
          if (/تفاصيل العرض|فريق العمل|افلام اخري|الحلقات|المواسم/.test(nt)) break;
          next = next.nextElementSibling;
          guard++;
        }
        if (collected.length) return clean(collected.join(' '));
      }
    }
    return '';
  }
  var pageText = clean(document.body ? document.body.innerText || '' : '');
  function match(re){ var m = pageText.match(re); return m ? clean(m[1]) : ''; }
  function genres(){
    var arr = [];
    var nodes = Array.from(document.querySelectorAll('a[href]'));
    nodes.forEach(function(a){
      var href = a.href || '';
      var t = text(a);
      if (!t || t.length > 40) return;
      if (/genre|نوع العرض|Drama|Romance|Comedy|Action|Crime|Horror|Sci-Fi|Animation|Family|Adventure|Thriller/i.test(href + ' ' + t)) {
        if (!/مشاهدة|تحميل|عرب سيد|الافلام|المسلسلات/.test(t)) arr.push(t);
      }
    });
    return Array.from(new Set(arr)).slice(0, 8);
  }
  function episodes(){
    var out = [];
    var seen = {};
    Array.from(document.querySelectorAll('a[href]')).forEach(function(a){
      var href = clean(a.href || '');
      var t = text(a);
      if (!href || !t) return;
      if (!/الحلقة|الموسم|episode|season/i.test(t + ' ' + href)) return;
      if (/watch|download|category|actor|search/i.test(href)) return;
      if (seen[href]) return;
      seen[href] = true;
      out.push({ title: t, url: href, subtitle: '' });
    });
    return out.slice(0, 40);
  }
  function actionLink(label, hint){
    var nodes = Array.from(document.querySelectorAll('a[href]'));
    for (var i = 0; i < nodes.length; i++) {
      var a = nodes[i];
      var href = clean(a.href || '');
      var t = text(a);
      if (!href) continue;
      if (t.indexOf(label) !== -1) return href;
      if (hint && href.indexOf(hint) !== -1) return href;
    }
    return '';
  }
  var title = text(document.querySelector('h1')) || clean((document.title || '').replace(/\s*-.*$/, ''));
  var description = sectionText('قصة العرض') || attr(document.querySelector('meta[name="description"]'), 'content');
  var watchUrl = actionLink('مشاهدة الآن', '/watch') || actionLink('الذهاب لصفحة المشاهدة', '/watch');
  var downloadUrl = actionLink('تحميل الآن', '/download') || actionLink('الذهاب لصفحة التحميل', '/download');
  return JSON.stringify({
    title: title,
    description: description,
    posterUrl: bestPoster(),
    watchUrl: watchUrl,
    downloadUrl: downloadUrl,
    rating: match(/([0-9]+(?:\.[0-9]+)?)\s*\/\s*10/),
    year: match(/سنة العرض\s*:?\s*([0-9]{4})/),
    duration: match(/مدة العرض\s*:?\s*([^\n]+)/),
    quality: match(/جودة العرض\s*:?\s*([^\n]+)/),
    country: match(/بلد العرض\s*:?\s*([^\n]+)/),
    language: match(/لغة العرض\s*:?\s*([^\n]+)/),
    category: match(/تصنيف العرض\s*:?\s*([^\n]+)/),
    genres: genres(),
    episodes: episodes()
  });
})();''';
