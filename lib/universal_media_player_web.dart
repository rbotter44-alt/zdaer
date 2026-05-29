import 'dart:async';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

class UniversalMediaPlayerResult {
  final double positionSeconds;
  final bool completed;

  const UniversalMediaPlayerResult({
    required this.positionSeconds,
    this.completed = false,
  });
}

typedef UniversalOptionCallback = FutureOr<void> Function(Map<String, dynamic> option);

Future<UniversalMediaPlayerResult?> openUniversalMediaPlayer(
  BuildContext context, {
  required String url,
  String? title,
  String? pageUrl,
  String? mimeType,
  Map<String, String> headers = const <String, String>{},
  double currentTime = 0,
  List<Map<String, dynamic>> qualityOptions = const <Map<String, dynamic>>[],
  String? currentQualityLabel,
  List<Map<String, dynamic>> serverOptions = const <Map<String, dynamic>>[],
  String? currentServerLabel,
  List<Map<String, dynamic>> subtitleTracks = const <Map<String, dynamic>>[],
  UniversalOptionCallback? onQualitySelected,
  UniversalOptionCallback? onServerSelected,
}) {
  return Navigator.of(context).push<UniversalMediaPlayerResult>(
    MaterialPageRoute(
      fullscreenDialog: true,
      maintainState: true,
      builder: (_) => UniversalMediaPlayerWebPage(
        url: url,
        title: title,
        pageUrl: pageUrl,
        currentTime: currentTime,
      ),
    ),
  );
}

class UniversalMediaPlayerWebPage extends StatefulWidget {
  final String url;
  final String? title;
  final String? pageUrl;
  final double currentTime;

  const UniversalMediaPlayerWebPage({
    super.key,
    required this.url,
    this.title,
    this.pageUrl,
    this.currentTime = 0,
  });

  @override
  State<UniversalMediaPlayerWebPage> createState() => _UniversalMediaPlayerWebPageState();
}

class _UniversalMediaPlayerWebPageState extends State<UniversalMediaPlayerWebPage> {
  late final String _viewType;
  late final html.DivElement _root;
  late final html.IFrameElement _iframe;

  StreamSubscription<html.Event>? _resizeSub;
  StreamSubscription<html.Event>? _orientationSub;
  StreamSubscription<html.Event>? _fullscreenSub;
  StreamSubscription<html.Event>? _webkitFullscreenSub;

  late final String _activeUrl;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now().microsecondsSinceEpoch;
    _viewType = 'lighton-direct-source-view-$now';
    _activeUrl = _providerUrlWithDefaults(widget.url.trim());
    _applyImmersivePageCss(true);

    _root = html.DivElement()
      ..style.width = '100vw'
      ..style.height = '100dvh'
      ..style.backgroundColor = '#000'
      ..style.position = 'fixed'
      ..style.left = '0'
      ..style.top = '0'
      ..style.right = '0'
      ..style.bottom = '0'
      ..style.margin = '0'
      ..style.padding = '0'
      ..style.overflow = 'hidden'
      ..style.setProperty('touch-action', 'manipulation')
      ..style.setProperty('user-select', 'none');

    _iframe = html.IFrameElement()
      // لا نضع src مباشرة حتى لا نضيف about:blank/initial navigation في history قدر الإمكان.
      ..allow = 'autoplay; fullscreen; encrypted-media; picture-in-picture; screen-wake-lock; orientation-lock'
      ..allowFullscreen = true
      ..referrerPolicy = 'origin'
      ..style.border = '0'
      ..style.backgroundColor = '#000'
      ..style.position = 'absolute'
      ..style.left = '0'
      ..style.top = '0'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.margin = '0'
      ..style.padding = '0';

    _root.append(_iframe);

    // ignore: undefined_prefixed_name
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) => _root);

    _resizeSub = html.window.onResize.listen((_) => _forceFullscreenLayout());
    _orientationSub = html.EventStreamProvider<html.Event>('orientationchange')
        .forTarget(html.window)
        .listen((_) => _forceFullscreenLayout());

    // إذا ضغط المستخدم زر fullscreen من داخل VidFast نفسه، نقفل landscape ونصلح المقاسات.
    _fullscreenSub = html.EventStreamProvider<html.Event>('fullscreenchange')
        .forTarget(html.document)
        .listen((_) => unawaited(_handleBrowserFullscreenChanged()));
    _webkitFullscreenSub = html.EventStreamProvider<html.Event>('webkitfullscreenchange')
        .forTarget(html.document)
        .listen((_) => unawaited(_handleBrowserFullscreenChanged()));

    Timer.run(() {
      _navigateIframeWithReplace(_activeUrl);
      _forceFullscreenLayout();
    });
    Future<void>.delayed(const Duration(milliseconds: 250), _forceFullscreenLayout);
  }

  @override
  void dispose() {
    _resizeSub?.cancel();
    _orientationSub?.cancel();
    _fullscreenSub?.cancel();
    _webkitFullscreenSub?.cancel();
    unawaited(_unlockOrientationIfPossible());
    try {
      _iframe.remove();
      _root.remove();
    } catch (_) {}
    _applyImmersivePageCss(false);
    super.dispose();
  }

  void _navigateIframeWithReplace(String url) {
    if (url.isEmpty) return;
    try {
      final frameWindow = _iframe.contentWindow;
      if (frameWindow != null) {
        final location = js_util.getProperty<Object?>(frameWindow as Object, 'location');
        if (location != null) {
          js_util.callMethod<Object?>(location, 'replace', <Object>[url]);
          return;
        }
      }
    } catch (_) {}
    _iframe.src = url;
  }

  void _applyImmersivePageCss(bool enabled) {
    try {
      final htmlEl = html.document.documentElement;
      final body = html.document.body;
      if (enabled) {
        final htmlStyle = htmlEl?.style;
        if (htmlStyle != null) {
          htmlStyle
            ..backgroundColor = '#000'
            ..overflow = 'hidden'
            ..width = '100%'
            ..height = '100%'
            ..margin = '0'
            ..padding = '0';
        }

        final bodyStyle = body?.style;
        if (bodyStyle != null) {
          bodyStyle
            ..backgroundColor = '#000'
            ..overflow = 'hidden'
            ..width = '100%'
            ..height = '100%'
            ..margin = '0'
            ..padding = '0';
          bodyStyle.setProperty('overscroll-behavior', 'none');
        }
      } else {
        body?.style.removeProperty('overscroll-behavior');
        body?.style.overflow = '';
      }
    } catch (_) {}
  }

  String _providerUrlWithDefaults(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return text;
    final uri = Uri.tryParse(text);
    if (uri == null || !uri.hasScheme) return text;
    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();
    final isVidFast = host.contains('vidfast.') || host.contains('vidfast.net');
    if (!isVidFast) return text;

    final params = Map<String, String>.from(uri.queryParameters);
    params.putIfAbsent('autoPlay', () => 'true');
    params.putIfAbsent('title', () => 'false');
    params.putIfAbsent('poster', () => 'true');
    params.putIfAbsent('theme', () => 'E50914');
    params.putIfAbsent('sub', () => 'ar');
    if (path.contains('/tv/')) {
      params.putIfAbsent('nextButton', () => 'true');
      params.putIfAbsent('autoNext', () => 'true');
    }
    return uri.replace(queryParameters: params).toString();
  }

  Object? _currentFullscreenElement() {
    try {
      final fs = html.document.fullscreenElement;
      if (fs != null) return fs;
    } catch (_) {}
    try {
      final fs = js_util.getProperty<Object?>(html.document as Object, 'webkitFullscreenElement');
      if (fs != null) return fs;
    } catch (_) {}
    return null;
  }

  bool _isAnyFullscreenActive() => _currentFullscreenElement() != null;

  Future<void> _handleBrowserFullscreenChanged() async {
    final active = _isAnyFullscreenActive();
    if (active) {
      _applyImmersivePageCss(true);
      _forceFullscreenLayout();
      await _lockLandscapeIfPossible();
      Future<void>.delayed(const Duration(milliseconds: 120), _forceFullscreenLayout);
      Future<void>.delayed(const Duration(milliseconds: 420), _forceFullscreenLayout);
    } else {
      await _unlockOrientationIfPossible();
      _applyImmersivePageCss(true);
      _forceFullscreenLayout();
    }
  }

  void _forceFullscreenLayout() {
    try {
      _root.style
        ..position = 'fixed'
        ..left = '0'
        ..top = '0'
        ..right = '0'
        ..bottom = '0'
        ..width = '100vw'
        ..height = '100dvh'
        ..backgroundColor = '#000'
        ..margin = '0'
        ..padding = '0'
        ..overflow = 'hidden';
      _iframe.style
        ..position = 'absolute'
        ..left = '0'
        ..top = '0'
        ..width = '100%'
        ..height = '100%'
        ..margin = '0'
        ..padding = '0'
        ..border = '0'
        ..backgroundColor = '#000';
    } catch (_) {}
  }

  Future<void> _lockLandscapeIfPossible() async {
    try {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      final orientation = js_util.getProperty<Object?>(html.window.screen as Object, 'orientation');
      if (orientation != null) {
        final result = js_util.callMethod<Object?>(orientation, 'lock', <Object>['landscape']);
        if (result != null) await js_util.promiseToFuture<void>(result);
        return;
      }
    } catch (_) {}

    try {
      final screen = html.window.screen as Object;
      for (final method in <String>['lockOrientation', 'mozLockOrientation', 'msLockOrientation']) {
        final fn = js_util.getProperty<Object?>(screen, method);
        if (fn != null) {
          js_util.callMethod<Object?>(screen, method, <Object>['landscape']);
          return;
        }
      }
    } catch (_) {}
  }

  Future<void> _unlockOrientationIfPossible() async {
    try {
      final orientation = js_util.getProperty<Object?>(html.window.screen as Object, 'orientation');
      if (orientation != null) {
        js_util.callMethod<Object?>(orientation, 'unlock', const <Object>[]);
        return;
      }
    } catch (_) {}

    try {
      final screen = html.window.screen as Object;
      for (final method in <String>['unlockOrientation', 'mozUnlockOrientation', 'msUnlockOrientation']) {
        final fn = js_util.getProperty<Object?>(screen, method);
        if (fn != null) {
          js_util.callMethod<Object?>(screen, method, const <Object>[]);
          return;
        }
      }
    } catch (_) {}
  }

  Future<void> _closePlayerRoute() async {
    try {
      if (_isAnyFullscreenActive()) {
        html.document.exitFullscreen();
      }
    } catch (_) {}
    try {
      await _unlockOrientationIfPossible();
    } catch (_) {}
    if (!mounted) return;
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop(const UniversalMediaPlayerResult(positionSeconds: 0));
    }
  }

  @override
  Widget build(BuildContext context) {
    // مهم: لا نترك زر الرجوع يذهب إلى history الخاص بـ iframe/VidFast.
    // Back يجب أن يغلق صفحة المشغل فقط ويرجع إلى آخر صفحة Flutter داخل Light On.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_closePlayerRoute());
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: HtmlElementView(viewType: _viewType),
      ),
    );
  }
}
