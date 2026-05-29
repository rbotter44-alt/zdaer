package com.lighton.app

import android.Manifest
import android.app.Activity
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

object BackgroundDownloadBridge {
    private val CHANNEL = StringVault.d("3OgZ2S8RoC_0PBcfUgIj0xOPeOq-U_XATQ")
    private const val NOTIFICATION_PERMISSION_REQUEST = 7607

    fun setup(activity: Activity, messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                StringVault.d("44JlDjmFxGbUryBds9yKc6Widx8feMNs4Ay0yuk") -> {
                    if (Build.VERSION.SDK_INT >= 33) {
                        try {
                            activity.requestPermissions(
                                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                                NOTIFICATION_PERMISSION_REQUEST
                            )
                        } catch (_: Throwable) {}
                    }
                    result.success(true)
                }
                StringVault.d("Fp51A8ULzQ") -> {
                    val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                    val id = BackgroundDownloadService.enqueue(activity.applicationContext, args)
                    result.success(id)
                }
                StringVault.d("CX6Z4NE") -> {
                    val id = call.argument<String>(StringVault.d("EWE")) ?: ""
                    BackgroundDownloadService.pause(activity.applicationContext, id)
                    result.success(true)
                }
                StringVault.d("nrCo-gTZ") -> {
                    val id = call.argument<String>(StringVault.d("EWE")) ?: ""
                    BackgroundDownloadService.resume(activity.applicationContext, id)
                    result.success(true)
                }
                StringVault.d("j7S17AzQ") -> {
                    val id = call.argument<String>(StringVault.d("EWE")) ?: ""
                    BackgroundDownloadService.cancel(activity.applicationContext, id)
                    result.success(true)
                }
                StringVault.d("iLC36h3Z") -> {
                    val id = call.argument<String>(StringVault.d("EWE")) ?: ""
                    BackgroundDownloadService.delete(activity.applicationContext, id)
                    result.success(true)
                }
                StringVault.d("ccAdQg") -> {
                    val source = call.argument<String>(StringVault.d("n7qu_QrZ"))
                    result.success(BackgroundDownloadService.snapshots(source))
                }
                else -> result.notImplemented()
            }
        }
    }
}
