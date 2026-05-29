package com.lighton.app

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

object SecurityChannel {
    private val CHANNEL = StringVault.d("XaDnjqsGRK_BixWqXwicB-2y")
    private val METHOD_CHECK = StringVault.d("GneJ8N8")

    fun install(context: Context, messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                METHOD_CHECK -> result.success(SecurityGuard.status(context.applicationContext))
                else -> result.notImplemented()
            }
        }
    }
}
