import 'dart:async';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

class PwaExternalSitePage extends StatefulWidget {
  final String title;
  final String initialUrl;

  const PwaExternalSitePage({
    super.key,
    required this.title,
    required this.initialUrl,
  });

  @override
  State<PwaExternalSitePage> createState() => _PwaExternalSitePageState();
}

class _PwaExternalSitePageState extends State<PwaExternalSitePage> {
  late final String _viewType;
  late final html.DivElement _root;
  late final html.IFrameElement _iframe;
  StreamSubscription<html.Event>? _loadSub;

  @override
  void initState() {
    super.initState();
    _viewType = 'lighton-pwa-site-frame-${DateTime.now().microsecondsSinceEpoch}';

    _root = html.DivElement()
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.backgroundColor = '#000'
      ..style.position = 'relative'
      ..style.overflow = 'hidden'
      ..style.margin = '0'
      ..style.padding = '0';

    _iframe = html.IFrameElement()
      ..allow = 'autoplay; fullscreen; encrypted-media; picture-in-picture; clipboard-read; clipboard-write; screen-wake-lock; orientation-lock'
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
      ..style.padding = '0'
      ..style.display = 'block';

    _root.append(_iframe);

    // ignore: undefined_prefixed_name
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) => _root);

    _loadSub = _iframe.onLoad.listen((_) {
      // لا نعرض أي طبقة Flutter فوق الموقع/المشغل.
    });

    Timer.run(() => _load(widget.initialUrl));
  }

  @override
  void dispose() {
    _loadSub?.cancel();
    try {
      _iframe.remove();
      _root.remove();
    } catch (_) {}
    super.dispose();
  }

  void _load(String url) {
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

  @override
  Widget build(BuildContext context) {
    // صفحة PWA للمواقع الخارجية: iframe فقط بدون AppBar وبدون طبقات تحميل سوداء.
    // الرجوع يكون من زر Back الخاص بالمتصفح/الجهاز حتى لا نغطي المشغل بأي UI.
    return Scaffold(
      backgroundColor: Colors.black,
      body: SizedBox.expand(
        child: HtmlElementView(viewType: _viewType),
      ),
    );
  }
}
