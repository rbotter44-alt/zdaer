import 'dart:async';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class UniversalMediaPlayerResult {
  final double positionSeconds;
  final bool completed;

  const UniversalMediaPlayerResult({
    required this.positionSeconds,
    this.completed = false,
  });
}

typedef UniversalOptionCallback = FutureOr<void> Function(Map<String, dynamic> option);

enum _WebResizeMode { full, screen, crop, fit, width, height }

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
  late final html.DivElement _controls;
  late final html.DivElement _hotZone;
  late final html.ButtonElement _fillButton;
  late final html.ButtonElement _fullscreenButton;
  late final html.ButtonElement _closeButton;

  StreamSubscription<html.Event>? _resizeSub;
  StreamSubscription<html.KeyboardEvent>? _keySub;
  final List<StreamSubscription<dynamic>> _interactionSubs = <StreamSubscription<dynamic>>[];
  Timer? _controlsHideTimer;

  late final String _activeUrl;
  _WebResizeMode _resizeMode = _WebResizeMode.full;
  bool _controlsVisible = true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now().microsecondsSinceEpoch;
    _viewType = 'lighton-direct-vidfast-view-$now';
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
      ..src = _activeUrl
      ..allow = 'autoplay; fullscreen; encrypted-media; picture-in-picture; screen-wake-lock'
      ..allowFullscreen = true
      ..referrerPolicy = 'origin'
      ..style.border = '0'
      ..style.backgroundColor = '#000'
      ..style.zIndex = '1';

    _root.append(_iframe);
    _buildHtmlControls();

    void bindInteraction(html.Element target) {
      _interactionSubs.add(target.onMouseEnter.listen((_) => _showControls()));
      _interactionSubs.add(target.onMouseMove.listen((_) => _showControls()));
      _interactionSubs.add(target.onMouseDown.listen((_) => _showControls()));
      _interactionSubs.add(target.onTouchStart.listen((_) => _showControls()));
      _interactionSubs.add(target.onClick.listen((_) => _showControls()));
    }

    // لا نضع طبقة شفافة فوق كامل iframe لأنها تمنع أزرار VidFast.
    // نسمع قدر الإمكان من عنصر iframe نفسه، ونترك hot-zone صغير أسفل اليسار لإظهار أزرارنا عند الحاجة.
    bindInteraction(_root);
    bindInteraction(_iframe);
    bindInteraction(_hotZone);
    bindInteraction(_controls);

    // ignore: undefined_prefixed_name
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) => _root);

    _resizeSub = html.window.onResize.listen((_) {
      _applyFillFit();
      _showControls();
    });
    _keySub = html.window.onKeyDown.listen((html.KeyboardEvent event) {
      final key = (event.key ?? '').toLowerCase();
      if (key == 'escape') {
        event.preventDefault();
        unawaited(_close());
      } else if (key == 'f') {
        event.preventDefault();
        _toggleFill();
      } else if (key == 'enter') {
        event.preventDefault();
        _toggleFullscreen();
      }
    });
    Timer.run(() {
      _applyFillFit();
      _showControls();
    });
    Future<void>.delayed(const Duration(milliseconds: 250), _applyFillFit);
  }

  void _buildHtmlControls() {
    _controls = html.DivElement()
      ..style.position = 'absolute'
      ..style.left = '14px'
      ..style.bottom = '14px'
      ..style.zIndex = '2147483647'
      ..style.display = 'flex'
      ..style.alignItems = 'center'
      ..style.gap = '7px'
      ..style.padding = '7px'
      ..style.borderRadius = '999px'
      ..style.background = 'rgba(0, 0, 0, 0.43)'
      ..style.border = '1px solid rgba(255,255,255,0.18)'
      ..style.setProperty('backdrop-filter', 'blur(6px)')
      ..style.setProperty('-webkit-backdrop-filter', 'blur(6px)')
      ..style.transition = 'opacity 180ms ease, transform 180ms ease'
      ..style.opacity = '1'
      ..style.pointerEvents = 'auto';

    html.ButtonElement makeButton(String text, String title) {
      final b = html.ButtonElement()
        ..text = text
        ..title = title
        ..style.minWidth = '44px'
        ..style.height = '34px'
        ..style.padding = '0 10px'
        ..style.border = '0'
        ..style.borderRadius = '999px'
        ..style.background = 'rgba(255,255,255,0.13)'
        ..style.color = '#fff'
        ..style.fontWeight = '900'
        ..style.fontSize = '13px'
        ..style.cursor = 'pointer'
        ..style.outline = 'none'
        ..style.setProperty('touch-action', 'manipulation');
      _interactionSubs.add(b.onMouseEnter.listen((_) => b.style.background = 'rgba(255,255,255,0.22)'));
      _interactionSubs.add(b.onMouseLeave.listen((_) => b.style.background = 'rgba(255,255,255,0.13)'));
      return b;
    }

    _fillButton = makeButton('FULL', 'FULL / SCREEN / CROP / FIT / WIDTH / HEIGHT');
    _fullscreenButton = makeButton('⛶', 'Fullscreen');
    _closeButton = makeButton('✕', 'Close');

    _interactionSubs.add(_fillButton.onClick.listen((html.MouseEvent event) {
      event.preventDefault();
      event.stopPropagation();
      _toggleFill();
    }));
    _interactionSubs.add(_fullscreenButton.onClick.listen((html.MouseEvent event) {
      event.preventDefault();
      event.stopPropagation();
      _toggleFullscreen();
    }));
    _interactionSubs.add(_closeButton.onClick.listen((html.MouseEvent event) {
      event.preventDefault();
      event.stopPropagation();
      unawaited(_close());
    }));

    _controls
      ..append(_fillButton)
      ..append(_fullscreenButton)
      ..append(_closeButton);
    _root.append(_controls);

    // منطقة صغيرة فقط لإظهار أزرار Light On بدون منع التحكم داخل مشغل VidFast كله.
    _hotZone = html.DivElement()
      ..title = 'Light On controls'
      ..style.position = 'absolute'
      ..style.left = '0'
      ..style.bottom = '0'
      ..style.width = '180px'
      ..style.height = '104px'
      ..style.zIndex = '2147483646'
      ..style.background = 'transparent'
      ..style.pointerEvents = 'auto'
      ..style.setProperty('touch-action', 'manipulation');
    _root.append(_hotZone);
  }

  @override
  void dispose() {
    _resizeSub?.cancel();
    _keySub?.cancel();
    for (final sub in _interactionSubs) {
      try {
        sub.cancel();
      } catch (_) {}
    }
    _interactionSubs.clear();
    _controlsHideTimer?.cancel();
    try {
      _iframe.remove();
      _controls.remove();
      _hotZone.remove();
      _root.remove();
    } catch (_) {}
    _applyImmersivePageCss(false);
    super.dispose();
  }

  void _applyImmersivePageCss(bool enabled) {
    try {
      final htmlEl = html.document.documentElement;
      final body = html.document.body;
      if (enabled) {
        htmlEl?.style
          ..backgroundColor = '#000'
          ..overflow = 'hidden'
          ..width = '100%'
          ..height = '100%'
          ..margin = '0'
          ..padding = '0';
        body?.style
          ..backgroundColor = '#000'
          ..overflow = 'hidden'
          ..width = '100%'
          ..height = '100%'
          ..margin = '0'
          ..padding = '0'
          ..setProperty('overscroll-behavior', 'none');
      } else {
        body?.style.removeProperty('overscroll-behavior');
      }
    } catch (_) {}
  }

  double _viewportWidth() {
    try {
      final visualViewport = js_util.getProperty<Object?>(html.window as Object, 'visualViewport');
      if (visualViewport != null) {
        final value = js_util.getProperty<Object?>(visualViewport, 'width');
        if (value is num && value > 0) return value.toDouble();
      }
    } catch (_) {}
    return (html.window.innerWidth ?? _root.clientWidth).toDouble();
  }

  double _viewportHeight() {
    try {
      final visualViewport = js_util.getProperty<Object?>(html.window as Object, 'visualViewport');
      if (visualViewport != null) {
        final value = js_util.getProperty<Object?>(visualViewport, 'height');
        if (value is num && value > 0) return value.toDouble();
      }
    } catch (_) {}
    return (html.window.innerHeight ?? _root.clientHeight).toDouble();
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

  String _resizeModeLabel([_WebResizeMode? mode]) {
    switch (mode ?? _resizeMode) {
      case _WebResizeMode.full:
        return 'FULL';
      case _WebResizeMode.screen:
        return 'SCREEN';
      case _WebResizeMode.crop:
        return 'CROP';
      case _WebResizeMode.fit:
        return 'FIT';
      case _WebResizeMode.width:
        return 'WIDTH';
      case _WebResizeMode.height:
        return 'HEIGHT';
    }
  }

  String _resizeModeTitle([_WebResizeMode? mode]) {
    switch (mode ?? _resizeMode) {
      case _WebResizeMode.full:
        return 'FULL: يملأ الشاشة مع قص خفيف مثل وضع Android الأساسي';
      case _WebResizeMode.screen:
        return 'SCREEN: تمديد على كامل الشاشة';
      case _WebResizeMode.crop:
        return 'CROP: تكبير وقص أكثر';
      case _WebResizeMode.fit:
        return 'FIT: عرض كامل الصورة بدون قص';
      case _WebResizeMode.width:
        return 'WIDTH: تثبيت العرض على عرض الشاشة';
      case _WebResizeMode.height:
        return 'HEIGHT: تثبيت الارتفاع على ارتفاع الشاشة';
    }
  }

  void _applyFillFit() {
    final cw = (_root.clientWidth > 0 ? _root.clientWidth.toDouble() : _viewportWidth()).clamp(1.0, 10000.0);
    final ch = (_root.clientHeight > 0 ? _root.clientHeight.toDouble() : _viewportHeight()).clamp(1.0, 10000.0);
    const ar = 16.0 / 9.0;
    double w = cw;
    double h = ch;

    switch (_resizeMode) {
      case _WebResizeMode.full:
        // Native FULL: cover the screen and crop the extra area.
        if (cw / ch > ar) {
          w = cw;
          h = cw / ar;
        } else {
          h = ch;
          w = ch * ar;
        }
        break;
      case _WebResizeMode.screen:
        // Native SCREEN: stretch the player surface to the screen.
        w = cw;
        h = ch;
        break;
      case _WebResizeMode.crop:
        // Native CROP: cover like FULL, with a little extra zoom so it is visibly different.
        if (cw / ch > ar) {
          w = cw * 1.10;
          h = (cw / ar) * 1.10;
        } else {
          h = ch * 1.10;
          w = (ch * ar) * 1.10;
        }
        break;
      case _WebResizeMode.fit:
        // Native FIT: contain the whole 16:9 frame.
        if (cw / ch > ar) {
          h = ch;
          w = ch * ar;
        } else {
          w = cw;
          h = cw / ar;
        }
        break;
      case _WebResizeMode.width:
        // Native WIDTH: full width, keep 16:9 height.
        w = cw;
        h = cw / ar;
        break;
      case _WebResizeMode.height:
        // Native HEIGHT: full height, keep 16:9 width.
        h = ch;
        w = ch * ar;
        break;
    }

    _iframe.style
      ..position = 'absolute'
      ..left = '50%'
      ..top = '50%'
      ..width = '${w.ceil()}px'
      ..height = '${h.ceil()}px'
      ..transform = 'translate(-50%, -50%)'
      ..maxWidth = 'none'
      ..maxHeight = 'none';
    _fillButton.text = _resizeModeLabel();
    _fillButton.title = _resizeModeTitle();
  }

  void _showControls() {
    _controlsHideTimer?.cancel();
    _controlsVisible = true;
    _controls.style
      ..opacity = '1'
      ..transform = 'translateY(0)'
      ..pointerEvents = 'auto';
    _controlsHideTimer = Timer(const Duration(seconds: 5), _hideControls);
  }

  void _hideControls() {
    _controlsVisible = false;
    _controls.style
      ..opacity = '0'
      ..transform = 'translateY(10px)'
      ..pointerEvents = 'none';
  }

  Future<void> _close() async {
    await _unlockOrientationIfPossible();
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(const UniversalMediaPlayerResult(positionSeconds: 0));
    }
  }

  Future<void> _toggleFullscreen() async {
    _showControls();
    try {
      if (html.document.fullscreenElement != null) {
        html.document.exitFullscreen();
        await _unlockOrientationIfPossible();
        _forceFullscreenLayout();
      } else {
        await _root.requestFullscreen();
        _applyImmersivePageCss(true);
        await _lockLandscapeIfPossible();
        _forceFullscreenLayout();
      }
    } catch (_) {
      try {
        await html.document.documentElement?.requestFullscreen();
        _applyImmersivePageCss(true);
        await _lockLandscapeIfPossible();
        _forceFullscreenLayout();
      } catch (_) {}
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
      _applyFillFit();
      Future<void>.delayed(const Duration(milliseconds: 120), _applyFillFit);
      Future<void>.delayed(const Duration(milliseconds: 450), _applyFillFit);
    } catch (_) {}
  }

  Future<void> _lockLandscapeIfPossible() async {
    // Android Chrome يسمح بقفل الاتجاه غالبًا بعد الدخول إلى Fullscreen فقط.
    // iOS Safari ومع بعض المتصفحات قد يرفض الطلب؛ لذلك نفشل بصمت ونبقي fullscreen عادي.
    try {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      final orientation = js_util.getProperty<Object?>(html.window.screen as Object, 'orientation');
      if (orientation != null) {
        final result = js_util.callMethod<Object?>(orientation, 'lock', <Object>['landscape']);
        if (result != null) {
          await js_util.promiseToFuture<void>(result);
        }
        return;
      }
    } catch (_) {}

    // Fallback قديم لبعض WebViews/متصفحات Android.
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

  void _toggleFill() {
    _showControls();
    const order = <_WebResizeMode>[
      _WebResizeMode.full,
      _WebResizeMode.screen,
      _WebResizeMode.crop,
      _WebResizeMode.fit,
      _WebResizeMode.width,
      _WebResizeMode.height,
    ];
    final currentIndex = order.indexOf(_resizeMode);
    _resizeMode = order[(currentIndex < 0 ? 0 : currentIndex + 1) % order.length];
    _applyFillFit();
    Future<void>.delayed(const Duration(milliseconds: 80), _applyFillFit);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_close());
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: HtmlElementView(viewType: _viewType),
      ),
    );
  }
}

class _ToggleFillIntent extends Intent {
  const _ToggleFillIntent();
}


class _ControlsPill extends StatelessWidget {
  final String fillLabel;
  final VoidCallback onClose;
  final VoidCallback onToggleFill;

  const _ControlsPill({
    required this.fillLabel,
    required this.onClose,
    required this.onToggleFill,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.42),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MiniButton(
              label: fillLabel,
              tooltip: fillLabel == 'Fill' ? 'ملء الشاشة مع قص بسيط' : 'عرض كامل الصورة بدون قص',
              onTap: onToggleFill,
            ),
            const SizedBox(width: 6),
            _MiniButton(
              label: '✕',
              tooltip: 'إغلاق',
              onTap: onClose,
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  final String label;
  final String tooltip;
  final VoidCallback onTap;

  const _MiniButton({
    required this.label,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minWidth: 42, minHeight: 32),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            alignment: Alignment.center,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
