package com.example.flutter_application_1

import io.flutter.app.FlutterApplication

class MainApplication : FlutterApplication() {
    override fun onCreate() {
        super.onCreate()
        SecurityGuard.install(this)
    }
}
