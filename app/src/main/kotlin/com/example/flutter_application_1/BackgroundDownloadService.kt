package com.example.flutter_application_1

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import java.io.BufferedInputStream
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.max

class BackgroundDownloadService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        createChannel()
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager
            wakeLock = pm?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Cima4U:BackgroundDownloads")
            wakeLock?.setReferenceCounted(false)
            wakeLock?.acquire(6 * 60 * 60 * 1000L)
        } catch (_: Throwable) {}
        val firstTask = foregroundTask()
        if (firstTask != null) {
            startForeground(firstTask.notificationId, buildTaskNotification(firstTask))
            foregroundNotificationId = firstTask.notificationId
        } else {
            startForeground(SUMMARY_NOTIFICATION_ID, buildStarterNotification())
            stopForegroundAndRemove()
            stopSelf()
        }
        startWaitingTasks()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_PAUSE -> pause(applicationContext, intent.getStringExtra(EXTRA_ID) ?: "")
            ACTION_RESUME -> resume(applicationContext, intent.getStringExtra(EXTRA_ID) ?: "")
            ACTION_CANCEL -> cancel(applicationContext, intent.getStringExtra(EXTRA_ID) ?: "")
            ACTION_DELETE -> delete(applicationContext, intent.getStringExtra(EXTRA_ID) ?: "")
            else -> startWaitingTasks()
        }
        return START_STICKY
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        try { if (wakeLock?.isHeld == true) wakeLock?.release() } catch (_: Throwable) {}
        super.onDestroy()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= 26) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Video downloads",
                NotificationManager.IMPORTANCE_LOW
            )
            channel.description = "Download progress with pause and resume actions"
            manager?.createNotificationChannel(channel)
        }
    }

    private fun startWaitingTasks() {
        tasks.values.forEach { task ->
            if (task.worker == null && task.status != "done" && task.status != "error" && !task.cancelRequested) {
                startTask(task)
            }
        }
        refreshSummary()
    }

    private fun startTask(task: DownloadTask) {
        if (task.worker != null) return
        task.worker = Thread {
            runTask(task)
        }.also { it.name = "bg-download-${task.id}"; it.start() }
    }

    private fun runTask(task: DownloadTask) {
        try {
            task.status = "preparing"
            updateNotification(task)
            val finalFile = File(task.finalPath)
            val tempFile = File(task.tempPath)
            finalFile.parentFile?.mkdirs()
            tempFile.parentFile?.mkdirs()
            if (!task.startedOnce) {
                if (finalFile.exists()) finalFile.delete()
                if (tempFile.exists()) tempFile.delete()
                task.startedOnce = true
            }
            if (task.type.lowercase(Locale.US) == "hls") {
                downloadHls(task)
            } else {
                while (!task.cancelRequested && task.status != "done") {
                    waitIfPaused(task)
                    val completed = downloadDirectPass(task)
                    if (completed) break
                    if (task.cancelRequested) break
                    waitIfPaused(task)
                }
            }
            if (task.cancelRequested) {
                task.status = "cancelled"
                updateNotification(task)
                return
            }
            if (tempFile.exists()) {
                if (finalFile.exists()) finalFile.delete()
                tempFile.renameTo(finalFile)
            }
            task.status = "done"
            task.progress = 1.0
            task.downloadedBytes = if (finalFile.exists()) finalFile.length() else task.downloadedBytes
            updateNotification(task)
        } catch (e: Throwable) {
            if (task.cancelRequested) {
                task.status = "cancelled"
            } else {
                task.status = "error"
                task.errorMessage = e.message ?: e.javaClass.simpleName
            }
            updateNotification(task)
        } finally {
            task.worker = null
            refreshSummary()
        }
    }

    private fun downloadDirectPass(task: DownloadTask): Boolean {
        val tempFile = File(task.tempPath)
        var existing = if (tempFile.exists()) tempFile.length() else 0L
        var connection = openConnection(task.url, task.headers, if (existing > 0L) "bytes=$existing-" else null)
        val responseCode = connection.responseCode
        if (existing > 0L && responseCode != HttpURLConnection.HTTP_PARTIAL) {
            try { connection.disconnect() } catch (_: Throwable) {}
            tempFile.delete()
            existing = 0L
            connection = openConnection(task.url, task.headers, null)
        }
        if (connection.responseCode !in 200..299) {
            throw IllegalStateException("HTTP ${connection.responseCode}")
        }
        val contentLength = getContentLength(connection)
        task.totalBytes = if (existing > 0L && connection.responseCode == HttpURLConnection.HTTP_PARTIAL && contentLength > 0L) {
            existing + contentLength
        } else {
            contentLength
        }
        task.downloadedBytes = existing
        task.status = "downloading"
        updateNotification(task)

        try {
            BufferedInputStream(connection.inputStream).use { input ->
                FileOutputStream(tempFile, existing > 0L).use { output ->
                    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                    var lastNotify = 0L
                    while (true) {
                        if (task.cancelRequested) return false
                        if (task.pauseRequested) {
                            task.status = "paused"
                            updateNotification(task)
                            return false
                        }
                        val read = input.read(buffer)
                        if (read < 0) break
                        output.write(buffer, 0, read)
                        task.downloadedBytes += read.toLong()
                        if (task.totalBytes > 0L) {
                            task.progress = (task.downloadedBytes.toDouble() / task.totalBytes.toDouble()).coerceIn(0.0, 0.999)
                        }
                        val now = System.currentTimeMillis()
                        if (now - lastNotify > 700L) {
                            lastNotify = now
                            updateNotification(task)
                        }
                    }
                    output.flush()
                }
            }
        } finally {
            try { connection.disconnect() } catch (_: Throwable) {}
        }
        return true
    }

    private fun downloadHls(task: DownloadTask) {
        val tempFile = File(task.tempPath)
        val downloadedKeys = HashSet<String>()
        FileOutputStream(tempFile, false).use { output ->
            var playlistUrl = selectMediaPlaylistUrl(task, task.url)
            var idleRounds = 0
            var completedParts = 0
            var knownParts = 0
            while (!task.cancelRequested) {
                waitIfPaused(task)
                val body = fetchText(playlistUrl, task.headers)
                if (body.contains("#EXT-X-KEY", ignoreCase = true) &&
                    !body.contains("METHOD=NONE", ignoreCase = true)) {
                    throw IllegalStateException("هذا البث مشفّر ولا يمكن تنزيله مباشرة")
                }
                val parsed = parseMediaPlaylist(playlistUrl, body)
                if (parsed.entries.isEmpty()) {
                    throw IllegalStateException("لم أجد مقاطع داخل ملف HLS")
                }
                knownParts = max(knownParts, parsed.entries.size)
                var newParts = 0
                for (entry in parsed.entries) {
                    if (task.cancelRequested) return
                    waitIfPaused(task)
                    if (!downloadedKeys.add(entry.key)) continue
                    val bytes = fetchBytes(entry.url, task.headers, entry.rangeHeader)
                    output.write(bytes)
                    output.flush()
                    completedParts += 1
                    newParts += 1
                    task.downloadedBytes += bytes.size.toLong()
                    task.totalBytes = 0L
                    task.progress = if (knownParts > 0) {
                        (completedParts.toDouble() / knownParts.toDouble()).coerceIn(0.0, 0.999)
                    } else 0.0
                    task.status = "downloading"
                    updateNotification(task)
                }
                if (parsed.endList) break
                idleRounds = if (newParts == 0) idleRounds + 1 else 0
                if (idleRounds >= 8) break
                val sleepMs = parsed.targetDuration.coerceIn(2, 8) * 1000L
                val until = System.currentTimeMillis() + sleepMs
                while (System.currentTimeMillis() < until) {
                    if (task.cancelRequested) return
                    waitIfPaused(task)
                    Thread.sleep(200L)
                }
            }
        }
    }

    private fun waitIfPaused(task: DownloadTask) {
        if (!task.pauseRequested) return
        task.status = "paused"
        updateNotification(task)
        while (task.pauseRequested && !task.cancelRequested) {
            try {
                Thread.sleep(300L)
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
                break
            }
        }
        if (!task.cancelRequested) {
            task.status = "downloading"
            updateNotification(task)
        }
    }

    private fun openConnection(rawUrl: String, headers: Map<String, String>, range: String? = null): HttpURLConnection {
        val connection = URL(rawUrl).openConnection() as HttpURLConnection
        connection.instanceFollowRedirects = true
        connection.connectTimeout = 25000
        connection.readTimeout = 30000
        connection.requestMethod = "GET"
        headers.forEach { (key, value) ->
            if (key.isNotBlank() && value.isNotBlank()) connection.setRequestProperty(key, value)
        }
        if (!headers.keys.any { it.equals("User-Agent", ignoreCase = true) }) {
            connection.setRequestProperty("User-Agent", DEFAULT_UA)
        }
        if (range != null) connection.setRequestProperty("Range", range)
        return connection
    }

    private fun fetchText(url: String, headers: Map<String, String>): String {
        val connection = openConnection(url, headers, null)
        try {
            if (connection.responseCode !in 200..299) throw IllegalStateException("HTTP ${connection.responseCode}")
            return connection.inputStream.bufferedReader(Charsets.UTF_8).use { it.readText() }
        } finally {
            try { connection.disconnect() } catch (_: Throwable) {}
        }
    }

    private fun fetchBytes(url: String, headers: Map<String, String>, rangeHeader: String? = null): ByteArray {
        val connection = openConnection(url, headers, rangeHeader)
        try {
            if (connection.responseCode !in 200..299) throw IllegalStateException("HTTP ${connection.responseCode}")
            return connection.inputStream.use { it.readBytes() }
        } finally {
            try { connection.disconnect() } catch (_: Throwable) {}
        }
    }

    private fun getContentLength(connection: HttpURLConnection): Long {
        val header = connection.getHeaderField("Content-Length") ?: return -1L
        return header.toLongOrNull() ?: -1L
    }

    private fun selectMediaPlaylistUrl(task: DownloadTask, manifestUrl: String): String {
        val body = fetchText(manifestUrl, task.headers)
        if (!body.contains("#EXT-X-STREAM-INF", ignoreCase = true)) return manifestUrl
        val lines = body.lines()
        val variants = ArrayList<HlsVariant>()
        var pendingBandwidth = 0
        var pendingHeight = 0
        for (lineRaw in lines) {
            val line = lineRaw.trim()
            if (line.startsWith("#EXT-X-STREAM-INF", ignoreCase = true)) {
                pendingBandwidth = Regex("BANDWIDTH=([0-9]+)", RegexOption.IGNORE_CASE).find(line)?.groupValues?.getOrNull(1)?.toIntOrNull() ?: 0
                pendingHeight = Regex("RESOLUTION=[0-9]+x([0-9]+)", RegexOption.IGNORE_CASE).find(line)?.groupValues?.getOrNull(1)?.toIntOrNull() ?: 0
            } else if (line.isNotEmpty() && !line.startsWith("#") && pendingBandwidth >= 0) {
                variants.add(HlsVariant(resolveUrl(manifestUrl, line), pendingBandwidth, pendingHeight))
                pendingBandwidth = 0
                pendingHeight = 0
            }
        }
        if (variants.isEmpty()) return manifestUrl
        val wanted = Regex("([0-9]{3,4})").find(task.qualityLabel ?: "")?.groupValues?.getOrNull(1)?.toIntOrNull()
        if (wanted != null && wanted > 0) {
            val withHeight = variants.filter { it.height > 0 }
            if (withHeight.isNotEmpty()) {
                return withHeight.minByOrNull { kotlin.math.abs(it.height - wanted) }?.url ?: withHeight.last().url
            }
            return variants.maxByOrNull { it.bandwidth }?.url ?: variants.last().url
        }
        return variants.maxWithOrNull(compareBy<HlsVariant> { it.height }.thenBy { it.bandwidth })?.url ?: variants.last().url
    }

    private fun parseMediaPlaylist(baseUrl: String, body: String): ParsedPlaylist {
        val entries = ArrayList<HlsEntry>()
        var targetDuration = 4
        var endList = false
        var pendingRange: String? = null
        var lastRangeEnd = 0L
        for (lineRaw in body.lines()) {
            val line = lineRaw.trim()
            if (line.isEmpty()) continue
            if (line.startsWith("#EXT-X-TARGETDURATION", ignoreCase = true)) {
                targetDuration = line.substringAfter(':', "4").trim().toIntOrNull() ?: 4
            } else if (line.startsWith("#EXT-X-ENDLIST", ignoreCase = true)) {
                endList = true
            } else if (line.startsWith("#EXT-X-MAP", ignoreCase = true)) {
                val uri = Regex("URI=\"([^\"]+)\"").find(line)?.groupValues?.getOrNull(1)
                val byterange = Regex("BYTERANGE=\"([^\"]+)\"").find(line)?.groupValues?.getOrNull(1)
                if (!uri.isNullOrBlank()) {
                    entries.add(HlsEntry(resolveUrl(baseUrl, uri), makeRangeHeader(byterange, 0L), "map:$uri:$byterange"))
                }
            } else if (line.startsWith("#EXT-X-BYTERANGE", ignoreCase = true)) {
                val value = line.substringAfter(':', "").trim()
                pendingRange = makeRangeHeader(value, lastRangeEnd + 1)
                val parts = value.split('@')
                val length = parts.getOrNull(0)?.toLongOrNull() ?: 0L
                val offset = parts.getOrNull(1)?.toLongOrNull() ?: (lastRangeEnd + 1)
                if (length > 0) lastRangeEnd = offset + length - 1
            } else if (!line.startsWith("#")) {
                val resolved = resolveUrl(baseUrl, line)
                val range = pendingRange
                pendingRange = null
                entries.add(HlsEntry(resolved, range, "$resolved:${range ?: ""}"))
            }
        }
        return ParsedPlaylist(entries, targetDuration, endList)
    }

    private fun makeRangeHeader(value: String?, implicitOffset: Long): String? {
        if (value.isNullOrBlank()) return null
        val parts = value.trim().split('@')
        val length = parts.getOrNull(0)?.toLongOrNull() ?: return null
        if (length <= 0L) return null
        val start = parts.getOrNull(1)?.toLongOrNull() ?: implicitOffset
        val end = start + length - 1
        return "bytes=$start-$end"
    }

    private fun resolveUrl(baseUrl: String, child: String): String {
        return try {
            URL(URL(baseUrl), child).toString()
        } catch (_: Throwable) {
            child
        }
    }

    private fun buildStarterNotification(): Notification {
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL_ID) else Notification.Builder(this)
        return builder
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle("Downloads")
            .setContentText("Starting")
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .build()
    }

    private fun buildTaskNotification(task: DownloadTask): Notification {
        val percent = (task.progress * 100.0).toInt().coerceIn(0, 100)
        val title = task.fileName.ifBlank { "Video" }
        val text = when (task.status) {
            "paused" -> "Paused • $percent%"
            "done" -> "Completed"
            "error" -> "Failed${task.errorMessage?.let { ": $it" } ?: ""}"
            "cancelled" -> "Cancelled"
            else -> "Downloading • $percent%"
        }
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL_ID) else Notification.Builder(this)
        builder
            .setSmallIcon(if (task.status == "done") android.R.drawable.stat_sys_download_done else android.R.drawable.stat_sys_download)
            .setContentTitle(title)
            .setContentText(text)
            .setOnlyAlertOnce(true)
            .setOngoing(task.status == "downloading" || task.status == "preparing" || task.status == "paused")
        if (task.totalBytes > 0L || task.progress > 0.0) {
            builder.setProgress(100, percent, task.totalBytes <= 0L && percent == 0)
        } else {
            builder.setProgress(100, 0, true)
        }
        if (task.status == "paused") {
            builder.addAction(android.R.drawable.ic_media_play, "Resume", actionIntent(ACTION_RESUME, task.id, 201))
        } else if (task.status == "downloading" || task.status == "preparing") {
            builder.addAction(android.R.drawable.ic_media_pause, "Pause", actionIntent(ACTION_PAUSE, task.id, 101))
        }
        if (task.status != "done") {
            builder.addAction(android.R.drawable.ic_menu_delete, "Delete", actionIntent(ACTION_DELETE, task.id, 301))
        }
        return builder.build()
    }

    private fun updateNotification(task: DownloadTask) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
        if (task.deleteRequested || task.cancelRequested && !tasks.containsKey(task.id)) {
            manager.cancel(task.notificationId)
            refreshSummary()
            return
        }
        if (task.status == "cancelled") {
            manager.cancel(task.notificationId)
            refreshSummary()
            return
        }
        manager.notify(task.notificationId, buildTaskNotification(task))
        refreshSummary()
    }

    private fun refreshSummary() {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
        try { manager?.cancel(SUMMARY_NOTIFICATION_ID) } catch (_: Throwable) {}
        val active = tasks.values.filter { it.status == "downloading" || it.status == "preparing" || it.status == "paused" }
        if (active.isEmpty()) {
            stopForegroundAndRemove()
            stopSelf()
            return
        }
        val task = active.maxByOrNull { it.notificationId } ?: return
        try {
            startForeground(task.notificationId, buildTaskNotification(task))
            foregroundNotificationId = task.notificationId
        } catch (_: Throwable) {}
    }

    private fun foregroundTask(): DownloadTask? {
        return tasks.values
            .filter { it.status == "downloading" || it.status == "preparing" || it.status == "paused" }
            .maxByOrNull { it.notificationId }
    }

    private fun stopForegroundAndRemove() {
        try {
            if (Build.VERSION.SDK_INT >= 24) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
            foregroundNotificationId = 0
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            manager?.cancel(SUMMARY_NOTIFICATION_ID)
        } catch (_: Throwable) {}
    }

    private fun actionIntent(action: String, id: String, requestBase: Int): PendingIntent {
        val intent = Intent(this, BackgroundDownloadService::class.java)
        intent.action = action
        intent.putExtra(EXTRA_ID, id)
        return PendingIntent.getService(this, requestBase + id.hashCode(), intent, pendingFlags())
    }

    private fun pendingFlags(): Int {
        return if (Build.VERSION.SDK_INT >= 23) PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE else PendingIntent.FLAG_UPDATE_CURRENT
    }

    data class HlsVariant(val url: String, val bandwidth: Int, val height: Int)
    data class HlsEntry(val url: String, val rangeHeader: String?, val key: String)
    data class ParsedPlaylist(val entries: List<HlsEntry>, val targetDuration: Int, val endList: Boolean)

    data class DownloadTask(
        val id: String,
        val source: String,
        val type: String,
        val url: String,
        val fileName: String,
        val tempPath: String,
        val finalPath: String,
        val headers: Map<String, String>,
        val pageUrl: String?,
        val qualityLabel: String?,
        val notificationId: Int,
        @Volatile var status: String = "preparing",
        @Volatile var progress: Double = 0.0,
        @Volatile var downloadedBytes: Long = 0L,
        @Volatile var totalBytes: Long = 0L,
        @Volatile var errorMessage: String? = null,
        @Volatile var pauseRequested: Boolean = false,
        @Volatile var cancelRequested: Boolean = false,
        @Volatile var deleteRequested: Boolean = false,
        @Volatile var worker: Thread? = null,
        @Volatile var startedOnce: Boolean = false,
    )

    companion object {
        private const val CHANNEL_ID = "video_background_downloads"
        private const val SUMMARY_NOTIFICATION_ID = 5000
        private const val ACTION_PAUSE = "com.example.flutter_application_1.BG_DOWNLOAD_PAUSE"
        private const val ACTION_RESUME = "com.example.flutter_application_1.BG_DOWNLOAD_RESUME"
        private const val ACTION_CANCEL = "com.example.flutter_application_1.BG_DOWNLOAD_CANCEL"
        private const val ACTION_DELETE = "com.example.flutter_application_1.BG_DOWNLOAD_DELETE"
        private const val EXTRA_ID = "id"
        private const val DEFAULT_BUFFER_SIZE = 128 * 1024
        private const val DEFAULT_UA = "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36"

        @Volatile private var instance: BackgroundDownloadService? = null
        @Volatile private var foregroundNotificationId: Int = 0
        private val tasks = ConcurrentHashMap<String, DownloadTask>()
        private val nextNotification = AtomicInteger(6100)

        fun enqueue(context: Context, args: Map<*, *>): String {
            val id = (args["id"]?.toString()?.takeIf { it.isNotBlank() }) ?: System.currentTimeMillis().toString()
            val headers = HashMap<String, String>()
            val rawHeaders = args["headers"] as? Map<*, *>
            rawHeaders?.forEach { (key, value) ->
                val k = key?.toString() ?: return@forEach
                val v = value?.toString() ?: return@forEach
                if (k.isNotBlank() && v.isNotBlank()) headers[k] = v
            }
            val task = DownloadTask(
                id = id,
                source = args["source"]?.toString() ?: "unknown",
                type = args["type"]?.toString() ?: "direct",
                url = args["url"]?.toString() ?: "",
                fileName = args["fileName"]?.toString() ?: "video.mp4",
                tempPath = args["tempPath"]?.toString() ?: "",
                finalPath = args["finalPath"]?.toString() ?: "",
                headers = headers,
                pageUrl = args["pageUrl"]?.toString(),
                qualityLabel = args["qualityLabel"]?.toString(),
                notificationId = nextNotification.incrementAndGet()
            )
            if (task.url.isBlank() || task.tempPath.isBlank() || task.finalPath.isBlank()) {
                throw IllegalArgumentException("Missing download url/path")
            }
            tasks[id] = task
            val intent = Intent(context, BackgroundDownloadService::class.java)
            if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent) else context.startService(intent)
            instance?.startTask(task)
            return id
        }

        fun pause(context: Context, id: String) {
            val task = tasks[id] ?: return
            task.pauseRequested = true
            task.status = "paused"
            instance?.updateNotification(task)
            val intent = Intent(context, BackgroundDownloadService::class.java)
            if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent) else context.startService(intent)
        }

        fun resume(context: Context, id: String) {
            val task = tasks[id] ?: return
            task.pauseRequested = false
            if (task.status == "paused") task.status = "downloading"
            val intent = Intent(context, BackgroundDownloadService::class.java)
            if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent) else context.startService(intent)
            instance?.startTask(task)
            instance?.updateNotification(task)
        }

        fun cancel(context: Context, id: String) {
            val task = tasks[id] ?: return
            task.cancelRequested = true
            task.pauseRequested = false
            task.worker?.interrupt()
            task.status = "cancelled"
            instance?.updateNotification(task)
            val intent = Intent(context, BackgroundDownloadService::class.java)
            if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent) else context.startService(intent)
        }

        fun delete(context: Context, id: String) {
            val task = tasks.remove(id) ?: return
            task.deleteRequested = true
            task.cancelRequested = true
            task.pauseRequested = false
            task.worker?.interrupt()
            try { File(task.tempPath).delete() } catch (_: Throwable) {}
            try { File(task.finalPath).delete() } catch (_: Throwable) {}
            try {
                val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                manager?.cancel(task.notificationId)
                manager?.cancel(SUMMARY_NOTIFICATION_ID)
            } catch (_: Throwable) {}
            instance?.refreshSummary()
        }

        fun snapshots(source: String?): List<Map<String, Any?>> {
            val wanted = source?.trim()?.takeIf { it.isNotEmpty() }
            return tasks.values
                .filter { wanted == null || it.source == wanted }
                .sortedByDescending { it.notificationId }
                .map { task ->
                    mapOf(
                        "id" to task.id,
                        "source" to task.source,
                        "type" to task.type,
                        "url" to task.url,
                        "fileName" to task.fileName,
                        "tempPath" to task.tempPath,
                        "finalPath" to task.finalPath,
                        "status" to task.status,
                        "progress" to task.progress,
                        "downloadedBytes" to task.downloadedBytes,
                        "totalBytes" to task.totalBytes,
                        "errorMessage" to task.errorMessage,
                        "qualityLabel" to task.qualityLabel
                    )
                }
        }
    }
}
