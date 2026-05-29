package com.lighton.app

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
        private val SELECTOR_CHANNEL = StringVault.d("3zUyKVLLweisI8xUoEY3ilg3iA")
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
applySelectorWindow()
        enableHighestRefreshRate()
    }

    override fun onResume() {
        super.onResume()
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
        SecurityChannel.install(this, flutterEngine.dartExecutor.binaryMessenger)
        BackgroundDownloadBridge.setup(this, flutterEngine.dartExecutor.binaryMessenger)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SELECTOR_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    StringVault.d("Wsvv7hL7FdrcGg") -> {
                        val source = call.argument<String>(StringVault.d("n7qu_QrZ")) ?: ""
                        val target = when (source) {
                            StringVault.d("8XchekKjalo") -> LightOnActivity::class.java
                            StringVault.d("GHGF_tE") -> AnimeActivity::class.java
                            StringVault.d("gSfN") -> EgyActivity::class.java
                            StringVault.d("fNsPVA") -> ArabActivity::class.java
                            else -> null
                        }

                        if (target == null) {
                            result.success(false)
                            return@setMethodCallHandler
                        }

                        startActivity(
                            Intent(this, target).apply {
                                putExtra(StringVault.d("etMzCJuoHpIDpeTEwn5SbdFj1sBixEtS"), true)
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
