import 'dart:async';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

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
  bool _redirectStarted = false;

  @override
  void initState() {
    super.initState();
    // PWA/GitHub Pages cannot host these old sources reliably inside iframe.
    // Many of them return X-Frame-Options / CSP frame-ancestors and the result is
    // the gray blank page the user saw. Open the site in the same browser tab
    // instead, so the real website loads normally. Browser Back returns to Light On.
    Timer.run(_openSameTab);
  }

  void _openSameTab() {
    if (_redirectStarted) return;
    _redirectStarted = true;
    try {
      html.window.location.assign(widget.initialUrl);
    } catch (_) {
      try {
        html.window.open(widget.initialUrl, '_self');
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(strokeWidth: 3),
              const SizedBox(height: 18),
              Text(
                'جاري فتح ${widget.title}...',
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'إذا لم يفتح تلقائياً اضغط الزر أدناه.',
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: _openSameTab,
                child: const Text('فتح الموقع'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
