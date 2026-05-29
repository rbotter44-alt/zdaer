package com.lighton.app

import io.flutter.app.FlutterApplication

class MainApplication : FlutterApplication() {
    override fun onCreate() {
        super.onCreate()
        // لا نشغل فحوصات Native أثناء الإقلاع حتى لا يتجمد التطبيق.
        // فحص التوقيع يبقى من خلال SecurityChannel بعد ظهور الواجهة.
    }
}
