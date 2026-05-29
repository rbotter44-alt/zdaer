package com.example.flutter_application_1

import android.content.Intent
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.view.WindowInsetsController
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val SELECTOR_CHANNEL = "app.selector/launch"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
                SecurityGuard.protect(this)
applySelectorWindow()
        enableHighestRefreshRate()
    }

    override fun onResume() {
        super.onResume()
                SecurityGuard.protect(this)
applySelectorWindow()
        enableHighestRefreshRate()
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        enableHighestRefreshRate()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            applySelectorWindow()
            enableHighestRefreshRate()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        BackgroundDownloadBridge.setup(this, flutterEngine.dartExecutor.binaryMessenger)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SELECTOR_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openSource" -> {
                        val source = call.argument<String>("source") ?: ""
                        val target = when (source) {
                            "light_on" -> LightOnActivity::class.java
                            "anime" -> AnimeActivity::class.java
                            "egy" -> EgyActivity::class.java
                            "arab" -> ArabActivity::class.java
                            else -> null
                        }

                        if (target == null) {
                            result.success(false)
                            return@setMethodCallHandler
                        }

                        startActivity(
                            Intent(this, target).apply {
                                putExtra("return_selector_on_close", true)
                            }
                        )

                        // نغلق الواجهة الأولى بعد فتح المصدر حتى لا تظهر خلف PiP.
                        finish()

                        result.success(true)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun applySelectorWindow() {
        try {
            window.decorView.setBackgroundColor(Color.rgb(99, 129, 139))
            window.statusBarColor = Color.TRANSPARENT
            window.navigationBarColor = Color.TRANSPARENT

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                window.insetsController?.setSystemBarsAppearance(
                    0,
                    WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS or
                        WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS
                )
            }
        } catch (_: Exception) {
        }
    }

    private fun enableHighestRefreshRate() {
        try {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return

            val currentDisplay = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                display
            } else {
                @Suppress("DEPRECATION")
                windowManager.defaultDisplay
            } ?: return

            val highestMode = currentDisplay.supportedModes
                .filter { it.refreshRate > 0f }
                .maxWithOrNull(
                    compareBy<android.view.Display.Mode> { it.refreshRate }
                        .thenBy { it.physicalWidth * it.physicalHeight }
                ) ?: return

            val attrs = window.attributes
            attrs.preferredDisplayModeId = highestMode.modeId
            attrs.preferredRefreshRate = highestMode.refreshRate
            window.attributes = attrs

            // لا نكرر الطلب كل أجزاء الثانية؛ فقط عند lifecycle حتى لا يسبب jank.
        } catch (_: Exception) {
        }
    }
}
