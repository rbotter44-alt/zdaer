package com.lighton.app

import android.content.Intent
import android.app.AlertDialog
import android.app.Dialog
import android.app.PictureInPictureParams
import android.content.pm.ActivityInfo
import android.content.ContentUris
import android.content.ContentValues
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.Rect
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.provider.MediaStore
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.util.Log
import android.util.Rational
import android.util.TypedValue
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.widget.Button
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.TextView
import android.view.WindowManager
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.CaptionStyleCompat
import androidx.media3.ui.PlayerView
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import kotlin.math.max
import kotlin.math.roundToLong

class AnimeActivity : FlutterActivity() {

    override fun getDartEntrypointFunctionName(): String = StringVault.d("Cff2kvkG-Agr")


    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        enableHighRefreshRate()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) enableHighRefreshRate()
    }

    private fun enableHighRefreshRate() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        try {
            val currentDisplay = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) display
            else @Suppress("DEPRECATION") windowManager.defaultDisplay
            val modes = currentDisplay?.supportedModes ?: emptyArray()
            val highestMode = modes.maxByOrNull { it.refreshRate }
            val params: WindowManager.LayoutParams = window.attributes
            var changed = false

            if (highestMode != null) {
                val targetHz = highestMode.refreshRate
                if (params.preferredDisplayModeId != highestMode.modeId) {
                    params.preferredDisplayModeId = highestMode.modeId
                    changed = true
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
                    kotlin.math.abs(params.preferredRefreshRate - targetHz) > 0.01f
                ) {
                    params.preferredRefreshRate = targetHz
                    changed = true
                }
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
                kotlin.math.abs(params.preferredRefreshRate - 120f) > 0.01f
            ) {
                params.preferredRefreshRate = 120f
                changed = true
            }

            if (changed) window.attributes = params
        } catch (e: Exception) {
            Log.w(LOG_TAG, "enableHighRefreshRate failed", e)
        }
    }

    companion object {
        private val CHANNEL = StringVault.d("ocxecOv8d7yQIInjeQ")
        private const val MIN_PIP_RATIO = 0.41841
        private const val MAX_PIP_RATIO = 2.39
        private const val LOG_TAG = "NativePlayer"
        private const val SUBTITLE_PREFS = "native_subtitle_prefs"
        private const val PREF_SUB_SIZE = "subtitle_size_percent"
        private const val PREF_SUB_OFFSET = "subtitle_vertical_offset_percent"
        private const val PREF_SUB_BG = "subtitle_background_enabled"
        private const val PREF_SUB_DELAY = "subtitle_delay_ms"
        private const val PREF_SUB_DELAY_PROFILE_PREFIX = "subtitle_delay_profile_"
        private const val MAX_SUB_DELAY_MS = 15000
        private const val PREF_SUB_STYLE_VERSION = "subtitle_style_version"
        private const val CURRENT_SUB_STYLE_VERSION = 2
        private var instance: AnimeActivity? = null

        fun updateOptions(
            qualityOptions: List<Map<String, Any?>>,
            currentQualityLabel: String,
            serverOptions: List<Map<String, Any?>>,
            currentServerLabel: String,
        ) {
            instance?.runOnUiThread {
                instance?.applyUpdatedOptions(
                    qualityOptions = qualityOptions,
                    currentQualityLabel = currentQualityLabel,
                    serverOptions = serverOptions,
                    currentServerLabel = currentServerLabel,
                )
            }
        }
    }

    private var channel: MethodChannel? = null
    private var exoPlayer: ExoPlayer? = null
    private var playerView: PlayerView? = null
    private var playerContainer: FrameLayout? = null
    private var loadingOverlay: FrameLayout? = null
    private var loadingTextView: TextView? = null
    private var controlsScroll: HorizontalScrollView? = null
    private var controlsBar: LinearLayout? = null
    private var flutterContentView: View? = null

    private var fitButton: Button? = null
    private var qualityButton: Button? = null
    private var serverButton: Button? = null
    private var subtitleButton: Button? = null
    private var pipButton: Button? = null
    private var closeButton: Button? = null

    private var controllerVisible = true
    private var waitFirstRenderedFrame = false
    private var nativePlayerActive = false
    private var nativePlayerClosing = false
    private var currentResizeMode = AspectRatioFrameLayout.RESIZE_MODE_FILL
    private var inManualPipTransition = false
    private var beforePipResizeMode = AspectRatioFrameLayout.RESIZE_MODE_FILL
    private var pipControllerEnabledBeforeStableMode = true
    private var lastAspectW = 16
    private var lastAspectH = 9
    private var requestedPipRatio: Rational? = null
    private var pageQualityOptions: List<PageQualityOption> = emptyList()
    private var pageServerOptions: List<PageServerOption> = emptyList()
    private var externalSubtitleTracks: List<ExternalSubtitle> = emptyList()

    // ─── Track currently selected subtitle URL (null = off) ───────────────
    private var selectedSubtitleUrl: String? = null
    // ─── Current media URL and headers (needed to reload with subtitle) ───
    private var currentMediaUrl: String? = null
    private var currentMediaMime: String? = null
    private var currentMediaHeaders: Map<String, String> = emptyMap()
    private var selectedSubtitleResolvedUrl: String? = null
    private var manualSubtitleSelection = false
    private var activeSubtitleRawTrack: ExternalSubtitle? = null
    private var activeSubtitleProfileKey: String? = null
    private var activeSubtitleRateMultiplier = 1.0

    private lateinit var subtitlePrefs: SharedPreferences
    private var subtitleSizePercent = 140
    private var subtitleVerticalOffsetPercent = 5
    private var subtitleBackgroundEnabled = false
    private var subtitleDelayMs = 0

    private data class TrackChoice(
        val label: String,
        val group: Tracks.Group,
        val trackIndex: Int,
        val selected: Boolean,
    )

    private data class ExternalSubtitle(
        val url: String,
        val label: String,
        val language: String,
        val source: String,
        val mimeType: String?,
        val autoSelect: Boolean,
        val release: String,
        val hearingImpaired: Boolean,
        val hashMatched: Boolean,
    )

    private data class PageQualityOption(
        val label: String,
        val key: String,
        val url: String?,
        val selected: Boolean,
    )

    private data class PageServerOption(
        val label: String,
        val key: String,
        val embedUrl: String?,
        val selected: Boolean,
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
instance = this
        subtitlePrefs = getSharedPreferences(SUBTITLE_PREFS, MODE_PRIVATE)
        loadSubtitlePrefs()
        window.decorView.setBackgroundColor(Color.BLACK)
        enableHighRefreshRate()
    }


    private fun shouldReturnSelectorOnClose(): Boolean {
        return intent?.getBooleanExtra(StringVault.d("etMzCJuoHpIDpeTEwn5SbdFj1sBixEtS"), true) != false
    }

    private fun openSelectorAfterSourceClose() {
        if (!shouldReturnSelectorOnClose()) return
        if (isChangingConfigurations) return

        try {
            val selectorIntent = Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            }
            startActivity(selectorIntent)
        } catch (_: Exception) {
        }
    }

    override fun finish() {
        openSelectorAfterSourceClose()
        super.finish()
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        if (nativePlayerActive || nativePlayerClosing) {
            closeNativePlayer()
            return
        }
        super.onBackPressed()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        SecurityChannel.install(this, flutterEngine.dartExecutor.binaryMessenger)
        BackgroundDownloadBridge.setup(this, flutterEngine.dartExecutor.binaryMessenger)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "isPipSupported" -> result.success(isPipSupported())

                "openNativePlayer" -> {
                    val url = call.argument<String>("url")
                    val startTime = call.argument<Double>("currentTime") ?: 0.0
                    val mimeType = call.argument<String>("mimeType")
                    val aspectW = call.argument<Int>("aspectRatioNumerator") ?: 16
                    val aspectH = call.argument<Int>("aspectRatioDenominator") ?: 9
                    @Suppress("UNCHECKED_CAST")
                    val headers = (call.argument<Map<String, Any?>>("headers") ?: emptyMap())
                        .mapNotNull { (k, v) -> if (k.isBlank()) null else k to (v?.toString() ?: "") }
                        .toMap()
                    @Suppress("UNCHECKED_CAST")
                    val rawSubs = call.argument<List<Map<String, Any?>>>("subtitleTracks")
                    val subtitleTracks = parseSubtitleTracks(rawSubs)
                    @Suppress("UNCHECKED_CAST")
                    val rawQualities = call.argument<List<Map<String, Any?>>>("qualityOptions")
                    val currentQualityLabel = call.argument<String>("currentQualityLabel")
                    val qualityOptions = parseQualityOptions(rawQualities, currentQualityLabel)
                    @Suppress("UNCHECKED_CAST")
                    val rawServers = call.argument<List<Map<String, Any?>>>("serverOptions")
                    val currentServerLabel = call.argument<String>("currentServerLabel")
                    val serverOptions = parseServerOptions(rawServers, currentServerLabel)
                    result.success(
                        openNativePlayer(
                            url = url,
                            startTime = startTime,
                            mimeType = mimeType,
                            headers = headers,
                            subtitleTracks = subtitleTracks,
                            aspectW = aspectW,
                            aspectH = aspectH,
                            qualityOptions = qualityOptions,
                            serverOptions = serverOptions,
                        )
                    )
                }

                "openNativePlayerShell" -> {
                    val aspectW = call.argument<Int>("aspectRatioNumerator") ?: 16
                    val aspectH = call.argument<Int>("aspectRatioDenominator") ?: 9
                    @Suppress("UNCHECKED_CAST")
                    val rawQualities = call.argument<List<Map<String, Any?>>>("qualityOptions")
                    val currentQualityLabel = call.argument<String>("currentQualityLabel")
                    val qualityOptions = parseQualityOptions(rawQualities, currentQualityLabel)
                    @Suppress("UNCHECKED_CAST")
                    val rawServers = call.argument<List<Map<String, Any?>>>("serverOptions")
                    val currentServerLabel = call.argument<String>("currentServerLabel")
                    val serverOptions = parseServerOptions(rawServers, currentServerLabel)
                    @Suppress("UNCHECKED_CAST")
                    val rawSubs = call.argument<List<Map<String, Any?>>>("subtitleTracks")
                    val subtitleTracks = parseSubtitleTracks(rawSubs)
                    result.success(
                        openNativePlayerShell(
                            aspectW = aspectW,
                            aspectH = aspectH,
                            qualityOptions = qualityOptions,
                            serverOptions = serverOptions,
                            subtitleTracks = subtitleTracks,
                        )
                    )
                }

                "updateNativePlayerSource" -> {
                    val url = call.argument<String>("url")
                    val startTime = call.argument<Double>("currentTime") ?: 0.0
                    val mimeType = call.argument<String>("mimeType")
                    val aspectW = call.argument<Int>("aspectRatioNumerator") ?: lastAspectW
                    val aspectH = call.argument<Int>("aspectRatioDenominator") ?: lastAspectH
                    @Suppress("UNCHECKED_CAST")
                    val headers = (call.argument<Map<String, Any?>>("headers") ?: emptyMap())
                        .mapNotNull { (k, v) -> if (k.isBlank()) null else k to (v?.toString() ?: "") }
                        .toMap()
                    @Suppress("UNCHECKED_CAST")
                    val rawSubs = call.argument<List<Map<String, Any?>>>("subtitleTracks")
                    val subtitleTracks = parseSubtitleTracks(rawSubs)
                    @Suppress("UNCHECKED_CAST")
                    val rawQualities = call.argument<List<Map<String, Any?>>>("qualityOptions")
                    val currentQualityLabel = call.argument<String>("currentQualityLabel")
                    val qualityOptions = parseQualityOptions(rawQualities, currentQualityLabel)
                    @Suppress("UNCHECKED_CAST")
                    val rawServers = call.argument<List<Map<String, Any?>>>("serverOptions")
                    val currentServerLabel = call.argument<String>("currentServerLabel")
                    val serverOptions = parseServerOptions(rawServers, currentServerLabel)
                    result.success(
                        updateNativePlayerSource(
                            url = url,
                            startTime = startTime,
                            mimeType = mimeType,
                            headers = headers,
                            subtitleTracks = subtitleTracks,
                            aspectW = aspectW,
                            aspectH = aspectH,
                            qualityOptions = qualityOptions,
                            serverOptions = serverOptions,
                        )
                    )
                }

                "updatePlayerOptions" -> {
                    @Suppress("UNCHECKED_CAST")
                    val rawQualities = call.argument<List<Map<String, Any?>>>("qualityOptions")
                    val currentQualityLabel = call.argument<String>("currentQualityLabel") ?: ""
                    @Suppress("UNCHECKED_CAST")
                    val rawServers = call.argument<List<Map<String, Any?>>>("serverOptions")
                    val currentServerLabel = call.argument<String>("currentServerLabel") ?: ""
                    @Suppress("UNCHECKED_CAST")
                    val rawSubs = call.argument<List<Map<String, Any?>>>("subtitleTracks")
                    applyUpdatedOptions(
                        qualityOptions = rawQualities ?: emptyList(),
                        currentQualityLabel = currentQualityLabel,
                        serverOptions = rawServers ?: emptyList(),
                        currentServerLabel = currentServerLabel,
                        subtitleTracks = parseSubtitleTracks(rawSubs),
                    )
                    result.success(true)
                }

                "enterPip" -> result.success(enterNativePip())

                "getCurrentPosition" -> {
                    val pos = exoPlayer?.currentPosition ?: 0L
                    result.success(pos.toDouble() / 1000.0)
                }

                "closeNativePlayer" -> {
                    closeNativePlayer()
                    result.success(true)
                }

                "readSharedQualityProfile" -> {
                    val relativePath = call.argument<String>("relativePath") ?: "ASDPlayer/quality_profile.json"
                    result.success(readSharedQualityProfile(relativePath))
                }

                "writeSharedQualityProfile" -> {
                    val relativePath = call.argument<String>("relativePath") ?: "ASDPlayer/quality_profile.json"
                    val content = call.argument<String>("content") ?: ""
                    result.success(writeSharedQualityProfile(relativePath, content))
                }

                else -> result.notImplemented()
            }
        }
    }



    private data class SharedProfileParts(
        val displayName: String,
        val relativePath: String,
    )

    private fun splitSharedProfilePath(relativePath: String): SharedProfileParts {
        val clean = relativePath
            .replace('\\', '/')
            .trim('/')
            .ifBlank { "ASDPlayer/quality_profile.json" }

        val segments = clean.split('/').filter { it.isNotBlank() }
        val displayName = segments.lastOrNull()?.takeIf { it.isNotBlank() } ?: "quality_profile.json"
        val folderSegments = segments.dropLast(1)
        val relativeDir = buildString {
            append(Environment.DIRECTORY_DOWNLOADS)
            append("/")
            if (folderSegments.isNotEmpty()) {
                append(folderSegments.joinToString("/"))
                append("/")
            }
        }
        return SharedProfileParts(
            displayName = displayName,
            relativePath = relativeDir,
        )
    }

    private fun findSharedQualityProfileUri(parts: SharedProfileParts): Uri? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
        val projection = arrayOf(MediaStore.MediaColumns._ID)
        val selection = "${MediaStore.MediaColumns.DISPLAY_NAME}=? AND ${MediaStore.MediaColumns.RELATIVE_PATH}=?"
        val args = arrayOf(parts.displayName, parts.relativePath)

        contentResolver.query(collection, projection, selection, args, null)?.use { cursor ->
            if (!cursor.moveToFirst()) return null
            val id = cursor.getLong(cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID))
            return ContentUris.withAppendedId(collection, id)
        }
        return null
    }

    private fun legacySharedQualityProfileFile(relativePath: String): File {
        val clean = relativePath.replace('\\', '/').trim('/').ifBlank { "ASDPlayer/quality_profile.json" }
        val base = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        return File(base, clean)
    }

    private fun readSharedQualityProfile(relativePath: String): String? {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val parts = splitSharedProfilePath(relativePath)
                val uri = findSharedQualityProfileUri(parts)
                if (uri != null) {
                    return contentResolver.openInputStream(uri)?.bufferedReader(Charsets.UTF_8)?.use { it.readText() }
                }
            }

            val legacy = legacySharedQualityProfileFile(relativePath)
            if (legacy.exists()) {
                Log.d(LOG_TAG, "readSharedQualityProfile legacy hit: ${legacy.absolutePath}")
                return legacy.readText(Charsets.UTF_8)
            }
            null
        } catch (e: Exception) {
            Log.e(LOG_TAG, "readSharedQualityProfile failed", e)
            null
        }
    }

    private fun writeSharedQualityProfile(relativePath: String, content: String): String? {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val parts = splitSharedProfilePath(relativePath)
                val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
                var targetUri = findSharedQualityProfileUri(parts)

                if (targetUri == null) {
                    val values = ContentValues().apply {
                        put(MediaStore.MediaColumns.DISPLAY_NAME, parts.displayName)
                        put(MediaStore.MediaColumns.MIME_TYPE, "application/json")
                        put(MediaStore.MediaColumns.RELATIVE_PATH, parts.relativePath)
                        put(MediaStore.MediaColumns.IS_PENDING, 1)
                    }
                    targetUri = contentResolver.insert(collection, values)
                }

                if (targetUri != null) {
                    contentResolver.openOutputStream(targetUri, "wt")?.bufferedWriter(Charsets.UTF_8)?.use {
                        it.write(content)
                        it.flush()
                    }

                    val finalize = ContentValues().apply {
                        put(MediaStore.MediaColumns.IS_PENDING, 0)
                    }
                    contentResolver.update(targetUri, finalize, null, null)
                    val out = "MediaStore:Download/${parts.relativePath.removePrefix(Environment.DIRECTORY_DOWNLOADS + "/")}${parts.displayName}"
                    Log.d(LOG_TAG, "writeSharedQualityProfile MediaStore success: $out")
                    return out
                }
            }

            val legacy = legacySharedQualityProfileFile(relativePath)
            legacy.parentFile?.mkdirs()
            legacy.writeText(content, Charsets.UTF_8)
            Log.d(LOG_TAG, "writeSharedQualityProfile legacy success: ${legacy.absolutePath}")
            legacy.absolutePath
        } catch (e: Exception) {
            Log.e(LOG_TAG, "writeSharedQualityProfile failed", e)
            null
        }
    }

    // ─── Parsers ──────────────────────────────────────────────────────────

    private fun parseSubtitleTracks(raw: List<Map<String, Any?>>?): List<ExternalSubtitle> {
        if (raw.isNullOrEmpty()) return emptyList()
        return raw.mapNotNull { map ->
            val url = map["url"]?.toString()?.trim().orEmpty()
            if (url.isBlank()) return@mapNotNull null
            val label = map["label"]?.toString()?.trim().takeUnless { it.isNullOrEmpty() } ?: "Subtitle"
            val language = map["language"]?.toString()?.trim().orEmpty()
            val source = map["source"]?.toString()?.trim().takeUnless { it.isNullOrEmpty() }
                ?: label.substringBefore('•').trim().takeIf { it.isNotEmpty() }
                ?: "External"
            val release = map["release"]?.toString()?.trim().orEmpty()
            val hi = map["hearingImpaired"] == true ||
                map["hi"] == true ||
                map["hearingImpaired"]?.toString()?.trim()?.equals("true", ignoreCase = true) == true ||
                map["hi"]?.toString()?.trim()?.equals("true", ignoreCase = true) == true ||
                label.lowercase().contains(" hi ") ||
                label.lowercase().endsWith(" hi") ||
                label.lowercase().contains("hearing")
            val autoSelect = map["autoSelect"] == true ||
                map["default"] == true ||
                map["autoSelect"]?.toString()?.trim()?.equals("true", ignoreCase = true) == true ||
                map["default"]?.toString()?.trim()?.equals("true", ignoreCase = true) == true
            val hashMatched = map["hashMatched"] == true ||
                map["moviehash_match"] == true ||
                map["hashMatched"]?.toString()?.trim()?.equals("true", ignoreCase = true) == true ||
                map["moviehash_match"]?.toString()?.trim()?.equals("true", ignoreCase = true) == true ||
                label.lowercase().contains(" hash")
            ExternalSubtitle(
                url = url,
                label = label,
                language = language,
                source = source,
                mimeType = inferSubtitleMimeType(url, map["mimeType"]?.toString()),
                autoSelect = autoSelect,
                release = release,
                hearingImpaired = hi,
                hashMatched = hashMatched,
            )
        }
            .distinctBy { it.url.lowercase() }
            .sortedBy { subtitleAutoSelectionScore(it) }
    }

    private fun isOpenSubtitlesTrack(track: ExternalSubtitle): Boolean {
        val source = track.source.lowercase()
        val label = track.label.lowercase()
        val url = track.url.lowercase()
        return source.contains("opensubtitle") ||
            label.contains("opensubtitle") ||
            url.contains("api.opensubtitles.com") ||
            url.contains("opensubtitles")
    }

    private fun isArabicSubtitleTrack(track: ExternalSubtitle): Boolean {
        val label = track.label.lowercase()
        val language = track.language.lowercase()
        return language.startsWith("ar") || label.contains("arabic") || label.contains("عرب")
    }

    private fun isEnglishSubtitleTrack(track: ExternalSubtitle): Boolean {
        val label = track.label.lowercase()
        val language = track.language.lowercase()
        return language.startsWith("en") || label.contains("english")
    }

    private fun currentVideoSubtitleContext(): String =
        listOfNotNull(
            currentMediaUrl?.takeIf { it.isNotBlank() },
            currentSelectedQualityLabel().takeIf { it.isNotBlank() },
            currentSelectedServerLabel().takeIf { it.isNotBlank() },
        ).joinToString(" ")

    private fun collectReleaseTokens(text: String?): Set<String> {
        if (text.isNullOrBlank()) return emptySet()
        val s = text.lowercase()
        val out = linkedSetOf<String>()

        fun addIfContains(token: String, vararg needles: String) {
            if (needles.any { s.contains(it) }) out.add(token)
        }

        addIfContains("bluray", "bluray", "brrip", "bdrip", "blu-ray")
        addIfContains("webrip", "webrip")
        addIfContains("webdl", "web-dl", "webdl")
        addIfContains("hdrip", "hdrip")
        addIfContains("dvdrip", "dvdrip")
        addIfContains("nf", "netflix", " nf ", ".nf.", "-nf", "_nf")
        addIfContains("amzn", "amzn", "amazon")
        addIfContains("dsnp", "dsnp", "disney")
        addIfContains("hmax", "hmax", "hbomax")
        addIfContains("atvp", "atvp", "apple")
        addIfContains("hevc", "hevc", "x265", "h265")
        addIfContains("avc", "x264", "h264", "avc")
        addIfContains("av1", "av1")
        addIfContains("hdr", " hdr ", "hdr10", "hdrip")
        addIfContains("dv", "dolby vision", "dolbyvision", " dv ")

        Regex("""(2160|1440|1080|720|576|540|480|360|240)p""", RegexOption.IGNORE_CASE)
            .findAll(s)
            .forEach { out.add(it.value.lowercase()) }

        detectFpsValue(s)?.let { fps ->
            val normalized = when {
                kotlin.math.abs(fps - 23.976) < 0.01 -> "23.976"
                kotlin.math.abs(fps - 29.97) < 0.01 -> "29.97"
                kotlin.math.abs(fps - 59.94) < 0.01 -> "59.94"
                else -> java.lang.String.format(java.util.Locale.US, "%.3f", fps).trimEnd('0').trimEnd('.')
            }
            out.add(normalized)
        }

        return out
    }

    private fun subtitleReleaseMatchScore(track: ExternalSubtitle): Int {
        val videoTokens = collectReleaseTokens(currentVideoSubtitleContext())
        if (videoTokens.isEmpty()) return 0

        val subtitleTokens = collectReleaseTokens(
            listOf(track.release, track.label, track.source, track.url).joinToString(" ")
        )
        if (subtitleTokens.isEmpty()) return 0

        var score = 0
        val common = videoTokens.intersect(subtitleTokens)
        for (token in common) {
            score += when {
                token in setOf("bluray", "webrip", "webdl", "hdrip", "dvdrip") -> 220
                token in setOf("nf", "amzn", "dsnp", "hmax", "atvp") -> 190
                token in setOf("hevc", "avc", "av1") -> 120
                token in setOf("hdr", "dv") -> 90
                token.endsWith("p") -> 140
                else -> 80
            }
        }

        val videoFps = inferVideoFrameRate()
        val subtitleFps = inferSubtitleFrameRate(track)
        if (videoFps != null && subtitleFps != null) {
            score += if (kotlin.math.abs(videoFps - subtitleFps) < 0.02) 260 else -260
        }

        if (track.release.isNotBlank() && common.isNotEmpty()) {
            score += 60
        }

        return score
    }

    private fun subtitleAutoSelectionScore(track: ExternalSubtitle): Int {
        val isArabic = isArabicSubtitleTrack(track)
        val isEnglish = isEnglishSubtitleTrack(track)
        val isOpen = isOpenSubtitlesTrack(track)

        var score = 0
        score += when {
            isOpen && isArabic -> 0
            isArabic -> 160
            isOpen -> 260
            isEnglish -> 520
            else -> 760
        }
        if (track.hashMatched) score -= 1200
        if (track.autoSelect) score -= 40
        if (track.hearingImpaired) score += 24
        score -= subtitleReleaseMatchScore(track)
        return score
    }

    private fun pickAutoSubtitleTrack(
        tracks: List<ExternalSubtitle> = externalSubtitleTracks,
        preferredUrl: String? = selectedSubtitleUrl,
    ): ExternalSubtitle? {
        if (tracks.isEmpty()) return null

        val exact = preferredUrl?.trim()?.takeIf { it.isNotEmpty() }?.let { wanted ->
            tracks.firstOrNull { it.url == wanted }
        }
        if (manualSubtitleSelection && exact != null) return exact

        val officialTracks = tracks.filter { isOpenSubtitlesTrack(it) }
        if (officialTracks.isNotEmpty()) {
            return officialTracks.minByOrNull { subtitleAutoSelectionScore(it) }
        }

        return if (manualSubtitleSelection) {
            exact ?: tracks.minByOrNull { subtitleAutoSelectionScore(it) }
        } else {
            exact ?: tracks.minByOrNull { subtitleAutoSelectionScore(it) }
        }
    }

    private fun parseQualityOptions(raw: List<Map<String, Any?>>?, currentLabel: String?): List<PageQualityOption> {
        if (raw.isNullOrEmpty()) return emptyList()
        val current = currentLabel?.trim()?.lowercase().orEmpty()
        val byLabel = linkedMapOf<String, PageQualityOption>()

        fun score(option: PageQualityOption): Int {
            var score = 0
            val url = option.url?.trim().orEmpty()
            if (url.isNotEmpty()) score += 100
            if (option.selected) score += 20
            return score
        }

        raw.forEach { map ->
            val label = map["label"]?.toString()?.trim().orEmpty()
            val key = map["key"]?.toString()?.trim().orEmpty()
            if (label.isBlank()) return@forEach

            val candidate = PageQualityOption(
                label = label,
                key = if (key.isNotBlank()) key else label,
                url = map["url"]?.toString()?.trim().takeUnless { it.isNullOrEmpty() },
                selected = label.lowercase() == current || map["selected"] == true,
            )

            val dedupeKey = label.lowercase()
            val existing = byLabel[dedupeKey]
            if (existing == null || score(candidate) >= score(existing)) {
                byLabel[dedupeKey] = candidate
            }
        }

        return byLabel.values.toList()
    }

    private fun parseServerOptions(raw: List<Map<String, Any?>>?, currentLabel: String?): List<PageServerOption> {
        if (raw.isNullOrEmpty()) return emptyList()
        val current = currentLabel?.trim()?.lowercase().orEmpty()
        return raw.mapNotNull { map ->
            val label = map["label"]?.toString()?.trim().orEmpty()
            val key = map["key"]?.toString()?.trim().orEmpty()
            if (label.isBlank()) return@mapNotNull null
            PageServerOption(
                label = label,
                key = if (key.isNotBlank()) key else label,
                embedUrl = map["embedUrl"]?.toString()?.trim().takeUnless { it.isNullOrEmpty() }
                    ?: map["url"]?.toString()?.trim().takeUnless { it.isNullOrEmpty() },
                selected = label.lowercase() == current || map["selected"] == true,
            )
        }.distinctBy { "${it.label.lowercase()}|${it.embedUrl.orEmpty().lowercase()}" }
    }

    private fun extractEmbeddedMediaHeaders(url: String): Map<String, String> {
        val out = LinkedHashMap<String, String>()
        return try {
            val uri = Uri.parse(url)
            val raw = uri.getQueryParameter("headers")?.trim().orEmpty()
            if (raw.isBlank()) return out
            val decoded = Uri.decode(raw)
            val json = JSONObject(decoded)
            val keys = json.keys()
            while (keys.hasNext()) {
                val rawKey = keys.next()
                val rawValue = json.optString(rawKey).trim()
                if (rawValue.isEmpty()) continue
                when (rawKey.trim().lowercase()) {
                    "referer" -> out["Referer"] = rawValue
                    "origin" -> out["Origin"] = rawValue
                    "user-agent" -> out["User-Agent"] = rawValue
                    "cookie" -> out["Cookie"] = rawValue
                    else -> out[rawKey.trim()] = rawValue
                }
            }
            out
        } catch (_: Exception) {
            out
        }
    }

    private fun isFlixerWorkerUrl(url: String?, headers: Map<String, String> = emptyMap()): Boolean {
        val lower = url?.trim()?.lowercase().orEmpty()
        val referer = headers.entries.firstOrNull { it.key.equals("Referer", ignoreCase = true) }?.value?.lowercase().orEmpty()
        val origin = headers.entries.firstOrNull { it.key.equals("Origin", ignoreCase = true) }?.value?.lowercase().orEmpty()
        val flixerContext = referer.contains("flixer") || origin.contains("flixer") ||
            referer.contains("vidsrc") || origin.contains("vidsrc")
        return lower.contains("wind.10018.workers.dev/") ||
            lower.contains("/orbitbear") ||
            (lower.contains("/file2/") && flixerContext)
    }

    private fun prepareMediaHeaders(url: String, headers: Map<String, String>): Map<String, String> {
        val out = LinkedHashMap<String, String>()
        headers.forEach { (key, value) ->
            val cleanKey = key.trim()
            val cleanValue = value.trim()
            if (cleanKey.isNotEmpty() && cleanValue.isNotEmpty()) {
                out[cleanKey] = cleanValue
            }
        }

        extractEmbeddedMediaHeaders(url).forEach { (key, value) ->
            if (key.isNotBlank() && value.isNotBlank()) {
                out[key] = value
            }
        }

        out.putIfAbsent(
            "User-Agent",
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
        )
        out.putIfAbsent("Accept", "*/*")

        if (isFlixerWorkerUrl(url, out)) {
            out["Origin"] = "https://flixer.su"
            out["Referer"] = "https://flixer.su/"
            out["Accept"] = "*/*"
            out.putIfAbsent("Accept-Language", "en-US,en;q=0.9")
            out["sec-ch-ua"] = "\"Chromium\";v=\"124\", \"Not-A.Brand\";v=\"24\""
            out["sec-ch-ua-mobile"] = "?1"
            out["sec-ch-ua-platform"] = "\"Android\""
            out.remove("Sec-Fetch-Site")
            out.remove("Sec-Fetch-Mode")
            out.remove("Sec-Fetch-Dest")
            out.remove("X-Requested-With")
            out.remove("Cache-Control")
            out.remove("Pragma")
            out.remove("Connection")
        }

        return out
    }


    // ─── PiP helpers ──────────────────────────────────────────────────────

    private fun isPipSupported(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    // ─── Open player ──────────────────────────────────────────────────────

    @OptIn(UnstableApi::class)
    private fun openNativePlayer(
        url: String?,
        startTime: Double,
        mimeType: String?,
        headers: Map<String, String>,
        subtitleTracks: List<ExternalSubtitle>,
        aspectW: Int,
        aspectH: Int,
        qualityOptions: List<PageQualityOption>,
        serverOptions: List<PageServerOption>,
    ): Boolean {
        if (url.isNullOrBlank() || url.startsWith("blob:")) return false

        lastAspectW = max(1, aspectW)
        lastAspectH = max(1, aspectH)
        requestedPipRatio = sanitizeRatio(lastAspectW, lastAspectH)
        pageQualityOptions = qualityOptions
        pageServerOptions = serverOptions
        externalSubtitleTracks = subtitleTracks
        manualSubtitleSelection = false
        currentMediaUrl = url
        currentMediaMime = mimeType
        currentMediaHeaders = prepareMediaHeaders(url, headers)
        selectedSubtitleUrl = pickAutoSubtitleTrack(subtitleTracks, null)?.url

        applyLandscapeMode()
        waitFirstRenderedFrame = false
        waitFirstRenderedFrame = true
        ensurePlayerUi()
        releasePlayerOnly()
        playerContainer?.setBackgroundColor(Color.BLACK)
        playerContainer?.visibility = View.VISIBLE
        playerView?.alpha = 0f
        playerView?.visibility = View.INVISIBLE
        hidePlayerLoadingOverlay()
        applyLandscapeMode()

        buildAndLoadMedia(url, mimeType, headers, (startTime * 1000.0).toLong(), subtitleTracks, selectedSubtitleUrl)

        nativePlayerActive = true
        notifyNativePlayerChanged(true)
        return true
    }

    private fun openNativePlayerShell(
        aspectW: Int,
        aspectH: Int,
        qualityOptions: List<PageQualityOption>,
        serverOptions: List<PageServerOption>,
        subtitleTracks: List<ExternalSubtitle>,
    ): Boolean {
        lastAspectW = max(1, aspectW)
        lastAspectH = max(1, aspectH)
        requestedPipRatio = sanitizeRatio(lastAspectW, lastAspectH)
        pageQualityOptions = qualityOptions
        pageServerOptions = serverOptions
        if (subtitleTracks.isNotEmpty()) {
            externalSubtitleTracks = subtitleTracks
            manualSubtitleSelection = false
            selectedSubtitleUrl = pickAutoSubtitleTrack(subtitleTracks, null)?.url
        }
        ensurePlayerUi()
        releasePlayerOnly()
        showNativeSurface()
        hidePlayerLoadingOverlay()
        applyLandscapeMode()
        if (!nativePlayerActive) {
            nativePlayerActive = true
            notifyNativePlayerChanged(true)
        }
        return true
    }

    @OptIn(UnstableApi::class)
    private fun updateNativePlayerSource(
        url: String?,
        startTime: Double,
        mimeType: String?,
        headers: Map<String, String>,
        subtitleTracks: List<ExternalSubtitle>,
        aspectW: Int,
        aspectH: Int,
        qualityOptions: List<PageQualityOption>,
        serverOptions: List<PageServerOption>,
    ): Boolean {
        if (url.isNullOrBlank() || url.startsWith("blob:")) return false
        lastAspectW = max(1, aspectW)
        lastAspectH = max(1, aspectH)
        requestedPipRatio = sanitizeRatio(lastAspectW, lastAspectH)
        pageQualityOptions = qualityOptions
        pageServerOptions = serverOptions
        if (subtitleTracks.isNotEmpty()) externalSubtitleTracks = subtitleTracks
        manualSubtitleSelection = false
        currentMediaUrl = url
        currentMediaMime = mimeType
        currentMediaHeaders = prepareMediaHeaders(url, headers)
        selectedSubtitleUrl = pickAutoSubtitleTrack(externalSubtitleTracks, null)?.url
        waitFirstRenderedFrame = true
        ensurePlayerUi()
        playerContainer?.visibility = View.VISIBLE
        playerContainer?.setBackgroundColor(Color.BLACK)
        playerView?.alpha = 0f
        playerView?.visibility = View.INVISIBLE
        hidePlayerLoadingOverlay()
        buildAndLoadMedia(url, mimeType, headers, (startTime * 1000.0).toLong(), externalSubtitleTracks, selectedSubtitleUrl)
        if (!nativePlayerActive) {
            nativePlayerActive = true
            notifyNativePlayerChanged(true)
        }
        return true
    }

    // ─── Build & load MediaItem (called on open AND on subtitle change) ───

    @OptIn(UnstableApi::class)
    private fun buildAndLoadMedia(
        url: String,
        mimeType: String?,
        headers: Map<String, String>,
        startTimeMs: Long = 0L,
        tracks: List<ExternalSubtitle> = externalSubtitleTracks,
        subtitleUrl: String? = selectedSubtitleUrl,
        playWhenReady: Boolean = true,
    ) {
        val effectiveHeaders = prepareMediaHeaders(url, headers)
        val player = exoPlayer ?: run {
            val httpFactory = DefaultHttpDataSource.Factory()
                .setAllowCrossProtocolRedirects(true)
                .setUserAgent(effectiveHeaders["User-Agent"] ?: "Mozilla/5.0")
                .setDefaultRequestProperties(effectiveHeaders)
            val dataSourceFactory = DefaultDataSource.Factory(this, httpFactory)
            val p = ExoPlayer.Builder(this)
                .setMediaSourceFactory(DefaultMediaSourceFactory(dataSourceFactory))
                .build()
            exoPlayer = p
            playerView?.player = p
            playerView?.resizeMode = currentResizeMode
            p.repeatMode = Player.REPEAT_MODE_OFF
            p.setVideoChangeFrameRateStrategy(C.VIDEO_CHANGE_FRAME_RATE_STRATEGY_OFF)
            attachPlayerListeners(p)
            p
        }

        val rawActiveTrack = pickAutoSubtitleTrack(tracks, subtitleUrl)
        selectedSubtitleUrl = rawActiveTrack?.url
        activeSubtitleRawTrack = rawActiveTrack
        activeSubtitleProfileKey = buildSubtitleProfileKey(rawActiveTrack)
        subtitleDelayMs = 0
        val activeTrack = rawActiveTrack
        selectedSubtitleResolvedUrl = activeTrack?.url
        activeSubtitleRateMultiplier = 1.0
        Log.d(
            LOG_TAG,
            "buildAndLoadMedia subtitleUrl=$subtitleUrl active=${activeTrack?.label} totalTracks=${tracks.size} delayMs=$subtitleDelayMs fpsScale=$activeSubtitleRateMultiplier profile=$activeSubtitleProfileKey"
        )

        player.trackSelectionParameters = player.trackSelectionParameters
            .buildUpon()
            .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, activeTrack == null)
            .setPreferredTextLanguage(activeTrack?.language?.takeIf { it.isNotBlank() })
            .setSelectUndeterminedTextLanguage(true)
            .clearOverridesOfType(C.TRACK_TYPE_TEXT)
            .build()

        player.playWhenReady = playWhenReady
        player.setMediaItem(buildMediaItemWithOptionalSubtitle(url, mimeType, activeTrack), startTimeMs)
        player.prepare()
        if (playWhenReady) player.play()
        playerView?.subtitleView?.visibility = View.VISIBLE
        applySubtitleAppearance()
        updateSpeedButtonLabel(player.playbackParameters.speed)

        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
            if (waitFirstRenderedFrame && nativePlayerActive) {
                waitFirstRenderedFrame = false
                playerView?.alpha = 1f
                playerView?.visibility = View.VISIBLE
                playerContainer?.visibility = View.VISIBLE
                Log.d(LOG_TAG, "buildAndLoadMedia: fallback timeout - forcing player visible")
            }
        }, 4000L)
    }

    @OptIn(UnstableApi::class)
    private fun buildMediaItemWithOptionalSubtitle(
        url: String,
        mimeType: String?,
        selectedTrack: ExternalSubtitle?,
    ): MediaItem {
        val lowerUrl = url.lowercase()
        val lowerMime = (mimeType ?: "").lowercase()
        val builder = MediaItem.Builder().setUri(Uri.parse(url))

        when {
            lowerMime.contains("mpegurl") || lowerUrl.contains(".m3u8") -> {
                builder.setMimeType(MimeTypes.APPLICATION_M3U8)
                Log.d(LOG_TAG, "buildMediaItemWithOptionalSubtitle: forced HLS for $url mime=$mimeType")
            }
            lowerMime.contains("dash+xml") || lowerUrl.contains(".mpd") -> {
                builder.setMimeType(MimeTypes.APPLICATION_MPD)
                Log.d(LOG_TAG, "buildMediaItemWithOptionalSubtitle: forced DASH for $url mime=$mimeType")
            }
            lowerMime == "video/mp4" || lowerUrl.contains(".mp4") ->
                builder.setMimeType(MimeTypes.VIDEO_MP4)
            lowerMime == "video/webm" || lowerUrl.contains(".webm") ->
                builder.setMimeType(MimeTypes.VIDEO_WEBM)
        }

        if (selectedTrack != null) {
            val subtitleConfig = MediaItem.SubtitleConfiguration.Builder(Uri.parse(selectedTrack.url))
                .setLabel(selectedTrack.label)
                .setSelectionFlags(C.SELECTION_FLAG_DEFAULT)
                .setRoleFlags(C.ROLE_FLAG_SUBTITLE)
                .apply {
                    selectedTrack.language.takeIf { it.isNotBlank() }?.let { setLanguage(it) }
                    selectedTrack.mimeType?.takeIf { it.isNotBlank() }?.let { setMimeType(it) }
                }
                .build()
            builder.setSubtitleConfigurations(listOf(subtitleConfig))
            Log.d(
                LOG_TAG,
                "buildMediaItemWithOptionalSubtitle subtitle=${selectedTrack.label} url=${selectedTrack.url} mime=${selectedTrack.mimeType} lang=${selectedTrack.language}"
            )
        } else {
            Log.d(LOG_TAG, "buildMediaItemWithOptionalSubtitle: no subtitle selected")
        }

        return builder.build()
    }

    private fun attachPlayerListeners(player: ExoPlayer) {
        player.addListener(object : Player.Listener {
            override fun onVideoSizeChanged(videoSize: VideoSize) {
                if (videoSize.width > 0 && videoSize.height > 0) {
                    lastAspectW = videoSize.width
                    lastAspectH = videoSize.height
                    requestedPipRatio = sanitizeRatio(lastAspectW, lastAspectH)
                    updatePipParams()
                }
            }
            override fun onTracksChanged(tracks: Tracks) { updatePipParams() }
            override fun onPlaybackStateChanged(playbackState: Int) {
                when (playbackState) {
                    Player.STATE_READY -> {
                        updatePipParams()
                        hidePlayerLoadingOverlay()
                        if (waitFirstRenderedFrame) {
                            waitFirstRenderedFrame = false
                            runOnUiThread {
                                playerView?.alpha = 1f
                                playerView?.visibility = View.VISIBLE
                                playerContainer?.visibility = View.VISIBLE
                            }
                        } else {
                            showNativeSurface()
                        }
                    }
                    Player.STATE_BUFFERING, Player.STATE_IDLE -> hidePlayerLoadingOverlay()
                    Player.STATE_ENDED -> hidePlayerLoadingOverlay()
                }
            }
            override fun onPlaybackParametersChanged(params: PlaybackParameters) {
                updateSpeedButtonLabel(params.speed)
            }
            override fun onPlayerError(error: PlaybackException) {
                Log.e(LOG_TAG, "onPlayerError url=${currentMediaUrl ?: ""} worker=${isFlixerWorkerUrl(currentMediaUrl)} message=${error.message}", error)
                channel?.invokeMethod("onNativePipError", error.message ?: "فشل تشغيل الفيديو")
            }
        })
    }

    // ─── UI setup ─────────────────────────────────────────────────────────

    private fun ensurePlayerUi() {
        if (playerContainer != null) return

        val root = findViewById<ViewGroup>(android.R.id.content)
        root.fitsSystemWindows = false
        if (root.childCount > 0) flutterContentView = root.getChildAt(0)

        val container = FrameLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT)
            setBackgroundColor(Color.BLACK)
            visibility = View.GONE
            fitsSystemWindows = false
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT_WATCH) {
                setOnApplyWindowInsetsListener { _, _ -> WindowInsets.CONSUMED }
            }
            isClickable = true
            isFocusable = true
        }

        val pv = buildNativePlayerView()
        playerView = pv
        container.addView(pv)

        val loading = FrameLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT)
            setBackgroundColor(0xCC000000.toInt())
            visibility = View.GONE
            isClickable = false
            isFocusable = false
        }
        val loadingInner = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            layoutParams = FrameLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT, Gravity.CENTER)
        }
        val spinner = ProgressBar(this).apply {
            isIndeterminate = true
        }
        val loadingText = TextView(this).apply {
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            gravity = Gravity.CENTER
            text = ""
            visibility = View.GONE
            setPadding(0, 0, 0, 0)
        }
        loadingInner.addView(spinner)
        loading.addView(loadingInner)
        container.addView(loading)
        loadingOverlay = loading
        loadingTextView = loadingText

        val scroll = HorizontalScrollView(this).apply {
            layoutParams = FrameLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
                bottomMargin = dp(14)
            }
            isHorizontalScrollBarEnabled = false
            overScrollMode = View.OVER_SCROLL_NEVER
        }
        controlsScroll = scroll

        val bar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(2), dp(2), dp(2), dp(2))
        }
        controlsBar = bar

        fitButton = makeControlButton("FILL") { cycleResizeMode() }
        qualityButton = null
        serverButton = null
        subtitleButton = null
        pipButton = makeControlButton("PiP") { enterNativePip() }
        closeButton = makeControlButton("✕") { closeNativePlayer() }

        listOf(fitButton, pipButton, closeButton)
            .forEach { btn -> if (btn != null) bar.addView(btn) }

        scroll.addView(bar)
        container.addView(scroll)
        root.addView(container, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        playerContainer = container
    }

    private fun buildNativePlayerView(): PlayerView {
        return PlayerView(this).apply {
            layoutParams = FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT)
            useController = true
            controllerAutoShow = true
            controllerHideOnTouch = true
            controllerShowTimeoutMs = 4500
            resizeMode = currentResizeMode
            keepScreenOn = true
            alpha = 1f
            visibility = View.VISIBLE
            setShutterBackgroundColor(Color.BLACK)
            setBackgroundColor(Color.BLACK)
            setKeepContentOnPlayerReset(false)
            applySubtitleAppearance(subtitleView)
            setControllerVisibilityListener(
                PlayerView.ControllerVisibilityListener { visibility ->
                    controllerVisible = visibility == View.VISIBLE
                    updateOverlayVisibility()
                }
            )
        }
    }

    private fun rebuildPlayerView() {
        val container = playerContainer ?: return
        val oldView = playerView
        try {
            oldView?.player = null
            oldView?.hideController()
        } catch (_: Exception) {}
        if (oldView != null) {
            container.removeView(oldView)
        }
        val freshView = buildNativePlayerView()
        playerView = freshView
        container.addView(freshView, 0)
    }

    private fun hideNativeSurfaceImmediately() {
        controllerVisible = false
        try {
            playerView?.hideController()
            playerView?.player = null
            playerView?.alpha = 0f
            playerView?.visibility = View.INVISIBLE
        } catch (_: Exception) {}
        playerContainer?.setBackgroundColor(Color.BLACK)
        playerContainer?.visibility = View.GONE
        hidePlayerLoadingOverlay()
        updateOverlayVisibility()
    }

    private fun notifyNativePlayerChanged(active: Boolean) {
        channel?.invokeMethod("onNativePlayerChanged", active)
    }

    private fun applyUpdatedOptions(
        qualityOptions: List<Map<String, Any?>>,
        currentQualityLabel: String,
        serverOptions: List<Map<String, Any?>>,
        currentServerLabel: String,
        subtitleTracks: List<ExternalSubtitle> = externalSubtitleTracks,
    ) {
        pageQualityOptions = parseQualityOptions(qualityOptions, currentQualityLabel)
        pageServerOptions = parseServerOptions(serverOptions, currentServerLabel)
        // Only update subtitle list if new tracks arrived (don't clear existing)
        if (subtitleTracks.isNotEmpty()) {
            externalSubtitleTracks = subtitleTracks
        }

        if (!manualSubtitleSelection) {
            val current = selectedSubtitleUrl?.let { wanted -> externalSubtitleTracks.firstOrNull { it.url == wanted } }
            val shouldResetAutoSelection = current == null || !isOpenSubtitlesTrack(current) || !current.hashMatched
            if (shouldResetAutoSelection) {
                selectedSubtitleUrl = null
            }
        }

        val bestTrack = pickAutoSubtitleTrack(externalSubtitleTracks, selectedSubtitleUrl)
        val bestUrl = bestTrack?.url
        if (bestUrl == null) {
            selectedSubtitleUrl = null
        } else if (bestUrl != selectedSubtitleUrl) {
            selectedSubtitleUrl = bestUrl
            if (nativePlayerActive && exoPlayer != null && currentMediaUrl != null) {
                applySubtitleSelection(bestUrl)
            }
        }

        updateOverlayVisibility()
    }

    private fun makeControlButton(text: String, onClick: () -> Unit): Button {
        return Button(this).apply {
            this.text = text
            isAllCaps = false
            minHeight = 0; minimumHeight = 0; minWidth = 0; minimumWidth = 0
            textSize = 12.5f
            setTextColor(0xF2FFFFFF.toInt())
            setPadding(dp(16), dp(8), dp(16), dp(8))
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dpF(18f)
                setColor(0x7A111111)
                setStroke(dp(1), 0x33FFFFFF)
            }
            elevation = 0f
            stateListAnimator = null
            setOnClickListener { onClick() }
            layoutParams = LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                marginStart = dp(2); marginEnd = dp(2)
            }
        }
    }

    private fun updateOverlayVisibility() {
        controlsScroll?.visibility =
            if (nativePlayerActive && !isInPictureInPictureMode && controllerVisible)
                View.VISIBLE else View.GONE
    }

    private fun showPlayerLoadingOverlay(message: String = "") {
        loadingTextView?.text = ""
        loadingTextView?.visibility = View.GONE
        loadingOverlay?.visibility = View.GONE
    }

    private fun hidePlayerLoadingOverlay() {
        loadingOverlay?.visibility = View.GONE
    }

    private fun showNativeSurface() {
        enterImmersiveMode(true)
        playerContainer?.apply {
            setBackgroundColor(Color.BLACK)
            visibility = View.VISIBLE
            layoutParams = FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT)
            fitsSystemWindows = false
            requestLayout()
        }
        playerView?.apply {
            alpha = 1f
            visibility = View.VISIBLE
            resizeMode = currentResizeMode
            requestLayout()
            showController()
        }
        controllerVisible = true
        updateOverlayVisibility()
    }

    private fun releasePlayerOnly() {
        val player = exoPlayer ?: run {
            playerView?.player = null
            return
        }
        try { player.playWhenReady = false } catch (_: Exception) {}
        try { player.pause() } catch (_: Exception) {}
        try { player.stop() } catch (_: Exception) {}
        try { player.clearMediaItems() } catch (_: Exception) {}
        try { playerView?.player = null } catch (_: Exception) {}
        try { player.release() } catch (_: Exception) {}
        exoPlayer = null
    }

    // ─── PiP ──────────────────────────────────────────────────────────────

        private fun prepareVideoOnlyForPip() {
        if (inManualPipTransition) return
        inManualPipTransition = true

        try {
            beforePipResizeMode = currentResizeMode
            pipControllerEnabledBeforeStableMode = playerView?.useController ?: true

            val root = findViewById<ViewGroup>(android.R.id.content)
            root?.apply {
                setBackgroundColor(Color.BLACK)
                setPadding(0, 0, 0, 0)
                clipChildren = false
                clipToPadding = false
            }

            playerContainer?.apply {
                visibility = View.VISIBLE
                alpha = 1f
                setBackgroundColor(Color.BLACK)
                setPadding(0, 0, 0, 0)
                isClickable = true
                isEnabled = true
                isFocusable = true
                clipChildren = false
                clipToPadding = false
                layoutParams = FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT).apply {
                    gravity = Gravity.CENTER
                    setMargins(0, 0, 0, 0)
                }
                bringToFront()
                requestLayout()
            }

            playerView?.apply {
                alpha = 1f
                visibility = View.VISIBLE
                setPadding(0, 0, 0, 0)
                setBackgroundColor(Color.BLACK)
                resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
                useController = false
                controllerAutoShow = false
                controllerShowTimeoutMs = 0
                hideController()
                requestLayout()
            }

            controlsScroll?.visibility = View.GONE
            controlsBar?.visibility = View.GONE
            loadingOverlay?.visibility = View.GONE
            hidePlayerLoadingOverlay()

            try {
                exoPlayer?.setVideoScalingMode(C.VIDEO_SCALING_MODE_SCALE_TO_FIT)
            } catch (_: Exception) {
            }

            requestedPipRatio = safePipRatio()
            updatePipParams()
        } catch (_: Exception) {
        }
    }

    
    private fun applyRoundedCornersForPip() {
    }

    private fun removeRoundedCornersAfterPip() {
        try {
            playerView?.clipToOutline = false
            playerContainer?.clipToOutline = false
        } catch (_: Exception) {
        }
    }

    private fun restoreVideoOnlyAfterPip() {
        inManualPipTransition = false

        try {
            removeRoundedCornersAfterPip()

            playerContainer?.apply {
                visibility = View.VISIBLE
                alpha = 1f
                setBackgroundColor(Color.BLACK)
                isClickable = true
                isEnabled = true
                isFocusable = true
                layoutParams = FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT).apply {
                    gravity = Gravity.CENTER
                    setMargins(0, 0, 0, 0)
                }
                bringToFront()
                requestLayout()
            }

            playerView?.apply {
                useController = true
                controllerAutoShow = true
                controllerHideOnTouch = true
                controllerShowTimeoutMs = 4500
                resizeMode = currentResizeMode
                alpha = 1f
                visibility = View.VISIBLE
                isClickable = true
                isEnabled = true
                isFocusable = true
                requestLayout()
                showController()
            }

            controllerVisible = true
            controlsScroll?.visibility = View.VISIBLE
            controlsBar?.visibility = View.VISIBLE
            fitButton?.visibility = View.VISIBLE
            qualityButton?.visibility = View.VISIBLE
            subtitleButton?.visibility = View.VISIBLE
            pipButton?.visibility = View.VISIBLE
            closeButton?.visibility = View.VISIBLE

            hidePlayerLoadingOverlay()
            updateOverlayVisibility()
        } catch (_: Exception) {
        }
    }

        private fun hideEveryOverlayForPip() {
        try {
            controllerVisible = false
            controlsScroll?.visibility = View.GONE
            controlsBar?.visibility = View.GONE
            loadingOverlay?.visibility = View.GONE

            playerView?.apply {
                useController = false
                controllerAutoShow = false
                controllerHideOnTouch = true
                controllerShowTimeoutMs = 0
                hideController()
            }
        } catch (_: Exception) {
        }
    }

        private fun restoreEveryOverlayAfterPip() {
        try {
            controllerVisible = true

            controlsScroll?.apply {
                visibility = View.VISIBLE
                alpha = 1f
                isEnabled = true
                isClickable = true
                bringToFront()
            }

            controlsBar?.apply {
                visibility = View.VISIBLE
                alpha = 1f
                isEnabled = true
                isClickable = true
                bringToFront()
            }

            fitButton?.visibility = View.VISIBLE
            qualityButton?.visibility = View.VISIBLE
            subtitleButton?.visibility = View.VISIBLE
            pipButton?.visibility = View.VISIBLE
            closeButton?.visibility = View.VISIBLE

            playerView?.apply {
                useController = true
                controllerAutoShow = true
                controllerHideOnTouch = true
                controllerShowTimeoutMs = 4500
                alpha = 1f
                visibility = View.VISIBLE
                showController()
            }
        } catch (_: Exception) {
        }
    }

    private fun enterNativePip(): Boolean {
        if (!nativePlayerActive || !isPipSupported()) return false
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        if (isInPictureInPictureMode) return true

        return try {
            prepareVideoOnlyForPip()

            val enterBlock = Runnable {
                try {
                    hideEveryOverlayForPip()
                    requestedPipRatio = safePipRatio()
                    val params = buildPipParams() ?: return@Runnable
                    setPictureInPictureParams(params)
                    enterPictureInPictureMode(params)
                } catch (_: Exception) {
                }
            }

            playerContainer?.postDelayed(enterBlock, 180L)
                ?: android.os.Handler(android.os.Looper.getMainLooper()).postDelayed(enterBlock, 180L)

            true
        } catch (_: Exception) {
            false
        }
    }

    private fun pauseNativePlayerForBackground() {
        if (!nativePlayerActive) return
        try {
            exoPlayer?.playWhenReady = false
            exoPlayer?.pause()
        } catch (_: Exception) {
        }
    }

    private fun closeNativePlayer() {
        if (nativePlayerClosing) return
        nativePlayerClosing = true

        nativePlayerActive = false
        requestedPipRatio = null
        pageQualityOptions = emptyList()
        pageServerOptions = emptyList()
        externalSubtitleTracks = emptyList()
        selectedSubtitleUrl = null
        currentMediaUrl = null
        currentMediaMime = null
        currentMediaHeaders = emptyMap()
        hidePlayerLoadingOverlay()

        try {
            exoPlayer?.playWhenReady = false
            exoPlayer?.pause()
            exoPlayer?.stop()
            exoPlayer?.clearMediaItems()
        } catch (_: Exception) {}

        hideNativeSurfaceImmediately()
        releasePlayerOnly()
        rebuildPlayerView()

        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_FULL_SENSOR
        enterImmersiveMode(false)
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        notifyNativePlayerChanged(false)

        nativePlayerClosing = false
    }

    private fun applyLandscapeMode() {
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
        enterImmersiveMode(true)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    private fun enterImmersiveMode(hideBars: Boolean) {
        window.statusBarColor = Color.BLACK
        window.navigationBarColor = Color.BLACK

        if (hideBars) {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            window.addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)
            window.addFlags(WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                window.attributes = window.attributes.apply {
                    layoutInDisplayCutoutMode =
                        WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
                }
            }
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)
            window.clearFlags(WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                window.attributes = window.attributes.apply {
                    layoutInDisplayCutoutMode =
                        WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_DEFAULT
                }
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(!hideBars)
            val controller = window.insetsController
            if (hideBars) {
                controller?.hide(WindowInsets.Type.statusBars() or WindowInsets.Type.navigationBars())
                controller?.systemBarsBehavior =
                    WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            } else {
                controller?.show(WindowInsets.Type.statusBars() or WindowInsets.Type.navigationBars())
            }
        }

        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility = if (hideBars) {
            View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
                View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_FULLSCREEN or
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
        } else {
            View.SYSTEM_UI_FLAG_LAYOUT_STABLE
        }

        if (hideBars) {
            window.decorView.post {
                @Suppress("DEPRECATION")
                window.decorView.systemUiVisibility =
                    View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
                    View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                    View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                    View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                    View.SYSTEM_UI_FLAG_FULLSCREEN or
                    View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    window.setDecorFitsSystemWindows(false)
                    window.insetsController?.hide(
                        WindowInsets.Type.statusBars() or WindowInsets.Type.navigationBars()
                    )
                }
                playerContainer?.requestLayout()
                playerView?.requestLayout()
            }
        }
    }

    private fun cycleResizeMode() {
        currentResizeMode = when (currentResizeMode) {
            AspectRatioFrameLayout.RESIZE_MODE_FILL -> AspectRatioFrameLayout.RESIZE_MODE_FIT
            AspectRatioFrameLayout.RESIZE_MODE_FIT -> AspectRatioFrameLayout.RESIZE_MODE_ZOOM
            else -> AspectRatioFrameLayout.RESIZE_MODE_FILL
        }
        playerView?.resizeMode = currentResizeMode
        fitButton?.text = when (currentResizeMode) {
            AspectRatioFrameLayout.RESIZE_MODE_FILL -> "FILL"
            AspectRatioFrameLayout.RESIZE_MODE_FIT -> "FIT"
            else -> "ZOOM"
        }
    }

    private fun updateSpeedButtonLabel(speed: Float) {
        // speedButton?.text = if (kotlin.math.abs(speed - speed.toInt().toFloat()) < 0.01f) "${speed.toInt()}x" else "${speed}x"
    }

    // ─── Quality dialog ───────────────────────────────────────────────────

    private fun showVideoTracksDialog() {
        if (pageQualityOptions.isNotEmpty()) {
            val labels = pageQualityOptions.map { it.label }.toTypedArray()
            val checked = pageQualityOptions.indexOfFirst { it.selected }.let { if (it >= 0) it else 0 }
            AlertDialog.Builder(this).setTitle("الجودة")
                .setSingleChoiceItems(labels, checked) { dialog, which ->
                    val option = pageQualityOptions[which]
                    pageQualityOptions = pageQualityOptions.mapIndexed { i, item -> item.copy(selected = i == which) }
                    channel?.invokeMethod("onQualitySelected", mapOf("label" to option.label, "key" to option.key, "url" to (option.url ?: "")))
                    dialog.dismiss()
                }
                .setNegativeButton("إغلاق", null).show()
            return
        }
        val player = exoPlayer ?: return
        val tracks = collectTrackChoices(player.currentTracks, C.TRACK_TYPE_VIDEO)
        if (tracks.isEmpty()) { simpleMessage("لا توجد جودات متعددة"); return }
        val labels = tracks.map { it.label }.toTypedArray()
        val checked = tracks.indexOfFirst { it.selected }.coerceAtLeast(0)
        AlertDialog.Builder(this).setTitle("الجودة")
            .setSingleChoiceItems(labels, checked) { dialog, which ->
                applyTrackSelection(C.TRACK_TYPE_VIDEO, tracks[which]); dialog.dismiss()
            }
            .setNegativeButton("إغلاق", null).show()
    }

    // ─── Server dialog ────────────────────────────────────────────────────

    private fun showServerDialog() {
        if (pageServerOptions.isEmpty()) { simpleMessage("لا توجد سيرفرات متعددة"); return }
        val labels = pageServerOptions.map { it.label }.toTypedArray()
        val checked = pageServerOptions.indexOfFirst { it.selected }.let { if (it >= 0) it else 0 }
        AlertDialog.Builder(this).setTitle("السيرفر")
            .setSingleChoiceItems(labels, checked) { dialog, which ->
                val option = pageServerOptions[which]
                pageServerOptions = pageServerOptions.mapIndexed { i, item -> item.copy(selected = i == which) }
                channel?.invokeMethod("onServerSelected", mapOf("label" to option.label, "key" to option.key, "url" to (option.embedUrl ?: "")))
                dialog.dismiss()
            }
            .setNegativeButton("إغلاق", null).show()
    }

    // ─── ★ FIXED Subtitle dialog ──────────────────────────────────────────
    // Uses externalSubtitleTracks directly (not MediaItem configs)
    // Applies subtitle by reloading media at current position

    private fun showTextTracksDialog() {
        val tracks = externalSubtitleTracks
        if (tracks.isEmpty()) {
            simpleMessage("لا توجد ترجمات - انتظر لحظة وحاول مجددًا")
            return
        }

        val langs = tracks.map { normalizeLanguage(it.language) }.distinct()
        var selectedLang = tracks.firstOrNull { it.url == selectedSubtitleUrl }
            ?.let { normalizeLanguage(it.language) } ?: langs.first()

        val dialog = Dialog(this, android.R.style.Theme_Black_NoTitleBar_Fullscreen)
        val root = FrameLayout(this).apply {
            setBackgroundColor(0xAA000000.toInt())
            layoutParams = FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT)
            setOnClickListener { dialog.dismiss() }
        }

        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(14), dp(20), dp(18))
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dpF(28f)
                setColor(0xFF17131F.toInt())
            }
            layoutParams = FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT).apply {
                leftMargin = dp(16)
                rightMargin = dp(16)
                topMargin = dp(10)
                bottomMargin = dp(10)
            }
            isClickable = true
        }

        card.addView(View(this).apply {
            layoutParams = LinearLayout.LayoutParams(dp(72), dp(8)).apply {
                gravity = Gravity.CENTER_HORIZONTAL
                bottomMargin = dp(14)
            }
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dpF(20f)
                setColor(0xFFD8D1DE.toInt())
            }
            alpha = 0.92f
        })

        card.addView(TextView(this).apply {
            text = "الترجمات"
            setTextColor(Color.WHITE)
            textSize = 19f
            setTypeface(typeface, Typeface.BOLD)
            gravity = Gravity.START
            setPadding(dp(4), 0, dp(4), dp(10))
        })

        val body = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(MATCH_PARENT, 0, 1f)
        }

        val languageColumn = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(0, MATCH_PARENT, 0.26f)
        }

        val languageScroll = ScrollView(this).apply {
            isFillViewport = true
            overScrollMode = View.OVER_SCROLL_NEVER
            layoutParams = LinearLayout.LayoutParams(0, MATCH_PARENT, 0.26f)
        }
        languageScroll.addView(languageColumn)

        fun makeDivider(): View = View(this).apply {
            layoutParams = LinearLayout.LayoutParams(dp(1), MATCH_PARENT).apply {
                leftMargin = dp(12)
                rightMargin = dp(12)
            }
            setBackgroundColor(0x18FFFFFF)
        }

        val optionsColumn = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
        }
        val optionsScroll = ScrollView(this).apply {
            isFillViewport = true
            overScrollMode = View.OVER_SCROLL_NEVER
            layoutParams = LinearLayout.LayoutParams(0, MATCH_PARENT, 0.44f)
            addView(optionsColumn)
        }

        val settingsScroll = ScrollView(this).apply {
            isFillViewport = true
            overScrollMode = View.OVER_SCROLL_NEVER
            layoutParams = LinearLayout.LayoutParams(0, MATCH_PARENT, 0.30f)
        }

        val settingsColumn = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
        }
        settingsScroll.addView(settingsColumn)

        fun addSettingsStepper(title: String, valueProvider: () -> String, onMinus: () -> Unit, onPlus: () -> Unit) {
            val row = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                layoutParams = LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                    bottomMargin = dp(18)
                }
            }

            fun circle(symbol: String, click: () -> Unit): TextView = TextView(this).apply {
                text = symbol
                gravity = Gravity.CENTER
                textSize = 17f
                setTextColor(Color.WHITE)
                setTypeface(typeface, Typeface.BOLD)
                layoutParams = LinearLayout.LayoutParams(dp(40), dp(40))
                background = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(0xFF302B3A.toInt())
                }
                setOnClickListener {
                    click()
                    applySubtitleAppearance()
                    saveSubtitlePrefs()
                }
            }

            val center = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER
                layoutParams = LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f)
            }
            val valueView = TextView(this).apply {
                setTextColor(Color.WHITE)
                textSize = 13.5f
                setTypeface(typeface, Typeface.BOLD)
                gravity = Gravity.CENTER
            }
            center.addView(TextView(this).apply {
                text = title
                setTextColor(0xE6FFFFFF.toInt())
                textSize = 13.5f
                gravity = Gravity.CENTER
                setPadding(0, 0, 0, dp(6))
            })
            center.addView(valueView)
            row.addView(circle("−") { onMinus() })
            row.addView(center)
            row.addView(circle("+") { onPlus() })
            valueView.text = valueProvider()
            settingsColumn.addView(row)
        }

        settingsColumn.addView(TextView(this).apply {
            text = "إعدادات الترجمة"
            setTextColor(Color.WHITE)
            textSize = 18f
            setTypeface(typeface, Typeface.BOLD)
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(0, dp(4), 0, dp(18))
        })

        addSettingsStepper(
            "التأخير",
            valueProvider = { String.format(java.util.Locale.US, "%.1fs", subtitleDelayMs / 1000f) },
            onMinus = { adjustSubtitleDelayBy(-100) },
            onPlus = { adjustSubtitleDelayBy(100) },
        )

        addSettingsStepper(
            "الحجم",
            valueProvider = { "${subtitleSizePercent}%" },
            onMinus = { subtitleSizePercent = (subtitleSizePercent - 10).coerceAtLeast(70) },
            onPlus = { subtitleSizePercent = (subtitleSizePercent + 10).coerceAtMost(190) },
        )

        addSettingsStepper(
            "الموضع العمودي",
            valueProvider = { "${subtitleVerticalOffsetPercent}%" },
            onMinus = { subtitleVerticalOffsetPercent = (subtitleVerticalOffsetPercent - 1).coerceAtLeast(0) },
            onPlus = { subtitleVerticalOffsetPercent = (subtitleVerticalOffsetPercent + 1).coerceAtMost(24) },
        )

        settingsColumn.addView(TextView(this).apply {
            text = "الغلاف"
            setTextColor(Color.WHITE)
            textSize = 15f
            setTypeface(typeface, Typeface.BOLD)
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(0, dp(2), 0, dp(8))
        })

        val chipRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                bottomMargin = dp(10)
            }
        }

        fun makeChip(label: String, active: Boolean, onClick: () -> Unit): TextView = TextView(this).apply {
            text = label
            setTextColor(if (active) Color.WHITE else 0xE6FFFFFF.toInt())
            textSize = 12.5f
            gravity = Gravity.CENTER
            setPadding(dp(12), dp(9), dp(12), dp(9))
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dpF(16f)
                setColor(if (active) 0xFF6E56CF.toInt() else 0xFF2B2734.toInt())
            }
            setOnClickListener {
                onClick()
                applySubtitleAppearance()
                saveSubtitlePrefs()
                dialog.dismiss()
                showTextTracksDialog()
            }
        }

        chipRow.addView(makeChip("بدون غلاف", !subtitleBackgroundEnabled) { subtitleBackgroundEnabled = false })
        chipRow.addView(View(this).apply { layoutParams = LinearLayout.LayoutParams(dp(8), 1) })
        chipRow.addView(makeChip("غلاف", subtitleBackgroundEnabled) { subtitleBackgroundEnabled = true })
        settingsColumn.addView(chipRow)

        settingsColumn.addView(TextView(this).apply {
            text = "كلما قلّ الموضع العمودي نزلت الترجمة أكثر"
            setTextColor(0x99FFFFFF.toInt())
            textSize = 12.5f
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(4), dp(4), dp(4), 0)
        })

        fun renderOptions() {
            optionsColumn.removeAllViews()
            if (selectedLang == "__OFF__") {
                optionsColumn.addView(TextView(this).apply {
                    text = "الترجمة متوقفة"
                    setTextColor(0x88FFFFFF.toInt())
                    textSize = 15f
                    setPadding(dp(12), dp(10), dp(12), dp(10))
                })
                return
            }

            val current = tracks.filter { normalizeLanguage(it.language) == selectedLang }
            current.forEachIndexed { index, item ->
                val isSelected = item.url == selectedSubtitleUrl
                val row = LinearLayout(this).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.CENTER_VERTICAL
                    layoutParams = LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
                    setPadding(dp(10), dp(16), dp(10), dp(16))
                    setOnClickListener {
                        manualSubtitleSelection = true
                        applySubtitleSelection(item.url)
                        dialog.dismiss()
                    }
                }

                val left = LinearLayout(this).apply {
                    orientation = LinearLayout.VERTICAL
                    layoutParams = LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f)
                }

                val title = item.label.substringAfter("• ", item.label).trim().ifBlank { item.label }
                left.addView(TextView(this).apply {
                    text = title
                    setTextColor(Color.WHITE)
                    textSize = 13.5f
                    setTypeface(typeface, if (isSelected) Typeface.BOLD else Typeface.NORMAL)
                    maxLines = 2
                })
                left.addView(TextView(this).apply {
                    text = item.source
                    setTextColor(0xFFD7D0DD.toInt())
                    textSize = 12.5f
                    setPadding(0, dp(4), 0, 0)
                })
                row.addView(left)

                val fmt = when ((item.mimeType ?: "").lowercase()) {
                    "text/vtt" -> "VTT"
                    "text/x-ssa" -> "ASS"
                    "application/x-subrip" -> "SRT"
                    else -> item.url.substringAfterLast('.', "SUB").uppercase().take(4)
                }
                row.addView(TextView(this).apply {
                    text = fmt
                    setTextColor(0xFFE8E0EE.toInt())
                    textSize = 11f
                    setPadding(dp(10), dp(5), dp(10), dp(5))
                    background = GradientDrawable().apply {
                        shape = GradientDrawable.RECTANGLE
                        cornerRadius = dpF(12f)
                        setColor(0x223D3947)
                    }
                })

                if (isSelected) {
                    row.addView(TextView(this).apply {
                        text = "  ✓"
                        setTextColor(0xFF8B6CFF.toInt())
                        textSize = 19f
                        setTypeface(typeface, Typeface.BOLD)
                    })
                }

                optionsColumn.addView(row)
                if (index != current.lastIndex) {
                    optionsColumn.addView(View(this).apply {
                        layoutParams = LinearLayout.LayoutParams(MATCH_PARENT, dp(1))
                        setBackgroundColor(0x14FFFFFF)
                    })
                }
            }
        }

        fun renderLanguages() {
            languageColumn.removeAllViews()

            fun addLangRow(text: String, active: Boolean, onClick: () -> Unit) {
                val row = LinearLayout(this).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.CENTER_VERTICAL
                    layoutParams = LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
                    setPadding(dp(6), dp(16), dp(6), dp(16))
                    setOnClickListener { onClick() }
                }
                row.addView(TextView(this).apply {
                    this.text = text
                    setTextColor(if (active) 0xFF8B6CFF.toInt() else 0xFFEDE7F2.toInt())
                    textSize = 16f
                    setTypeface(typeface, if (active) Typeface.BOLD else Typeface.NORMAL)
                    layoutParams = LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f)
                })
                if (active) {
                    row.addView(TextView(this).apply {
                        this.text = "✓"
                        setTextColor(0xFF8B6CFF.toInt())
                        textSize = 20f
                        setTypeface(typeface, Typeface.BOLD)
                    })
                }
                languageColumn.addView(row)
                languageColumn.addView(View(this).apply {
                    layoutParams = LinearLayout.LayoutParams(MATCH_PARENT, dp(1))
                    setBackgroundColor(0x12FFFFFF)
                })
            }

            addLangRow("إيقاف", selectedLang == "__OFF__") {
                selectedLang = "__OFF__"
                manualSubtitleSelection = true
                applySubtitleSelection(null)
                renderLanguages(); renderOptions()
            }

            langs.forEach { lang ->
                addLangRow(lang, selectedLang == lang) {
                    selectedLang = lang
                    renderLanguages(); renderOptions()
                }
            }
        }

        body.addView(languageScroll)
        body.addView(makeDivider())
        body.addView(optionsScroll)
        body.addView(makeDivider())
        body.addView(settingsScroll)
        card.addView(body)
        root.addView(card)
        dialog.setContentView(root)
        renderLanguages()
        renderOptions()
        dialog.show()
    }

    // ─── ★ Apply subtitle by reloading media at current position ──────────

    @OptIn(UnstableApi::class)
    private fun applySubtitleSelection(subtitleUrl: String?) {
        val player = exoPlayer ?: return
        val url = currentMediaUrl ?: return
        val posMs = player.currentPosition
        val wasPlaying = player.isPlaying || player.playWhenReady

        selectedSubtitleUrl = subtitleUrl
        selectedSubtitleResolvedUrl = null

        val rawSelectedTrack = if (subtitleUrl != null) {
            externalSubtitleTracks.firstOrNull { it.url == subtitleUrl }
        } else {
            null
        }

        activeSubtitleRawTrack = rawSelectedTrack
        activeSubtitleProfileKey = buildSubtitleProfileKey(rawSelectedTrack)

        subtitleDelayMs = 0
        if (rawSelectedTrack == null) {
            resetActiveSubtitleProfile()
        }

        val selectedTrack = rawSelectedTrack
        selectedSubtitleResolvedUrl = selectedTrack?.url
        activeSubtitleRateMultiplier = 1.0

        Log.d(
            LOG_TAG,
            "applySubtitleSelection subtitleUrl=$subtitleUrl selected=${selectedTrack?.label} mime=${selectedTrack?.mimeType} lang=${selectedTrack?.language} delayMs=$subtitleDelayMs fpsScale=$activeSubtitleRateMultiplier profile=$activeSubtitleProfileKey"
        )

        player.trackSelectionParameters = player.trackSelectionParameters
            .buildUpon()
            .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, selectedTrack == null)
            .setPreferredTextLanguage(selectedTrack?.language?.takeIf { it.isNotBlank() })
            .setSelectUndeterminedTextLanguage(true)
            .clearOverridesOfType(C.TRACK_TYPE_TEXT)
            .build()

        player.playWhenReady = wasPlaying
        player.setMediaItem(
            buildMediaItemWithOptionalSubtitle(url, currentMediaMime, selectedTrack),
            false
        )
        player.prepare()
        player.seekTo(posMs)

        if (wasPlaying) {
            player.play()
        } else {
            player.pause()
        }

        playerView?.subtitleView?.visibility = View.VISIBLE
        applySubtitleAppearance()
        updateSpeedButtonLabel(player.playbackParameters.speed)
    }

    // ─── Track selection (internal ExoPlayer tracks) ──────────────────────

    private fun collectTrackChoices(tracks: Tracks, type: Int): List<TrackChoice> {
        val result = mutableListOf<TrackChoice>()
        for (group in tracks.groups) {
            if (group.type != type) continue
            for (i in 0 until group.length) {
                if (!group.isTrackSupported(i)) continue
                val format = group.getTrackFormat(i)
                val label = when (type) {
                    C.TRACK_TYPE_VIDEO -> {
                        val h = format.height
                        val bitrate = if (format.bitrate > 0) " ${format.bitrate / 1000}kbps" else ""
                        if (h > 0) "${h}p$bitrate" else format.label?.takeIf { it.isNotBlank() } ?: "Video ${i + 1}"
                    }
                    C.TRACK_TYPE_AUDIO ->
                        listOfNotNull(
                            format.label?.takeIf { it.isNotBlank() },
                            format.language?.takeIf { it.isNotBlank() },
                            format.sampleMimeType?.substringAfterLast('.')?.uppercase(),
                        ).joinToString(" • ").ifBlank { "Audio ${i + 1}" }
                    else ->
                        listOfNotNull(
                            format.label?.takeIf { it.isNotBlank() },
                            format.language?.takeIf { it.isNotBlank() },
                        ).joinToString(" • ").ifBlank { "Subtitle ${i + 1}" }
                }
                result += TrackChoice(label, group, i, group.isTrackSelected(i))
            }
        }
        return result.distinctBy { it.label }
    }

    private fun applyTrackSelection(type: Int, choice: TrackChoice) {
        val player = exoPlayer ?: return
        val override = TrackSelectionOverride(choice.group.mediaTrackGroup, listOf(choice.trackIndex))
        player.trackSelectionParameters = player.trackSelectionParameters.buildUpon()
            .clearOverridesOfType(type)
            .addOverride(override)
            .setTrackTypeDisabled(type, false)
            .build()
    }


    private fun currentSelectedQualityLabel(): String =
        pageQualityOptions.firstOrNull { it.selected }?.label?.trim().orEmpty()

    private fun currentSelectedServerLabel(): String =
        pageServerOptions.firstOrNull { it.selected }?.label?.trim().orEmpty()

    private fun sanitizeProfilePart(value: String): String =
        value.lowercase()
            .replace(Regex("[^a-z0-9._-]+"), "_")
            .replace(Regex("_+"), "_")
            .trim('_')
            .take(80)

    private fun extractReleaseSignature(text: String): String {
        val s = text.lowercase()
        fun pick(vararg keys: String): String = keys.firstOrNull { s.contains(it) }.orEmpty()

        val source = when {
            s.contains("bluray") || s.contains("brrip") || s.contains("bdrip") -> "bluray"
            s.contains("webrip") -> "webrip"
            s.contains("web-dl") || s.contains("webdl") -> "webdl"
            s.contains("hdrip") -> "hdrip"
            s.contains("dvdrip") -> "dvdrip"
            else -> ""
        }
        val platform = pick("netflix", "nf", "amzn", "amazon", "dsnp", "disney", "hmax", "max", "atvp", "apple")
        val codec = when {
            s.contains("hevc") || s.contains("x265") || s.contains("h265") -> "hevc"
            s.contains("av1") -> "av1"
            s.contains("x264") || s.contains("h264") || s.contains("avc") -> "avc"
            else -> ""
        }
        val res = Regex("(2160|1440|1080|720|576|540|480|360|240)p", RegexOption.IGNORE_CASE)
            .find(s)?.groupValues?.getOrNull(1)?.let { "${it}p" }.orEmpty()
        val fps = detectFpsValue(s)?.let {
            when {
                kotlin.math.abs(it - 23.976) < 0.01 -> "23.976"
                kotlin.math.abs(it - 29.97) < 0.01 -> "29.97"
                kotlin.math.abs(it - 59.94) < 0.01 -> "59.94"
                else -> java.lang.String.format(java.util.Locale.US, "%.3f", it).trimEnd('0').trimEnd('.')
            }
        }.orEmpty()

        return listOf(source, platform, codec, res, fps)
            .filter { it.isNotBlank() }
            .joinToString("_")
            .ifBlank { sanitizeProfilePart(s.take(80)) }
    }

    private fun detectFpsValue(text: String?): Double? {
        if (text.isNullOrBlank()) return null
        val s = text.lowercase()
        fun parse(raw: String): Double? = raw.replace(',', '.').toDoubleOrNull()

        Regex("""(23[.,]?976|24(?:\.0+)?|25(?:\.0+)?|29[.,]?97|30(?:\.0+)?|50(?:\.0+)?|59[.,]?94|60(?:\.0+)?)\s*(?:fps|hz)?""")
            .find(s)?.groupValues?.getOrNull(1)?.let { return parse(it) }

        if (s.contains("24000/1001")) return 23.976
        if (s.contains("30000/1001")) return 29.97
        if (s.contains("60000/1001")) return 59.94
        return null
    }

    private fun inferVideoFrameRate(): Double? {
        val joined = listOfNotNull(
            currentMediaUrl,
            currentSelectedQualityLabel().takeIf { it.isNotBlank() },
            currentSelectedServerLabel().takeIf { it.isNotBlank() },
        ).joinToString(" ")
        return detectFpsValue(joined)
    }

    private fun inferSubtitleFrameRate(track: ExternalSubtitle?): Double? {
        if (track == null) return null
        val joined = listOf(track.release, track.label, track.language, track.source, track.url).joinToString(" ")
        return detectFpsValue(joined)
    }

    private fun computeSubtitleRateMultiplier(track: ExternalSubtitle?): Double {
        val subtitleFps = inferSubtitleFrameRate(track) ?: return 1.0
        val videoFps = inferVideoFrameRate() ?: return 1.0
        if (videoFps <= 0.0 || subtitleFps <= 0.0) return 1.0
        val ratio = subtitleFps / videoFps
        return if (kotlin.math.abs(ratio - 1.0) in 0.001..0.15) ratio else 1.0
    }

    private fun buildSubtitleProfileKey(track: ExternalSubtitle?): String? {
        if (track == null) return null
        val videoSig = extractReleaseSignature(
            listOfNotNull(
                currentMediaUrl,
                currentSelectedQualityLabel().takeIf { it.isNotBlank() },
                currentSelectedServerLabel().takeIf { it.isNotBlank() },
            ).joinToString(" ")
        )
        val subSig = extractReleaseSignature(
            listOf(track.release, track.label, track.language, track.source, track.url).joinToString(" ")
        )
        val lang = sanitizeProfilePart(track.language.ifBlank { track.label.ifBlank { "sub" } })
        return listOf(videoSig, subSig, lang)
            .filter { it.isNotBlank() }
            .joinToString("|")
            .ifBlank { null }
    }

    private fun profileDelayPrefKey(profileKey: String): String =
        PREF_SUB_DELAY_PROFILE_PREFIX + sanitizeProfilePart(profileKey)

    private fun loadDelayForProfile(profileKey: String?): Int {
        if (profileKey.isNullOrBlank()) return subtitlePrefs.getInt(PREF_SUB_DELAY, 0).coerceIn(-MAX_SUB_DELAY_MS, MAX_SUB_DELAY_MS)
        val key = profileDelayPrefKey(profileKey)
        if (!subtitlePrefs.contains(key)) return subtitlePrefs.getInt(PREF_SUB_DELAY, 0).coerceIn(-MAX_SUB_DELAY_MS, MAX_SUB_DELAY_MS)
        return subtitlePrefs.getInt(key, 0).coerceIn(-MAX_SUB_DELAY_MS, MAX_SUB_DELAY_MS)
    }

    private fun saveDelayForProfile(profileKey: String?, delayMs: Int) {
        if (profileKey.isNullOrBlank()) return
        subtitlePrefs.edit().putInt(profileDelayPrefKey(profileKey), delayMs.coerceIn(-MAX_SUB_DELAY_MS, MAX_SUB_DELAY_MS)).apply()
    }

    private fun resolveAutoDelayForTrack(track: ExternalSubtitle): Int =
        loadDelayForProfile(buildSubtitleProfileKey(track))

    private fun resetActiveSubtitleProfile() {
        activeSubtitleRawTrack = null
        activeSubtitleProfileKey = null
        activeSubtitleRateMultiplier = 1.0
        selectedSubtitleResolvedUrl = null
    }

    private fun persistActiveSubtitleDelay() {
        saveDelayForProfile(activeSubtitleProfileKey, subtitleDelayMs)
    }

    private fun adjustSubtitleDelayBy(deltaMs: Int) {
        subtitleDelayMs = (subtitleDelayMs + deltaMs).coerceIn(-MAX_SUB_DELAY_MS, MAX_SUB_DELAY_MS)
        persistActiveSubtitleDelay()
        saveSubtitlePrefs()
        selectedSubtitleUrl?.let { applySubtitleSelection(it) }
    }

    private fun loadSubtitlePrefs() {
        val savedVersion = subtitlePrefs.getInt(PREF_SUB_STYLE_VERSION, 0)
        if (savedVersion != CURRENT_SUB_STYLE_VERSION) {
            subtitleSizePercent = 140
            subtitleVerticalOffsetPercent = 5
            subtitleBackgroundEnabled = false
            subtitleDelayMs = 0
            saveSubtitlePrefs()
            return
        }
        subtitleSizePercent = subtitlePrefs.getInt(PREF_SUB_SIZE, 140).coerceIn(70, 190)
        subtitleVerticalOffsetPercent = subtitlePrefs.getInt(PREF_SUB_OFFSET, 5).coerceIn(0, 24)
        subtitleBackgroundEnabled = subtitlePrefs.getBoolean(PREF_SUB_BG, false)
        subtitleDelayMs = subtitlePrefs.getInt(PREF_SUB_DELAY, 0).coerceIn(-MAX_SUB_DELAY_MS, MAX_SUB_DELAY_MS)
    }

    private fun saveSubtitlePrefs() {
        subtitlePrefs.edit()
            .putInt(PREF_SUB_STYLE_VERSION, CURRENT_SUB_STYLE_VERSION)
            .putInt(PREF_SUB_SIZE, subtitleSizePercent)
            .putInt(PREF_SUB_OFFSET, subtitleVerticalOffsetPercent)
            .putBoolean(PREF_SUB_BG, subtitleBackgroundEnabled)
            .putInt(PREF_SUB_DELAY, subtitleDelayMs.coerceIn(-MAX_SUB_DELAY_MS, MAX_SUB_DELAY_MS))
            .apply()
    }

    private fun applySubtitleAppearance(view: androidx.media3.ui.SubtitleView? = playerView?.subtitleView) {
        val subtitleView = view ?: return
        subtitleView.setApplyEmbeddedStyles(false)
        subtitleView.setApplyEmbeddedFontSizes(false)
        subtitleView.setFixedTextSize(TypedValue.COMPLEX_UNIT_SP, 15f * (subtitleSizePercent / 100f))
        subtitleView.setBottomPaddingFraction((subtitleVerticalOffsetPercent.coerceIn(0, 24)) / 100f)
        subtitleView.setPadding(0, 0, 0, 0)
        subtitleView.setStyle(
            CaptionStyleCompat(
                Color.WHITE,
                if (subtitleBackgroundEnabled) 0xB3000000.toInt() else Color.TRANSPARENT,
                Color.TRANSPARENT,
                CaptionStyleCompat.EDGE_TYPE_OUTLINE,
                0xCC000000.toInt(),
                Typeface.DEFAULT_BOLD,
            )
        )
        subtitleView.invalidate()
    }

    private fun showSubtitleStyleDialog() {
        val dialog = Dialog(this)
        dialog.window?.setBackgroundDrawableResource(android.R.color.transparent)
        dialog.window?.clearFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND)

        val root = FrameLayout(this).apply {
            setBackgroundColor(Color.TRANSPARENT)
            layoutParams = FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT)
            setOnClickListener { dialog.dismiss() }
        }

        val scroll = ScrollView(this).apply {
            isFillViewport = false
            layoutParams = FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                gravity = Gravity.TOP
                leftMargin = dp(18)
                rightMargin = dp(18)
                topMargin = dp(6)
                bottomMargin = dp(18)
            }
        }

        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(18), dp(18), dp(18), dp(18))
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dpF(24f)
                setColor(0xFF17131F.toInt())
            }
            layoutParams = ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
            isClickable = true
        }

        card.addView(TextView(this).apply {
            text = "إعدادات الترجمة"
            setTextColor(Color.WHITE)
            textSize = 18f
            setTypeface(typeface, Typeface.BOLD)
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(0, 0, 0, dp(6))
        })

        card.addView(TextView(this).apply {
            text = "كبّر النص، حرّكه للأسفل، أضف تأخيرًا، واختر غلافًا أو بدون غلاف."
            setTextColor(0xB3FFFFFF.toInt())
            textSize = 12.5f
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(8), 0, dp(8), dp(14))
        })

        fun addStepperRow(title: String, valueText: () -> String, onMinus: () -> Unit, onPlus: () -> Unit) {
            val row = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                layoutParams = LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                    bottomMargin = dp(12)
                }
            }

            fun makeCircleButton(symbol: String, action: () -> Unit): TextView = TextView(this).apply {
                text = symbol
                gravity = Gravity.CENTER
                textSize = 18f
                setTextColor(Color.WHITE)
                layoutParams = LinearLayout.LayoutParams(dp(40), dp(40))
                background = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(0xFF2B2734.toInt())
                }
                setOnClickListener { action() }
            }

            val center = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER
                layoutParams = LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f)
            }

            val valueView = TextView(this).apply {
                setTextColor(Color.WHITE)
                textSize = 15f
                gravity = Gravity.CENTER
                setTypeface(typeface, Typeface.BOLD)
            }

            center.addView(TextView(this).apply {
                text = title
                setTextColor(0xD9FFFFFF.toInt())
                textSize = 13.5f
                gravity = Gravity.CENTER
                setPadding(0, 0, 0, dp(4))
            })
            center.addView(valueView)

            fun refresh() {
                valueView.text = valueText()
                applySubtitleAppearance()
                saveSubtitlePrefs()
            }

            row.addView(makeCircleButton("−") { onMinus(); refresh() })
            row.addView(center)
            row.addView(makeCircleButton("+") { onPlus(); refresh() })
            refresh()
            card.addView(row)
        }

        addStepperRow(
            "الحجم",
            valueText = { "${subtitleSizePercent}%" },
            onMinus = { subtitleSizePercent = (subtitleSizePercent - 10).coerceAtLeast(70) },
            onPlus = { subtitleSizePercent = (subtitleSizePercent + 10).coerceAtMost(190) },
        )

        addStepperRow(
            "الموضع العمودي",
            valueText = { "${subtitleVerticalOffsetPercent}%" },
            onMinus = { subtitleVerticalOffsetPercent = (subtitleVerticalOffsetPercent - 1).coerceAtLeast(0) },
            onPlus = { subtitleVerticalOffsetPercent = (subtitleVerticalOffsetPercent + 1).coerceAtMost(24) },
        )

        addStepperRow(
            "التأخير",
            valueText = { String.format(java.util.Locale.US, "%.1fs", subtitleDelayMs / 1000f) },
            onMinus = { adjustSubtitleDelayBy(-100) },
            onPlus = { adjustSubtitleDelayBy(100) },
        )

        card.addView(TextView(this).apply {
            text = "الغلاف"
            setTextColor(Color.WHITE)
            textSize = 13.5f
            setTypeface(typeface, Typeface.BOLD)
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(0, dp(2), 0, dp(10))
        })

        val chipRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                bottomMargin = dp(10)
            }
        }

        fun makeChip(label: String, active: Boolean, onClick: () -> Unit): TextView = TextView(this).apply {
            text = label
            setTextColor(if (active) Color.WHITE else 0xD9FFFFFF.toInt())
            textSize = 13f
            gravity = Gravity.CENTER
            setPadding(dp(12), dp(9), dp(12), dp(9))
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dpF(15f)
                setColor(if (active) 0xFF6E56CF.toInt() else 0xFF2B2734.toInt())
            }
            setOnClickListener {
                onClick()
                applySubtitleAppearance()
                saveSubtitlePrefs()
                dialog.dismiss()
                showSubtitleStyleDialog()
            }
        }

        chipRow.addView(makeChip("بدون غلاف", !subtitleBackgroundEnabled) { subtitleBackgroundEnabled = false })
        chipRow.addView(View(this).apply { layoutParams = LinearLayout.LayoutParams(dp(8), 1) })
        chipRow.addView(makeChip("غلاف", subtitleBackgroundEnabled) { subtitleBackgroundEnabled = true })
        card.addView(chipRow)

        card.addView(TextView(this).apply {
            text = "ملاحظة: كلما قلّ الموضع العمودي نزلت الترجمة أكثر. التأخير الموجب يؤخر الترجمة، والسالب يقدّمها."
            setTextColor(0x99FFFFFF.toInt())
            textSize = 12.5f
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(4), dp(6), dp(4), dp(10))
        })

        card.addView(Button(this).apply {
            text = "إغلاق"
            setTextColor(Color.WHITE)
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dpF(16f)
                setColor(0xFF2B2734.toInt())
            }
            setOnClickListener { dialog.dismiss() }
        })

        scroll.addView(card)
        root.addView(scroll)
        dialog.setContentView(root)
        dialog.show()
    }

    private fun withAppliedDelay(track: ExternalSubtitle?): ExternalSubtitle? {
        if (track == null) return null
        val rateMultiplier = computeSubtitleRateMultiplier(track)
        if (subtitleDelayMs == 0 && kotlin.math.abs(rateMultiplier - 1.0) < 0.0005) return track
        return try {
            val body = readSubtitleText(track) ?: return track
            val mime = inferSubtitleMimeType(track.url, track.mimeType) ?: track.mimeType.orEmpty()
            val lower = mime.lowercase()
            val transformed = when {
                lower.contains("vtt") || track.url.lowercase().endsWith(".vtt") -> transformVttText(body, subtitleDelayMs, rateMultiplier)
                lower.contains("ssa") || lower.contains("ass") || track.url.lowercase().endsWith(".ass") || track.url.lowercase().endsWith(".ssa") -> transformAssText(body, subtitleDelayMs, rateMultiplier)
                lower.contains("subrip") || track.url.lowercase().endsWith(".srt") -> transformSrtText(body, subtitleDelayMs, rateMultiplier)
                else -> {
                    Log.w(LOG_TAG, "withAppliedDelay: unsupported subtitle transform for ${track.url}")
                    body
                }
            }
            val ext = when {
                lower.contains("vtt") || track.url.lowercase().endsWith(".vtt") -> "vtt"
                lower.contains("ssa") || lower.contains("ass") || track.url.lowercase().endsWith(".ass") || track.url.lowercase().endsWith(".ssa") -> "ass"
                else -> "srt"
            }
            val dir = java.io.File(cacheDir, "shifted_subs").apply { mkdirs() }
            val sig = "${track.url}|${subtitleDelayMs}|${java.lang.String.format(java.util.Locale.US, "%.5f", rateMultiplier)}"
            val outFile = java.io.File(dir, "sub_${kotlin.math.abs(sig.hashCode())}.$ext")
            outFile.writeText(transformed)
            track.copy(
                url = outFile.toURI().toString(),
                mimeType = when (ext) {
                    "vtt" -> MimeTypes.TEXT_VTT
                    "ass" -> "text/x-ssa"
                    else -> MimeTypes.APPLICATION_SUBRIP
                }
            )
        } catch (e: Exception) {
            Log.e(LOG_TAG, "withAppliedDelay failed", e)
            track
        }
    }

    private fun readSubtitleText(track: ExternalSubtitle): String? {
        return try {
            val uri = Uri.parse(track.url)
            when ((uri.scheme ?: "").lowercase()) {
                "", "file" -> {
                    val file = when {
                        uri.scheme.equals("file", ignoreCase = true) -> java.io.File(uri.path ?: return null)
                        else -> java.io.File(track.url)
                    }
                    if (!file.exists()) return null
                    file.readText()
                }
                else -> {
                    val headers = prepareMediaHeaders(track.url, currentMediaHeaders)
                    val reqBuilder = okhttp3.Request.Builder().url(track.url)
                    headers.forEach { (k, v) -> if (k.isNotBlank() && v.isNotBlank()) reqBuilder.header(k, v) }
                    okhttp3.OkHttpClient().newCall(reqBuilder.build()).execute().use { response ->
                        if (!response.isSuccessful) return null
                        response.body?.string()
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(LOG_TAG, "readSubtitleText failed", e)
            null
        }
    }

    private fun transformTimeMs(rawMs: Long, delayMs: Int, rateMultiplier: Double): Long {
        return ((rawMs.toDouble() * rateMultiplier) + delayMs.toDouble())
            .roundToLong()
            .coerceAtLeast(0L)
    }

    private fun transformSrtText(text: String, delayMs: Int, rateMultiplier: Double): String {
        val regex = Regex("""((?:\d{2}:)?\d{2}:\d{2},\d{3})\s*-->\s*((?:\d{2}:)?\d{2}:\d{2},\d{3})""")
        return regex.replace(text) { m ->
            val start = transformTimeMs(parseSubtitleTimeMs(m.groupValues[1]) ?: 0L, delayMs, rateMultiplier)
            val end = transformTimeMs(parseSubtitleTimeMs(m.groupValues[2]) ?: 0L, delayMs, rateMultiplier)
            "${formatSrtTimeMs(start)} --> ${formatSrtTimeMs(end)}"
        }
    }

    private fun transformVttText(text: String, delayMs: Int, rateMultiplier: Double): String {
        val regex = Regex("""((?:\d{2}:)?\d{2}:\d{2}\.\d{3})\s*-->\s*((?:\d{2}:)?\d{2}:\d{2}\.\d{3})""")
        return regex.replace(text) { m ->
            val start = transformTimeMs(parseSubtitleTimeMs(m.groupValues[1]) ?: 0L, delayMs, rateMultiplier)
            val end = transformTimeMs(parseSubtitleTimeMs(m.groupValues[2]) ?: 0L, delayMs, rateMultiplier)
            "${formatVttTimeMs(start)} --> ${formatVttTimeMs(end)}"
        }
    }

    private fun transformAssText(text: String, delayMs: Int, rateMultiplier: Double): String {
        return text.split("\n").joinToString("\n") { line ->
            if (!line.startsWith("Dialogue:", ignoreCase = true) && !line.startsWith("Comment:", ignoreCase = true)) {
                line
            } else {
                val parts = line.split(",", limit = 10).toMutableList()
                if (parts.size < 3) {
                    line
                } else {
                    val startRaw = parts[1].trim()
                    val endRaw = parts[2].trim()
                    val start = parseAssTimeMs(startRaw)
                    val end = parseAssTimeMs(endRaw)
                    if (start == null || end == null) {
                        line
                    } else {
                        parts[1] = formatAssTimeMs(transformTimeMs(start, delayMs, rateMultiplier))
                        parts[2] = formatAssTimeMs(transformTimeMs(end, delayMs, rateMultiplier))
                        parts.joinToString(",")
                    }
                }
            }
        }
    }

    private fun parseSubtitleTimeMs(raw: String): Long? {
        val s = raw.trim().replace(',', '.')
        val parts = s.split(':')
        val normalized = when (parts.size) {
            2 -> listOf("0", parts[0], parts[1])
            3 -> parts
            else -> return null
        }
        val h = normalized[0].toLongOrNull() ?: return null
        val m = normalized[1].toLongOrNull() ?: return null
        val secParts = normalized[2].split('.')
        val sec = secParts.getOrNull(0)?.toLongOrNull() ?: return null
        val ms = secParts.getOrNull(1)?.padEnd(3, '0')?.take(3)?.toLongOrNull() ?: 0L
        return (((h * 60 + m) * 60) + sec) * 1000 + ms
    }

    private fun parseAssTimeMs(raw: String): Long? {
        val parts = raw.trim().split(':')
        if (parts.size != 3) return null
        val h = parts[0].toLongOrNull() ?: return null
        val m = parts[1].toLongOrNull() ?: return null
        val secParts = parts[2].split('.')
        val sec = secParts.getOrNull(0)?.toLongOrNull() ?: return null
        val cs = secParts.getOrNull(1)?.padEnd(2, '0')?.take(2)?.toLongOrNull() ?: 0L
        return (((h * 60 + m) * 60) + sec) * 1000 + (cs * 10)
    }

    private fun formatSrtTimeMs(ms: Long): String {
        val total = ms.coerceAtLeast(0)
        val h = total / 3600000
        val m = (total % 3600000) / 60000
        val s = (total % 60000) / 1000
        val rem = total % 1000
        return String.format(java.util.Locale.US, "%02d:%02d:%02d,%03d", h, m, s, rem)
    }

    private fun formatVttTimeMs(ms: Long): String {
        val total = ms.coerceAtLeast(0)
        val h = total / 3600000
        val m = (total % 3600000) / 60000
        val s = (total % 60000) / 1000
        val rem = total % 1000
        return String.format(java.util.Locale.US, "%02d:%02d:%02d.%03d", h, m, s, rem)
    }

    private fun formatAssTimeMs(ms: Long): String {
        val total = ms.coerceAtLeast(0)
        val h = total / 3600000
        val m = (total % 3600000) / 60000
        val s = (total % 60000) / 1000
        val cs = (total % 1000) / 10
        return String.format(java.util.Locale.US, "%01d:%02d:%02d.%02d", h, m, s, cs)
    }

    private fun simpleMessage(message: String) {
        AlertDialog.Builder(this).setMessage(message).setPositiveButton("حسنًا", null).show()
    }

    // ─── Helpers ──────────────────────────────────────────────────────────

    private fun normalizeLanguage(raw: String): String {
        val v = raw.trim().lowercase()
        return when {
            v.startsWith("ar") || v.contains("arab") -> "Arabic"
            v.startsWith("en") || v.contains("engl") -> "English"
            v.length <= 3 && v.isNotEmpty() -> v.uppercase()
            v.isEmpty() -> "Unknown"
            else -> v.replaceFirstChar { it.uppercase() }
        }
    }

    private fun sanitizeRatio(w: Int, h: Int): Rational {
        val raw = if (w > 0 && h > 0) w.toDouble() / h.toDouble() else 16.0 / 9.0
        val clamped = raw.coerceIn(MIN_PIP_RATIO, MAX_PIP_RATIO)
        val base = 10_000
        return Rational(max((clamped * base).toInt(), 1), base)
    }

        
    
    

    private fun safePipRatio(): Rational {
        val w = if (lastAspectW > 0) lastAspectW else 16
        val h = if (lastAspectH > 0) lastAspectH else 9
        return sanitizeRatio(w, h) ?: Rational(16, 9)
    }

    private fun currentSourceRectHint(): Rect? {
        val rect = Rect()
        val target = playerView ?: playerContainer ?: return null
        return if (target.getGlobalVisibleRect(rect) && !rect.isEmpty) rect else null
    }

    private fun buildPipParams(): PictureInPictureParams? {
        if (!isPipSupported()) return null
        return try {
            val builder = PictureInPictureParams.Builder()
                .setAspectRatio(safePipRatio())

            currentSourceRectHint()?.let { builder.setSourceRectHint(it) }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                builder.setSeamlessResizeEnabled(true)
                builder.setAutoEnterEnabled(false)
            }

            builder.build()
        } catch (_: Exception) {
            null
        }
    }

    private fun updatePipParams() {
        if (!isPipSupported()) return
        try { buildPipParams()?.let { setPictureInPictureParams(it) } } catch (_: Exception) {}
    }

    private fun inferSubtitleMimeType(url: String, hinted: String?): String? {
        val hint = hinted?.lowercase()?.trim().orEmpty()
        if (hint.isNotEmpty()) return hint
        val lower = url.lowercase()
        return when {
            lower.endsWith(".vtt") -> MimeTypes.TEXT_VTT
            lower.endsWith(".srt") -> MimeTypes.APPLICATION_SUBRIP
            lower.endsWith(".ass") || lower.endsWith(".ssa") -> "text/x-ssa"
            lower.endsWith(".ttml") || lower.endsWith(".xml") -> MimeTypes.APPLICATION_TTML
            else -> null
        }
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()
    private fun dpF(value: Float): Float = value * resources.displayMetrics.density

    // ─── Lifecycle ────────────────────────────────────────────────────────

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        channel?.invokeMethod("onPipChanged", isInPictureInPictureMode)

        if (isInPictureInPictureMode) {
            hideEveryOverlayForPip()
            updateOverlayVisibility()
            return
        }

        if (nativePlayerActive) {
            restoreVideoOnlyAfterPip()
            applyLandscapeMode()
            showNativeSurface()

            playerContainer?.postDelayed({ restoreVideoOnlyAfterPip(); showNativeSurface() }, 80L)
            playerContainer?.postDelayed({ restoreVideoOnlyAfterPip(); showNativeSurface() }, 220L)
            return
        }

        restoreVideoOnlyAfterPip()
        updateOverlayVisibility()
    }

    override fun onResume() {
        super.onResume()
enableHighRefreshRate()
        if (nativePlayerActive && !isInPictureInPictureMode) {
            applyLandscapeMode()
            showNativeSurface()
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        // Do not auto-enter PiP on back/home. PiP should only be entered explicitly.
    }

    override fun onPictureInPictureRequested(): Boolean {
        return false
    }

    override fun onPause() {
        if (nativePlayerActive && !isInPictureInPictureMode) {
            pauseNativePlayerForBackground()
        }
        super.onPause()
    }

    override fun onStop() {
        super.onStop()
        if (!isInPictureInPictureMode) {
            if (isFinishing) {
                closeNativePlayer()
            } else {
                pauseNativePlayerForBackground()
            }
        }
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        hideNativeSurfaceImmediately()
        releasePlayerOnly()
        super.onDestroy()
    }
}
