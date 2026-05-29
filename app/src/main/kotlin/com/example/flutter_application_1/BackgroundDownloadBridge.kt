package com.example.flutter_application_1

import android.Manifest
import android.app.Activity
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

object BackgroundDownloadBridge {
    private const val CHANNEL = "app.background_downloader"
    private const val NOTIFICATION_PERMISSION_REQUEST = 7607

    fun setup(activity: Activity, messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestNotificationPermission" -> {
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
                "enqueue" -> {
                    val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                    val id = BackgroundDownloadService.enqueue(activity.applicationContext, args)
                    result.success(id)
                }
                "pause" -> {
                    val id = call.argument<String>("id") ?: ""
                    BackgroundDownloadService.pause(activity.applicationContext, id)
                    result.success(true)
                }
                "resume" -> {
                    val id = call.argument<String>("id") ?: ""
                    BackgroundDownloadService.resume(activity.applicationContext, id)
                    result.success(true)
                }
                "cancel" -> {
                    val id = call.argument<String>("id") ?: ""
                    BackgroundDownloadService.cancel(activity.applicationContext, id)
                    result.success(true)
                }
                "delete" -> {
                    val id = call.argument<String>("id") ?: ""
                    BackgroundDownloadService.delete(activity.applicationContext, id)
                    result.success(true)
                }
                "list" -> {
                    val source = call.argument<String>("source")
                    result.success(BackgroundDownloadService.snapshots(source))
                }
                else -> result.notImplemented()
            }
        }
    }
}
