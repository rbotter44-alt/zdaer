import 'package:flutter/material.dart';

class PwaExternalSitePage extends StatelessWidget {
  final String title;
  final String initialUrl;

  const PwaExternalSitePage({
    super.key,
    required this.title,
    required this.initialUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF102A33),
      appBar: AppBar(
        backgroundColor: const Color(0xFF102A33),
        foregroundColor: Colors.white,
        title: Text(title),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            'هذا القسم يعمل داخل Web/PWA فقط هنا. على Android يستخدم WebView الأصلي.',
            textAlign: TextAlign.center,
            textDirection: TextDirection.rtl,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}
