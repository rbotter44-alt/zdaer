import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import '../pwa/io_compat.dart';
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

@pragma('vm:entry-point')
void egySourceMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(NativeSecurityGuard.ensureClean());
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp, DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: C4uPlayer()));
}

class DownloadItem {
  final String id, url;
  String fileName, status;
  double progress;
  String? savedPath, thumbnailPath, tempPath, finalPath, errorMessage;
  CancelToken? cancelToken;
  bool pauseRequested;
  Completer<void>? resumeCompleter;

  DownloadItem({required this.id, required this.url, required this.fileName,
    this.progress = 0, this.status = 'downloading', this.savedPath,
    this.thumbnailPath, this.tempPath, this.finalPath, this.cancelToken,
    this.errorMessage, this.pauseRequested = false, this.resumeCompleter});
}

class PageQualityOption {
  final String label, key;
  final String? url;
  final bool selected;
  const PageQualityOption({required this.label, required this.key, this.url, this.selected = false});

  static String cleanLabel(String input) {
    final value = input.trim();
    final m = RegExp(r'(?:^|[^0-9])([1-9][0-9]{2,3})\s*p\b', caseSensitive: false).firstMatch(value);
    if (m == null) return value;
    return '${m.group(1)}p';
  }

  int get rank => int.tryParse(RegExp(r'[0-9]+').firstMatch(label)?.group(0) ?? '0') ?? 0;

  factory PageQualityOption.fromMap(Map<String, dynamic> m) {
    final rawLabel = (m['label']?.toString().trim().isNotEmpty ?? false)
        ? m['label'].toString().trim()
        : 'Quality';
    return PageQualityOption(
      label: cleanLabel(rawLabel),
      key: m['key']?.toString() ?? '',
      url: m['url']?.toString(),
      selected: m['selected'] == true,
    );
  }

  Map<String, String> toMap() => {
    'label': cleanLabel(label),
    'key': key,
    if (url != null && url!.isNotEmpty) 'url': url!,
  };
}

class PageServerOption {
  final String label, key;
  final String? url;
  final bool selected;
  const PageServerOption({required this.label, required this.key, this.url, this.selected = false});
  factory PageServerOption.fromMap(Map<String, dynamic> m) => PageServerOption(
    label: (m['label']?.toString().trim().isNotEmpty ?? false) ? m['label'].toString().trim() : 'Server',
    key: m['key']?.toString() ?? '', url: m['url']?.toString(), selected: m['selected'] == true);
  Map<String, String> toMap() => {'label': label, 'key': key, if (url != null && url!.isNotEmpty) 'url': url!};
}

class C4uPlayer extends StatefulWidget {
  const C4uPlayer({super.key});
  @override
  State<C4uPlayer> createState() => _C4uPlayerState();
}

class _C4uPlayerState extends State<C4uPlayer> with WidgetsBindingObserver {
  InAppWebViewController? _wc;
  PullToRefreshController? _ptr;

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 25),
    receiveTimeout: const Duration(minutes: 30),
    followRedirects: true, maxRedirects: 10,
    validateStatus: (s) => s != null && s >= 200 && s < 400,
    headers: {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36'},
  ));

  double _progress = 0;
  bool _fullscreen = false, _videoPlaying = false, _inPip = false, _videoDetected = false;
  bool _nativePlayerActive = false, _nativePlayerOpening = false, _fullscreenBusy = false;
  bool _nativePauseSentForBackground = false;
  bool _qualitySwitchPending = false, _serverSwitchPending = false, _showDownloads = false;
  bool _watchButtonWaitingForCapture = false;
  bool _downloadButtonWaitingForCapture = false;
  bool _watchLinkReadyForSecondTap = false;
  bool _overlayCaptureBusy = false;
  int _quickActionCaptureTicket = 0;
  int _lastBlankPopupWindowAt = 0;
  String? _lastNativePlayerUrl, _lastTrusted, _currentHost, _currentDocumentTitle, _contentTitleForDownload;
  String? _capturedVideoUrl, _capturedVideoPageUrl, _capturedVideoMimeType, _capturedVideoQualityLabel;
  int _nativeOpenTicket = 0, _suppressAutoOpenUntil = 0, _pendingNativeIntentUntil = 0;
  double _capturedVideoTime = 0, _pendingNativeStartTime = 0;
  int _videoAspectW = 16, _videoAspectH = 9;
  List<PageQualityOption> _pageQualityOptions = const [];
  String? _currentPageQualityLabel;
  PageQualityOption? _pendingDownloadQualityOption;
  List<PageServerOption> _pageServerOptions = const [];
  String? _currentPageServerLabel;
  final List<DownloadItem> _downloads = [];
  Timer? _backgroundDownloadSyncTimer;
  final Set<String> _discoveredDownloadUrls = {}, _runtimeAllowedHosts = {};

  static final MethodChannel _pip = MethodChannel(AppSecureText.s('nTmvYMq5fRFtg50'));
  static const String _ua = 'Mozilla/5.0 (Linux; Android 13; RMX3370) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';
  static const _videoExts = ['.m3u8', '.mp4', '.mkv', '.webm', '.ts', '.m4v', '.avi', '.mov'];
  static const _dlExts = ['.mp4', '.mkv', '.avi', '.mov', '.webm', '.m4v'];

  final _white = const [
    "egydead.pics","egydead","egydeadcdn","streamruby.com","streamruby",
    "streamhg","stream-hg","streamix","deathstream","death-stream",
    "earnvids","earn-vids","forafile","fora-file","fly.io","flycdn","finger",
    "mixdrop.ag","mixdrop.co","mixdrop","jwplatform","jwpcdn",
    "akamaized","cloudfront","cdnjs.cloudflare","fonts.googleapis","fonts.gstatic",
    "static.cloudflareinsights","s3.amazonaws","googleapis","gstatic","bunnycdn","b-cdn",
    "mega.nz","megaup.net","megaup","mediafire","1fichier","1cloudfile","1cloudfile.com",
    "krakenfiles","krakenfiles.com","vikingfile","vikingfile.com","koramaup","koramaup.com",
    "bowfile","bowfile.com","doodstream","dood","dooood","doodstream.com",
    "uploadrar","usersdrive","filerio","hexupload","sendcm","dailyuploads","turbobit",
    "nitroflare","rapidgator","katfile","filefox","racaty","gofile","pixeldrain",
    "streamtape","stape",
    "vibuxer.com","vibuxer","masukestin.com","masukestin",
    "audinifer.com","audinifer","huntrexus","hanerix",
    "streamruby.com","streamruby","streamhg","streamix",
    "deathstream","earnvids","forafile","mixdrop.ag","mixdrop",
  ];
  final _blocked = const [
    "pyppo.com","popcash.net","popads.net","popunder.net","pop.pro",
    "clickunder.net","trafficshop.com","plugrush.com","adcash.com","zeropark.com",
    "richpush.co","doubleclick.net","googlesyndication.com","adservice.google.com",
    "pagead2.googlesyndication.com","tpc.googlesyndication.com","adnxs.com",
    "rubiconproject.com","openx.net","casalemedia.com","criteo.com","taboola.com",
    "outbrain.com","revcontent.com","mgid.com","propellerads.com","hilltopads.net",
    "exoclick.com","juicyads.com","trafficjunky.net","adsterra.com",
    "melbet.org","www.melbet.org","melbet",
    "bvtpk.com","b7510.com","405kk.com","071kk.com","crummydevioussucculent.com",
    "yawncollaremotion.com","preferencenail.com","newshinyd.com","bobapsoabauns.com",
    "fleraprt.com","tzegilo.com","imasdk.googleapis.com","googletagmanager.com",
    "mc.yandex.ru","dtscout.com","dtscdn.com","mrktmtrcs.net","onaudience.com",
    "histats.com","rtmark.net","44555games.com","trffk.g2afse.com","tiktokcdn.com",
    "llvpn.com","affidavitheadfirstonward.com","omoonsih.net","jnbhi.com","oyo4d.com",
    "sourshaped.com","deductpursue.com","protrafficinspector.com","tfnvuckb.pro",
    "waust.at","whacmoltibsay.net","fundingchoicesmessages.google.com",
    "ads.pubmatic.com","securepubads.g.doubleclick.net","stapleleisure.com",
    "kettledroopingcontinuation.com",
    "cuppedajitter.com",
    "liccayouth.top",
    "justinepulvino.qpon",
    "waggelvet.qpon",
    "parcookgoofah.qpon",
    "azotesdanian.cyou",
    ".qpon",
    "sentry.io","hotjar.com","mouseflow.com","clarity.ms",
  ];
  final _redirectOk = const [
    "egydead.pics","egydead","streamruby","streamhg","streamix",
    "deathstream","earnvids","forafile","mixdrop","streamtape","stape","nitroflare","rapidgator",
    "vibuxer","masukestin","audinifer",
    "krakenfiles","megaup","1fichier","1cloudfile","vikingfile","koramaup","bowfile","doodstream",
  ];

  bool _isVideoUrl(String url) => _videoExts.any((e) => url.toLowerCase().split('?').first.endsWith(e));
  bool _isDownloadUrl(String url) => _dlExts.any((e) => url.toLowerCase().split('?').first.endsWith(e));
  bool _isW(String u) => _white.any((d) => u.contains(d));
  bool _isB(String u) => _blocked.any((d) => u.contains(d));
  bool _canRedir(String u) => _redirectOk.any((d) => u.contains(d));

  String? _hostOf(String? rawUrl) {
    final host = Uri.tryParse(rawUrl ?? '')?.host.toLowerCase();
    return (host == null || host.isEmpty) ? null : host;
  }
  void _rememberAllowedHost(String? rawUrl) { final h = _hostOf(rawUrl); if (h != null) _runtimeAllowedHosts.add(h); }
  bool _isRuntimeAllowed(String? rawUrl) {
    final host = _hostOf(rawUrl);
    if (host == null) return false;
    return _runtimeAllowedHosts.any((a) => host == a || host.endsWith('.$a') || a.endsWith('.$host'));
  }

  bool _isLikelyDownloadLandingUrl(String url) {
    final lower = url.toLowerCase();
    return ['/download','/downloads','/watch','/embed','/e/','/f/','/file/','streamruby','streamhg','streamix',
      'deathstream','earnvids','forafile','mixdrop','nitroflare','rapidgator','1fichier',
      'krakenfiles','megaup','1cloudfile','vikingfile','koramaup','bowfile','doodstream','dooood']
      .any((s) => lower.contains(s));
  }

  bool _isKnownDownloadProviderUrl(String url) {
    final lower = url.toLowerCase();
    return [
      'krakenfiles','megaup','mixdrop','1fichier','vikingfile','koramaup',
      '1cloudfile','bowfile','doodstream','dooood','earnvids',
      '/download','/downloads','/file/','/f/'
    ].any((s) => lower.contains(s));
  }

  String _sanitizeFileName(String input) {
    final clean = input.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
    return clean.isEmpty ? 'video.mp4' : clean;
  }
  String _inferFileName(String url, [String fallback = 'video.mp4']) {
    try {
      final last = Uri.parse(url).pathSegments.isNotEmpty ? Uri.parse(url).pathSegments.last : fallback;
      final decoded = Uri.decodeComponent(last);
      if (decoded.isNotEmpty && decoded.contains('.')) return _sanitizeFileName(decoded);
    } catch (_) {}
    return _sanitizeFileName(fallback);
  }

  Future<Directory> _downloadsBaseDir() async {
    if (Platform.isAndroid) {
      final ext = await getExternalStorageDirectory();
      if (ext != null) { final d = Directory('${ext.path}/Videos/Egy'); if (!await d.exists()) await d.create(recursive: true); return d; }
    }
    final appDir = await getApplicationDocumentsDirectory();
    final d = Directory('${appDir.path}/Videos/Egy'); if (!await d.exists()) await d.create(recursive: true); return d;
  }

  String _buildReferer(String downloadUrl) {
    try {
      final host = Uri.parse(downloadUrl).host.toLowerCase();
      if (['streamruby','streamhg','deathstream','streamix','earnvids','forafile'].any((s) => host.contains(s))) {
        return _currentHost != null ? 'https://$_currentHost/' : 'https://egydead.pics/';
      }
      if (host.contains('mixdrop')) return 'https://mixdrop.ag/';
    } catch (_) {}
    return _currentHost != null ? 'https://$_currentHost/' : 'https://egydead.pics/';
  }
  Map<String, dynamic> _downloadHeaders(String url, {String? pageUrl}) {
    final referer = (pageUrl != null && pageUrl.trim().isNotEmpty)
        ? pageUrl.trim()
        : ((_capturedVideoPageUrl ?? '').trim().isNotEmpty
            ? _capturedVideoPageUrl!.trim()
            : _buildReferer(url));
    String origin = 'https://${_currentHost ?? 'egydead.pics'}';
    try { origin = Uri.parse(referer).origin; } catch (_) {}
    return {
      'User-Agent': _ua,
      'Accept': '*/*',
      'Connection': 'keep-alive',
      'Referer': referer,
      'Origin': origin,
    };
  }

  bool _looksLikePlayableMediaUrl(String? url) {
    if (url == null || url.isEmpty || url.toLowerCase().startsWith('blob:')) return false;
    final lower = url.toLowerCase();
    return ['.m3u8','.mp4','.mkv','.webm','.m4v','.ts','.mov','.mpd','mime=video',
      'contenttype=video','/hls/','/playlist','/manifest'].any((s) => lower.contains(s));
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

  bool _isCloudflareChallengeUrl(String url) {
    final u = url.toLowerCase();
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    return u.contains('/cdn-cgi/') ||
        host == 'challenges.cloudflare.com' ||
        host.endsWith('.challenges.cloudflare.com') ||
        u.contains('turnstile') ||
        u.contains('cf_chl') ||
        u.contains('cf-chl') ||
        u.contains('challenge-platform') ||
        (host.endsWith('cloudflare.com') &&
            (u.contains('challenge') || u.contains('turnstile')));
  }

  bool _isAdResourceUrl(String url) {
    if (_isCloudflareChallengeUrl(url)) return false;
    if (_isB(url)) return true;
    final u = url.toLowerCase();
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    if (host.endsWith('.qpon') || host == 'qpon') return true;
    if (RegExp(r'\.(qpon|cyou|xyz|top|click)$').hasMatch(host) &&
        !_isW(url) && !_isRuntimeAllowed(url)) {
      if (!['egydead','streamruby','krakenfiles','mixdrop',
            'vibuxer','masukestin','audinifer'].any((s) => host.contains(s))) {
        return true;
      }
    }
    const adHosts = [
      'doubleclick.net','googlesyndication.com','pagead2','googletagmanager.com',
      'adnxs.com','adservice.google.','pubmatic.com','rubiconproject.com','criteo.com',
      'taboola.com','outbrain.com','revcontent.com','mgid.com','propellerads','exoclick',
      'imasdk','imasdk.googleapis.com','gstatic.com/pagead',
      'cuppedajitter.com','liccayouth.top','azotesdanian.cyou',
      'llvpn.com','melbet.org','melbet',
    ];
    const adPaths = [
      '/ads/','/ad/','/gpt/','ad_unit','adunit','interstitial','rewarded',
      'adsbygoogle','/async/ads','/pagead','gpt-ad','/tsk/','/tsf/','/cuid/',
    ];
    return adHosts.any((h) => u.contains(h)) || adPaths.any((p) => u.contains(p));
  }

  void _capturePlayableUrl(String? rawUrl, {String? pageUrl, double? currentTime, String? mimeType}) {
    final url = rawUrl?.trim();
    if (!_looksLikePlayableMediaUrl(url)) return;

    final isHls = url!.toLowerCase().contains('.m3u8');
    final currentIsHls = (_capturedVideoUrl ?? '').toLowerCase().contains('.m3u8');
    final shouldReplace = _capturedVideoUrl == null ||
        (isHls && !currentIsHls) ||
        (_capturedVideoUrl?.startsWith('blob:') ?? false) ||
        _watchButtonWaitingForCapture ||
        _downloadButtonWaitingForCapture;

    if (shouldReplace) {
      _capturedVideoUrl = url;
      final quality = _normalizeQualityLabel(_currentPageQualityLabel ?? '');
      _capturedVideoQualityLabel = quality.isEmpty ? null : quality;
    }

    _capturedVideoMimeType = _inferMimeType(url, mimeType);
    if (pageUrl != null && pageUrl.isNotEmpty) _capturedVideoPageUrl = pageUrl;
    if (currentTime != null && currentTime >= 0) _capturedVideoTime = currentTime;
    if (mounted && !_videoDetected) setState(() => _videoDetected = true);
    if (_watchButtonWaitingForCapture || _downloadButtonWaitingForCapture) {
      Future.microtask(_tryCompletePendingQuickAction);
    }
  }

  Future<Map<String, String>> _buildPipHeaders(String mediaUrl, {String? pageUrl}) async {
    final referer = (pageUrl != null && pageUrl.isNotEmpty) ? pageUrl : (_lastTrusted ?? 'https://egydead.pics/');
    String origin = 'https://egydead.pics';
    try { origin = Uri.parse(referer).origin; } catch (_) {}
    final cookieManager = CookieManager.instance();
    final cookieMap = <String, String>{};
    Future<void> appendCookies(String? url) async {
      if (url == null || url.isEmpty) return;
      try {
        final cookies = await cookieManager.getCookies(url: WebUri(url));
        for (final c in cookies) { if (c.name.isNotEmpty) cookieMap[c.name] = c.value; }
      } catch (_) {}
    }
    await appendCookies(pageUrl); await appendCookies(mediaUrl);
    final headers = <String, String>{'User-Agent': _ua, 'Accept': '*/*', 'Connection': 'keep-alive', 'Referer': referer, 'Origin': origin};
    if (cookieMap.isNotEmpty) headers['Cookie'] = cookieMap.entries.map((e) => '${e.key}=${e.value}').join('; ');
    return headers;
  }

  // ─── JavaScript Scripts ───────────────────────────────────────────────────

  static const String _stealthAdBlock = r"""
(function(){
  'use strict';
  if (window.__asdSABv2) return;
  window.__asdSABv2 = true;
  var _host = (window.location && window.location.host || '').toLowerCase();
  var _mainSite = _host.indexOf('egydead') !== -1 || _host.indexOf('c4u') !== -1;
  if (!_mainSite) return;

  var fakeSlot = {
    addService: function(){ return fakeSlot; }, defineSizeMapping: function(){ return fakeSlot; },
    setTargeting: function(){ return fakeSlot; }, setCollapseEmptyDiv: function(){ return fakeSlot; },
    getSlotElementId: function(){ return 'div-gpt-ad-fake'; }, getAdUnitPath: function(){ return '/fake/ad'; },
    getResponseInformation: function(){ return null; }
  };
  var fakePubads = {
    enableSingleRequest: function(){}, setTargeting: function(){ return fakePubads; },
    refresh: function(){}, clear: function(){ return true; }, addEventListener: function(){},
    removeEventListener: function(){}, collapseEmptyDivs: function(){}, enableLazyLoad: function(){},
    disableInitialLoad: function(){}, setPrivacySettings: function(){}, updateCorrelator: function(){},
    getTargeting: function(){ return []; }, getTargetingKeys: function(){ return []; }
  };
  var fakeSizeMapping = { addSize: function(){ return fakeSizeMapping; }, build: function(){ return []; } };

  if (!window.googletag || !window.googletag._asdFaked) {
    window.googletag = {
      _asdFaked: true, cmd: [],
      defineSlot: function(){ return fakeSlot; }, defineOutOfPageSlot: function(){ return fakeSlot; },
      pubads: function(){ return fakePubads; }, enableServices: function(){}, display: function(){},
      destroySlots: function(){ return true; }, sizeMapping: function(){ return fakeSizeMapping; },
      companionAds: function(){ return { enableSyncLoading: function(){}, setRefreshUnfilledSlots: function(){} }; }
    };
    window.googletag.cmd.push = function(fn){ try { if (typeof fn === 'function') fn(); } catch(e) {} };
  }
  if (!window.adsbygoogle) { window.adsbygoogle = []; }
  window.adsbygoogle.loaded = true;
  window.adsbygoogle.push = function(cfg){ Array.prototype.push.call(window.adsbygoogle, cfg); };
  window._taboola = window._taboola || []; window._taboola.push = function(){};
  window.OBR = window.OBR || { extern: { renderST: function(){} } };
  window.OutbrainPerf = window.OutbrainPerf || { mark: function(){} };
  window.ExoLoader = window.ExoLoader || { serve: function(){}, load: function(){} };
  window.propellerads = window.propellerads || { push: function(){} };
  window.popns = window.popns || function(){};
  window.IABConsent_CMPPresent = true;
  window.__tcfapi = window.__tcfapi || function(cmd, ver, cb){ try { cb({}, true); } catch(e) {} };
  window.__cmp = window.__cmp || function(cmd, arg, cb){ try { cb({}, true); } catch(e) {} };

  var _adDomains = ['pagead2','googlesyndication','doubleclick.net','adnxs','exoclick','juicyads',
    'adsterra','propellerads','popcash','popads','trafficjunky','hilltopads','adcash','zeropark',
    'melbet.org','melbet',
    'richpush','revcontent','mgid','rubiconproject','openx','criteo','bvtpk','b7510','oyo4d',
    'omoonsih','jnbhi','sourshaped','tfnvuckb','rtmark','fundingchoicesmessages','imasdk',
    'popunder','clickunder','trafficshop','plugrush'];

  function _isAdDomain(url) {
    if (!url) return false;
    var s = (url + '').toLowerCase();
    return _adDomains.some(function(d){ return s.indexOf(d) !== -1; });
  }

  try {
    if (window !== window.top) {
      var _origAssign = window.location.assign.bind(window.location);
      var _origReplace = window.location.replace.bind(window.location);
      window.location.assign = function(url) { if (_isAdDomain(url ? url.toString() : '')) return; _origAssign(url); };
      window.location.replace = function(url) { if (_isAdDomain(url ? url.toString() : '')) return; _origReplace(url); };
      try {
        Object.defineProperty(window, 'top', { configurable: true, get: function() {
          return new Proxy(window.parent, { get: function(target, prop) {
            if (prop === 'location') {
              return new Proxy({href: ''}, {
                set: function(t, p, v) { if (p === 'href' && _isAdDomain(v ? v.toString() : '')) return true; return true; },
                get: function(t, p) { try { return target.location[p]; } catch(e) { return t[p]; } }
              });
            }
            try { return target[prop]; } catch(e) { return undefined; }
          }});
        }});
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
        if ((attr === 'src' || attr === 'data-src') && _isAdDomain(val)) { el._asdBlocked = true; return; }
        _origSetAttr(attr, val);
      };
      try {
        Object.defineProperty(el, 'src', { configurable: true,
          set: function(val) { if (_isAdDomain(val)) { el._asdBlocked = true; return; } _origSetAttr('src', val); },
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
      if (_isAdDomain(url)) return Promise.resolve(new Response('/* ok */', {status: 200, headers: {'Content-Type': 'text/javascript'}}));
      return _origFetch.apply(window, arguments);
    };
  }

  var _origGCS = window.getComputedStyle;
  window.getComputedStyle = function(el, pseudo) {
    var style = _origGCS.call(window, el, pseudo);
    try {
      var cls = ((el.className || '') + ' ' + (el.id || '')).toString().toLowerCase();
      if (/adsbox|ad-placement|ads-placeholder|adsbygoogle|ad_unit|ad-slot|adnxs/i.test(cls)) {
        return new Proxy(style, { get: function(t, p) {
          if (p === 'height') return '90px'; if (p === 'display') return 'block';
          if (p === 'visibility') return 'visible'; if (p === 'opacity') return '1';
          var v = t[p]; return typeof v === 'function' ? v.bind(t) : v;
        }});
      }
    } catch(e) {}
    return style;
  };

  var _antiPhrases = ['adblock','ad block','adblocker','ad blocker','disable your ad',
    'turn off your ad','whitelist','please allow ads','please disable','detected ad',
    'يرجى إيقاف','إيقاف مانع','تعطيل مانع'];
  function _hasAntiPhrase(text) { var t = text.toLowerCase(); return _antiPhrases.some(function(p){ return t.indexOf(p) !== -1; }); }

  function _nukeAntiAdblock() {
    var sel = ['[class*="adblock"],[id*="adblock"]','[class*="ad-block"],[id*="ad-block"]',
      '[class*="adblocker"],[id*="adblocker"]','[class*="anti-ad"],[id*="anti-ad"]',
      '[class*="blockad"],[id*="blockad"]','.ab-modal,.ab-overlay,.adblock-notice,.adBlockNotice',
      '#adblock-warning,#ab-warning,#adblock-overlay'].join(',');
    try { document.querySelectorAll(sel).forEach(function(el){ try { el.remove(); } catch(e) {} }); } catch(e) {}
    try {
      var all = document.querySelectorAll('div,section,aside,dialog,article,span');
      for (var i = 0; i < all.length; i++) {
        var el = all[i];
        try {
          var cs = _origGCS.call(window, el);
          var zIdx = parseInt(cs.zIndex || '0');
          var isOverlay = (cs.position === 'fixed' || cs.position === 'absolute') && zIdx > 999 && cs.display !== 'none';
          if (!isOverlay) continue;
          var txt = (el.textContent || '');
          if (txt.length > 10 && txt.length < 2000 && _hasAntiPhrase(txt)) el.remove();
        } catch(e) {}
      }
    } catch(e) {}
    try {
      if (document.body && !window.__asdForcedFs && !document.fullscreenElement) {
        var bs = _origGCS.call(window, document.body);
        if (bs.overflow === 'hidden') document.body.style.removeProperty('overflow');
      }
    } catch(e) {}
  }
  function _bakeBaits() {
    try {
      document.querySelectorAll('.adsbox,#adsbox,.ad-placement,#ad-placement,.ads,.ad-unit,ins.adsbygoogle').forEach(function(el){
        if (el.offsetHeight === 0) el.style.cssText += ';height:1px!important;display:block!important;visibility:visible!important;';
      });
    } catch(e) {}
  }
  [300, 800, 1500, 3000, 6000].forEach(function(ms){ setTimeout(_nukeAntiAdblock, ms); });
  setTimeout(_bakeBaits, 600); setTimeout(_bakeBaits, 2000);
  try {
    new MutationObserver(function(muts) {
      var hasNew = muts.some(function(m){ return m.addedNodes.length > 0; });
      if (hasNew) { setTimeout(_nukeAntiAdblock, 50); setTimeout(_nukeAntiAdblock, 200); }
    }).observe(document.documentElement, {childList: true, subtree: true});
  } catch(e) {}
})();
""";

  static const String _ads = r"""
(function(){
  'use strict';

  window.__asdAdsInstalled = true;
  window.__asdStableUrl = window.__asdStableUrl || location.href;

  var adDomains = [
    'popads','popcash','adcash','doubleclick','googlesyndication','adnxs',
    'exoclick','juicyads','adsterra','propellerads','trafficjunky','hilltopads',
    'richpush','zeropark','revcontent','taboola','outbrain','mgid','rubiconproject',
    'openx','criteo','b7510','oyo4d','bvtpk','omoonsih','jnbhi','sourshaped',
    'tfnvuckb','waust','whacmoltibsay','rtmark','fundingchoices','popunder',
    'clickunder','trafficshop','plugrush','imasdk','pyppo','pop.pro','trffk',
    'g2afse','llvpn','melbet.org','melbet','onclickads','onclickmega','popmyads','ad-maven',
    'adspyglass','pushads','push-notifications','prplads','adclick','adserver',
    'adform','adskeeper','profitablerate','highperformanceformat','xmlppcbuzz',
    'qpon','dbm','adservice','pagead2'
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
      /(^|[.\/_-])(ads?|adserver|popunder|popads|pushads?|clickunder|trk|track|traffic)([.\/_-]|$)/i.test(s);
  }

  function stableHost() { return hostOf(window.__asdStableUrl || location.href); }

  function allowedExternalHost(host) {
    if (!host) return false;
    return /(^|\.)(egydead\.pics|egydead\.live|tv[0-9]*\.egydead\.live|c4u[0-9a-z_-]*\.sbs|streamruby\.com|stmruby\.com|mixdrop\.[a-z]+|krakenfiles\.com|megaup\.net|1fichier\.com|1cloudfile\.com|vikingfile\.com|koramaup\.com|bowfile\.com|doodstream\.com)$/i.test(host) ||
      host.indexOf('streamruby') !== -1 ||
      host.indexOf('stmruby') !== -1 ||
      host.indexOf('cdnz.online') !== -1 ||
      host.indexOf('okcdn') !== -1;
  }

  function isBadNavigation(url) {
    if (!url) return false;
    var s = (url || '').toString();
    var l = lower(s);
    if (l.indexOf('javascript:') === 0 || l.indexOf('intent:') === 0 ||
        l.indexOf('market:') === 0 || l.indexOf('tg:') === 0) return true;
    if (isAdUrl(s)) return true;
    var h = hostOf(s);
    var sh = stableHost();
    if (h && sh && h !== sh && !allowedExternalHost(h)) return true;
    return false;
  }

  function rememberStable() {
    try { if (!isBadNavigation(location.href)) window.__asdStableUrl = location.href; } catch(e) {}
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

  function isMyButtons(el) {
    try {
      var p = el;
      for (var i = 0; p && i < 10; i++, p = p.parentElement) {
        var id = lower(p.id || '');
        if (id.indexOf('__asd_site_player_actions') !== -1 ||
            id.indexOf('__asd_site_player_play_btn') !== -1 ||
            id.indexOf('__asd_site_player_download_btn') !== -1) return true;
      }
    } catch(e) {}
    return false;
  }

  function isPlayerNode(el) {
    if (isMyButtons(el)) return true;
    var d = 0;
    while (el && d < 10) {
      try {
        var blob = lower((el.className || '') + ' ' + (el.id || '') + ' ' + (el.tagName || ''));
        if (blob.indexOf('jw') !== -1 || blob.indexOf('vjs') !== -1 ||
            blob.indexOf('plyr') !== -1 || blob.indexOf('player') !== -1 ||
            blob.indexOf('video') !== -1 || blob.indexOf('media') !== -1 ||
            (el.tagName && lower(el.tagName) === 'video')) return true;
      } catch(e) {}
      el = el.parentElement;
      d++;
    }
    return false;
  }

  function visible(el) {
    try {
      if (!el || !el.getBoundingClientRect) return false;
      var r = el.getBoundingClientRect();
      var cs = getComputedStyle(el);
      return r.width > 8 && r.height > 8 && cs.display !== 'none' &&
        cs.visibility !== 'hidden' && parseFloat(cs.opacity || '1') > 0.05;
    } catch(e) { return false; }
  }

  function closeText(el) {
    var txt = lower((el.textContent || el.innerText || '').trim());
    var aria = lower(el.getAttribute && (el.getAttribute('aria-label') || el.getAttribute('title') || ''));
    var blob = (txt + ' ' + aria + ' ' + lower((el.className || '') + ' ' + (el.id || ''))).trim();
    return blob === 'x' || blob === '×' || blob === '✕' || blob === '✖' ||
      blob.indexOf('close') !== -1 || blob.indexOf('dismiss') !== -1 ||
      blob.indexOf('skip') !== -1 || blob.indexOf('اغلاق') !== -1 ||
      blob.indexOf('إغلاق') !== -1 || blob.indexOf('تخطي') !== -1 ||
      blob.indexOf('لا شكرا') !== -1 || blob.indexOf('no thanks') !== -1;
  }

  function looksPopText(el) {
    try {
      var blob = lower(
        (el.innerText || '') + ' ' + (el.textContent || '') + ' ' +
        (el.className || '') + ' ' + (el.id || '') + ' ' +
        (el.src || '') + ' ' + (el.outerHTML || '').slice(0, 900)
      );
      return blob.indexOf('popup') !== -1 || blob.indexOf('popunder') !== -1 ||
        blob.indexOf('qpon') !== -1 || blob.indexOf('dbm') !== -1 ||
        blob.indexOf('adservice') !== -1 || blob.indexOf('googlesyndication') !== -1 ||
        blob.indexOf('doubleclick') !== -1 || blob.indexOf('voice message') !== -1 ||
        blob.indexOf('الرسائل الصوتية') !== -1 || blob.indexOf('لديك مكافأة') !== -1 ||
        blob.indexOf('مبروك') !== -1 || blob.indexOf('bonanza') !== -1 ||
        blob.indexOf('spin') !== -1 || blob.indexOf('sales') !== -1 ||
        blob.indexOf('antivirus') !== -1 ||
        blob.indexOf('norton') !== -1 ||
        blob.indexOf('protection') !== -1 ||
        blob.indexOf('turned on') !== -1 ||
        blob.indexOf('total protection') !== -1 ||
        blob.indexOf('play.google') !== -1;
    } catch(e) { return false; }
  }

  function isBigPopupLayer(el) {
    if (!el || isPlayerNode(el) || !visible(el)) return false;
    try {
      if (el === document.body || el === document.documentElement) return false;
      var cs = getComputedStyle(el);
      var r = el.getBoundingClientRect();
      var area = r.width * r.height;
      var screen = Math.max(1, innerWidth * innerHeight);
      var z = parseInt(cs.zIndex || '0', 10) || 0;
      var blob = lower((el.className || '') + ' ' + (el.id || '') + ' ' + (el.getAttribute('role') || ''));
      var fixed = cs.position === 'fixed' || cs.position === 'absolute' || cs.position === 'sticky';
      var looksPopup = /popup|pop|modal|overlay|advert|ads?|banner|interstitial|promo|sponsor|lightbox|backdrop/.test(blob) || looksPopText(el);
      var hasBadLink = false;
      try {
        el.querySelectorAll('a[href],iframe[src]').forEach(function(a){
          var u = (a.href || a.src || '').toString();
          if (isBadNavigation(u)) hasBadLink = true;
        });
      } catch(e) {}
      return fixed && (z > 50 || looksPopup || hasBadLink) &&
        (area > screen * 0.10 || looksPopup || hasBadLink) &&
        r.width < innerWidth * 1.02 && r.height < innerHeight * 1.02;
    } catch(e) { return false; }
  }

  function findPlayerAdCardFromClose(btn) {
    try {
      if (!btn || !isPlayerNode(btn) || isMyButtons(btn)) return null;
      var p = btn.parentElement;
      for (var i = 0; p && i < 8; i++, p = p.parentElement) {
        if (p === document.body || p === document.documentElement || isMyButtons(p)) break;
        if (!visible(p)) continue;
        var r = p.getBoundingClientRect();
        if (r.width < 70 || r.height < 35) continue;
        if (r.width > innerWidth * 0.98 && r.height > innerHeight * 0.85) continue;
        if (looksPopText(p)) return p;
      }
    } catch(e) {}
    return null;
  }

  function isPlayerAdCloseButton(el) {
    try {
      if (!el || !visible(el) || !isPlayerNode(el) || isMyButtons(el)) return false;
      if (!closeText(el)) return false;
      var blob = lower((el.className || '') + ' ' + (el.id || '') + ' ' +
        (el.getAttribute && ((el.getAttribute('aria-label') || '') + ' ' + (el.getAttribute('title') || '')) || ''));
      if (/play|pause|volume|mute|setting|quality|speed|fullscreen|caption|subtitle|control|jw-icon|vjs-|plyr/.test(blob) &&
          blob.indexOf('close') === -1 && blob.indexOf('dismiss') === -1 && blob.indexOf('mfp-close') === -1) {
        return false;
      }
      return !!findPlayerAdCardFromClose(el);
    } catch(e) { return false; }
  }

  function firePlayerAdClose(el) {
    if (!isPlayerAdCloseButton(el)) return false;
    try {
      var now = Date.now();
      var last = parseInt(el.getAttribute('data-asd-player-ad-close-at') || '0', 10) || 0;
      if (now - last < 5000) return false;
      el.setAttribute('data-asd-player-ad-close-at', String(now));
      var card = findPlayerAdCardFromClose(el);
      rememberStable();
      try {
        var r = el.getBoundingClientRect();
        el.dispatchEvent(new MouseEvent('click', {
          bubbles: true,
          cancelable: true,
          view: window,
          clientX: r.left + r.width / 2,
          clientY: r.top + r.height / 2
        }));
      } catch(e) {}
      try { el.click(); } catch(e) {}
      if (card) {
        setTimeout(function(){
          try {
            if (visible(card) && looksPopText(card)) {
              card.style.setProperty('display','none','important');
              card.style.setProperty('visibility','hidden','important');
              card.style.setProperty('opacity','0','important');
              card.style.setProperty('pointer-events','none','important');
            }
          } catch(e) {}
        }, 650);
      }
      setTimeout(restoreStable, 80);
      return true;
    } catch(e) { return false; }
  }

  function isRewardPopupCard(el) {
    try {
      if (!el || !visible(el) || isMyButtons(el) || isPlayerNode(el)) return false;
      if (el === document.body || el === document.documentElement) return false;
      if (!looksPopText(el)) return false;

      var r = el.getBoundingClientRect();
      if (!r) return false;
      if (r.width < 95 || r.height < 40) return false;
      if (r.width > innerWidth * 0.92 || r.height > innerHeight * 0.72) return false;

      var blob = lower((el.innerText || '') + ' ' + (el.textContent || '') + ' ' +
        (el.className || '') + ' ' + (el.id || '') + ' ' + (el.outerHTML || '').slice(0, 900));

      var hasRewardWords = blob.indexOf('لديك مكافأة') !== -1 ||
        blob.indexOf('مكافأة') !== -1 ||
        blob.indexOf('bonus') !== -1 ||
        blob.indexOf('bonanza') !== -1 ||
        blob.indexOf('spin') !== -1 ||
        blob.indexOf('claim') !== -1 ||
        blob.indexOf('reward') !== -1 ||
        blob.indexOf('antivirus') !== -1 ||
        blob.indexOf('norton') !== -1 ||
        blob.indexOf('protection') !== -1 ||
        blob.indexOf('turned on') !== -1 ||
        blob.indexOf('total protection') !== -1 ||
        blob.indexOf('play.google') !== -1 ||
        blob.indexOf('3200') !== -1 ||
        blob.indexOf('1000') !== -1 ||
        blob.indexOf('تسجل') !== -1 ||
        blob.indexOf('سجل') !== -1;

      return hasRewardWords;
    } catch(e) { return false; }
  }

  function cardKey(el) {
    try {
      var r = el.getBoundingClientRect();
      return [Math.round(r.left), Math.round(r.top), Math.round(r.width), Math.round(r.height)].join('|');
    } catch(e) { return ''; }
  }

  function pickRewardPopupCards(root) {
    var out = [], seen = {};
    try {
      var nodes = (root || document).querySelectorAll('div,section,aside,a,button,span');
      for (var i = 0; i < nodes.length; i++) {
        var el = nodes[i];
        if (!looksPopText(el)) continue;

        var best = null;
        var p = el;
        for (var d = 0; p && d < 6; d++, p = p.parentElement) {
          if (p === document.body || p === document.documentElement || isMyButtons(p)) break;
          if (!isRewardPopupCard(p)) continue;
          var r = p.getBoundingClientRect();
          if (r.width >= 95 && r.height >= 40 &&
              r.width <= innerWidth * 0.92 && r.height <= innerHeight * 0.72) {
            best = p;
          }
        }
        if (!best) continue;
        var key = cardKey(best);
        if (!key || seen[key]) continue;
        seen[key] = true;
        out.push(best);
      }
    } catch(e) {}
    return out;
  }

  function findAdConfirmTarget(card) {
    try {
      var candidates = card.querySelectorAll('button,a,[role="button"],input,div,span');
      var fallback = null;
      for (var i = 0; i < candidates.length; i++) {
        var el = candidates[i];
        if (!visible(el) || isMyButtons(el)) continue;
        var txt = lower(((el.value || '') + ' ' + (el.textContent || el.innerText || '') + ' ' +
          (el.getAttribute && ((el.getAttribute('aria-label') || '') + ' ' + (el.getAttribute('title') || '')) || '')).trim());
        var cls = lower((el.className || '') + ' ' + (el.id || ''));
        var r = el.getBoundingClientRect();
        if (!r || r.width < 22 || r.height < 14) continue;

        if (txt === 'ok' || txt.indexOf(' ok ') !== -1 || txt.indexOf('موافق') !== -1 || txt.indexOf('continue') !== -1 || cls.indexOf('ok') !== -1) {
          return el;
        }
        if (!fallback && (txt.indexOf('cancel') !== -1 || txt.indexOf('close') !== -1 || txt.indexOf('×') !== -1 || txt.indexOf('x') !== -1)) {
          fallback = el;
        }
      }
      return fallback;
    } catch(e) { return null; }
  }

  function clickRewardPopupCard(card) {
    try {
      if (!isRewardPopupCard(card)) return false;
      var now = Date.now();
      var last = parseInt(card.getAttribute('data-asd-reward-card-click-at') || '0', 10) || 0;
      if (now - last < 12000) return false;
      card.setAttribute('data-asd-reward-card-click-at', String(now));

      var target = findAdConfirmTarget(card);
      var r = (target || card).getBoundingClientRect();
      var x = target ? (r.left + r.width / 2) : (r.left + Math.min(r.width * 0.62, r.width - 18));
      var y = target ? (r.top + r.height / 2) : (r.top + Math.min(r.height * 0.55, r.height - 14));
      if (!target) target = document.elementFromPoint(x, y) || card;
      if (!target || isMyButtons(target)) target = card;

      rememberStable();
      try {
        target.dispatchEvent(new MouseEvent('click', {
          bubbles: true,
          cancelable: true,
          view: window,
          clientX: x,
          clientY: y
        }));
      } catch(e) {}
      try { target.click(); } catch(e) {}

      setTimeout(function(){
        try {
          if (visible(card) && looksPopText(card)) {
            card.style.setProperty('display','none','important');
            card.style.setProperty('visibility','hidden','important');
            card.style.setProperty('opacity','0','important');
            card.style.setProperty('pointer-events','none','important');
          }
        } catch(e) {}
      }, 900);
      setTimeout(restoreStable, 100);
      return true;
    } catch(e) { return false; }
  }

  function clickRewardPopups(root) {
    var clicked = false;
    try {
      var cards = pickRewardPopupCards(root || document);
      for (var i = 0; i < cards.length; i++) {
        if (clickRewardPopupCard(cards[i])) clicked = true;
      }
    } catch(e) {}
    return clicked;
  }

  function fireClick(el) {
    if (!el || !visible(el) || isPlayerNode(el)) return false;
    try {
      rememberStable();
      ['pointerdown','mousedown','mouseup','click'].forEach(function(type){
        try { el.dispatchEvent(new MouseEvent(type, {bubbles:true, cancelable:true, view:window})); } catch(e) {}
      });
      try { el.click(); } catch(e) {}
      setTimeout(restoreStable, 20);
      setTimeout(restoreStable, 120);
      return true;
    } catch(e) { return false; }
  }

  function hidePopupLayer(n) {
    try { n.style.setProperty('display','none','important'); } catch(e) {}
    try { n.style.setProperty('visibility','hidden','important'); } catch(e) {}
    try { n.style.setProperty('pointer-events','none','important'); } catch(e) {}
    try { n.style.setProperty('opacity','0','important'); } catch(e) {}
    try { if (n.parentElement) n.parentElement.removeChild(n); } catch(e) {}
  }

  function autoClosePopups(root) {
    root = root || document;
    rememberStable();

    try { clickRewardPopups(root); } catch(e) {}

    try {
      var closeCandidates = root.querySelectorAll(
        '[aria-label*="close" i],[title*="close" i],[class*="close" i],[id*="close" i],' +
        '[data-dismiss],[data-bs-dismiss],.mfp-close,.modal-close,.btn-close,' +
        'button,a,[role="button"]'
      );
      for (var i = 0; i < closeCandidates.length; i++) {
        var el = closeCandidates[i];
        if (!visible(el)) continue;
        if (isPlayerNode(el)) {
          continue;
        }
        if (closeText(el)) fireClick(el);
      }
    } catch(e) {}

    try {
      var nodes = root.querySelectorAll('div,section,aside,dialog');
      for (var j = 0; j < nodes.length; j++) {
        var n = nodes[j];
        if (isBigPopupLayer(n)) hidePopupLayer(n);
      }
    } catch(e) {}

    restoreStable();
  }

  var _origOpen = window.open;
  var __asdLastBlankOpenAt = 0;
  var __asdLastAnyOpenAt = 0;
  window.open = function(url, target, features) {
    var now = Date.now();
    var raw = (url == null ? '' : url.toString()).trim();

    if (!raw) {
      if (now - __asdLastBlankOpenAt < 8000) return null;
      __asdLastBlankOpenAt = now;
      return null;
    }

    if (isBadNavigation(raw)) { restoreStable(); return null; }
    if (now - __asdLastAnyOpenAt < 900) return null;
    __asdLastAnyOpenAt = now;
    return _origOpen ? _origOpen.call(window, raw, target, features) : null;
  };

  try {
    var __asdNativeReload = window.location.reload.bind(window.location);
    function __asdCloudflareChallengeActive() {
      try {
        var href = lower(location.href || '');
        var title = lower(document.title || '');
        if (href.indexOf('/cdn-cgi/') !== -1 || href.indexOf('challenges.cloudflare.com') !== -1) return true;
        if (title.indexOf('just a moment') !== -1 || title.indexOf('attention required') !== -1) return true;
        if (document.querySelector('#challenge-stage,.cf-turnstile,iframe[src*="challenges.cloudflare.com"],form[action*="/cdn-cgi/"],input[name="cf-turnstile-response"]')) return true;
        var bodyText = lower((document.body && document.body.innerText || '').slice(0, 1800));
        return bodyText.indexOf('verify you are human') !== -1 ||
          bodyText.indexOf('checking your browser') !== -1 ||
          bodyText.indexOf('security of your connection') !== -1;
      } catch(e) { return false; }
    }
    window.location.reload = function(forceGet){
      if (__asdCloudflareChallengeActive()) return __asdNativeReload(forceGet);
      restoreStable();
      return;
    };
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
        var oc = lower((el.getAttribute('onclick') || '') + ' ' +
          (el.getAttribute('onmousedown') || '') + ' ' +
          (el.getAttribute('onpointerdown') || ''));
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
    if (isPlayerNode(el)) return true;
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
    setTimeout(restoreStable, 80);
  }

  ['click'].forEach(function(evt) {
    try { document.addEventListener(evt, captureClick, true); } catch(e) {}
  });

  [1200, 3500, 7000].forEach(function(ms) {
    setTimeout(function(){ stripInlinePopups(document); autoClosePopups(document); }, ms);
  });
  setInterval(function(){ stripInlinePopups(document); autoClosePopups(document); }, 6500);

  try {
    var __asdPopupTimer = null;
    new MutationObserver(function(muts) {
      var changed = false;
      muts.forEach(function(m) {
        m.addedNodes.forEach(function(node) {
          if (node.nodeType === 1) changed = true;
        });
      });
      if (changed) {
        if (__asdPopupTimer) clearTimeout(__asdPopupTimer);
        __asdPopupTimer = setTimeout(function(){
          __asdPopupTimer = null;
          stripInlinePopups(document);
          autoClosePopups(document);
        }, 900);
      }
    }).observe(document.documentElement, { childList: true, subtree: true });
  } catch(e) {}

  var __asdLastManualPopupSweep = 0;
  window.__asdAutoClosePopups = function(){
    var now = Date.now();
    if (now - __asdLastManualPopupSweep < 2500) return true;
    __asdLastManualPopupSweep = now;
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

  static const String _melbetBottomPopupStealth = r"""
(function(){
  'use strict';
  if (window.__asdMelbetBottomPopupStealthV1) return;
  window.__asdMelbetBottomPopupStealthV1 = true;

  function lower(v){ return (v || '').toString().toLowerCase(); }
  function visible(el){
    try {
      if (!el || !el.getBoundingClientRect) return false;
      var r = el.getBoundingClientRect();
      var cs = getComputedStyle(el);
      return r.width > 8 && r.height > 8 && cs.display !== 'none' &&
        cs.visibility !== 'hidden' && parseFloat(cs.opacity || '1') > 0.05;
    } catch(e) { return false; }
  }
  function cloudflareActive(){
    try {
      var href = lower(location.href || '');
      var title = lower(document.title || '');
      if (href.indexOf('/cdn-cgi/') !== -1 || href.indexOf('challenges.cloudflare.com') !== -1) return true;
      if (title.indexOf('just a moment') !== -1 || title.indexOf('attention required') !== -1) return true;
      if (document.querySelector('#challenge-stage,.cf-turnstile,iframe[src*="challenges.cloudflare.com"],form[action*="/cdn-cgi/"],input[name="cf-turnstile-response"]')) return true;
      var text = lower((document.body && document.body.innerText || '').slice(0, 1800));
      return text.indexOf('verify you are human') !== -1 ||
        text.indexOf('checking your browser') !== -1 ||
        text.indexOf('security of your connection') !== -1 ||
        text.indexOf('التحقق من أنك إنسان') !== -1 ||
        text.indexOf('تحقق من أنك إنسان') !== -1;
    } catch(e) { return false; }
  }
  function nearBottomFixedish(el){
    try {
      if (!visible(el) || el === document.body || el === document.documentElement) return false;
      var r = el.getBoundingClientRect();
      var cs = getComputedStyle(el);
      var pos = lower(cs.position || '');
      var bottom = Math.abs(innerHeight - r.bottom) < 95 || (cs.bottom && cs.bottom !== 'auto');
      var wide = r.width >= Math.max(180, innerWidth * 0.45);
      var bannerHeight = r.height >= 45 && r.height <= innerHeight * 0.70;
      var lowerHalf = r.top >= innerHeight * 0.20;
      var z = parseInt(cs.zIndex || '0', 10) || 0;
      return wide && bannerHeight && lowerHalf && bottom &&
        (pos === 'fixed' || pos === 'sticky' || pos === 'absolute' || z >= 20);
    } catch(e) { return false; }
  }
  function hasMelbetRef(el){
    try {
      var blob = lower(
        (el.getAttribute && (el.getAttribute('href') || '')) + ' ' +
        (el.getAttribute && (el.getAttribute('src') || '')) + ' ' +
        (el.getAttribute && (el.getAttribute('data-href') || '')) + ' ' +
        (el.getAttribute && (el.getAttribute('data-url') || '')) + ' ' +
        (el.getAttribute && (el.getAttribute('data-src') || '')) + ' ' +
        (el.getAttribute && (el.getAttribute('onclick') || '')) + ' ' +
        (el.getAttribute && (el.getAttribute('onmousedown') || '')) + ' ' +
        (el.getAttribute && (el.getAttribute('onpointerdown') || '')) + ' ' +
        (el.className || '') + ' ' + (el.id || '')
      );
      if (blob.indexOf('melbet') !== -1 || blob.indexOf('melbet.org') !== -1) return true;
      var html = lower((el.outerHTML || '').slice(0, 2800));
      return html.indexOf('melbet') !== -1 || html.indexOf('melbet.org') !== -1;
    } catch(e) { return false; }
  }
  function hide(el){
    try { el.style.setProperty('display','none','important'); } catch(e) {}
    try { el.style.setProperty('visibility','hidden','important'); } catch(e) {}
    try { el.style.setProperty('opacity','0','important'); } catch(e) {}
    try { el.style.setProperty('pointer-events','none','important'); } catch(e) {}
    try { if (el.parentElement) el.parentElement.removeChild(el); } catch(e) {}
  }
  function bestPopupCard(start){
    var best = start;
    try {
      var p = start;
      for (var i = 0; p && i < 9; i++, p = p.parentElement) {
        if (p === document.body || p === document.documentElement) break;
        if (!visible(p)) continue;
        if (nearBottomFixedish(p) && hasMelbetRef(p)) return p;
        if (hasMelbetRef(p)) best = p;
      }
    } catch(e) {}
    return best;
  }
  function scan(root){
    if (cloudflareActive()) return false;
    root = root || document;
    var removed = false;
    try {
      var direct = root.querySelectorAll(
        'a[href*="melbet" i],iframe[src*="melbet" i],script[src*="melbet" i],' +
        '[onclick*="melbet" i],[onmousedown*="melbet" i],[onpointerdown*="melbet" i],' +
        '[data-href*="melbet" i],[data-url*="melbet" i],[data-src*="melbet" i],' +
        '[class*="melbet" i],[id*="melbet" i]'
      );
      for (var i = 0; i < direct.length; i++) {
        var el = direct[i];
        if (!el) continue;
        var card = bestPopupCard(el);
        hide(card || el);
        removed = true;
      }
    } catch(e) {}
    try {
      var candidates = root.querySelectorAll('div,section,aside,dialog,article,figure,a');
      for (var j = 0; j < candidates.length; j++) {
        var n = candidates[j];
        if (!nearBottomFixedish(n)) continue;
        if (!hasMelbetRef(n)) continue;
        hide(n);
        removed = true;
      }
    } catch(e) {}
    return removed;
  }

  [90, 180, 360, 700, 1400, 2800, 5200, 9000].forEach(function(ms){
    setTimeout(function(){ try { scan(document); } catch(e) {} }, ms);
  });

  try {
    var timer = null;
    new MutationObserver(function(muts){
      if (cloudflareActive()) return;
      var touched = false;
      for (var i = 0; i < muts.length; i++) {
        if (muts[i].addedNodes && muts[i].addedNodes.length) { touched = true; break; }
      }
      if (!touched) return;
      if (timer) clearTimeout(timer);
      timer = setTimeout(function(){ timer = null; try { scan(document); } catch(e) {} }, 70);
    }).observe(document.documentElement, {childList:true, subtree:true});
  } catch(e) {}

  window.__asdHideMelbetBottomPopupNow = function(){
    try { return scan(document); } catch(e) { return false; }
  };
})();
""";

  static const String _css = r"""
(function(){
  var _host = (window.location && window.location.host || '').toLowerCase();
  var _mainSite = _host.indexOf('egydead') !== -1 || _host.indexOf('c4u') !== -1;
  if (!_mainSite) return;
  var s=document.createElement('style');
  s.textContent=`
    .jw-dialog,.jw-dialog-overlay,[class*="ad-dialog"],[id*="ad-dialog"],
    [class*="popup"]:not([class*="player"]):not([class*="video"]):not([class*="jw"]):not([class*="vjs"]):not([class*="plyr"]),
    [id*="popup"]:not([id*="player"]):not([id*="video"]):not([id*="jw"]):not([id*="vjs"]),
    .play-overlay-ad,.ad-overlay,[class*="ad-overlay"],[class*="adOverlay"],
    .uq-ad,.uq-overlay,#outbrain_widget,.OUTBRAIN,[id*="taboola"],[class*="taboola"],
    [id*="adnxs"],[class*="adnxs"],[id*="exo_"],[class*="exo-"],[id*="pop_"],[class*="pop-up"],
    [id*="overlay_ad"],[class*="overlay_ad"],.content-locker,.link-locker,
    [class*="locker"],[id*="locker"]{display:none!important;visibility:hidden!important;opacity:0!important;pointer-events:none!important;}
  `;
  (document.head||document.documentElement).appendChild(s);
})();
""";

  static const String _hideServers = r"""
(function(){
  var _host = (window.location && window.location.host || '').toLowerCase();
  var _mainSite = _host.indexOf('egydead') !== -1 || _host.indexOf('c4u') !== -1;
  if (!_mainSite) return;
  var href = window.location.href.toLowerCase();
  var isWatchPage = href.indexOf('/watch/') !== -1 || href.indexOf('wat=1') !== -1 ||
    document.querySelector('.servers, .server-list, .servers-list, ul.servers, ul.server-list, [class*="server"]');
  if (!isWatchPage) return;

  var keepVisible = ['krakenfiles','megaup','mixdrop','1fichier','vikingfile','koramaup','1cloudfile','bowfile','doodstream','dooood','earnvids','تحميل مباشر','متعدد الجودات'];

  function restoreDownloadLinks() {
    var links = document.querySelectorAll('a, button, li, [class*="download-link"], [class*="download"], [id*="download"]');
    links.forEach(function(el) {
      var text = (el.textContent || el.innerText || '').toLowerCase();
      var linkHref = (el.href || el.getAttribute('data-link') || el.getAttribute('data-url') || el.getAttribute('data-src') || '').toLowerCase();
      var matched = keepVisible.some(function(s){ return text.indexOf(s) !== -1 || linkHref.indexOf(s) !== -1; });
      if (!matched) return;
      el.style.setProperty('display','', 'important');
      el.style.setProperty('visibility','visible','important');
      el.style.setProperty('opacity','1','important');
      el.style.setProperty('pointer-events','auto','important');
    });
  }
  restoreDownloadLinks();
  setInterval(restoreDownloadLinks, 1200);
})();
""";


  static const String _sitePlayerActionsOverlay = r"""
(function(){
  'use strict';
  if (window.__asdSitePlayerActionsV2) return;
  window.__asdSitePlayerActionsV2 = true;

  function lower(v) { return (v || '').toString().toLowerCase(); }

  function looksLikeAdText(el) {
    try {
      var t = lower((el.innerText || el.textContent || '') + ' ' + (el.className || '') + ' ' + (el.id || '') + ' ' + (el.src || ''));
      return t.indexOf('الرسائل الصوتية') !== -1 ||
        t.indexOf('voice message') !== -1 ||
        t.indexOf('dbm') !== -1 ||
        t.indexOf('adservice') !== -1 ||
        t.indexOf('googlesyndication') !== -1 ||
        t.indexOf('doubleclick') !== -1 ||
        t.indexOf('qpon') !== -1 ||
        t.indexOf('popup') !== -1 ||
        t.indexOf('popunder') !== -1;
    } catch(e) {
      return false;
    }
  }

  function cleanupAnnoyingAds() {
    try {
      var nodes = document.querySelectorAll('div,section,aside,iframe,ins');
      for (var i = 0; i < nodes.length; i++) {
        var el = nodes[i];
        if (!el || el.id === '__asd_site_player_actions') continue;
        if (!looksLikeAdText(el)) continue;
        var r = el.getBoundingClientRect ? el.getBoundingClientRect() : null;
        if (!r) continue;
        if (r.width > 80 && r.height > 30) {
          el.style.setProperty('display','none','important');
          el.style.setProperty('visibility','hidden','important');
          el.style.setProperty('opacity','0','important');
          el.style.setProperty('pointer-events','none','important');
        }
      }
    } catch(e) {}
  }

  function visibleRect(el) {
    if (!el || !el.getBoundingClientRect) return null;
    try {
      var s = getComputedStyle(el);
      if (s.display === 'none' || s.visibility === 'hidden' || Number(s.opacity || '1') <= 0.04) return null;
    } catch(e) {}
    var r = el.getBoundingClientRect();
    if (!r || r.width < 180 || r.height < 90) return null;
    return r;
  }

  function badContainer(el) {
    try {
      var t = lower((el.innerText || el.textContent || '') + ' ' + (el.className || '') + ' ' + (el.id || ''));
      if (t.indexOf('سيرفرات التحميل') !== -1 ||
          t.indexOf('جميع الجودات') !== -1 ||
          t.indexOf('حمل الان') !== -1 ||
          t.indexOf('حمل الآن') !== -1 ||
          t.indexOf('تحميل مباشر') !== -1 ||
          t.indexOf('رجوع للموضوع الأصلي') !== -1 ||
          t.indexOf('الرسائل الصوتية') !== -1) return true;
    } catch(e) {}
    return false;
  }

  function scoreCandidate(el) {
    var r = visibleRect(el);
    if (!r) return -1;
    if (looksLikeAdText(el) || badContainer(el)) return -1;

    var tag = lower(el.tagName);
    var blob = lower((el.className || '') + ' ' + (el.id || '') + ' ' + (el.src || '') + ' ' + (el.getAttribute && (el.getAttribute('data-src') || '') || ''));
    var area = r.width * r.height;
    var score = area;

    if (tag === 'iframe' || tag === 'video') score += 900000;
    if (/player|video|embed|watch|stream|jw|vjs|plyr|dplayer/.test(blob)) score += 700000;
    if (/ad|ads|banner|popup|google|doubleclick|qpon|voice|dbm/.test(blob)) score -= 1500000;

    var docTop = r.top + (window.scrollY || window.pageYOffset || 0);
    if (docTop > 1400) score -= 600000;

    return score;
  }

  function pickPlayerElement() {
    cleanupAnnoyingAds();

    try {
      var oldPlayer = window.__asdLastSitePlayerElement;
      if (oldPlayer && document.contains(oldPlayer)) return oldPlayer;
      var marked = document.querySelector('[data-asd-site-player-mini="1"]');
      if (marked && document.contains(marked)) {
        window.__asdLastSitePlayerElement = marked;
        return marked;
      }
    } catch(e) {}

    var selectors = [
      '.jwplayer','.video-js','.plyr','.dplayer','.mejs-container',
      '#player','[id*="player"]','[class*="player"]',
      'iframe[src]','video'
    ];

    var best = null, bestScore = -1;
    for (var s = 0; s < selectors.length; s++) {
      try {
        var nodes = document.querySelectorAll(selectors[s]);
        for (var i = 0; i < nodes.length; i++) {
          var el = nodes[i];
          var sc = scoreCandidate(el);
          if (sc > bestScore) {
            bestScore = sc;
            best = el;
          }
        }
      } catch(e) {}
    }

    if (!best) return null;

    var container = best;
    try {
      var r = best.getBoundingClientRect();
      var p = best.parentElement;
      var depth = 0;
      while (p && p !== document.body && depth < 4) {
        var pr = p.getBoundingClientRect ? p.getBoundingClientRect() : null;
        if (!pr) break;
        if (badContainer(p) || looksLikeAdText(p)) break;
        var closeWidth = Math.abs(pr.width - r.width) < Math.max(80, r.width * 0.25);
        var closeHeight = pr.height <= r.height + 180;
        if (closeWidth && closeHeight) container = p;
        p = p.parentElement;
        depth++;
      }
    } catch(e) {}

    return container;
  }

  function iconPlay() {
    return '<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M8 6.5v11l9-5.5-9-5.5Z" fill="currentColor"/></svg>';
  }

  function iconDownload() {
    return '<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M12 4v9m0 0 3.5-3.5M12 13 8.5 9.5M5 18h14" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>';
  }

  function makeButton(id, label, icon, handlerName) {
    var btn = document.getElementById(id);
    if (!btn) {
      btn = document.createElement('button');
      btn.id = id;
      btn.type = 'button';
      btn.addEventListener('click', function(ev){
        ev.preventDefault();
        ev.stopPropagation();
        try { window.flutter_inappwebview.callHandler(handlerName); } catch(e) {}
      }, true);
    }

    btn.innerHTML = '<span style="display:inline-flex;width:25px;height:25px;flex:0 0 25px">' + icon + '</span><span>' + label + '</span>';
    btn.style.cssText = [
      'height:120px',
      'min-height:120px',
      'flex:1 1 0',
      'width:auto',
      'margin:0',
      'padding:0 12px',
      'border:none',
      'outline:none',
      'border-radius:0',
      'display:flex',
      'align-items:center',
      'justify-content:center',
      'gap:9px',
      'font-size:18px',
      'font-weight:900',
      'color:#fff',
      'background:#2e9b34',
      'box-shadow:none',
      'pointer-events:auto',
      'touch-action:manipulation',
      'opacity:1'
    ].join(';');

    return btn;
  }

  function ensureRoot() {
    var root = document.getElementById('__asd_site_player_actions');
    if (!root) {
      root = document.createElement('div');
      root.id = '__asd_site_player_actions';
    }

    root.style.cssText = [
      'display:flex',
      'flex-direction:row',
      'align-items:stretch',
      'justify-content:stretch',
      'width:100%',
      'height:120px',
      'min-height:120px',
      'margin:0 0 12px 0',
      'padding:0',
      'gap:0',
      'z-index:50',
      'position:relative',
      'direction:rtl',
      'background:#000',
      'overflow:hidden',
      'border-radius:0',
      'box-sizing:border-box'
    ].join(';');

    var play = makeButton('__asd_site_player_play_btn', 'مشاهدة', iconPlay(), 'onOverlayPlayTap');
    var download = makeButton('__asd_site_player_download_btn', 'تحميل', iconDownload(), 'onOverlayDownloadTap');

    if (!root.contains(play)) root.appendChild(play);
    if (!root.contains(download)) root.appendChild(download);

    return root;
  }

  function ensureSitePlayerMiniMode(player) {
    try {
      var mask = document.getElementById('__asd_site_player_black_mask');
      if (mask) mask.style.setProperty('display','none','important');

      if (!player || !player.parentElement) return;

      window.__asdLastSitePlayerElement = player;
      try { player.setAttribute('data-asd-site-player-mini', '1'); } catch(e) {}

      var oldWidth = 0;
      try {
        var r = player.getBoundingClientRect();
        oldWidth = Math.round(r.width || 0);
        if (oldWidth > 80) window.__asdLastSitePlayerWidth = oldWidth;
      } catch(e) {}

      var parent = player.parentElement;
      try {
        var ps = getComputedStyle(parent);
        if (ps.position === 'static' || !ps.position) {
          parent.style.setProperty('position', 'relative', 'important');
        }
      } catch(e) {}

      var tinyStyle = [
        'display:block',
        'width:1px',
        'max-width:1px',
        'min-width:1px',
        'height:1px',
        'max-height:1px',
        'min-height:1px',
        'opacity:0.01',
        'overflow:hidden',
        'pointer-events:none',
        'touch-action:none',
        'position:relative',
        'z-index:0',
        'margin:0',
        'padding:0',
        'border:0',
        'box-sizing:border-box',
        'background:#000'
      ];
      player.style.cssText = tinyStyle.map(function(x){ return x + '!important'; }).join(';');

      try {
        var pr = parent.getBoundingClientRect();
        if (parent !== document.body && parent !== document.documentElement && pr && pr.height > 80 && !parent.querySelector('#__asd_site_player_actions')) {
          var blob = lower((parent.className || '') + ' ' + (parent.id || ''));
          if (/player|video|embed|watch|server|stream|jw|vjs|plyr|dplayer/.test(blob)) {
            parent.style.setProperty('min-height','1px','important');
            parent.style.setProperty('max-height','1px','important');
            parent.style.setProperty('height','1px','important');
            parent.style.setProperty('overflow','hidden','important');
            parent.style.setProperty('background','#000','important');
          }
        }
      } catch(e) {}
    } catch(e) {}
  }

  function update() {
    try {
      cleanupAnnoyingAds();

      var player = pickPlayerElement();
      var root = ensureRoot();

      if (!player || !player.parentElement) {
        root.style.display = 'none';
        return;
      }

      root.style.display = 'flex';

      if (root.parentElement !== player.parentElement || root.previousElementSibling !== player) {
        player.parentElement.insertBefore(root, player.nextSibling);
      }
      var r = player.getBoundingClientRect();
      var rememberedWidth = window.__asdLastSitePlayerWidth || 0;
      if (r && r.width > 80) {
        rememberedWidth = Math.round(r.width);
        window.__asdLastSitePlayerWidth = rememberedWidth;
      }
      root.style.width = rememberedWidth > 80 ? (rememberedWidth + 'px') : '100%';
      ensureSitePlayerMiniMode(player);
    } catch(e) {}
  }

  function insideMiniPlayer(el) {
    try {
      var p = el;
      for (var i = 0; p && i < 12; i++, p = p.parentElement) {
        if (p === window.__asdLastSitePlayerElement) return true;
        if (p.getAttribute && p.getAttribute('data-asd-site-player-mini') === '1') return true;
      }
    } catch(e) {}
    return false;
  }

  function clickPlayerPlay() {
    var selectors = [
      '.jw-icon-display','.jw-icon-playback','.jw-display-icon-container','.jwplayer .jw-icon-playback',
      '.vjs-big-play-button','.vjs-play-control',
      '.plyr__control--overlaid','[data-plyr="play"]',
      '.dplayer-play-icon','.dplayer-play-button',
      'button[aria-label*="play" i]','button[title*="play" i]',
      'video'
    ];
    for (var i = 0; i < selectors.length; i++) {
      try {
        var nodes = document.querySelectorAll(selectors[i]);
        for (var j = 0; j < nodes.length; j++) {
          var el = nodes[j];
          if (looksLikeAdText(el)) continue;
          if (!visibleRect(el) && el.tagName !== 'VIDEO' && !insideMiniPlayer(el)) continue;
          try {
            el.dispatchEvent(new MouseEvent('pointerdown', {bubbles:true,cancelable:true,view:window}));
            el.dispatchEvent(new MouseEvent('mousedown', {bubbles:true,cancelable:true,view:window}));
            el.dispatchEvent(new MouseEvent('mouseup', {bubbles:true,cancelable:true,view:window}));
            el.dispatchEvent(new MouseEvent('click', {bubbles:true,cancelable:true,view:window}));
            if (el.tagName === 'VIDEO') { try { el.play(); } catch(e) {} }
            return true;
          } catch(e) {}
        }
      } catch(e) {}
    }
    return false;
  }

  window.__asdUpdateSitePlayerActions = update;
  window.__asdClickSitePlayerPlay = clickPlayerPlay;

  [250, 650, 1200, 2200, 4000].forEach(function(ms){ setTimeout(update, ms); });
  setInterval(update, 1200);
  try {
    new MutationObserver(function(){ setTimeout(update, 80); }).observe(document.documentElement, {childList:true, subtree:true});
  } catch(e) {}
})();
""";






  static const String _popupClickOnly = r"""
(function(){
  'use strict';
  if (window.__asdPopupBridgeV1) return;
  window.__asdPopupBridgeV1 = true;

  function run() {
    try {
      if (window.__asdAutoClosePopups) window.__asdAutoClosePopups();
    } catch(e) {}
  }

  [1500, 4500, 8500].forEach(function(ms){ setTimeout(run, ms); });
  setInterval(run, 7000);
  try {
    var __asdPopupBridgeTimer = null;
    new MutationObserver(function(){
      if (__asdPopupBridgeTimer) clearTimeout(__asdPopupBridgeTimer);
      __asdPopupBridgeTimer = setTimeout(function(){
        __asdPopupBridgeTimer = null;
        run();
      }, 900);
    }).observe(document.documentElement || document.body, {childList:true, subtree:true});
  } catch(e) {}
})();
""";

  static const String _forcePhoneFullscreen = r"""
(function(){
  if (window.__asdForceFsInstalled) return;
  window.__asdForceFsInstalled = true;
  window.__asdForcedFs = false;
  var style = document.createElement('style');
  style.textContent = `
    html.asd-phone-fs,body.asd-phone-fs{width:100%!important;height:100%!important;overflow:hidden!important;background:#000!important;margin:0!important;padding:0!important;}
    .asd-fs-parent{position:fixed!important;inset:0!important;width:100vw!important;height:100vh!important;max-width:100vw!important;max-height:100vh!important;margin:0!important;padding:0!important;transform:none!important;z-index:2147483645!important;overflow:hidden!important;background:#000!important;border:none!important;border-radius:0!important;}
    .asd-fs-target,.asd-fs-target iframe,.asd-fs-target video,.asd-fs-target .jwplayer,.asd-fs-target .jw-video,.asd-fs-target .jw-media,.asd-fs-target .video-js,.asd-fs-target .vjs-tech,.asd-fs-target .plyr,.asd-fs-target .plyr__video-wrapper,.asd-fs-target .dplayer,.asd-fs-target .mejs-container{position:fixed!important;inset:0!important;width:100vw!important;height:100vh!important;max-width:100vw!important;max-height:100vh!important;min-width:100vw!important;min-height:100vh!important;margin:0!important;padding:0!important;transform:none!important;z-index:2147483647!important;background:#000!important;border:none!important;border-radius:0!important;aspect-ratio:auto!important;box-sizing:border-box!important;}
    .asd-fs-target video,.asd-fs-target .jw-video,.asd-fs-target .vjs-tech{object-fit:contain!important;background:#000!important;}
    .asd-fs-target .jw-controlbar,.asd-fs-target .jw-controls,.asd-fs-target .jw-button-container,.asd-fs-target .jw-icon,.asd-fs-target .jw-slider-container,.asd-fs-target .jw-display-icon-container,.asd-fs-target .jw-display,.asd-fs-target .jw-display-container,.asd-fs-target .vjs-control-bar,.asd-fs-target .vjs-big-play-button,.asd-fs-target .vjs-control,.asd-fs-target .vjs-slider,.asd-fs-target .plyr__controls,.asd-fs-target .plyr__control,.asd-fs-target .dplayer-controller,.asd-fs-target .dplayer-bar,.asd-fs-target .dplayer-icons,.asd-fs-target .mejs__controls,.asd-fs-target [class*="controlbar"],.asd-fs-target [class*="control-bar"],.asd-fs-target [class*="controls"]{pointer-events:auto!important;z-index:2147483647!important;}
    .asd-phone-fs .jwplayer.jw-flag-user-inactive .jw-controlbar,.asd-phone-fs .jwplayer.jw-flag-user-inactive .jw-controls{opacity:0;visibility:hidden;transition:opacity 0.3s ease,visibility 0.3s ease;}
    .asd-fs-hide{opacity:0!important;visibility:hidden!important;pointer-events:none!important;}
  `;
  (document.head || document.documentElement).appendChild(style);

  var currentTarget = null, _stickyWanted = false, _explicitExit = false, _reenterTimer = null;
  function fl(name, value) { try { window.flutter_inappwebview.callHandler(name, value); } catch(e) {} }
  function nativeFsActive() { return !!(document.fullscreenElement || document.webkitFullscreenElement); }
  function isVisible(el) { if (!el || !el.getBoundingClientRect) return false; var r = el.getBoundingClientRect(); return r.width > 120 && r.height > 80; }
  function hasActiveTarget() { return !!(currentTarget && document.contains(currentTarget) && isVisible(currentTarget)); }

  function pickTarget() {
    var selectors = ['.jwplayer','.video-js','.plyr','.dplayer','.mejs-container','#player','[id*="player"]','[class*="player"]','iframe[src]','video'];
    for (var i = 0; i < selectors.length; i++) {
      var els = document.querySelectorAll(selectors[i]);
      for (var j = 0; j < els.length; j++) {
        var el = els[j];
        if (!isVisible(el)) continue;
        if (el.tagName === 'IFRAME' || el.tagName === 'VIDEO' || el.querySelector('video') || el.querySelector('iframe') ||
            selectors[i] === '.jwplayer' || selectors[i] === '.video-js' || selectors[i] === '.plyr' || selectors[i] === '.dplayer') return el;
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
        if (node.tagName === 'VIDEO' || node.tagName === 'IFRAME' || node.querySelector('video') || node.querySelector('iframe') ||
            /player|video|embed|jw|plyr|vjs/i.test((node.id||'')+' '+(node.className||''))) { biggest = node; biggestArea = area; }
      }
    }
    return biggest;
  }

  function markParents(el) { var p = el && el.parentElement, count = 0; while (p && p !== document.body && count < 6) { p.classList.add('asd-fs-parent'); count++; p = p.parentElement; } }
  function unmarkParents(el) { var p = el && el.parentElement, count = 0; while (p && p !== document.body && count < 6) { p.classList.remove('asd-fs-parent'); count++; p = p.parentElement; } }

  function hidePageNoise(enable) {
    var blocks = document.querySelectorAll('header:not([class*="player"]):not([class*="jw"]):not([class*="vjs"]),footer:not([class*="player"]):not([class*="jw"]),nav.navbar,nav.nav,.site-header,.site-footer,.sidebar:not([class*="player"]),.social-share,.share-buttons,.cookie-banner,.gdpr-banner');
    blocks.forEach(function(el){ enable ? el.classList.add('asd-fs-hide') : el.classList.remove('asd-fs-hide'); });
  }

  function applyForcedState() {
    if (!currentTarget) return false;
    window.__asdForcedFs = true;
    document.documentElement.classList.add('asd-phone-fs');
    if (document.body) document.body.classList.add('asd-phone-fs');
    currentTarget.classList.add('asd-fs-target'); markParents(currentTarget); hidePageNoise(true); fl('onForcePhoneFs', true); return true;
  }
  function clearForcedState() {
    window.__asdForcedFs = false;
    document.documentElement.classList.remove('asd-phone-fs');
    if (document.body) document.body.classList.remove('asd-phone-fs');
    hidePageNoise(false);
    if (currentTarget) { currentTarget.classList.remove('asd-fs-target'); unmarkParents(currentTarget); }
    currentTarget = null; fl('onForcePhoneFs', false);
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
  function enterForcedPhoneFs() { currentTarget = pickTarget() || currentTarget; if (!currentTarget) return false; _stickyWanted = true; _explicitExit = false; return applyForcedState(); }
  function exitForcedPhoneFs(force) {
    if (force !== true && _stickyWanted) { scheduleReenter(60); return false; }
    _stickyWanted = false; _explicitExit = true;
    if (_reenterTimer) { clearTimeout(_reenterTimer); _reenterTimer = null; }
    clearForcedState(); return true;
  }

  window.__asdForceFullscreenNow = function() { _stickyWanted = true; _explicitExit = false; return enterForcedPhoneFs(); };
  window.__asdExitForcedFullscreen = function() { return exitForcedPhoneFs(true); };

  document.addEventListener('fullscreenchange', function() {
    var active = nativeFsActive();
    if (active) { enterForcedPhoneFs(); return; }
    if (_explicitExit) { exitForcedPhoneFs(true); return; }
    if (_stickyWanted) { scheduleReenter(30); return; }
    exitForcedPhoneFs(true);
  }, true);
  document.addEventListener('webkitfullscreenchange', function() {
    var active = nativeFsActive();
    if (active) { enterForcedPhoneFs(); return; }
    if (_explicitExit) { exitForcedPhoneFs(true); return; }
    if (_stickyWanted) { scheduleReenter(30); return; }
    exitForcedPhoneFs(true);
  }, true);

  document.addEventListener('click', function(e) {
    var el = e.target && e.target.closest ? e.target.closest('.jw-icon-fullscreen,.vjs-fullscreen-control,[data-plyr="fullscreen"],.plyr__control--overlaid,.plyr__control--fullscreen,[class*="fullscreen"],[id*="fullscreen"],[aria-label*="full"],[title*="Full"],[title*="fullscreen"]') : null;
    if (!el) return;
    var txt = ((el.textContent||'')+' '+(el.getAttribute('aria-label')||'')+' '+(el.getAttribute('title')||'')).toLowerCase();
    var cls = (el.className||'').toString().toLowerCase();
    var dataPlyr = ((el.getAttribute&&el.getAttribute('data-plyr'))||'').toLowerCase();
    var pressed = ((el.getAttribute&&el.getAttribute('aria-pressed'))||'').toLowerCase();
    var isExit = txt.indexOf('exit')!==-1||cls.indexOf('exit-fullscreen')!==-1||pressed==='true';
    var isFull = txt.indexOf('full')!==-1||cls.indexOf('fullscreen')!==-1||dataPlyr==='fullscreen';
    if (!isFull && !isExit) return;
    if (isExit) { _stickyWanted = false; _explicitExit = true; setTimeout(function(){ exitForcedPhoneFs(true); }, 60); return; }
    _stickyWanted = true; _explicitExit = false;
    setTimeout(function(){ enterForcedPhoneFs(); }, 60);
    setTimeout(function(){ enterForcedPhoneFs(); }, 400);
  }, true);
})();
""";

  // ─── FIX: collectQualityOptions — deduplicate by resolution label only, strip bitrate ───
  static const String _fsVid = r"""
(function injectAll(doc, win) {
  'use strict';
  function fl(n, v) {
    try { win.flutter_inappwebview.callHandler(n, v); } catch(e) {
      try { win.top.flutter_inappwebview.callHandler(n, v); } catch(e2) {} }
  }
  win.__asdLastUserGesture = win.__asdLastUserGesture || 0;
  ['pointerdown','touchstart','mousedown','keydown'].forEach(function(evt){ doc.addEventListener(evt, function(){ win.__asdLastUserGesture = Date.now(); }, true); });

  function maybeUrl(url) {
    if (!url || typeof url !== 'string') return null;
    var s = url.trim();
    if (!s || s.indexOf('blob:') === 0) return null;
    var lower = s.toLowerCase();
    if (['.m3u8','.mp4','.mkv','.webm','.m4v','.ts','.mov','.mpd','mime=video','/playlist','/manifest','/hls/'].some(function(x){ return lower.indexOf(x) !== -1; })) return s;
    return null;
  }
  function sendCandidate(url, extra) {
    var clean = maybeUrl(url); if (!clean) return;
    var payload = { url: clean, pageUrl: win.location.href, currentTime: 0, mimeType: null };
    if (extra) { for (var k in extra) payload[k] = extra[k]; }
    fl('onVideoFound', payload);
  }

  function qualityLabelFromText(text) {
    text = (text || '').replace(/\s+/g, ' ').trim();
    var m = text.match(/(?:^|[^0-9])([1-9][0-9]{2,3})\s*p\b/i);
    return m ? (m[1] + 'p') : null;
  }

  function clickEl(el) {
    if (!el) return false;
    try { el.dispatchEvent(new MouseEvent('pointerdown', {bubbles:true,cancelable:true})); } catch(e) {}
    try { el.dispatchEvent(new MouseEvent('mousedown', {bubbles:true,cancelable:true})); } catch(e) {}
    try { el.dispatchEvent(new MouseEvent('mouseup', {bubbles:true,cancelable:true})); } catch(e) {}
    try { el.click(); return true; } catch(e) {} return false;
  }

  function collectQualityOptions() {
    var out = [], seenByRes = {};
    try {
      var nodes = doc.querySelectorAll('a,button,li,div,span');
      for (var i = 0; i < nodes.length; i++) {
        var el = nodes[i]; if (!el || !el.textContent) continue;
        var label = qualityLabelFromText((el.textContent || '') + ' ' + (el.getAttribute && (el.getAttribute('title') || el.getAttribute('aria-label')) || ''));
        if (!label) continue;
        if (seenByRes[label]) continue;
        seenByRes[label] = true;
        var href = (el.href || (el.getAttribute && (el.getAttribute('data-url') || el.getAttribute('data-link') || el.getAttribute('href'))) || '').trim();
        var key = (label + '_' + out.length);
        var selected = /active|current|selected|checked/.test(((el.className || '') + ' ' + (el.parentElement && el.parentElement.className || '')).toLowerCase()) ||
          (el.getAttribute && (el.getAttribute('aria-current') === 'true' || el.getAttribute('aria-selected') === 'true' || el.getAttribute('aria-pressed') === 'true'));
        try { el.setAttribute('data-asd-quality-key', key); } catch(e) {}
        out.push({ label: label, key: key, url: href || '', selected: selected });
      }
    } catch(e) {}
    if (out.length) {
      out.sort(function(a, b) {
        var ra = parseInt((a.label.match(/\d+/) || ['0'])[0]);
        var rb = parseInt((b.label.match(/\d+/) || ['0'])[0]);
        return rb - ra;
      });
      var current = null;
      for (var j = 0; j < out.length; j++) { if (out[j].selected) { current = out[j].label; break; } }
      fl('onQualityOptions', { options: out, current: current });
    }
    return out;
  }

  win.__asdSelectQualityOption = function(key, label, url) {
    try {
      collectQualityOptions();
      var byKey = key ? doc.querySelector('[data-asd-quality-key="' + String(key).replace(/"/g,'\\"') + '"]') : null;
      if (byKey) return clickEl(byKey);
      var nodes = doc.querySelectorAll('a,button,li,div,span');
      for (var i = 0; i < nodes.length; i++) {
        var el = nodes[i];
        var txt = qualityLabelFromText((el.textContent || '') + ' ' + (el.getAttribute && (el.getAttribute('title') || el.getAttribute('aria-label')) || ''));
        var href = (el.href || (el.getAttribute && (el.getAttribute('data-url') || el.getAttribute('data-link') || el.getAttribute('href'))) || '').trim();
        if ((label && txt === label) || (url && href === url)) return clickEl(el);
      }
    } catch(e) {} return false;
  };
  function getVideoInfo(v) {
    var url = maybeUrl(v.currentSrc) || maybeUrl(v.src);
    if (!url) { var srcs = v.querySelectorAll('source'); for (var i = 0; i < srcs.length; i++) { var s = maybeUrl(srcs[i].src || srcs[i].getAttribute('src')); if (s) { url = s; break; } } }
    return { url: url, pageUrl: win.location.href, currentTime: isFinite(v.currentTime) ? v.currentTime : 0,
      duration: isFinite(v.duration) ? v.duration : 0, paused: v.paused, isBlob: !url,
      videoWidth: v.videoWidth || 0, videoHeight: v.videoHeight || 0,
      mimeType: v.currentSrc && v.currentSrc.toLowerCase().indexOf('.m3u8')!==-1 ? 'application/x-mpegURL' :
        (v.currentSrc && v.currentSrc.toLowerCase().indexOf('.mp4')!==-1 ? 'video/mp4' : (v.getAttribute('type') || null))
    };
  }
  try {
    var proto = win.HTMLVideoElement ? win.HTMLVideoElement.prototype : null;
    if (proto && !proto._asd_pip_patched) {
      proto._asd_pip_patched = true;
      var _origPlay = proto.play;
      proto.play = function() {
        var self = this, info = getVideoInfo(self), recentGesture = Date.now() - (win.__asdLastUserGesture || 0) < 1600;
        if (win.__asdNativePlayerActive || win.__asdNativePlayerOpening) { try { self.pause(); self.muted = true; self.volume = 0; } catch(e) {} return Promise.resolve(); }
        if (recentGesture) { try { self.pause(); self.muted = true; self.volume = 0; } catch(e) {} fl('onPlayIntent', info); return Promise.resolve(); }
        return _origPlay ? _origPlay.apply(this, arguments) : Promise.resolve();
      };
      proto.requestPictureInPicture = function() {
        var info = getVideoInfo(this);
        if (info.url) sendCandidate(info.url, info);
        fl('onPip', info);
        return Promise.resolve({ addEventListener: function(){}, removeEventListener: function(){}, dispatchEvent: function(){ return true; }, width: 0, height: 0 });
      };
    }
  } catch(e) {}
  try {
    if (win.Hls && win.Hls.prototype && !win.Hls.prototype._asd_patched) {
      win.Hls.prototype._asd_patched = true;
      var _origLoadSource = win.Hls.prototype.loadSource;
      win.Hls.prototype.loadSource = function(url) { sendCandidate(url, { mimeType: 'application/x-mpegURL' }); return _origLoadSource ? _origLoadSource.apply(this, arguments) : undefined; };
    }
  } catch(e) {}
  function probeJwPlayer() {
    try {
      if (!win.jwplayer) return; var jw = win.jwplayer(); if (!jw) return;
      var item = jw.getPlaylistItem && jw.getPlaylistItem();
      if (item) {
        if (item.file) sendCandidate(item.file, { currentTime: jw.getPosition ? (jw.getPosition()||0) : 0 });
        if (Array.isArray(item.sources)) item.sources.forEach(function(src){ if (!src) return; sendCandidate(src.file||src.src, { currentTime: jw.getPosition?(jw.getPosition()||0):0, mimeType: src.type||null }); });
      }
    } catch(e) {}
  }
  function probeVideoJs() {
    try {
      if (!win.videojs || !win.videojs.getPlayers) return;
      Object.keys(win.videojs.getPlayers()||{}).forEach(function(key){
        try { var p = win.videojs.getPlayers()[key]; if (!p) return; var src = p.currentSource && p.currentSource(); sendCandidate(src&&(src.src||src.file), { currentTime: p.currentTime?(p.currentTime()||0):0, mimeType: src&&(src.type||null) }); } catch(e) {}
      });
    } catch(e) {}
  }
  var _fs = false;
  function onFsChange() { var now = !!(doc.fullscreenElement || doc.webkitFullscreenElement); if (now != _fs) { _fs = now; fl('onFS', now); } }
  doc.addEventListener('fullscreenchange', onFsChange);
  doc.addEventListener('webkitfullscreenchange', onFsChange);

  function setupVideo(v) {
    if (v._asd_vid) return; v._asd_vid = true;
    function pushInfo() { var info = getVideoInfo(v); if (info.url) sendCandidate(info.url, info); fl('onVid', { playing: !v.paused && !v.ended, info: info }); }
    v.addEventListener('play', pushInfo); v.addEventListener('playing', pushInfo);
    v.addEventListener('pause', function(){ fl('onVid', { playing: false, info: getVideoInfo(v) }); });
    v.addEventListener('ended', function(){ fl('onVid', { playing: false, info: getVideoInfo(v) }); });
    v.addEventListener('loadedmetadata', pushInfo); v.addEventListener('loadeddata', pushInfo);
    pushInfo();
    setInterval(function() {
      if (!v.paused && !v.ended && isFinite(v.currentTime)) {
        var info = getVideoInfo(v); if (info.url) sendCandidate(info.url, info);
        fl('onTime', v.currentTime);
        if (v.videoWidth > 0 && v.videoHeight > 0) fl('onVideoDimensions', { width: v.videoWidth, height: v.videoHeight });
      }
    }, 1000);
  }
  function scanVideos(root) { try { (root||doc).querySelectorAll('video').forEach(setupVideo); } catch(e) {} }
  win.__asdCollectMediaNow = function() { scanVideos(doc); probeJwPlayer(); probeVideoJs(); collectQualityOptions(); };
  scanVideos(doc); probeJwPlayer(); probeVideoJs(); collectQualityOptions();
  setInterval(win.__asdCollectMediaNow, 1500);
  new MutationObserver(function(muts) {
    muts.forEach(function(m) { m.addedNodes.forEach(function(node) { if (node.tagName === 'VIDEO') setupVideo(node); if (node.querySelectorAll) node.querySelectorAll('video').forEach(setupVideo); }); });
  }).observe(doc.body || doc.documentElement, {childList: true, subtree: true});
})(document, window);
""";

  static const String _touchFix = r"""
(function(){
  'use strict';
  if (window.__asdTouchFixInstalled) return;
  window.__asdTouchFixInstalled = true;
  var HOLD_MS = 7000, _hideTimer = null, _styleInjected = false;
  var CONTROL_SELS = ['.jw-controlbar','.jw-controls','.jw-button-container','.jw-icon','.jw-slider-container','.jw-text-elapsed','.jw-text-duration','.jw-display-icon-container','.jw-slider-time','.jw-knob','.jw-icon-display','.jw-icon-rewind','.jw-icon-playback','.jw-icon-forward','.jw-icon-fullscreen','.jw-icon-volume','.jw-icon-cast','.jw-icon-settings','.jw-icon-cc','.jw-display','.jw-display-container','.jw-display-icon-next','.vjs-control-bar','.vjs-big-play-button','.vjs-control','.vjs-slider','.vjs-progress-control','.vjs-play-control','.vjs-volume-panel','.vjs-fullscreen-control','.vjs-menu','.plyr__controls','.plyr__control','.plyr__progress','.plyr__time','.plyr__volume','.plyr__menu','.dplayer-controller','.dplayer-bar','.dplayer-icons','.mejs__controls','[class*="controlbar"]','[class*="control-bar"]','[class*="controls"]','[class*="progress"]','[class*="seek"]','[class*="playback"]','[class*="toolbar"]','[role="button"]','[role="slider"]','button','input[type="range"]'];

  function inFs() {
    try { if (window !== window.top) return !!(window.top.__asdForcedFs) || !!(window.top.document && window.top.document.documentElement && window.top.document.documentElement.classList.contains('asd-phone-fs')); } catch(e) {}
    return !!(window.__asdForcedFs || document.fullscreenElement || document.webkitFullscreenElement || (document.documentElement && document.documentElement.classList.contains('asd-phone-fs')));
  }
  function injectStyle() {
    if (_styleInjected) return; _styleInjected = true;
    var s = document.createElement('style'); s.id = 'asd-touch-fix-style';
    s.textContent = 'html.asd-controls-force-visible .jw-controlbar,html.asd-controls-force-visible .jw-controls,html.asd-controls-force-visible .jw-button-container,html.asd-controls-force-visible .jw-icon,html.asd-controls-force-visible .jw-slider-container,html.asd-controls-force-visible .jw-text-elapsed,html.asd-controls-force-visible .jw-text-duration,html.asd-controls-force-visible .jw-display-icon-container,html.asd-controls-force-visible .jw-display,html.asd-controls-force-visible .jw-display-container,html.asd-controls-force-visible .jw-slider-time,html.asd-controls-force-visible .jw-knob,html.asd-controls-force-visible .vjs-control-bar,html.asd-controls-force-visible .vjs-big-play-button,html.asd-controls-force-visible .vjs-control,html.asd-controls-force-visible .vjs-slider,html.asd-controls-force-visible .vjs-progress-control,html.asd-controls-force-visible .plyr__controls,html.asd-controls-force-visible .plyr__control,html.asd-controls-force-visible .plyr__progress,html.asd-controls-force-visible .dplayer-controller,html.asd-controls-force-visible .dplayer-bar,html.asd-controls-force-visible .dplayer-icons,html.asd-controls-force-visible .mejs__controls,html.asd-controls-force-visible [class*="controlbar"],html.asd-controls-force-visible [class*="control-bar"],html.asd-controls-force-visible [class*="controls"],html.asd-controls-force-visible [class*="progress"],html.asd-controls-force-visible [class*="seek"]{opacity:1!important;visibility:visible!important;pointer-events:auto!important;transition-delay:0s!important;}html.asd-controls-force-visible .jwplayer.jw-flag-user-inactive .jw-controlbar,html.asd-controls-force-visible .jwplayer.jw-flag-user-inactive .jw-controls{opacity:1!important;visibility:visible!important;pointer-events:auto!important;}';
    (document.head || document.documentElement).appendChild(s);
  }
  function wakePlayer() {
    try { var mv = new MouseEvent('mousemove', {bubbles:true,cancelable:true,view:window}); document.dispatchEvent(mv); document.querySelectorAll('video,iframe,.jwplayer,.video-js,.plyr,.dplayer').forEach(function(el){ try { el.dispatchEvent(mv); } catch(e) {} }); } catch(e) {}
    try { if (window.jwplayer) { var jw = window.jwplayer(); if (jw && jw.getState && jw.getState() !== 'idle') { var jwEl = document.querySelector('.jwplayer'); if (jwEl) jwEl.dispatchEvent(new MouseEvent('mousemove', {bubbles:true,view:window})); } } } catch(e) {}
    try { document.querySelectorAll('.jwplayer.jw-flag-user-inactive').forEach(function(el){ el.classList.remove('jw-flag-user-inactive'); }); } catch(e) {}
  }
  function forceShowNow() {
    injectStyle();
    document.documentElement.classList.add('asd-controls-force-visible');
    if (document.body) document.body.classList.add('asd-controls-force-visible');
    CONTROL_SELS.forEach(function(sel) {
      try { document.querySelectorAll(sel).forEach(function(el) { el.style.setProperty('opacity','1','important'); el.style.setProperty('visibility','visible','important'); el.style.setProperty('pointer-events','auto','important'); if (el.style.display === 'none') el.style.removeProperty('display'); }); } catch(e) {}
    });
    try { document.querySelectorAll('.jwplayer.jw-flag-user-inactive').forEach(function(el){ el.classList.remove('jw-flag-user-inactive'); }); } catch(e) {}
    wakePlayer();
  }
  function releaseControls() {
    document.documentElement.classList.remove('asd-controls-force-visible');
    if (document.body) document.body.classList.remove('asd-controls-force-visible');
    CONTROL_SELS.forEach(function(sel) { try { document.querySelectorAll(sel).forEach(function(el) { el.style.removeProperty('opacity'); el.style.removeProperty('visibility'); el.style.removeProperty('pointer-events'); }); } catch(e) {} });
  }
  function armHideTimer() { if (_hideTimer) clearTimeout(_hideTimer); _hideTimer = setTimeout(function() { _hideTimer = null; releaseControls(); }, HOLD_MS); }

  function hasInteractiveHints(target) {
    if (!target || !target.getAttribute) return false;
    var role = (target.getAttribute('role') || '').toLowerCase(), aria = (target.getAttribute('aria-label') || '').toLowerCase(), title = (target.getAttribute('title') || '').toLowerCase();
    return role === 'button' || role === 'slider' || ['play','pause','seek','full','volume','mute'].some(function(k){ return aria.indexOf(k) !== -1 || title.indexOf(k) !== -1; });
  }
  function isControlElement(node) {
    var target = node;
    while (target && target !== document.documentElement) {
      var cls = (target.className || '').toString(), tag = (target.tagName || '').toUpperCase(), id = (target.id || '').toString();
      if (/jw-icon|jw-button|jw-controlbar|jw-controls|jw-slider|jw-knob|jw-display|jw-icon-display|jw-icon-rewind|jw-icon-playback|jw-icon-forward|jw-icon-fullscreen|jw-icon-volume|jw-icon-settings|jw-icon-cc|jw-icon-cast/i.test(cls) ||
          /vjs-control|vjs-slider|vjs-big-play|vjs-play-control|vjs-volume|vjs-fullscreen|vjs-menu|vjs-time|vjs-progress/i.test(cls) ||
          /plyr__control|plyr__controls|plyr__progress|plyr__time|plyr__volume|plyr__menu/i.test(cls) ||
          /dplayer-controller|dplayer-bar|dplayer-icons|dplayer-setting|dplayer-volume/i.test(cls) ||
          /mejs__controls|mejs__button|mejs__playpause|mejs__time|mejs__volume/i.test(cls) ||
          /controlbar|control-bar|controls|progress-bar|seekbar|seek-bar|playback|toolbar/i.test(cls) ||
          /jw-|vjs-|plyr/i.test(id) || ['BUTTON','INPUT','A','SELECT','TEXTAREA','LABEL','SUMMARY','SVG','PATH','USE','G','CIRCLE','RECT','POLYGON','POLYLINE'].indexOf(tag) !== -1 || hasInteractiveHints(target))
        return true;
      target = target.parentElement;
    }
    return false;
  }
  function handleInteraction(e) {
    if (!inFs()) return;
    if (isControlElement(e.target)) { forceShowNow(); armHideTimer(); return; }
    var tag = e.target ? (e.target.tagName || '').toUpperCase() : '';
    if (tag !== 'VIDEO') return;
    forceShowNow(); armHideTimer();
  }
  ['touchstart','touchend','pointerdown','pointerup','mousedown','click'].forEach(function(evt){
    document.addEventListener(evt, handleInteraction, {passive:true, capture:true});
  });
  ['fullscreenchange','webkitfullscreenchange'].forEach(function(evt){
    document.addEventListener(evt, function() { if (!inFs()) { if (_hideTimer) { clearTimeout(_hideTimer); _hideTimer = null; } releaseControls(); } }, true);
  });
  window.__asdShowControls = function() { if (!inFs()) return; forceShowNow(); armHideTimer(); };
  window.__asdStopControls = function() { if (_hideTimer) { clearTimeout(_hideTimer); _hideTimer = null; } releaseControls(); };

  function startJwWatchdog() {
    try {
      var jwEl = document.querySelector('.jwplayer'); if (!jwEl || jwEl._asdWatchdog) return; jwEl._asdWatchdog = true;
      new MutationObserver(function(muts) { if (!inFs()) return; muts.forEach(function(m) { if (m.attributeName === 'class' && m.target.classList.contains('jw-flag-user-inactive')) setTimeout(function() { if (inFs() && _hideTimer) m.target.classList.remove('jw-flag-user-inactive'); }, 20); }); }).observe(jwEl, {attributes:true,subtree:false});
    } catch(e) {}
  }
  function startVjsWatchdog() {
    try {
      if (!window.videojs || !window.videojs.getPlayers) return;
      Object.keys(window.videojs.getPlayers() || {}).forEach(function(key) {
        try { var p = window.videojs.getPlayers()[key]; if (!p || p._asdWatchdog) return; p._asdWatchdog = true; p.on('userinactive', function() { if (inFs() && _hideTimer) setTimeout(function() { try { p.userActive(true); } catch(e) {} }, 20); }); } catch(e) {}
      });
    } catch(e) {}
  }
  [1000, 3000].forEach(function(ms){ setTimeout(startJwWatchdog, ms); setTimeout(startVjsWatchdog, ms); });
  try { new MutationObserver(function(muts) { var hasNew = muts.some(function(m){ return m.addedNodes.length > 0; }); if (hasNew) { setTimeout(startJwWatchdog, 500); setTimeout(startVjsWatchdog, 500); } }).observe(document.body || document.documentElement, {childList:true,subtree:true}); } catch(e) {}
})();
""";

  static const String _iframeVideoFix = r"""
(function(){
  'use strict';
  if (window.__asdIframeVideoFixInstalled) return;
  window.__asdIframeVideoFixInstalled = true;
  var _lastTouchTime = 0, _touchPauseBlocked = false, _lastTouchKind = 'other';
  function isInForcedFs() {
    try { if (window !== window.top) return !!(window.top.__asdForcedFs) || !!(window.top.document && window.top.document.documentElement && window.top.document.documentElement.classList.contains('asd-phone-fs')); } catch(e) {}
    return !!(window.__asdForcedFs || (document.documentElement && document.documentElement.classList.contains('asd-phone-fs')) || document.fullscreenElement || document.webkitFullscreenElement);
  }
  function hasInteractiveHints(target) {
    if (!target || !target.getAttribute) return false;
    var role = (target.getAttribute('role') || '').toLowerCase(), aria = (target.getAttribute('aria-label') || '').toLowerCase(), title = (target.getAttribute('title') || '').toLowerCase();
    return role === 'button' || role === 'slider' || ['play','pause','seek','full','volume','mute'].some(function(k){ return aria.indexOf(k) !== -1 || title.indexOf(k) !== -1; });
  }
  function isControlElement(node) {
    var target = node;
    while (target && target !== document.documentElement) {
      var cls = (target.className || '').toString(), tag = (target.tagName || '').toUpperCase(), id = (target.id || '').toString();
      if (/jw-icon|jw-button|jw-controlbar|jw-controls|jw-slider|jw-knob|jw-display|jw-icon-display|jw-icon-rewind|jw-icon-playback|jw-icon-forward|jw-icon-fullscreen|jw-icon-volume|jw-icon-settings|jw-icon-cc|jw-icon-cast/i.test(cls) ||
          /vjs-control|vjs-slider|vjs-big-play|vjs-play-control|vjs-volume|vjs-fullscreen|vjs-menu|vjs-time|vjs-progress/i.test(cls) ||
          /plyr__control|plyr__controls|plyr__progress|plyr__time|plyr__volume|plyr__menu/i.test(cls) ||
          /dplayer-controller|dplayer-bar|dplayer-icons|dplayer-setting|dplayer-volume/i.test(cls) ||
          /mejs__controls|mejs__button|mejs__playpause|mejs__time|mejs__volume/i.test(cls) ||
          /controlbar|control-bar|controls|progress-bar|seekbar|seek-bar|playback|toolbar/i.test(cls) ||
          /jw-|vjs-|plyr/i.test(id) || ['BUTTON','INPUT','A','SELECT','TEXTAREA','LABEL','SUMMARY','SVG','PATH','USE','G','CIRCLE','RECT','POLYGON','POLYLINE'].indexOf(tag) !== -1 || hasInteractiveHints(target))
        return true;
      target = target.parentElement;
    }
    return false;
  }
  function askShowControls() { try { if (window.__asdShowControls) window.__asdShowControls(); } catch(e) {} try { if (window.top && window.top.__asdShowControls) window.top.__asdShowControls(); } catch(e) {} }
  function askKeepFullscreen() { try { if (window.__asdForceFullscreenNow) window.__asdForceFullscreenNow(); } catch(e) {} try { if (window.top && window.top.__asdForceFullscreenNow) window.top.__asdForceFullscreenNow(); } catch(e) {} }
  function syncTapKind(kind) { _lastTouchKind = kind; try { window.__asdLastTapKind = kind; if (window.top) window.top.__asdLastTapKind = kind; } catch(e) {} }
  document.addEventListener('touchstart', function(e) {
    _lastTouchTime = Date.now(); _touchPauseBlocked = false; if (!isInForcedFs()) return;
    if (isControlElement(e.target)) { syncTapKind('control'); askShowControls(); return; }
    var tag = e.target ? (e.target.tagName || '').toUpperCase() : '';
    if (tag === 'VIDEO') { syncTapKind('surface'); askShowControls(); return; } syncTapKind('other');
  }, {passive:true,capture:true});
  document.addEventListener('pointerdown', function(e) {
    _lastTouchTime = Date.now(); _touchPauseBlocked = false; if (!isInForcedFs()) return;
    if (isControlElement(e.target)) { syncTapKind('control'); askShowControls(); return; }
    var tag = e.target ? (e.target.tagName || '').toUpperCase() : '';
    if (tag === 'VIDEO') { syncTapKind('surface'); askShowControls(); return; } syncTapKind('other');
  }, {passive:true,capture:true});
  try {
    var proto = window.HTMLMediaElement && window.HTMLMediaElement.prototype;
    if (proto && !proto._asdAutoResumePatch) {
      proto._asdAutoResumePatch = true;
      var _origPause = proto.pause;
      proto.pause = function() {
        var self = this, result;
        try { result = _origPause ? _origPause.apply(self, arguments) : undefined; } catch(e) {}
        if (isInForcedFs()) {
          var timeSinceTouch = Date.now() - _lastTouchTime;
          if (timeSinceTouch < 450 && !_touchPauseBlocked && _lastTouchKind === 'surface') {
            _touchPauseBlocked = true;
            setTimeout(function() { try { if (self.paused && isInForcedFs()) { self.play(); askShowControls(); askKeepFullscreen(); } } catch(e) {} _touchPauseBlocked = false; }, 90);
          }
        }
        return result;
      };
    }
  } catch(e) {}
  function blockVideoTap(e) {
    if (!isInForcedFs()) return;
    if (isControlElement(e.target)) { syncTapKind('control'); askShowControls(); return; }
    var tag = e.target ? (e.target.tagName || '').toUpperCase() : '';
    if (tag !== 'VIDEO') { syncTapKind('other'); return; }
    syncTapKind('surface'); askShowControls(); askKeepFullscreen();
  }
  ['click','touchend','pointerup'].forEach(function(evt){ document.addEventListener(evt, blockVideoTap, {passive:true,capture:true}); });
})();
""";

  static const String _dlCapture = r"""
(function(){
  'use strict';
  var _host = (window.location && window.location.host || '').toLowerCase();
  var _mainSite = _host.indexOf('egydead') !== -1 || _host.indexOf('c4u') !== -1;
  if (!_mainSite) return;
  var dlExts = ['.mp4','.mkv','.avi','.mov','.webm','.m4v'];
  var dlProviders = ['krakenfiles','megaup','mixdrop','1fichier','vikingfile','koramaup','1cloudfile','bowfile','doodstream','dooood','earnvids'];
  function maybeMedia(url) {
    if (!url || typeof url !== 'string') return null;
    var s = url.trim(); if (!s || s.indexOf('blob:') === 0) return null;
    var lower = s.toLowerCase();
    if (['.m3u8','.mp4','.mkv','.webm','.m4v','.ts','.mov','.mpd','mime=video','/playlist','/manifest','/hls/'].some(function(x){ return lower.indexOf(x) !== -1; })) return s;
    return null;
  }
  function isDlUrl(url) { var clean = maybeMedia(url); if (!clean) return false; var lower = clean.toLowerCase().split('?')[0].split('#')[0]; return dlExts.some(function(e){ return lower.endsWith(e); }); }
  function isDownloadLanding(url) {
    if (!url || typeof url !== 'string') return false;
    var lower = url.toLowerCase().trim();
    return dlProviders.some(function(x){ return lower.indexOf(x) !== -1; }) ||
      ['/download','/downloads','/file/','/f/'].some(function(x){ return lower.indexOf(x) !== -1; });
  }
  function extractName(url) { if (!url) return 'video.mp4'; var parts = url.split('?')[0].split('/'); var name = parts[parts.length-1]; return name && name.length > 0 ? name : 'video.mp4'; }
  function labelOf(el) {
    var txt = (el.getAttribute && (el.getAttribute('title') || el.getAttribute('aria-label')) || el.innerText || el.textContent || '').replace(/[\r\n\t]+/g, ' ').replace(/\s+/g, ' ').trim();
    return txt || null;
  }
  function sendDl(url, name) { if (!url || url.length < 5) return; try { window.flutter_inappwebview.callHandler('onDownload', { url: url, name: name || extractName(url) }); } catch(e) {} }
  function sendLanding(url, name) { if (!url || url.length < 5) return; try { window.flutter_inappwebview.callHandler('onDownloadLanding', { url: url, name: name || extractName(url), pageUrl: window.location.href }); } catch(e) {} }
  function sendVideo(url, mimeType) { var clean = maybeMedia(url); if (!clean) return; try { window.flutter_inappwebview.callHandler('onVideoFound', { url: clean, pageUrl: window.location.href, currentTime: 0, mimeType: mimeType || null }); } catch(e) {} }
  document.addEventListener('click', function(e) {
    var el = e.target;
    while (el && el !== document) { if (el.tagName === 'A' || el.tagName === 'BUTTON') break; el = el.parentElement; }
    if (!el || el === document) return;
    var href = el.href || el.getAttribute('data-url') || el.getAttribute('data-link') || el.getAttribute('data-src') || el.getAttribute('data-file') || '';
    if (href && isDlUrl(href)) { e.preventDefault(); e.stopPropagation(); sendDl(href, el.getAttribute('download') || extractName(href)); return; }
    if (href && isDownloadLanding(href)) { e.preventDefault(); e.stopPropagation(); sendLanding(href, labelOf(el)); return; }
    sendVideo(href, null);
  }, true);
  var origFetch = window.fetch;
  if (origFetch && !window.__asdFetchPatched) {
    window.__asdFetchPatched = true;
    window.fetch = function(input, init) {
      var url = typeof input === 'string' ? input : (input && input.url ? input.url : '');
      sendVideo(url, null); if (isDlUrl(url)) sendDl(url, extractName(url)); else if (isDownloadLanding(url)) sendLanding(url, extractName(url));
      return origFetch.call(window, input, init).then(function(response) {
        var resUrl = response.url || url, mime = null;
        try { mime = response.headers && response.headers.get ? response.headers.get('content-type') : null; } catch(e) {}
        sendVideo(resUrl, mime); if (isDlUrl(resUrl)) sendDl(resUrl, extractName(resUrl)); else if (isDownloadLanding(resUrl)) sendLanding(resUrl, extractName(resUrl));
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
        if (isDownloadLanding(url)) sendLanding(url, extractName(url));
        return _open.apply(this, arguments);
      };
      var _send = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.send = function() {
        this.addEventListener('readystatechange', function() {
          if (this.readyState === 2 || this.readyState === 4) {
            var mime = null;
            try { mime = this.getResponseHeader('content-type'); } catch(e) {}
            var finalUrl = this.responseURL || this._asdUrl;
            sendVideo(finalUrl, mime);
            if (isDlUrl(finalUrl)) sendDl(finalUrl, extractName(finalUrl));
            else if (isDownloadLanding(finalUrl)) sendLanding(finalUrl, extractName(finalUrl));
          }
        });
        return _send.apply(this, arguments);
      };
    }
  } catch(e) {}
})();
""";

  static const String _serverCapture = r"""
(function(){
  'use strict';
  var _host = (window.location && window.location.host || '').toLowerCase();
  var _mainSite = _host.indexOf('egydead') !== -1 || _host.indexOf('c4u') !== -1;
  if (!_mainSite) return;
  if (window.__egyServerCapture) return;
  window.__egyServerCapture = true;

  var KNOWN = ['streamruby','streamhg','stream-hg','finger','streamix',
    'deathstream','mixdrop','earnvids','fly','forafile','vibuxer',
    'masukestin','audinifer','server','srv'];

  function isKnownServer(text, url) {
    var t = (text || '').toLowerCase().trim();
    var u = (url || '').toLowerCase();
    if (/^[سيرفر\s]*\d+$/.test(t) || /^server\s*\d*$/i.test(t)) return true;
    if (/^\d+$/.test(t)) return true;
    return KNOWN.some(function(s){ return t.indexOf(s) !== -1 || u.indexOf(s) !== -1; });
  }

  function getBestLabel(el) {
    var sources = [
      el.getAttribute && el.getAttribute('data-name'),
      el.getAttribute && el.getAttribute('data-server'),
      el.getAttribute && el.getAttribute('title'),
      el.getAttribute && el.getAttribute('aria-label'),
      el.innerText, el.textContent
    ];
    for (var i = 0; i < sources.length; i++) {
      var t = (sources[i] || '').replace(/[\r\n\t]+/g,' ').replace(/\s+/g,' ').trim();
      if (t && t.length > 0 && t.length < 60) return t;
    }
    return null;
  }

  function getEmbedLink(el) {
    return (
      el.getAttribute('data-link') || el.getAttribute('data-src') ||
      el.getAttribute('data-embed') || el.getAttribute('data-url') ||
      el.getAttribute('data-iframe') || el.getAttribute('data-id') ||
      el.getAttribute('href') || el.href || ''
    ).trim();
  }

  var SELECTORS = [
    'ul.servers li', 'ul.server-list li', '.servers-list li',
    '.servers li', '.servers a', '.server-item', '.server-link',
    '[class*="server"] li', '[class*="server"] a',
    '[id*="server"] li', '[id*="server"] a',
    'li[data-link]', 'a[data-link]', 'div[data-link]', 'span[data-link]',
    'li[data-embed]', 'a[data-embed]', 'li[data-src]', 'a[data-src]',
    'li[data-id]', 'a[data-id]',
    '.watch-btns a', '.watch-btns li', '.watch-servers a', '.watch-servers li',
    '.link-btn', '.ep-link', '.ep_link li', '.episodeslinks li',
    '[class*="watch"] li', '[class*="watch"] a',
    '[class*="link"] li', '[class*="link"] a',
    '[class*="play"] li', '[class*="play"] a',
    'button', 'li', 'a', 'div.btn', 'span.btn',
  ];

  var _collected = false;

  function collectServers() {
    var out = [], seen = {};
    SELECTORS.forEach(function(sel) {
      try {
        document.querySelectorAll(sel).forEach(function(el) {
          var label = getBestLabel(el);
          var embedUrl = getEmbedLink(el);
          if (!label) return;
          if (/\.(mp4|mkv|avi|mov|webm|m4v|zip|rar)(\?|$)/i.test(embedUrl)) return;
          if (!isKnownServer(label, embedUrl)) return;
          var key = ('srv_' + label.replace(/[^a-zA-Z0-9\u0600-\u06FF]/g,'') + '_' + out.length);
          try { el.setAttribute('data-asd-srv-key', key); } catch(e) {}
          var cls = ((el.className||'') + ' ' + (el.parentElement&&el.parentElement.className||'')).toLowerCase();
          var selected = /active|current|selected|playing|on\b/i.test(cls) ||
                         el.getAttribute('aria-current') === 'true' ||
                         el.getAttribute('aria-selected') === 'true';
          var uniq = (label + '|' + embedUrl).toLowerCase();
          if (seen[uniq]) return;
          seen[uniq] = true;
          out.push({ label: label, key: key, url: embedUrl, selected: selected });
        });
      } catch(e) {}
    });

    if (out.length === 0) {
      try {
        var allEls = document.querySelectorAll('li, button, a, div, span');
        for (var i = 0; i < allEls.length; i++) {
          var el = allEls[i];
          var label = getBestLabel(el);
          if (!label || label.length > 40) continue;
          var embedUrl = getEmbedLink(el);
          if (!isKnownServer(label, embedUrl)) continue;
          var rect = el.getBoundingClientRect();
          if (rect.width < 20 || rect.height < 10) continue;
          var key = ('srv_' + label.replace(/[^a-zA-Z0-9\u0600-\u06FF]/g,'') + '_' + out.length);
          try { el.setAttribute('data-asd-srv-key', key); } catch(e) {}
          var cls2 = ((el.className||'') + ' ' + (el.parentElement&&el.parentElement.className||'')).toLowerCase();
          var selected2 = /active|current|selected|playing/i.test(cls2);
          var uniq2 = (label + '|' + embedUrl).toLowerCase();
          if (seen[uniq2]) continue;
          seen[uniq2] = true;
          out.push({ label: label, key: key, url: embedUrl, selected: selected2 });
        }
      } catch(e) {}
    }

    if (out.length === 0) return;
    if (out.length === _collected) return;
    _collected = out.length;

    var current = null;
    out.forEach(function(o){ if (o.selected && !current) current = o.label; });
    if (!current) current = out[0].label;

    try {
      window.flutter_inappwebview.callHandler('onServerOptions', { options: out, current: current });
    } catch(e) {}
  }

  var _watchedIframes = typeof WeakSet !== 'undefined' ? new WeakSet() :
    { _arr: [], has: function(x){ return this._arr.indexOf(x)!==-1; }, add: function(x){ this._arr.push(x); } };

  function watchIframe(iframe) {
    if (!iframe || _watchedIframes.has(iframe)) return;
    _watchedIframes.add(iframe);
    new MutationObserver(function(muts) {
      muts.forEach(function(m) {
        if (m.attributeName !== 'src') return;
        var src = iframe.getAttribute('src') || '';
        if (src && src.indexOf('http') === 0 && src.indexOf('about:blank') === -1) {
          try { window.flutter_inappwebview.callHandler('onServerIframeChanged', { embedUrl: src }); } catch(e) {}
        }
      });
    }).observe(iframe, { attributes: true, attributeFilter: ['src'] });
  }

  function watchAllIframes() { document.querySelectorAll('iframe').forEach(watchIframe); }

  window.__asdSelectServerOption = function(key, label, url) {
    try {
      var byKey = key ? document.querySelector('[data-asd-srv-key="' + String(key).replace(/"/g,'\\\"') + '"]') : null;
      if (byKey) { byKey.click(); return true; }
      var allEls = document.querySelectorAll('li,button,a,div,span');
      for (var i = 0; i < allEls.length; i++) {
        var el = allEls[i];
        var elLabel = getBestLabel(el);
        var elUrl = getEmbedLink(el);
        if ((label && elLabel === label) || (url && url.length > 3 && elUrl === url)) {
          el.click(); return true;
        }
      }
    } catch(e) {} return false;
  };

  watchAllIframes();
  collectServers();

  new MutationObserver(function(muts) {
    var changed = false;
    muts.forEach(function(m) {
      m.addedNodes.forEach(function(n) {
        if (n.tagName === 'IFRAME') watchIframe(n);
        if (n.querySelectorAll) n.querySelectorAll('iframe').forEach(watchIframe);
        changed = true;
      });
    });
    if (changed) setTimeout(collectServers, 400);
  }).observe(document.body || document.documentElement, { childList: true, subtree: true });

  setTimeout(collectServers, 600);
  setTimeout(collectServers, 1500);
  setTimeout(collectServers, 3000);
  setInterval(collectServers, 5000);
})();
""";

  // ─── Helper Methods ───────────────────────────────────────────────────────

  String _normalizeQualityLabel(String input) {
    final m = RegExp(r'(?:^|[^0-9])([1-9][0-9]{2,3})\s*p\b', caseSensitive: false).firstMatch(input.trim());
    return m != null ? '${m.group(1)}p' : input.trim();
  }

  void _updatePageQualityOptions(List<PageQualityOption> options, [String? currentLabel]) {
    final seenByResolution = <String>{};
    final normalized = <PageQualityOption>[];

    for (final opt in options) {
      final label = _normalizeQualityLabel(opt.label);
      if (label.isEmpty) continue;
      final dedupeKey = label.toLowerCase();
      if (seenByResolution.contains(dedupeKey)) continue;
      seenByResolution.add(dedupeKey);

      final key = opt.key.isNotEmpty ? opt.key : '${label}_${normalized.length}';
      normalized.add(PageQualityOption(
        label: label, key: key, url: opt.url, selected: opt.selected,
      ));
    }

    normalized.sort((a, b) {
      final ra = int.tryParse(RegExp(r'\d+').firstMatch(a.label)?.group(0) ?? '0') ?? 0;
      final rb = int.tryParse(RegExp(r'\d+').firstMatch(b.label)?.group(0) ?? '0') ?? 0;
      return rb.compareTo(ra);
    });

    _pageQualityOptions = normalized;

    final cleanCurrent = _normalizeQualityLabel(currentLabel ?? '');
    if (cleanCurrent.isNotEmpty &&
        normalized.any((q) => _normalizeQualityLabel(q.label) == cleanCurrent)) {
      _currentPageQualityLabel = cleanCurrent;
    } else {
      _currentPageQualityLabel = null;
    }
  }

  Future<double> _getCurrentPosition() async {
    try { final pos = await _pip.invokeMethod<num>('getCurrentPosition'); return pos?.toDouble() ?? _capturedVideoTime; }
    catch (_) { return _capturedVideoTime; }
  }

  Future<void> _switchPageQuality(PageQualityOption option) async {
    if (_wc == null) return;
    final seekSeconds = await _getCurrentPosition();
    if (mounted) {
      setState(() => _currentPageQualityLabel = option.label);
    } else {
      _currentPageQualityLabel = option.label;
    }
    await _pauseOriginalSitePlayer();
    if (_looksLikePlayableMediaUrl(option.url)) {
      _qualitySwitchPending = false;
      await _openNativePlayer(force: true, replace: true, startTimeOverride: seekSeconds, forcedUrl: option.url, forcedPageUrl: _capturedVideoPageUrl, forcedMimeType: _inferMimeType(option.url));
      return;
    }
    _qualitySwitchPending = true; _pendingNativeStartTime = seekSeconds;
    bool clicked = false;
    try {
      final raw = await _wc!.evaluateJavascript(source: '(function(){ try { if (!window.__asdSelectQualityOption) return false; return !!window.__asdSelectQualityOption(${jsonEncode(option.key)}, ${jsonEncode(option.label)}, ${jsonEncode(option.url ?? "")}); } catch(e) { return false; } })();');
      clicked = raw == true || raw?.toString() == 'true';
    } catch (_) {}
    if (!clicked) { _qualitySwitchPending = false; _showSnack('⚠️ تعذّر تغيير الجودة من الصفحة'); return; }
    Future.delayed(const Duration(seconds: 4), () { if (_qualitySwitchPending) { _qualitySwitchPending = false; _showSnack('⚠️ لم ألتقط رابط الجودة الجديدة'); } });
  }

  Future<void> _switchPageServer(PageServerOption option) async {
    if (_wc == null) return;
    final seekSeconds = await _getCurrentPosition();
    if (mounted) setState(() => _currentPageServerLabel = option.label);
    await _pauseOriginalSitePlayer();
    if (_looksLikePlayableMediaUrl(option.url)) {
      _serverSwitchPending = false;
      await _openNativePlayer(force: true, replace: true, startTimeOverride: seekSeconds, forcedUrl: option.url, forcedPageUrl: _capturedVideoPageUrl, forcedMimeType: _inferMimeType(option.url));
      return;
    }
    _serverSwitchPending = true; _pendingNativeStartTime = seekSeconds; _capturedVideoUrl = null;
    bool clicked = false;
    try {
      final raw = await _wc!.evaluateJavascript(source: '(function(){ try { if (!window.__asdSelectServerOption) return false; return !!window.__asdSelectServerOption(${jsonEncode(option.key)}, ${jsonEncode(option.label)}, ${jsonEncode(option.url ?? "")}); } catch(e) { return false; } })();');
      clicked = raw == true || raw?.toString() == 'true';
    } catch (_) {}
    if (!clicked) { _serverSwitchPending = false; _showSnack('⚠️ تعذّر تغيير السيرفر'); return; }
    Future.delayed(const Duration(seconds: 10), () { if (_serverSwitchPending) { _serverSwitchPending = false; _showSnack('⚠️ لم ألتقط فيديو من السيرفر الجديد'); } });
  }

  Map<String, int> _safePipAspectRatio() {
    const double minRatio = 0.42, maxRatio = 2.38;
    int w = _videoAspectW > 0 ? _videoAspectW : 16, h = _videoAspectH > 0 ? _videoAspectH : 9;
    if (w <= 0 || h <= 0) return {'w': 16, 'h': 9};
    final double ratio = w / h;
    if (ratio < minRatio || ratio > maxRatio) return {'w': 16, 'h': 9};
    int gcd(int a, int b) => b == 0 ? a : gcd(b, a % b);
    final g = gcd(w.abs(), h.abs()), rw = w ~/ g, rh = h ~/ g;
    if (rw > 239 || rh > 239 || rw <= 0 || rh <= 0) return {'w': 16, 'h': 9};
    if (rw / rh < minRatio || rw / rh > maxRatio) return {'w': 16, 'h': 9};
    return {'w': rw, 'h': rh};
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ptr = PullToRefreshController(settings: PullToRefreshSettings(color: Colors.orange), onRefresh: () async => await _wc?.reload());
    _pip.setMethodCallHandler((call) async {
      if (!mounted) return;
      switch (call.method) {
        case 'onPipChanged':
          final isInPip = call.arguments as bool? ?? false;
          setState(() => _inPip = isInPip);
          if (!isInPip && !_nativePlayerActive) await _restoreUI();
          break;
        case 'onNativePlayerChanged':
          final active = call.arguments as bool? ?? false;
          setState(() { _nativePlayerActive = active; if (!active) _lastNativePlayerUrl = null; _videoPlaying = active ? false : _videoPlaying; });
          if (active) { _clearPendingNativeIntent(); _suppressAutoOpenUntil = 0; await _pauseOriginalSitePlayer(); _scheduleOriginalPlayerHardPause(); }
          else { _suppressAutoOpenUntil = DateTime.now().millisecondsSinceEpoch + 1200; _clearPendingNativeIntent(); await _releaseOriginalSitePlayerBlock(); await _restoreUI(); }
          break;
        case 'onNativePipError':
          _nativePlayerOpening = false;
          final message = call.arguments?.toString();
          if (message != null && message.isNotEmpty) _showSnack('⚠️ $message');
          break;
        case 'onQualitySelected':
          if (call.arguments is Map) await _switchPageQuality(PageQualityOption.fromMap(Map<String, dynamic>.from(call.arguments as Map)));
          break;
        case 'onServerSelected':
          if (call.arguments is Map) await _switchPageServer(PageServerOption.fromMap(Map<String, dynamic>.from(call.arguments as Map)));
          break;
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

  Future<String?> _createVideoThumbnail(String videoPath) async {
    if (!Platform.isAndroid && !Platform.isIOS) return null;
    try { final tempDir = await getTemporaryDirectory(); return await VideoThumbnail.thumbnailFile(video: videoPath, thumbnailPath: tempDir.path, imageFormat: ImageFormat.JPEG, maxWidth: 420, quality: 85); }
    catch (_) { return null; }
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
      headers: _downloadHeaders(url, pageUrl: _capturedVideoPageUrl),
      pageUrl: _capturedVideoPageUrl ?? _lastTrusted,
    );
    if (!ok) _discoveredDownloadUrls.remove(url);
  }


  Future<void> _cancelDownload(DownloadItem item) async {
    await BackgroundDownloadBridge.cancel(item.id);
    item.cancelToken?.cancel('cancelled by user');
    if (!mounted) return;
    setState(() { item.status = 'cancelled'; item.progress = 0; });
    _discoveredDownloadUrls.remove(item.url);
    if (item.savedPath != null) { final file = File(item.savedPath!); if (await file.exists()) try { await file.delete(); } catch (_) {} }
    _showSnack('⛔ تم إلغاء التحميل: ${item.fileName}');
  }

  Future<void> _playVideo(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      _showSnack('⚠️ ملف التحميل غير موجود');
      return;
    }

    final fileUri = file.uri.toString();
    try {
      _closeDownloadsPanel();
      final ok = await _pip.invokeMethod<bool>('openNativePlayer', {
        'url': fileUri,
        'currentTime': 0.0,
        'pageUrl': fileUri,
        'mimeType': _inferMimeType(fileUri) ?? 'video/mp4',
        'headers': const <String, String>{},
        'aspectRatioNumerator': 16,
        'aspectRatioDenominator': 9,
        'subtitleTracks': const <Map<String, String>>[],
        'qualityOptions': const <Map<String, String>>[],
        'currentQualityLabel': '',
        'serverOptions': const <Map<String, String>>[],
        'currentServerLabel': '',
        'autoSelectHighestQuality': false,
      });
      if (ok == true && mounted) {
        setState(() {
          _nativePlayerActive = true;
          _lastNativePlayerUrl = fileUri;
        });
      } else {
        _showSnack('⚠️ تعذّر فتح التحميل داخل المشغل');
      }
    } on MissingPluginException {
      _showSnack('⚠️ المشغل الداخلي غير مفعّل');
    } catch (_) {
      _showSnack('⚠️ تعذّر فتح التحميل داخل المشغل');
    }
  }

  Future<void> _confirmDelete(DownloadItem item) async {
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF18212C), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text('حذف التحميل', style: TextStyle(color: Colors.white)),
      content: Text('هل تريد حذف "${item.fileName}" ؟', style: const TextStyle(color: Colors.white70)),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف'))],
    ));
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg, style: const TextStyle(color: Colors.white)), backgroundColor: const Color(0xFF18212C), behavior: SnackBarBehavior.floating));
  }



  
  static const String _backgroundDownloadSource = 'Egy';

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

  void _openDownloadsPanel() { if (!mounted) return; setState(() => _showDownloads = true); }
  void _closeDownloadsPanel() { if (!mounted) return; setState(() => _showDownloads = false); }

  Future<bool> _isPipSupported() async {
    if (!Platform.isAndroid) return true;
    try { return await _pip.invokeMethod<bool>('isPipSupported') ?? false; }
    on MissingPluginException { return false; } catch (_) { return false; }
  }

  bool get _allowNativeAutoOpen => false;
  bool get _hasPendingNativeIntent => DateTime.now().millisecondsSinceEpoch <= _pendingNativeIntentUntil;
  void _armPendingNativeIntent([int ms = 4500]) => _pendingNativeIntentUntil = DateTime.now().millisecondsSinceEpoch + ms;
  void _clearPendingNativeIntent() => _pendingNativeIntentUntil = 0;

  void _scheduleOriginalPlayerHardPause() {
    for (final ms in const [0, 120, 260, 520, 900, 1400, 2000]) {
      Future.delayed(Duration(milliseconds: ms), () async { await _pauseOriginalSitePlayer(); });
    }
  }

  Future<void> _pauseOriginalSitePlayer() async {
    try { await _wc?.evaluateJavascript(source: r"""
(function(){try{window.__asdNativePlayerActive=true;window.__asdNativePlayerOpening=true;window.__asdPauseAllSitePlayers=window.__asdPauseAllSitePlayers||function(){try{document.querySelectorAll('video,audio').forEach(function(v){try{v.pause();v.muted=true;v.volume=0;v.autoplay=false;v.removeAttribute('autoplay');}catch(e){}});}catch(e){}try{if(window.jwplayer){var jw=window.jwplayer();if(jw&&jw.setMute)jw.setMute(true);if(jw&&jw.pause)jw.pause(true);if(jw&&jw.stop)jw.stop();}}catch(e){}try{if(window.videojs&&window.videojs.getPlayers){Object.keys(window.videojs.getPlayers()||{}).forEach(function(key){try{var p=window.videojs.getPlayers()[key];if(p&&p.muted)p.muted(true);if(p&&p.pause)p.pause();}catch(e){}});}}catch(e){}};if(!window.__asdOrigMediaPlay){window.__asdOrigMediaPlay=HTMLMediaElement.prototype.play;HTMLMediaElement.prototype.play=function(){if(window.__asdNativePlayerActive||window.__asdNativePlayerOpening){try{this.pause();this.muted=true;this.volume=0;}catch(e){}return Promise.resolve();}return window.__asdOrigMediaPlay.apply(this,arguments);};}window.__asdPauseAllSitePlayers();try{clearInterval(window.__asdNativePauseLoop);}catch(e){}window.__asdNativePauseLoop=setInterval(function(){if(!window.__asdNativePlayerActive)return;try{window.__asdPauseAllSitePlayers();}catch(e){}},220);}catch(e){}})();
"""); } catch (_) {}
  }

  Future<void> _releaseOriginalSitePlayerBlock() async {
    try { await _wc?.evaluateJavascript(source: r"""
(function(){try{window.__asdNativePlayerActive=false;window.__asdNativePlayerOpening=false;try{clearInterval(window.__asdNativePauseLoop);}catch(e){}window.__asdNativePauseLoop=null;document.querySelectorAll('video,audio').forEach(function(v){try{v.pause();v.muted=false;v.volume=1;}catch(e){}});if(window.jwplayer){try{var jw=window.jwplayer();if(jw&&jw.setMute)jw.setMute(false);if(jw&&jw.pause)jw.pause(true);}catch(e){}}if(window.videojs&&window.videojs.getPlayers){try{Object.keys(window.videojs.getPlayers()||{}).forEach(function(key){try{var p=window.videojs.getPlayers()[key];if(p&&p.muted)p.muted(false);if(p&&p.pause)p.pause();}catch(e){}});}catch(e){}}}catch(e){}})();
"""); } catch (_) {}
  }

  Future<void> _closeNativePlayer() async {
    _suppressAutoOpenUntil = DateTime.now().millisecondsSinceEpoch + 1200;
    try { await _pip.invokeMethod<bool>('closeNativePlayer'); } catch (_) {}
    _clearPendingNativeIntent();
    await _releaseOriginalSitePlayerBlock();
  }

  Future<void> _updateNativePlayerOptions() async {
    if (!_nativePlayerActive) return;
    try {
      await _pip.invokeMethod('updatePlayerOptions', {
        'qualityOptions': _pageQualityOptions.map((e) => e.toMap()).toList(),
        'currentQualityLabel': _normalizeQualityLabel(_currentPageQualityLabel ?? ''),
        'autoSelectHighestQuality': false,
        'serverOptions': _pageServerOptions.map((e) => e.toMap()).toList(),
        'currentServerLabel': _currentPageServerLabel ?? '',
      });
    } catch (_) {}
  }

  bool get _hasAnyCapturedPlayableMedia =>
      ((_capturedVideoUrl ?? '').trim().isNotEmpty &&
          !(_capturedVideoUrl ?? '').trim().toLowerCase().startsWith('blob:'));

  void _clearQuickActionCaptureWaiters() {
    _watchButtonWaitingForCapture = false;
    _downloadButtonWaitingForCapture = false;
    _pendingDownloadQualityOption = null;
    _overlayCaptureBusy = false;
    _quickActionCaptureTicket++;
  }

  String _capturedFileNameForDownload({String? urlOverride, String? labelOverride}) {
    final url = (urlOverride ?? _capturedVideoUrl ?? '').trim();
    final label = _normalizeQualityLabel(labelOverride ?? _currentPageQualityLabel ?? '');
    final base = _inferFileName(url, _isVideoUrl(url) ? 'video.mp4' : 'video.m3u8');
    if (label.isEmpty || base.toLowerCase().contains(label.toLowerCase())) return base;
    final dot = base.lastIndexOf('.');
    if (dot <= 0) return _sanitizeFileName('${base}_$label');
    return _sanitizeFileName('${base.substring(0, dot)}_$label${base.substring(dot)}');
  }

  String _decodeMaybeJsString(Object? value) {
    var s = value?.toString().trim() ?? '';
    if (s.length >= 2 &&
        ((s.startsWith('"') && s.endsWith('"')) ||
            (s.startsWith("'") && s.endsWith("'")))) {
      try {
        final decoded = jsonDecode(s);
        if (decoded is String) s = decoded.trim();
      } catch (_) {
        s = s.substring(1, s.length - 1).trim();
      }
    }
    return s;
  }

  String _titleFromUrlForDownload(String? rawUrl) {
    try {
      final uri = Uri.parse(rawUrl ?? '');
      final segments = uri.pathSegments.where((e) => e.trim().isNotEmpty).toList();
      if (segments.isEmpty) return '';
      var slug = Uri.decodeComponent(segments.last);
      if (slug.contains('.')) slug = slug.substring(0, slug.lastIndexOf('.'));
      return slug.replaceAll(RegExp(r'[-_]+'), ' ').trim();
    } catch (_) {
      return '';
    }
  }

  String _cleanDownloadTitle(String raw) {
    var s = raw
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', ' ')
        .replaceAll('&#039;', ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    s = s.replaceAll(RegExp(r'\s*[-|–—]+\s*(ايجي\s*ديد|EgyDead).*$', caseSensitive: false), '').trim();
    s = s.replaceAll(RegExp(r'^(مشاهدة|تحميل|اونلاين|اون لاين)\s+', caseSensitive: false), '').trim();
    s = s.replaceAll(RegExp(r'\s+(اونلاين|اون لاين|Online)$', caseSensitive: false), '').trim();
    s = s.replaceAll(RegExp(r'\s*\|?\s*(ايجي\s*ديد|EgyDead)\s*$', caseSensitive: false), '').trim();

    if (s.length > 120) s = s.substring(0, 120).trim();
    return s;
  }

  bool _isEgyContentPageUrl(String? rawUrl) {
    final url = (rawUrl ?? '').trim();
    if (url.isEmpty) return false;
    final uri = Uri.tryParse(url);
    final host = uri?.host.toLowerCase() ?? '';
    if (!host.contains('egydead')) return false;
    final path = uri?.path.toLowerCase() ?? '';
    if (path.isEmpty || path == '/') return false;
    if (path.contains('/category/') ||
        path.contains('/tag/') ||
        path.contains('/page/') ||
        path.contains('/author/') ||
        path.contains('/search/') ||
        path.contains('/download')) {
      return false;
    }
    return true;
  }

  void _rememberContentTitleForDownload(String? title, {String? pageUrl}) {
    if (!_isEgyContentPageUrl(pageUrl)) return;
    final clean = _cleanDownloadTitle(title ?? '');
    if (clean.isEmpty) return;
    final lower = clean.toLowerCase();
    if (lower.contains('stream') || lower.contains('embed') || lower.contains('download')) return;
    _currentDocumentTitle = clean;
    _contentTitleForDownload = clean;
  }

  Future<String> _readMainPageTitleForDownload() async {
    final contentTitle = _cleanDownloadTitle(_contentTitleForDownload ?? '');
    if (contentTitle.isNotEmpty) return contentTitle;

    final activePage = (await _wc?.getUrl())?.toString() ?? _capturedVideoPageUrl ?? _lastTrusted;
    if (!_isEgyContentPageUrl(activePage)) {
      final remembered = _cleanDownloadTitle(_currentDocumentTitle ?? '');
      if (remembered.isNotEmpty) return remembered;
      final trustedTitle = _cleanDownloadTitle(_titleFromUrlForDownload(_lastTrusted));
      if (trustedTitle.isNotEmpty && !trustedTitle.toLowerCase().contains('embed')) return trustedTitle;
      final capturedTitle = _cleanDownloadTitle(_titleFromUrlForDownload(_capturedVideoPageUrl));
      if (capturedTitle.isNotEmpty && !capturedTitle.toLowerCase().contains('embed')) return capturedTitle;
      return 'video';
    }

    try {
      final result = await _wc?.evaluateJavascript(source: r'''
(function(){
  try {
    var selectors = [
      'h1.entry-title','h1.post-title','h1.Title','h1.title','h1',
      '.entry-title','.post-title','.single-title','.Title','.title',
      'meta[property="og:title"]','meta[name="twitter:title"]'
    ];
    for (var i = 0; i < selectors.length; i++) {
      var el = document.querySelector(selectors[i]);
      if (!el) continue;
      var txt = (el.getAttribute && (el.getAttribute('content') || el.getAttribute('title'))) || el.innerText || el.textContent || '';
      txt = (txt || '').replace(/[\r\n\t]+/g, ' ').replace(/\s+/g, ' ').trim();
      if (txt && txt.length > 2) return txt;
    }
    return (document.title || '').replace(/[\r\n\t]+/g, ' ').replace(/\s+/g, ' ').trim();
  } catch(e) {
    return document.title || '';
  }
})();
''');
      final title = _cleanDownloadTitle(_decodeMaybeJsString(result));
      if (title.isNotEmpty && !title.toLowerCase().contains('stmruby')) {
        _rememberContentTitleForDownload(title, pageUrl: activePage);
        if ((_contentTitleForDownload ?? '').isNotEmpty) return _contentTitleForDownload!;
        _currentDocumentTitle = title;
        return title;
      }
    } catch (_) {}

    final remembered = _cleanDownloadTitle(_currentDocumentTitle ?? '');
    if (remembered.isNotEmpty) return remembered;

    final trustedTitle = _cleanDownloadTitle(_titleFromUrlForDownload(_lastTrusted));
    if (trustedTitle.isNotEmpty && !trustedTitle.toLowerCase().contains('embed')) return trustedTitle;

    final capturedTitle = _cleanDownloadTitle(_titleFromUrlForDownload(_capturedVideoPageUrl));
    if (capturedTitle.isNotEmpty && !capturedTitle.toLowerCase().contains('embed')) return capturedTitle;

    return 'video';
  }

  Future<String> _downloadFileNameForContent({String? urlOverride, String? labelOverride}) async {
    final url = (urlOverride ?? _capturedVideoUrl ?? '').trim();
    final label = _normalizeQualityLabel(labelOverride ?? _currentPageQualityLabel ?? _capturedVideoQualityLabel ?? '');
    final title = _cleanDownloadTitle(await _readMainPageTitleForDownload());
    final fallback = _capturedFileNameForDownload(urlOverride: url, labelOverride: label);
    final baseTitle = title.isNotEmpty && title != 'video' ? title : _cleanDownloadTitle(fallback.replaceAll(RegExp(r'\.[^.]+$'), ''));
    final suffix = label.isEmpty || baseTitle.toLowerCase().contains(label.toLowerCase()) ? '' : ' - $label';
    return _sanitizeFileName('${baseTitle.isEmpty ? 'video' : baseTitle}$suffix.mp4');
  }

  Future<void> _collectAndClickSitePlayer() async {
    if (_wc == null) return;
    try {
      await _wc!.evaluateJavascript(source: r'''
(function(){
  try { if (window.__asdCollectMediaNow) window.__asdCollectMediaNow(); } catch(e) {}
  try { if (window.__asdClickSitePlayerPlay) window.__asdClickSitePlayerPlay(); } catch(e) {}
  try {
    document.querySelectorAll('iframe').forEach(function(fr){
      try {
        if (fr.contentWindow && fr.contentWindow.__asdClickSitePlayerPlay) {
          fr.contentWindow.__asdClickSitePlayerPlay();
        }
      } catch(e) {}
    });
  } catch(e) {}
})();
''');
    } catch (_) {}
  }

  Future<void> _collectQualityOptionsFromAllFrames() async {
    if (_wc == null) return;
    try {
      await _wc!.evaluateJavascript(source: r'''
(function(){
  try { if (window.__asdCollectMediaNow) window.__asdCollectMediaNow(); } catch(e) {}
  try {
    document.querySelectorAll('iframe').forEach(function(fr){
      try {
        if (fr.contentWindow && fr.contentWindow.__asdCollectMediaNow) {
          fr.contentWindow.__asdCollectMediaNow();
        }
      } catch(e) {}
    });
  } catch(e) {}
})();
''');
    } catch (_) {}
  }

  Future<List<PageQualityOption>> _qualityOptionsFromM3u8(String url) async {
    final lower = url.toLowerCase();
    if (!lower.contains('.m3u8') && !lower.contains('/master') && !lower.contains('.urlset/')) {
      return const [];
    }

    try {
      final response = await _dio.get<String>(
        url,
        options: Options(
          headers: _downloadHeaders(url, pageUrl: _capturedVideoPageUrl),
          responseType: ResponseType.plain,
        ),
      );
      final body = response.data ?? '';
      if (!body.contains('#EXT-X-STREAM-INF')) return const [];

      final parsed = <PageQualityOption>[];
      final seen = <String>{};
      final lines = body.split(RegExp(r'\r?\n'));

      for (int i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (!line.startsWith('#EXT-X-STREAM-INF')) continue;

        final height = int.tryParse(
              RegExp(r'RESOLUTION=\d+x(\d+)').firstMatch(line)?.group(1) ?? '',
            ) ??
            0;
        final bandwidth = int.tryParse(
              RegExp(r'BANDWIDTH=(\d+)').firstMatch(line)?.group(1) ?? '',
            ) ??
            0;

        int j = i + 1;
        while (j < lines.length) {
          final candidate = lines[j].trim();
          if (candidate.isNotEmpty && !candidate.startsWith('#')) break;
          j++;
        }
        if (j >= lines.length) continue;

        final child = lines[j].trim();
        final childUrl = Uri.parse(url).resolve(child).toString();
        final label = height > 0 ? '${height}p' : '${(bandwidth / 1000).round()}kbps';
        final key = 'm3u8_${height}_${bandwidth}_${parsed.length}';

        if (seen.add(label)) {
          parsed.add(PageQualityOption(
            label: label,
            key: key,
            url: childUrl,
            selected: parsed.isEmpty,
          ));
        }
      }

      parsed.sort((a, b) => b.rank.compareTo(a.rank));
      return parsed;
    } catch (_) {
      return const [];
    }
  }

  Future<String> _resolvePlayableM3u8MediaPlaylist(String url, String qualityLabel) async {
    final lower = url.toLowerCase();
    if (!lower.contains('.m3u8') && !lower.contains('/master') && !lower.contains('.urlset/')) {
      return url;
    }

    final targetHeight = int.tryParse(RegExp(r'\d+').firstMatch(qualityLabel)?.group(0) ?? '');
    try {
      final response = await _dio.get<String>(
        url,
        options: Options(
          headers: _downloadHeaders(url, pageUrl: _capturedVideoPageUrl),
          responseType: ResponseType.plain,
        ),
      );
      final body = response.data ?? '';
      if (!body.contains('#EXT-X-STREAM-INF')) return url;

      final lines = body.split(RegExp(r'\r?\n'));
      String? bestUrl;
      int bestScore = -2147483648;

      for (int i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (!line.startsWith('#EXT-X-STREAM-INF')) continue;

        final bw = int.tryParse(RegExp(r'BANDWIDTH=(\d+)').firstMatch(line)?.group(1) ?? '0') ?? 0;
        final height = int.tryParse(RegExp(r'RESOLUTION=\d+x(\d+)').firstMatch(line)?.group(1) ?? '0') ?? 0;

        int j = i + 1;
        while (j < lines.length) {
          final candidate = lines[j].trim();
          if (candidate.isNotEmpty && !candidate.startsWith('#')) break;
          j++;
        }
        if (j >= lines.length) continue;

        final childUrl = Uri.parse(url).resolve(lines[j].trim()).toString();
        if (targetHeight != null && targetHeight > 0 && height == targetHeight) return childUrl;

        final score = targetHeight != null && targetHeight > 0 && height > 0
            ? (100000000 - ((height - targetHeight).abs() * 100000) + bw)
            : bw;
        if (score > bestScore) {
          bestScore = score;
          bestUrl = childUrl;
        }
      }

      return bestUrl ?? url;
    } catch (_) {
      return url;
    }
  }

  String _downloadVideoFileName(String fileName, {bool hls = false}) {
    var safe = _sanitizeFileName(fileName);
    final dot = safe.lastIndexOf('.');
    const ext = '.mp4';
    if (dot <= 0) return '$safe$ext';
    final lower = safe.toLowerCase();
    if (lower.endsWith('.m3u8') || lower.endsWith('.txt') || lower.endsWith('.url')) {
      return '${safe.substring(0, dot)}$ext';
    }
    return safe;
  }

  Future<List<String>> _loadHlsSegmentUrls(String playlistUrl, String qualityLabel) async {
    var mediaPlaylistUrl = await _resolvePlayableM3u8MediaPlaylist(playlistUrl, qualityLabel);
    final loaded = <String>{};

    for (int depth = 0; depth < 3; depth++) {
      if (!loaded.add(mediaPlaylistUrl)) break;

      final response = await _dio.get<String>(
        mediaPlaylistUrl,
        options: Options(
          headers: _downloadHeaders(mediaPlaylistUrl, pageUrl: _capturedVideoPageUrl),
          responseType: ResponseType.plain,
        ),
      );
      final body = response.data ?? '';

      if (RegExp(r'#EXT-X-KEY:.*METHOD=AES-128', caseSensitive: false).hasMatch(body)) {
        throw StateError('هذا الرابط مشفر AES-128 ولا يمكن تحويله إلى ملف عادي من داخل التطبيق');
      }

      if (body.contains('#EXT-X-STREAM-INF')) {
        mediaPlaylistUrl = await _resolvePlayableM3u8MediaPlaylist(mediaPlaylistUrl, qualityLabel);
        continue;
      }

      final out = <String>[];
      final lines = body.split(RegExp(r'\r?\n'));

      for (final rawLine in lines) {
        final line = rawLine.trim();
        if (line.isEmpty) continue;

        if (line.startsWith('#EXT-X-MAP')) {
          final m = RegExp(r'URI="([^"]+)"').firstMatch(line);
          final mapUrl = m?.group(1);
          if (mapUrl != null && mapUrl.isNotEmpty) {
            out.add(Uri.parse(mediaPlaylistUrl).resolve(mapUrl).toString());
          }
          continue;
        }

        if (line.startsWith('#')) continue;
        out.add(Uri.parse(mediaPlaylistUrl).resolve(line).toString());
      }

      return out;
    }

    return const [];
  }


  Future<void> _startHlsDownload(String playlistUrl, String fileName, {String qualityLabel = ''}) async {
    final key = 'hls::$playlistUrl::$qualityLabel';
    if (_discoveredDownloadUrls.contains(key)) return;
    _discoveredDownloadUrls.add(key);

    final safeName = _downloadVideoFileName(fileName, hls: true);
    final dir = await _downloadsBaseDir();
    final fullPath = '${dir.path}/$safeName';
    final tempPath = '$fullPath.downloading';

    final item = DownloadItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      url: playlistUrl,
      fileName: safeName,
      savedPath: tempPath,
      tempPath: tempPath,
      finalPath: fullPath,
      status: 'preparing',
    );

    if (mounted) setState(() => _downloads.insert(0, item));
    _openDownloadsPanel();

    final ok = await _enqueueBackgroundHlsDownload(
      item,
      headers: _downloadHeaders(playlistUrl, pageUrl: _capturedVideoPageUrl),
      pageUrl: _capturedVideoPageUrl ?? _lastTrusted,
      qualityLabel: qualityLabel,
    );
    if (!ok) _discoveredDownloadUrls.remove(key);
  }


  Future<void> _startSmartDownload(String url, String fileName, {String qualityLabel = ''}) async {
    final lower = url.toLowerCase();
    if (lower.contains('.m3u8') || lower.contains('/master') || lower.contains('.urlset/')) {
      await _startHlsDownload(url, fileName, qualityLabel: qualityLabel);
      return;
    }
    await _startDownload(url, _downloadVideoFileName(fileName));
  }

  Future<bool> _preparePlayableCapture({
    required bool forDownload,
    bool showMessage = true,
    PageQualityOption? preferredQuality,
  }) async {
    if (_wc == null || _overlayCaptureBusy) return false;

    _overlayCaptureBusy = true;
    _watchButtonWaitingForCapture = !forDownload;
    _downloadButtonWaitingForCapture = forDownload;
    _pendingDownloadQualityOption = forDownload ? preferredQuality : null;
    _watchLinkReadyForSecondTap = false;
    _suppressAutoOpenUntil = DateTime.now().millisecondsSinceEpoch + 20000;
    _clearPendingNativeIntent();

    _capturedVideoUrl = null;
    _capturedVideoMimeType = null;
    _capturedVideoQualityLabel = null;

    try {
      await _wc!.evaluateJavascript(source: 'window.__asdCollectMediaNow && window.__asdCollectMediaNow();');
      await Future.delayed(const Duration(milliseconds: 150));
    } catch (_) {}

    final targetQuality = preferredQuality;
    if (targetQuality != null) {
      final label = _normalizeQualityLabel(targetQuality.label);
      if (label.isNotEmpty) {
        if (mounted) {
          setState(() => _currentPageQualityLabel = label);
        } else {
          _currentPageQualityLabel = label;
        }
      }

      final directUrl = (targetQuality.url ?? '').trim();
      if (_looksLikePlayableMediaUrl(directUrl)) {
        _capturePlayableUrl(
          directUrl,
          pageUrl: _capturedVideoPageUrl ?? _lastTrusted,
          mimeType: _inferMimeType(directUrl),
        );
        _overlayCaptureBusy = false;
        await _tryCompletePendingQuickAction();
        return true;
      }

      try {
        await _wc!.evaluateJavascript(source: '''
(function(){
  try {
    function trySelect(win) {
      try {
        if (win.__asdSelectQualityOption) {
          return !!win.__asdSelectQualityOption(
            ${jsonEncode(targetQuality.key)},
            ${jsonEncode(label)},
            ${jsonEncode(targetQuality.url ?? '')}
          );
        }
      } catch(e) {}
      return false;
    }
    if (trySelect(window)) return true;
    var ok = false;
    document.querySelectorAll('iframe').forEach(function(fr){
      try { if (!ok && fr.contentWindow) ok = trySelect(fr.contentWindow); } catch(e) {}
    });
    return ok;
  } catch(e) { return false; }
})();
''');
      } catch (_) {}
    }

    if (showMessage) {
      final label = _normalizeQualityLabel(targetQuality?.label ?? '');
      _showSnack(forDownload
          ? (label.isEmpty ? 'جاري التقاط رابط التحميل...' : 'جاري التقاط جودة $label للتحميل...')
          : 'جاري التقاط الرابط. بعد الجاهزية اضغط مشاهدة مرة ثانية');
    }

    await _collectAndClickSitePlayer();

    final ticket = ++_quickActionCaptureTicket;
    for (final ms in const [250, 700, 1200, 2200, 3500, 5200]) {
      Future.delayed(Duration(milliseconds: ms), () async {
        if (!mounted || ticket != _quickActionCaptureTicket) return;
        try { await _wc?.evaluateJavascript(source: 'window.__asdCollectMediaNow && window.__asdCollectMediaNow();'); } catch (_) {}
        if (_watchButtonWaitingForCapture || _downloadButtonWaitingForCapture) {
          await _tryCompletePendingQuickAction();
        }
      });
    }

    Future.delayed(const Duration(seconds: 10), () {
      if (!mounted || ticket != _quickActionCaptureTicket) return;
      if (_watchButtonWaitingForCapture || _downloadButtonWaitingForCapture) {
        _clearQuickActionCaptureWaiters();
        _showSnack('⚠️ لم ألتقط رابط الفيديو بعد');
      }
    });

    return true;
  }

  Future<void> _tryCompletePendingQuickAction() async {
    if (!_hasAnyCapturedPlayableMedia) return;

    _overlayCaptureBusy = false;

    if (_watchButtonWaitingForCapture) {
      _watchButtonWaitingForCapture = false;
      _downloadButtonWaitingForCapture = false;
      _watchLinkReadyForSecondTap = true;
      _showSnack('✅ تم التقاط الرابط. اضغط مشاهدة مرة ثانية للتشغيل');
      return;
    }

    if (_downloadButtonWaitingForCapture) {
      var selectedQuality = _pendingDownloadQualityOption;
      _watchButtonWaitingForCapture = false;
      _downloadButtonWaitingForCapture = false;
      _pendingDownloadQualityOption = null;
      _watchLinkReadyForSecondTap = false;

      if (selectedQuality == null) {
        var options = List<PageQualityOption>.from(_pageQualityOptions);
        if (options.isEmpty && _looksLikePlayableMediaUrl(_capturedVideoUrl)) {
          options = await _qualityOptionsFromM3u8(_capturedVideoUrl!);
          if (options.isNotEmpty && mounted) {
            setState(() => _updatePageQualityOptions(options));
          }
        }

        if (options.isNotEmpty) {
          selectedQuality = await _showDownloadQualityDialog(options);
          if (selectedQuality == null) return;
        }
      }

      await _downloadCapturedQuality(selectedQuality);
    }
  }

  Future<void> _handleOverlayWatchTap() async {
    _clearPendingNativeIntent();

    if (_watchLinkReadyForSecondTap && _hasAnyCapturedPlayableMedia) {
      _clearQuickActionCaptureWaiters();
      _watchLinkReadyForSecondTap = false;
      await _openNativePlayer(force: true);
      return;
    }

    if (_hasAnyCapturedPlayableMedia) {
      _watchLinkReadyForSecondTap = false;
      await _openNativePlayer(force: true);
      return;
    }

    await _preparePlayableCapture(forDownload: false);
  }

  Future<void> _handleOverlayDownloadTap() async {
    _clearPendingNativeIntent();
    _suppressAutoOpenUntil = DateTime.now().millisecondsSinceEpoch + 20000;

    try {
      await _collectQualityOptionsFromAllFrames();
      await Future.delayed(const Duration(milliseconds: 450));
    } catch (_) {}

    var options = List<PageQualityOption>.from(_pageQualityOptions);

    if (options.isEmpty && _looksLikePlayableMediaUrl(_capturedVideoUrl)) {
      options = await _qualityOptionsFromM3u8(_capturedVideoUrl!);
      if (options.isNotEmpty && mounted) {
        setState(() => _updatePageQualityOptions(options));
      }
    }

    if (options.isEmpty) {
      _showSnack('جاري التقاط رابط الفيديو والجودات...');
      await _preparePlayableCapture(forDownload: true);
      return;
    }

    final selected = await _showDownloadQualityDialog(options);
    if (selected == null) return;

    await _preparePlayableCapture(
      forDownload: true,
      preferredQuality: selected,
    );
  }

  Future<PageQualityOption?> _showDownloadQualityDialog(List<PageQualityOption> options) async {
    if (!mounted) return null;
    final sorted = List<PageQualityOption>.from(options)
      ..sort((a, b) => b.rank.compareTo(a.rank));

    return showDialog<PageQualityOption>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: const Color(0xFF18212C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('اختر جودة التحميل', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        children: sorted.map((option) {
          final label = _normalizeQualityLabel(option.label);
          final isCurrent = label == _normalizeQualityLabel(_currentPageQualityLabel ?? '');
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, option),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label.isEmpty ? option.label : label,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                if (isCurrent)
                  const Icon(Icons.check_circle, color: Color(0xFF2e9b34), size: 20),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Future<String> _resolveM3u8VariantForQuality(String url, String qualityLabel) async {
    return _resolvePlayableM3u8MediaPlaylist(url, qualityLabel);
  }

  Future<void> _downloadCapturedQuality([PageQualityOption? selectedQuality]) async {
    var url = (_capturedVideoUrl ?? selectedQuality?.url ?? '').trim();
    if (!_looksLikePlayableMediaUrl(url)) {
      _showSnack('⚠️ لم ألتقط رابط الفيديو الحقيقي بعد');
      return;
    }

    final selectedLabel = _normalizeQualityLabel(
      selectedQuality?.label ?? _currentPageQualityLabel ?? _capturedVideoQualityLabel ?? '',
    );
    if (selectedLabel.isNotEmpty) {
      if (mounted) {
        setState(() => _currentPageQualityLabel = selectedLabel);
      } else {
        _currentPageQualityLabel = selectedLabel;
      }
    }

    final resolvedUrl = await _resolveM3u8VariantForQuality(url, selectedLabel);
    final downloadName = await _downloadFileNameForContent(
      urlOverride: resolvedUrl,
      labelOverride: selectedLabel,
    );
    await _startSmartDownload(
      resolvedUrl,
      downloadName,
      qualityLabel: selectedLabel,
    );
  }

  Future<void> _openNativePlayer({
    bool force = false,
    bool enterPipAfter = false,
    bool replace = false,
    double? startTimeOverride,
    String? forcedUrl,
    String? forcedPageUrl,
    String? forcedMimeType,
  }) async {
    if (!replace && (_nativePlayerActive || _nativePlayerOpening)) return;
    if (_capturedVideoUrl == null || _capturedVideoUrl!.startsWith('blob:')) {
      try { await _wc?.evaluateJavascript(source: 'window.__asdCollectMediaNow && window.__asdCollectMediaNow();'); await Future.delayed(const Duration(milliseconds: 180)); } catch (_) {}
    }
    final mediaUrl = forcedUrl ?? _capturedVideoUrl;
    if (mediaUrl == null || mediaUrl.isEmpty || mediaUrl.startsWith('blob:')) { if (force) _armPendingNativeIntent(); return; }
    if (!force && !_videoPlaying) return;

    _nativePlayerOpening = true;
    final ticket = ++_nativeOpenTicket;
    try {
      await _pauseOriginalSitePlayer();
      final currentPage = (await _wc?.getUrl())?.toString();
      final pageUrl = forcedPageUrl ?? _capturedVideoPageUrl ?? currentPage ?? _lastTrusted;
      final headers = await _buildPipHeaders(mediaUrl, pageUrl: pageUrl);
      final aspectRatio = _safePipAspectRatio();

      final qualityLabel = _currentPageQualityLabel ?? _capturedVideoQualityLabel;

      if (!Platform.isAndroid) {
        if (ticket != _nativeOpenTicket) return;
        if (mounted) {
          setState(() {
            _nativePlayerActive = true;
            _lastNativePlayerUrl = mediaUrl;
          });
        }
        _clearPendingNativeIntent();
        await openUniversalMediaPlayer(
          context,
          url: mediaUrl,
          title: _contentTitleForDownload ?? _currentDocumentTitle ?? 'EGY',
          pageUrl: pageUrl,
          mimeType: forcedMimeType ?? _capturedVideoMimeType ?? _inferMimeType(mediaUrl),
          headers: headers,
          currentTime: startTimeOverride ?? _capturedVideoTime,
          qualityOptions: _pageQualityOptions.map((e) => Map<String, dynamic>.from(e.toMap())).toList(growable: false),
          currentQualityLabel: _normalizeQualityLabel(qualityLabel ?? ''),
          serverOptions: _pageServerOptions.map((e) => Map<String, dynamic>.from(e.toMap())).toList(growable: false),
          currentServerLabel: _currentPageServerLabel ?? '',
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
        await _restoreUI();
        return;
      }

      final ok = await _pip.invokeMethod<bool>('openNativePlayer', {
        'url': mediaUrl,
        'currentTime': startTimeOverride ?? _capturedVideoTime,
        'pageUrl': pageUrl,
        'mimeType': forcedMimeType ?? _capturedVideoMimeType ?? _inferMimeType(mediaUrl),
        'headers': headers,
        'aspectRatioNumerator': aspectRatio['w'],
        'aspectRatioDenominator': aspectRatio['h'],
        'subtitleTracks': const <Map<String, String>>[],
        'qualityOptions': _pageQualityOptions.map((e) => e.toMap()).toList(),
        'currentQualityLabel': _normalizeQualityLabel(qualityLabel ?? ''),
        'serverOptions': _pageServerOptions.map((e) => e.toMap()).toList(),
        'currentServerLabel': _currentPageServerLabel ?? '',
        'autoSelectHighestQuality': false,
      });
      if (ticket != _nativeOpenTicket) return;
      if (ok == true && mounted) {
        setState(() {
          _nativePlayerActive = true;
          _lastNativePlayerUrl = mediaUrl;
        });
        _clearPendingNativeIntent();
        if (enterPipAfter) { await Future.delayed(const Duration(milliseconds: 140)); await _enterPip(); }
      } else if (force) _showSnack('⚠️ تعذّر فتح مشغلك الأصلي');
    } on MissingPluginException {
      if (force) _showSnack('⚠️ المشغل الأصلي غير مفعّل');
      if (!_hasPendingNativeIntent) await _releaseOriginalSitePlayerBlock();
    } catch (_) {
      if (force) _showSnack('⚠️ تعذّر فتح المشغل الأصلي');
      if (!_hasPendingNativeIntent) await _releaseOriginalSitePlayerBlock();
    } finally {
      if (ticket == _nativeOpenTicket) { _nativePlayerOpening = false; if (!_nativePlayerActive && !_hasPendingNativeIntent) _clearPendingNativeIntent(); }
    }
  }

  Future<void> _enterPip() async {
    if (_inPip) return;
    final supported = await _isPipSupported();
    if (!supported) { _showSnack('⚠️ PiP غير مفعّل'); return; }
    if (!_nativePlayerActive) { await _openNativePlayer(force: true, enterPipAfter: true); return; }
    try {
      final ok = await _pip.invokeMethod<bool>('enterPip') ?? false;
      if (ok == true && mounted) {
        setState(() => _inPip = true);
      } else {
        _showSnack('⚠️ تعذّر إدخال المشغل إلى PiP');
      }
    } on MissingPluginException { _showSnack('⚠️ PiP غير مفعّل'); }
    catch (_) { _showSnack('⚠️ تعذّر تفعيل PiP'); }
  }

  Future<void> _enterFullscreen() async {
    if (!mounted || _fullscreen || _fullscreenBusy) return;
    _fullscreenBusy = true;
    try {
      setState(() => _fullscreen = true);
      await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await Future.delayed(const Duration(milliseconds: 80));
      try { await _wc?.evaluateJavascript(source: 'window.__asdForceFullscreenNow && window.__asdForceFullscreenNow();'); } catch (_) {}
    } finally { await Future.delayed(const Duration(milliseconds: 250)); _fullscreenBusy = false; }
  }

  Future<void> _exitFullscreen() async {
    if (!mounted || !_fullscreen || _fullscreenBusy) return;
    _fullscreenBusy = true;
    try {
      setState(() => _fullscreen = false);
      try { await _wc?.evaluateJavascript(source: 'window.__asdExitForcedFullscreen && window.__asdExitForcedFullscreen();'); } catch (_) {}
      await _restoreUI();
    } finally { await Future.delayed(const Duration(milliseconds: 250)); _fullscreenBusy = false; }
  }

  Future<void> _restoreUI() async {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown, DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  Future<bool> _isCloudflareChallengePage() async {
    if (_wc == null) return false;
    try {
      final result = await _wc!.evaluateJavascript(source: r'''
(function(){
  try {
    var href = String(location.href || '').toLowerCase();
    var title = String(document.title || '').toLowerCase();
    var text = String((document.body && document.body.innerText) || '').toLowerCase();
    return href.indexOf('/cdn-cgi/') !== -1 ||
      href.indexOf('challenges.cloudflare.com') !== -1 ||
      title.indexOf('just a moment') !== -1 ||
      title.indexOf('attention required') !== -1 ||
      text.indexOf('verify you are human') !== -1 ||
      text.indexOf('checking your browser') !== -1 ||
      text.indexOf('security of your connection') !== -1 ||
      text.indexOf('التحقق من أنك إنسان') !== -1 ||
      text.indexOf('تحقق من أنك إنسان') !== -1 ||
      !!document.querySelector('#challenge-stage,.cf-turnstile,iframe[src*="challenges.cloudflare.com"],form[action*="/cdn-cgi/"],input[name="cf-turnstile-response"]');
  } catch(e) { return false; }
})();
''');
      return result?.toString().trim().toLowerCase() == 'true';
    } catch (_) {
      return false;
    }
  }

  Future<void> _reinjectScripts() async {
    if (_wc == null) return;
    if (await _isCloudflareChallengePage()) return;
    // Hide the Melbet bottom popup first. This script is intentionally lightweight and
    // still self-skips while a Cloudflare challenge is visible.
    await _wc!.evaluateJavascript(source: _melbetBottomPopupStealth);
    try {
      await _wc!.evaluateJavascript(source: 'window.__asdHideMelbetBottomPopupNow && window.__asdHideMelbetBottomPopupNow();');
    } catch (_) {}
    await _wc!.evaluateJavascript(source: _stealthAdBlock);
    await _wc!.evaluateJavascript(source: _ads);
    await _wc!.evaluateJavascript(source: _popupClickOnly);
    await _wc!.evaluateJavascript(source: _css);
    await _wc!.evaluateJavascript(source: _hideServers);
    await _wc!.evaluateJavascript(source: _sitePlayerActionsOverlay);
    try {
      await _wc!.evaluateJavascript(source: 'window.__asdUpdateSitePlayerActions && window.__asdUpdateSitePlayerActions();');
    } catch (_) {}
    await _wc!.evaluateJavascript(source: _dlCapture);
    await _wc!.evaluateJavascript(source: _serverCapture);
  }

  bool _isAllowedNavigation(String url, bool isMainFrame) {
    if (!url.startsWith('http://') && !url.startsWith('https://')) return false;
    if (_isCloudflareChallengeUrl(url)) return true;
    if (_isB(url) || _isAdResourceUrl(url)) return false;
    if (!isMainFrame) return true;
    if (_isRuntimeAllowed(url)) { _lastTrusted = url; _currentHost = Uri.tryParse(url)?.host; return true; }
    if (url.contains('egydead.pics') || url.contains('egydead')) { _lastTrusted = url; _currentHost = Uri.tryParse(url)?.host; return true; }
    if (url.contains('vibuxer') || url.contains('masukestin') || url.contains('audinifer')) {
      _rememberAllowedHost(url);
      _currentHost = Uri.tryParse(url)?.host;
      return true;
    }
    if (_isW(url)) { _lastTrusted = url; _currentHost = Uri.tryParse(url)?.host; return true; }
    if (_isLikelyDownloadLandingUrl(url)) { _rememberAllowedHost(url); _lastTrusted = url; _currentHost = Uri.tryParse(url)?.host; return true; }
    if (_lastTrusted != null && _canRedir(_lastTrusted!) && (_isW(url) || _isRuntimeAllowed(url))) { _lastTrusted = url; _currentHost = Uri.tryParse(url)?.host; return true; }
    if (_currentHost != null && _canRedir(_currentHost!) && (_isW(url) || _isRuntimeAllowed(url))) { _currentHost = Uri.tryParse(url)?.host; return true; }
    return false;
  }

  void _handleVideoInfo(Map<String, dynamic> info) {
    _capturePlayableUrl(info['url']?.toString(), pageUrl: info['pageUrl']?.toString(), currentTime: (info['currentTime'] as num?)?.toDouble(), mimeType: info['mimeType']?.toString());
    final vw = (info['videoWidth'] as num?)?.toInt() ?? 0, vh = (info['videoHeight'] as num?)?.toInt() ?? 0;
    if (vw > 0 && vh > 0) { _videoAspectW = vw; _videoAspectH = vh; }
  }

  // ─── UI ──────────────────────────────────────────────────────────────────

  Widget _buildDownloadsPanel() {
    final panelHeight = MediaQuery.of(context).size.height * 0.75;
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic,
      top: _showDownloads ? 0 : -(panelHeight + 24), left: 0, right: 0,
      child: SafeArea(bottom: false, child: Container(
        height: panelHeight, margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF203040), Color(0xFF0F1720)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
          borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white10),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.45), blurRadius: 24, offset: const Offset(0, 10))],
        ),
        child: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 14, 8, 8), child: Row(children: [
            Container(width: 38, height: 38, decoration: BoxDecoration(color: Colors.orange.withOpacity(0.15), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.download_rounded, color: Colors.orange)),
            const SizedBox(width: 10),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('التحميلات', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
            ])),
            IconButton(onPressed: _closeDownloadsPanel, icon: const Icon(Icons.keyboard_arrow_up, color: Colors.white70)),
          ])),
          const Divider(color: Colors.white12, height: 1),
          Expanded(child: _downloads.isEmpty
              ? const Center(child: Text('لا توجد تحميلات', style: TextStyle(color: Colors.white38, fontSize: 15)))
              : ListView.builder(padding: const EdgeInsets.all(10), itemCount: _downloads.length, itemBuilder: (context, i) => _buildDownloadCard(_downloads[i]))),
        ]),
      )),
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
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: 108,
            height: 72,
            color: Colors.black26,
            child: d.thumbnailPath != null && File(d.thumbnailPath!).existsSync()
                ? pwaImageFile(d.thumbnailPath!, fit: BoxFit.cover)
                : Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.orange.withOpacity(0.25), Colors.deepOrange.withOpacity(0.15)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Icon(
                      isDone
                          ? Icons.movie_creation_outlined
                          : isErr
                              ? Icons.error_outline
                              : isCancelled
                                  ? Icons.remove_circle_outline
                                  : isPaused
                                      ? Icons.pause_circle_outline_rounded
                                      : Icons.downloading_rounded,
                      color: Colors.white70,
                      size: 30,
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
                  d.fileName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isCancelled ? Colors.white38 : Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                    height: 1.2,
                  ),
                ),
                const Spacer(),
                if (isDownloading || isPaused)
                  Column(
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
                else if (isDone)
                  Text(
                    d.savedPath != null ? 'اكتمل التحميل - اضغط تشغيل' : 'اكتمل التحميل',
                    style: const TextStyle(color: Colors.green, fontSize: 11.5),
                  )
                else if (isErr)
                  const Text('فشل التحميل', style: TextStyle(color: Colors.redAccent, fontSize: 11.5))
                else if (isCancelled)
                  const Text('تم إلغاء التحميل', style: TextStyle(color: Colors.white38, fontSize: 11.5)),
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
      ]),
    );
  }

  Widget _actionBtn({required IconData icon, required Color color, required VoidCallback onTap}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: InkWell(borderRadius: BorderRadius.circular(20), onTap: onTap,
      child: Container(width: 34, height: 34, decoration: BoxDecoration(color: color.withOpacity(0.12), shape: BoxShape.circle), child: Icon(icon, color: color, size: 20))),
  );

  @override
  Widget build(BuildContext context) {
    final activeDownloads = _downloads.where((d) => d.status == 'downloading' || d.status == 'preparing' || d.status == 'paused').length;
    return PopScope(canPop: false, onPopInvokedWithResult: (didPop, _) async {
      if (didPop) return;
      if (_nativePlayerActive) { await _closeNativePlayer(); return; }
      if (_fullscreen) { await _exitFullscreen(); return; }
      if (_showDownloads) { _closeDownloadsPanel(); return; }
      if (_wc != null && await _wc!.canGoBack()) { await _wc!.goBack(); return; }
      if (context.mounted) SystemNavigator.pop();
    }, child: Scaffold(backgroundColor: Colors.black,
      appBar: _fullscreen ? null : PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: AppBar(
          toolbarHeight: 56,
          backgroundColor: const Color(0xFF18212C),
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          titleSpacing: 16,
          title: const Text('EgyDead', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
          actions: [
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 10),
              child: Center(
                child: SizedBox(
                  width: 56,
                  height: 44,
                  child: Stack(clipBehavior: Clip.none, children: [
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white, width: 1.5),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          color: Colors.white,
                          onPressed: () => setState(() => _showDownloads = !_showDownloads),
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
                          child: Text('$activeDownloads', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                        ),
                      ),
                  ]),
                ),
              ),
            ),
          ],
        ),
      ),
      body: Stack(children: [
        InAppWebView(
          initialUrlRequest: URLRequest(url: WebUri('https://egydead.pics/'), headers: {'User-Agent': _ua}),
          pullToRefreshController: _ptr,
          // Important: ad/popup scripts are intentionally NOT injected at document-start.
          // Cloudflare challenge pages are served on the same site origin, so early JS tampering
          // can make the human-verification flow loop forever. They are injected later from
          // _reinjectScripts() only after the page is confirmed not to be a Cloudflare challenge.
          initialUserScripts: UnmodifiableListView([
            UserScript(source: _forcePhoneFullscreen, injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START, forMainFrameOnly: false),
            UserScript(source: _fsVid, injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START, forMainFrameOnly: false),
            UserScript(source: _touchFix, injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START, forMainFrameOnly: false),
            UserScript(source: _iframeVideoFix, injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START, forMainFrameOnly: false),
          ]),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true, useShouldInterceptRequest: true, useShouldOverrideUrlLoading: true,
            useOnDownloadStart: true, allowsInlineMediaPlayback: true, mediaPlaybackRequiresUserGesture: false,
            supportMultipleWindows: true, javaScriptCanOpenWindowsAutomatically: true, useHybridComposition: true,
            disableContextMenu: true, userAgent: _ua, preferredContentMode: UserPreferredContentMode.MOBILE,
            useWideViewPort: false, loadWithOverviewMode: false, textZoom: 100,
            allowsPictureInPictureMediaPlayback: true, isFraudulentWebsiteWarningEnabled: false,
            // Cloudflare's challenge flow depends on browser storage/cookies persisting correctly.
            domStorageEnabled: true, databaseEnabled: true, thirdPartyCookiesEnabled: true, cacheEnabled: true,
            allowFileAccess: true, allowUniversalAccessFromFileURLs: true,
          ),
          onWebViewCreated: (controller) {
            _wc = controller;

            controller.addJavaScriptHandler(handlerName: 'onVid', callback: (args) {
              if (!mounted || args.isEmpty || args[0] is! Map) return;
              final data = Map<String, dynamic>.from(args[0] as Map);
              final playing = data['playing'] == true;
              final info = data['info'];
              if (info is Map) _handleVideoInfo(Map<String, dynamic>.from(info));
              if (playing && (_nativePlayerActive || _nativePlayerOpening)) {
                _pauseOriginalSitePlayer(); _scheduleOriginalPlayerHardPause();
                setState(() { _videoPlaying = false; _videoDetected = true; }); return;
              }
              setState(() { _videoPlaying = playing; if (playing) _videoDetected = true; });
              if (playing && (_watchButtonWaitingForCapture || _downloadButtonWaitingForCapture)) {
                Future.microtask(_tryCompletePendingQuickAction);
              }
            });

            controller.addJavaScriptHandler(handlerName: 'onTime', callback: (args) {
              if (args.isNotEmpty && args[0] != null) _capturedVideoTime = (args[0] as num).toDouble();
            });

            controller.addJavaScriptHandler(handlerName: 'onVideoDimensions', callback: (args) {
              if (args.isNotEmpty && args[0] is Map) {
                final map = Map<String, dynamic>.from(args[0] as Map);
                final vw = (map['width'] as num?)?.toInt() ?? 0, vh = (map['height'] as num?)?.toInt() ?? 0;
                if (vw > 0 && vh > 0) { _videoAspectW = vw; _videoAspectH = vh; }
              }
            });

            controller.addJavaScriptHandler(handlerName: 'onPip', callback: (args) {
              if (args.isNotEmpty && args[0] is Map) _handleVideoInfo(Map<String, dynamic>.from(args[0] as Map));
              _openNativePlayer(force: true);
            });

            controller.addJavaScriptHandler(handlerName: 'onPlayIntent', callback: (args) {
              _clearPendingNativeIntent();
              if (args.isNotEmpty && args[0] is Map) _handleVideoInfo(Map<String, dynamic>.from(args[0] as Map));
              if (_watchButtonWaitingForCapture || _downloadButtonWaitingForCapture) {
                Future.microtask(_tryCompletePendingQuickAction);
              }
            });

            controller.addJavaScriptHandler(handlerName: 'onQualityOptions', callback: (args) {
              if (args.isEmpty || args[0] is! Map) return;
              final data = Map<String, dynamic>.from(args[0] as Map);
              final rawOptions = (data['options'] as List?)
                  ?.whereType<Map>()
                  .map((e) => PageQualityOption.fromMap(Map<String, dynamic>.from(e)))
                  .toList() ?? const <PageQualityOption>[];
              if (mounted) {
                setState(() => _updatePageQualityOptions(rawOptions, data['current']?.toString()));
                if (_nativePlayerActive && rawOptions.isNotEmpty) _updateNativePlayerOptions();
              } else {
                _updatePageQualityOptions(rawOptions, data['current']?.toString());
              }
            });

            controller.addJavaScriptHandler(handlerName: 'onServerOptions', callback: (args) {
              if (args.isEmpty || args[0] is! Map) return;
              final data = Map<String, dynamic>.from(args[0] as Map);
              final rawOptions = (data['options'] as List?)
                  ?.whereType<Map>()
                  .map((e) => PageServerOption.fromMap(Map<String, dynamic>.from(e)))
                  .toList() ?? const <PageServerOption>[];
              if (mounted) {
                setState(() {
                  _pageServerOptions = rawOptions;
                  _currentPageServerLabel = data['current']?.toString() ?? (rawOptions.isNotEmpty ? rawOptions.first.label : null);
                });
                if (_nativePlayerActive && rawOptions.isNotEmpty) _updateNativePlayerOptions();
              }
            });

            controller.addJavaScriptHandler(handlerName: 'onServerIframeChanged', callback: (args) async {
              if (args.isEmpty || args[0] is! Map) return;
              final embedUrl = (Map<String, dynamic>.from(args[0] as Map))['embedUrl']?.toString() ?? '';
              if (embedUrl.isEmpty) return;
              _rememberAllowedHost(embedUrl);
              if (_looksLikePlayableMediaUrl(embedUrl)) {
                _capturePlayableUrl(embedUrl, pageUrl: _capturedVideoPageUrl, mimeType: _inferMimeType(embedUrl));
                if (_serverSwitchPending) { _serverSwitchPending = false; await _openNativePlayer(force: true, replace: true, startTimeOverride: _pendingNativeStartTime, forcedUrl: embedUrl); }
                return;
              }
              if (_serverSwitchPending) _armPendingNativeIntent(6000);
            });

            controller.addJavaScriptHandler(handlerName: 'onDownload', callback: (args) {
              if (args.isNotEmpty && args[0] is Map) {
                final info = Map<String, dynamic>.from(args[0] as Map);
                final url = info['url']?.toString() ?? '';
                if (url.isNotEmpty && !_discoveredDownloadUrls.contains(url)) {
                  unawaited(() async {
                    final fileName = await _downloadFileNameForContent(urlOverride: url);
                    await _startDownload(url, fileName);
                  }());
                }
              }
            });

            controller.addJavaScriptHandler(handlerName: 'onOverlayPlayTap', callback: (args) async {
              await _handleOverlayWatchTap();
            });

            controller.addJavaScriptHandler(handlerName: 'onOverlayDownloadTap', callback: (args) async {
              await _handleOverlayDownloadTap();
            });

            controller.addJavaScriptHandler(handlerName: 'onDownloadLanding', callback: (args) async {
              if (args.isEmpty || args[0] is! Map || _wc == null) return;
              final info = Map<String, dynamic>.from(args[0] as Map);
              final url = info['url']?.toString() ?? '';
              if (url.isEmpty || !_isKnownDownloadProviderUrl(url)) return;
              _rememberAllowedHost(url);
              final currentPage = (await _wc!.getUrl())?.toString() ?? info['pageUrl']?.toString() ?? _lastTrusted;
              _lastTrusted = currentPage ?? _lastTrusted;
              await _wc!.loadUrl(urlRequest: URLRequest(
                url: WebUri(url),
                headers: {'User-Agent': _ua, if ((currentPage ?? '').isNotEmpty) 'Referer': currentPage!},
              ));
            });

            controller.addJavaScriptHandler(handlerName: 'onVideoFound', callback: (args) {
              if (!mounted || args.isEmpty || args[0] is! Map) return;
              final info = Map<String, dynamic>.from(args[0] as Map);
              final foundUrl = info['url']?.toString();
              _capturePlayableUrl(foundUrl, pageUrl: info['pageUrl']?.toString(), currentTime: (info['currentTime'] as num?)?.toDouble(), mimeType: info['mimeType']?.toString());
              if (_serverSwitchPending && foundUrl != null && foundUrl.isNotEmpty && foundUrl != _lastNativePlayerUrl) {
                _serverSwitchPending = false;
                Future.microtask(() => _openNativePlayer(force: true, replace: true, startTimeOverride: _pendingNativeStartTime, forcedUrl: foundUrl, forcedPageUrl: info['pageUrl']?.toString(), forcedMimeType: info['mimeType']?.toString())); return;
              }
              if (_qualitySwitchPending && foundUrl != null && foundUrl.isNotEmpty && foundUrl != _lastNativePlayerUrl) {
                _qualitySwitchPending = false;
                Future.microtask(() => _openNativePlayer(force: true, replace: true, startTimeOverride: _pendingNativeStartTime, forcedUrl: foundUrl, forcedPageUrl: info['pageUrl']?.toString(), forcedMimeType: info['mimeType']?.toString())); return;
              }
              if (_watchButtonWaitingForCapture || _downloadButtonWaitingForCapture) {
                Future.microtask(_tryCompletePendingQuickAction);
              }
            });

            controller.addJavaScriptHandler(handlerName: 'onFS', callback: (args) {
              if (!mounted || _nativePlayerActive || _nativePlayerOpening || args.isEmpty) return;
              final isFullscreen = args[0] == true;
              if (isFullscreen && !_fullscreen) {
                _enterFullscreen();
              } else if (!isFullscreen && _fullscreen) _exitFullscreen();
            });

            controller.addJavaScriptHandler(handlerName: 'onForcePhoneFs', callback: (args) {});
          },
          onEnterFullscreen: (_) => _enterFullscreen(),
          onExitFullscreen: (_) => _exitFullscreen(),
          onCreateWindow: (controller, action) async {
            final rawUrl = action.request.url?.toString() ?? '';
            if (rawUrl.isEmpty) {
              final now = DateTime.now().millisecondsSinceEpoch;
              if (now - _lastBlankPopupWindowAt < 8000) return false;
              _lastBlankPopupWindowAt = now;
              return false;
            }
            if (_isCloudflareChallengeUrl(rawUrl)) return false;
            if (_isB(rawUrl) || _isAdResourceUrl(rawUrl)) return false;
            final popHost = Uri.tryParse(rawUrl)?.host.toLowerCase() ?? '';
            if (popHost.endsWith('.qpon') || popHost.endsWith('.cyou') || popHost.endsWith('.click')) return false;
            if (!_isW(rawUrl) && !_isRuntimeAllowed(rawUrl) && !_isKnownDownloadProviderUrl(rawUrl) && !rawUrl.contains('egydead')) return false;
            if (_isDownloadUrl(rawUrl)) {
              if (!_discoveredDownloadUrls.contains(rawUrl)) {
                unawaited(() async {
                  final fileName = await _downloadFileNameForContent(urlOverride: rawUrl);
                  await _startDownload(rawUrl, fileName);
                }());
              }
              return true;
            }
            if (_isKnownDownloadProviderUrl(rawUrl) || _isAllowedNavigation(rawUrl, true)) {
              _rememberAllowedHost(rawUrl);
              await controller.loadUrl(urlRequest: URLRequest(
                url: WebUri(rawUrl),
                headers: {'User-Agent': _ua, if ((_lastTrusted ?? '').isNotEmpty) 'Referer': _lastTrusted!},
              ));
              return true;
            }
            return false;
          },
          onDownloadStartRequest: (controller, req) {
            final url = req.url.toString();
            if (!_discoveredDownloadUrls.contains(url)) {
              unawaited(() async {
                final fileName = await _downloadFileNameForContent(urlOverride: url);
                await _startDownload(url, fileName);
              }());
            }
          },
          shouldOverrideUrlLoading: (controller, nav) async {
            final url = nav.request.url?.toString() ?? '';
            final isMain = nav.isForMainFrame == true;
            if (!url.startsWith('http://') && !url.startsWith('https://')) return NavigationActionPolicy.CANCEL;
            if (_isCloudflareChallengeUrl(url)) return NavigationActionPolicy.ALLOW;
            if (_isB(url) || _isAdResourceUrl(url)) return NavigationActionPolicy.CANCEL;
            if (!isMain) return NavigationActionPolicy.ALLOW;
            if (_isDownloadUrl(url)) {
              if (!_discoveredDownloadUrls.contains(url)) {
                unawaited(() async {
                  final fileName = await _downloadFileNameForContent(urlOverride: url);
                  await _startDownload(url, fileName);
                }());
              }
              return NavigationActionPolicy.CANCEL;
            }
            if (_isKnownDownloadProviderUrl(url) || _isLikelyDownloadLandingUrl(url)) {
              _rememberAllowedHost(url);
              _lastTrusted = (await controller.getUrl())?.toString() ?? _lastTrusted;
              return NavigationActionPolicy.ALLOW;
            }
            if (_isAllowedNavigation(url, isMain)) return NavigationActionPolicy.ALLOW;
            return NavigationActionPolicy.CANCEL;
          },
          shouldInterceptRequest: (controller, req) async {
            final url = req.url.toString();
            if (_isCloudflareChallengeUrl(url)) return null;
            if (_isAdResourceUrl(url)) return WebResourceResponse(data: Uint8List(0));
            if (_looksLikePlayableMediaUrl(url)) {
              final pageUrl = _capturedVideoPageUrl ?? _lastTrusted;
              final mime = _inferMimeType(url);
              _capturePlayableUrl(url, pageUrl: pageUrl, mimeType: mime);
              final currentPage = (await controller.getUrl())?.toString() ?? pageUrl ?? '';
              final lowerCurrentPage = currentPage.toLowerCase();
              final onPrimaryWatchPage = lowerCurrentPage.contains('egydead') && !lowerCurrentPage.contains('/category/') && !lowerCurrentPage.contains('/tag/') && !lowerCurrentPage.contains('/page/') && !lowerCurrentPage.contains('/author/');
              if (_watchButtonWaitingForCapture || _downloadButtonWaitingForCapture) {
                Future.microtask(_tryCompletePendingQuickAction);
              }
              if (_nativePlayerActive || _nativePlayerOpening) {
                _pauseOriginalSitePlayer(); _scheduleOriginalPlayerHardPause();
                return WebResourceResponse(contentType: 'text/plain', contentEncoding: 'utf-8', data: Uint8List(0));
              }
            }
            return null;
          },
          onTitleChanged: (controller, title) {
            final clean = _cleanDownloadTitle(title ?? '');
            if (clean.isEmpty) return;
            _currentDocumentTitle = clean;
            unawaited(controller.getUrl().then((uri) {
              _rememberContentTitleForDownload(clean, pageUrl: uri?.toString());
            }).catchError((_) {}));
          },
          onLoadStop: (controller, url) async {
            _ptr?.endRefreshing();
            _currentHost = url?.host; _rememberAllowedHost(url?.toString());
            try {
              final pageUrl = url?.toString();
              final title = _cleanDownloadTitle(await controller.getTitle() ?? '');
              if (title.isNotEmpty) {
                _currentDocumentTitle = title;
                _rememberContentTitleForDownload(title, pageUrl: pageUrl);
              }
            } catch (_) {}
            _capturedVideoUrl = null; _capturedVideoTime = 0;
            _capturedVideoPageUrl = url?.toString(); _capturedVideoMimeType = null; _capturedVideoQualityLabel = null;
            _videoAspectW = 16; _videoAspectH = 9; _clearPendingNativeIntent(); _clearQuickActionCaptureWaiters(); _watchLinkReadyForSecondTap = false;
            if (mounted) {
              setState(() {
              _videoDetected = false; _videoPlaying = false;
              _pageQualityOptions = const []; _currentPageQualityLabel = null;
              _pageServerOptions = const []; _currentPageServerLabel = null;
              _serverSwitchPending = false;
            });
            }
            // Give Cloudflare's challenge DOM and cookies a moment to settle before deciding
            // whether it is safe to inject site automation/ad cleanup scripts.
            await Future.delayed(const Duration(milliseconds: 160));
            await _reinjectScripts();
          },
          onProgressChanged: (controller, p) { if (mounted) setState(() => _progress = p / 100); },
          onReceivedServerTrustAuthRequest: (controller, challenge) async => ServerTrustAuthResponse(action: ServerTrustAuthResponseAction.CANCEL),
        ),
        if (_progress < 1.0) LinearProgressIndicator(value: _progress, color: Colors.orange, backgroundColor: Colors.transparent),
        _buildDownloadsPanel(),
      ]),
    ));
  }
}
