package com.example.flutter_application_1

import android.animation.ValueAnimator
import android.content.Context
import android.content.Intent
import android.graphics.Canvas
import android.graphics.Paint
import android.view.animation.LinearInterpolator
import android.app.AlertDialog
import android.app.Dialog
import android.app.PictureInPictureParams
import android.content.pm.ActivityInfo
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.Rect
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.util.Rational
import android.util.TypedValue
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.View
import android.view.MotionEvent
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
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.CaptionStyleCompat
import androidx.media3.ui.PlayerView
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import kotlin.math.max
import kotlin.math.roundToLong

private class DropletCircleLoaderView(context: Context) : View(context) {
    private val backgroundWavePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(150, 255, 255, 255)
        style = Paint.Style.FILL
    }
    private val foregroundWavePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        style = Paint.Style.FILL
    }
    private val circleStrokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(70, 255, 255, 255)
        style = Paint.Style.STROKE
        strokeWidth = 0f
    }
    private val clipPath = android.graphics.Path()
    private val backgroundPath = android.graphics.Path()
    private val foregroundPath = android.graphics.Path()
    private var progress = 0f
    private val animator = ValueAnimator.ofFloat(0f, 1f).apply {
        duration = 3600L
        repeatCount = ValueAnimator.INFINITE
        interpolator = LinearInterpolator()
        addUpdateListener {
            progress = it.animatedValue as Float
            invalidate()
        }
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        if (!animator.isStarted) animator.start()
    }

    override fun onDetachedFromWindow() {
        animator.cancel()
        super.onDetachedFromWindow()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val w = width.toFloat()
        val h = height.toFloat()
        if (w <= 0f || h <= 0f) return

        val size = minOf(w, h)
        val radius = size / 2f
        val cx = w / 2f
        val cy = h / 2f
        val bubbleDiameter = size * 0.92f
        val waveRadius = bubbleDiameter * 0.44f
        val left = cx - waveRadius
        val bottom = cy + waveRadius

        val t = progress.toDouble()
        val waveHeight = reversingSplitParameters(
            position = t,
            numberBreaks = 5.0,
            parameterBase = bubbleDiameter * 0.06,
            parameterVariation = bubbleDiameter * 0.04,
        ).toFloat()
        val bgOffset = (bubbleDiameter * 0.45 - t * bubbleDiameter).toFloat()
        val fgOffset = (bubbleDiameter * 0.45 + reversingSplitParameters(
            position = t,
            numberBreaks = 6.0,
            parameterBase = bubbleDiameter * 0.04,
            parameterVariation = bubbleDiameter * 0.04,
        ) - t * bubbleDiameter).toFloat()

        clipPath.reset()
        clipPath.addCircle(cx, cy, waveRadius, android.graphics.Path.Direction.CW)

        backgroundPath.reset()
        buildWavePath(
            path = backgroundPath,
            startX = left,
            startY = cy + bgOffset,
            width = waveRadius * 2f,
            amplitude = waveHeight,
            phaseShift = (t * 10.0).toFloat(),
            closeToY = bottom,
        )

        foregroundPath.reset()
        buildWavePath(
            path = foregroundPath,
            startX = left,
            startY = cy + fgOffset,
            width = waveRadius * 2f,
            amplitude = waveHeight,
            phaseShift = (-t * 10.0).toFloat(),
            closeToY = bottom,
        )

        canvas.save()
        canvas.clipPath(clipPath)
        canvas.drawPath(backgroundPath, backgroundWavePaint)
        canvas.drawPath(foregroundPath, foregroundWavePaint)
        canvas.restore()

        circleStrokePaint.strokeWidth = size * 0.035f
        canvas.drawCircle(cx, cy, waveRadius - circleStrokePaint.strokeWidth / 2f, circleStrokePaint)
    }

    private fun buildWavePath(
        path: android.graphics.Path,
        startX: Float,
        startY: Float,
        width: Float,
        amplitude: Float,
        phaseShift: Float,
        closeToY: Float,
    ) {
        path.moveTo(startX, startY)
        var i = 0f
        while (i <= width) {
            val y = startY + amplitude * kotlin.math.sin((i * 2f * Math.PI.toFloat() / width) + phaseShift * Math.PI.toFloat())
            path.lineTo(startX + i, y)
            i += 1f
        }
        path.lineTo(startX + width, closeToY)
        path.lineTo(startX, closeToY)
        path.close()
    }

    private fun breakAnimationPosition(position: Double, numberBreaks: Double): Double {
        var finalAnimationPosition = 0.0
        val breakPoint = 1.0 / numberBreaks
        for (i in 0 until numberBreaks.toInt()) {
            if (position <= breakPoint * (i + 1)) {
                finalAnimationPosition = (position - i * breakPoint) * numberBreaks
                break
            }
        }
        return finalAnimationPosition.coerceIn(0.0, 1.0)
    }

    private fun reversingSplitParameters(
        position: Double,
        numberBreaks: Double,
        parameterBase: Double,
        parameterVariation: Double,
    ): Double {
        val finalAnimationPosition = breakAnimationPosition(position, numberBreaks)
        return if (finalAnimationPosition <= 0.5) {
            parameterBase - (finalAnimationPosition * 2.0 * parameterVariation)
        } else {
            parameterBase - ((1.0 - finalAnimationPosition) * 2.0 * parameterVariation)
        }
    }
}

class LightOnActivity : FlutterActivity() {

    override fun getDartEntrypointFunctionName(): String = "lightOnMain"


    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus && nativePlayerActive && !isInPictureInPictureMode) {
            applyPlayerFullscreenWindow()
        }
    }

    private fun enableHighRefreshRate() {
    }

    private fun detectSelectedVideoFrameRate(player: ExoPlayer): Float? {
        for (group in player.currentTracks.groups) {
            if (group.type != C.TRACK_TYPE_VIDEO) continue
            for (i in 0 until group.length) {
                if (!group.isTrackSelected(i)) continue
                val fps = group.getTrackFormat(i).frameRate
                if (fps > 0f && fps < 240f) return fps
            }
        }
        return null
    }

    private fun pickBestDisplayModeForFps(targetFps: Float): Int? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M || targetFps <= 0f) return null
        val currentDisplay = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) display
        else @Suppress("DEPRECATION") windowManager.defaultDisplay
        val modes = currentDisplay?.supportedModes ?: emptyArray()
        if (modes.isEmpty()) return null

        val best = modes.minByOrNull { mode ->
            val hz = mode.refreshRate
            if (hz <= 0f) {
                Float.MAX_VALUE
            } else {
                val multiple = hz / targetFps
                val nearestInt = kotlin.math.max(1f, kotlin.math.round(multiple))
                val multipleError = kotlin.math.abs(multiple - nearestInt)
                val idealHz = targetFps * nearestInt
                (multipleError * 1000f) + kotlin.math.abs(hz - idealHz)
            }
        }
        return best?.modeId
    }

    private fun applyPlaybackFrameRatePreference(videoFps: Float?) {
        appliedPlaybackFrameRate = null
    }

    private fun resetPlaybackFrameRatePreference() {
        appliedPlaybackFrameRate = null
    }

    companion object {
        private const val CHANNEL = "app.lighton/pip"
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
        private var instance: LightOnActivity? = null

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
    private var trackSelector: DefaultTrackSelector? = null
    private var playerView: PlayerView? = null
    private var playerContainer: FrameLayout? = null
    private var loadingOverlay: FrameLayout? = null
    private var loadingTextView: TextView? = null
    private var controlsScroll: HorizontalScrollView? = null
    private var controlsBar: LinearLayout? = null
    private var flutterContentView: View? = null

    private var fitButton: Button? = null
    private var qualityButton: Button? = null
    private var subtitleButton: Button? = null
    private var pipButton: Button? = null
    private var closeButton: Button? = null

    private var controllerVisible = true
    private var waitFirstRenderedFrame = false
    private var waitingForPlayableSource = false
    private var nativePlayerActive = false
    private var nativePlayerClosing = false
    private var currentResizeMode = AspectRatioFrameLayout.RESIZE_MODE_FILL
    private var inManualPipTransition = false
    private var beforePipFlutterVisibility = View.VISIBLE
    private var beforePipControllerEnabled = true
    private var beforePipResizeMode = AspectRatioFrameLayout.RESIZE_MODE_FILL
    private var pipControllerEnabledBeforeStableMode = true
    private var wasPlayingBeforeManualPip = false

    private val beforePipRootChildVisibility = LinkedHashMap<View, Int>()

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
    private var appliedPlaybackFrameRate: Float? = null

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
                SecurityGuard.protect(this)
instance = this
        subtitlePrefs = getSharedPreferences(SUBTITLE_PREFS, MODE_PRIVATE)
        loadSubtitlePrefs()
        window.decorView.setBackgroundColor(Color.BLACK)
        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = Color.TRANSPARENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isStatusBarContrastEnforced = false
            window.isNavigationBarContrastEnforced = false
        }
    }

    override fun onResume() {
        super.onResume()
                SecurityGuard.protect(this)
if (nativePlayerActive && !isInPictureInPictureMode) {
            applyPlayerFullscreenWindow()
            applyLandscapeMode()
            showNativeSurface()
            playerContainer?.postDelayed({ applyPlayerFullscreenWindow() }, 80L)
            playerContainer?.postDelayed({ applyPlayerFullscreenWindow() }, 240L)
        }
    }


    private fun shouldReturnSelectorOnClose(): Boolean {
        return intent?.getBooleanExtra("return_selector_on_close", true) != false
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

                else -> result.notImplemented()
            }
        }
    }

    // ─── Parsers ──────────────────────────────────────────────────────────

    private fun subtitleTrackIdentityKey(track: ExternalSubtitle): String {
        return listOf(
            track.url.trim().lowercase(),
            track.language.trim().lowercase(),
            track.source.trim().lowercase(),
            track.release.trim().lowercase(),
            track.label.trim().lowercase(),
            (track.mimeType ?: "").trim().lowercase(),
        ).joinToString("|")
    }

    private fun mergeSubtitleTracks(
        current: List<ExternalSubtitle>,
        incoming: List<ExternalSubtitle>,
    ): List<ExternalSubtitle> {
        return (current + incoming)
            .distinctBy { subtitleTrackIdentityKey(it) }
            .sortedBy { subtitleAutoSelectionScore(it) }
    }

    private fun parseSubtitleTracks(raw: List<Map<String, Any?>>?): List<ExternalSubtitle> {
        if (raw.isNullOrEmpty()) return emptyList()
        return raw.mapNotNull { map ->
            val url = map["url"]?.toString()?.trim().orEmpty()
            if (url.isBlank()) return@mapNotNull null
            val label = map["label"]?.toString()?.trim().takeUnless { it.isNullOrEmpty() } ?: "Subtitle"
            val language = map["language"]?.toString()?.trim().orEmpty()
            val providerGroup = map["providerGroup"]?.toString()?.trim()?.lowercase().orEmpty()
            val rawSource = map["source"]?.toString()?.trim().takeUnless { it.isNullOrEmpty() }
                ?: label.substringBefore('•').trim().takeIf { it.isNotEmpty() }
                ?: "External"
            val source = if (providerGroup == "subdl" && !rawSource.lowercase().contains("subdl")) {
                if (rawSource.isNotBlank()) "SubDL • $rawSource" else "SubDL"
            } else rawSource
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
            .distinctBy { subtitleTrackIdentityKey(it) }
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

    private fun isSubdlTrack(track: ExternalSubtitle): Boolean {
        val blob = listOf(track.source, track.label, track.release, track.url)
            .joinToString(" ")
            .lowercase()
        return blob.contains("subdl")
    }

    private fun subtitleAutoSelectionScore(track: ExternalSubtitle): Int {
        val isArabic = isArabicSubtitleTrack(track)
        val isEnglish = isEnglishSubtitleTrack(track)
        val isOpen = isOpenSubtitlesTrack(track)
        val isSubdl = isSubdlTrack(track)

        var score = 0
        score += when {
            isArabic && isSubdl -> 0
            isOpen && isArabic -> 40
            isArabic -> 120
            isOpen -> 260
            isEnglish -> 520
            else -> 760
        }
        if (track.hashMatched) score -= 1200
        if (track.autoSelect) score -= 40
        if (track.hearingImpaired) score += 24
        score -= (subtitleReleaseMatchScore(track) / 4)
        return score
    }

    private fun pickAutoSubtitleTrack(
        tracks: List<ExternalSubtitle> = externalSubtitleTracks,
        preferredUrl: String? = selectedSubtitleUrl,
    ): ExternalSubtitle? {
        if (tracks.isEmpty()) return null

        val wanted = preferredUrl?.trim()?.takeIf { it.isNotEmpty() }
        val exact = wanted?.let { target ->
            tracks.firstOrNull { it.url == target }
        }

        if (manualSubtitleSelection) {
            return exact
        }

        return exact ?: tracks.minByOrNull { subtitleAutoSelectionScore(it) }
    }

    private fun parseQualityOptions(raw: List<Map<String, Any?>>?, currentLabel: String?): List<PageQualityOption> {
        if (raw.isNullOrEmpty()) return emptyList()
        val current = currentLabel?.trim()?.lowercase().orEmpty()
        return raw.mapNotNull { map ->
            val label = map["label"]?.toString()?.trim().orEmpty()
            val key = map["key"]?.toString()?.trim().orEmpty()
            if (label.isBlank()) return@mapNotNull null
            PageQualityOption(
                label = label,
                key = if (key.isNotBlank()) key else label,
                url = map["url"]?.toString()?.trim().takeUnless { it.isNullOrEmpty() },
                selected = label.lowercase() == current || map["selected"] == true,
            )
        }.distinctBy { "${it.label.lowercase()}|${it.url.orEmpty().lowercase()}" }
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



    private var flutterVisibilityBeforePip = View.VISIBLE
    private var controllerEnabledBeforePip = true




    private fun hideRootSiblingsForPip() {
        try {
            val root = findViewById<ViewGroup>(android.R.id.content) ?: return
            beforePipRootChildVisibility.clear()

            for (i in 0 until root.childCount) {
                val child = root.getChildAt(i) ?: continue

                if (child == playerContainer) continue

                beforePipRootChildVisibility[child] = child.visibility
                child.visibility = View.GONE
                child.alpha = 0f
                child.isClickable = false
                child.isEnabled = false
            }

            playerContainer?.apply {
                visibility = View.VISIBLE
                alpha = 1f
                isClickable = true
                isEnabled = true
                bringToFront()
                requestLayout()
            }
        } catch (_: Exception) {
        }
    }

    private fun restoreRootSiblingsAfterPip() {
        try {
            for ((view, visibilityValue) in beforePipRootChildVisibility) {
                view.visibility = visibilityValue
                view.alpha = 1f
                view.isClickable = true
                view.isEnabled = true
            }
            beforePipRootChildVisibility.clear()
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

    private fun applyRoundedCornersForPip() {
        val radiusPx = resources.displayMetrics.density * 16f

        playerView?.apply {
            outlineProvider = object : android.view.ViewOutlineProvider() {
                override fun getOutline(view: android.view.View, outline: android.graphics.Outline) {
                    outline.setRoundRect(0, 0, view.width, view.height, radiusPx)
                }
            }
            clipToOutline = true
            elevation = 0f
        }

        playerContainer?.apply {
            outlineProvider = object : android.view.ViewOutlineProvider() {
                override fun getOutline(view: android.view.View, outline: android.graphics.Outline) {
                    outline.setRoundRect(0, 0, view.width, view.height, radiusPx)
                }
            }
            clipToOutline = true
        }
    }

    private fun removeRoundedCornersAfterPip() {
        playerView?.apply {
            outlineProvider = android.view.ViewOutlineProvider.BACKGROUND
            clipToOutline = false
        }

        playerContainer?.apply {
            outlineProvider = android.view.ViewOutlineProvider.BACKGROUND
            clipToOutline = false
        }
    }

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

        waitingForPlayableSource = false
        waitFirstRenderedFrame = true
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        currentResizeMode = AspectRatioFrameLayout.RESIZE_MODE_FILL
        applyPlayerFullscreenWindow()
        ensurePlayerUi()
        applyPlayerFullscreenWindow()
        releasePlayerOnly()
        playerContainer?.setBackgroundColor(Color.BLACK)
        playerContainer?.visibility = View.VISIBLE
        playerView?.alpha = 0f
        playerView?.visibility = View.INVISIBLE
        playerView?.resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FILL
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
            externalSubtitleTracks = mergeSubtitleTracks(externalSubtitleTracks, subtitleTracks)
            manualSubtitleSelection = false
            selectedSubtitleUrl = pickAutoSubtitleTrack(externalSubtitleTracks, null)?.url
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        currentResizeMode = AspectRatioFrameLayout.RESIZE_MODE_FILL
        applyPlayerFullscreenWindow()
        ensurePlayerUi()
        applyPlayerFullscreenWindow()
        releasePlayerOnly()
        waitingForPlayableSource = true
        waitFirstRenderedFrame = false
        playerContainer?.setBackgroundColor(Color.BLACK)
        playerContainer?.visibility = View.VISIBLE
        playerView?.alpha = 0f
        playerView?.visibility = View.INVISIBLE
        playerView?.resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FILL
        controllerVisible = false
        showPlayerLoadingOverlay()
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
        if (subtitleTracks.isNotEmpty()) {
            externalSubtitleTracks = mergeSubtitleTracks(externalSubtitleTracks, subtitleTracks)
        }
        manualSubtitleSelection = false
        currentMediaUrl = url
        currentMediaMime = mimeType
        currentMediaHeaders = prepareMediaHeaders(url, headers)
        selectedSubtitleUrl = pickAutoSubtitleTrack(externalSubtitleTracks, null)?.url
        waitingForPlayableSource = false
        waitFirstRenderedFrame = true
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        currentResizeMode = AspectRatioFrameLayout.RESIZE_MODE_FILL
        applyPlayerFullscreenWindow()
        ensurePlayerUi()
        applyPlayerFullscreenWindow()
        playerContainer?.visibility = View.VISIBLE
        playerContainer?.setBackgroundColor(Color.BLACK)
        playerView?.alpha = 0f
        playerView?.visibility = View.INVISIBLE
        playerView?.resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FILL
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
                .setConnectTimeoutMs(15000)
                .setReadTimeoutMs(30000)

            val dataSourceFactory = DefaultDataSource.Factory(this, httpFactory)

            val selector = DefaultTrackSelector(this).apply {
                parameters = buildUponParameters()
                    .setExceedVideoConstraintsIfNecessary(true)
                    .setAllowVideoMixedMimeTypeAdaptiveness(true)
                    .setAllowVideoNonSeamlessAdaptiveness(true)
                    .build()
            }
            trackSelector = selector

            val loadControl = DefaultLoadControl.Builder()
                .setBufferDurationsMs(
                    30000,
                    90000,
                    1500,
                    5000,
                )
                .build()

            val renderersFactory = DefaultRenderersFactory(this)
                .setEnableDecoderFallback(true)

            val p = ExoPlayer.Builder(this, renderersFactory)
                .setTrackSelector(selector)
                .setLoadControl(loadControl)
                .setMediaSourceFactory(DefaultMediaSourceFactory(dataSourceFactory))
                .build()
            exoPlayer = p
            playerView?.player = p
            playerView?.resizeMode = currentResizeMode
            p.repeatMode = Player.REPEAT_MODE_OFF
            p.setVideoScalingMode(C.VIDEO_SCALING_MODE_SCALE_TO_FIT_WITH_CROPPING)
            p.setVideoChangeFrameRateStrategy(C.VIDEO_CHANGE_FRAME_RATE_STRATEGY_OFF)
            attachPlayerListeners(p)
            p
        }

        val rawActiveTrack = pickAutoSubtitleTrack(tracks, subtitleUrl)
        selectedSubtitleUrl = rawActiveTrack?.url
        activeSubtitleRawTrack = rawActiveTrack
        activeSubtitleProfileKey = buildSubtitleProfileKey(rawActiveTrack)
        subtitleDelayMs = if (rawActiveTrack != null) {
            resolveAutoDelayForTrack(rawActiveTrack)
        } else {
            loadDelayForProfile(null)
        }
        activeSubtitleRateMultiplier = computeSubtitleRateMultiplier(rawActiveTrack)
        val activeTrack = withAppliedDelay(rawActiveTrack)
        selectedSubtitleResolvedUrl = activeTrack?.url
        Log.d(
            LOG_TAG,
            "buildAndLoadMedia subtitleUrl=$subtitleUrl active=${activeTrack?.label} totalTracks=${tracks.size} delayMs=$subtitleDelayMs fpsScale=$activeSubtitleRateMultiplier profile=$activeSubtitleProfileKey raw=${rawActiveTrack?.url} resolved=${activeTrack?.url}"
        )

        player.trackSelectionParameters = player.trackSelectionParameters
            .buildUpon()
            .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, activeTrack == null)
            .setPreferredTextLanguage(rawActiveTrack?.language?.takeIf { it.isNotBlank() })
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
                waitingForPlayableSource = false
                hidePlayerLoadingOverlay()
                playerView?.alpha = 1f
                playerView?.visibility = View.VISIBLE
                playerContainer?.visibility = View.VISIBLE
                hidePlayerLoadingOverlay()
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
            override fun onTracksChanged(tracks: Tracks) {
                updatePipParams()
                applyPlaybackFrameRatePreference(detectSelectedVideoFrameRate(player))
            }
            override fun onPlaybackStateChanged(playbackState: Int) {
                when (playbackState) {
                    Player.STATE_READY -> {
                        updatePipParams()
                        applyPlaybackFrameRatePreference(detectSelectedVideoFrameRate(player))
                        waitingForPlayableSource = false
                        hidePlayerLoadingOverlay()
                        if (!waitFirstRenderedFrame) {
                            showNativeSurface()
                        }
                    }
                    Player.STATE_BUFFERING, Player.STATE_IDLE -> {
                        if (waitingForPlayableSource) {
                            showPlayerLoadingOverlay()
                        } else {
                            hidePlayerLoadingOverlay()
                        }
                    }
                    Player.STATE_ENDED -> hidePlayerLoadingOverlay()
                }
            }
            override fun onRenderedFirstFrame() {
                waitFirstRenderedFrame = false
                waitingForPlayableSource = false
                runOnUiThread {
                    playerView?.alpha = 1f
                    playerView?.visibility = View.VISIBLE
                    playerContainer?.visibility = View.VISIBLE
                    hidePlayerLoadingOverlay()
                }
            }
            override fun onPlaybackParametersChanged(params: PlaybackParameters) {
                updateSpeedButtonLabel(params.speed)
            }
            override fun onPlayerError(error: PlaybackException) {
                waitingForPlayableSource = false
                hidePlayerLoadingOverlay()
                resetPlaybackFrameRatePreference()
                Log.e(LOG_TAG, "onPlayerError url=${currentMediaUrl ?: ""} worker=${isFlixerWorkerUrl(currentMediaUrl)} message=${error.message}", error)
                channel?.invokeMethod("onNativePipError", error.message ?: "فشل تشغيل الفيديو")
            }
        })
    }

    // ─── UI setup ─────────────────────────────────────────────────────────

    private fun ensurePlayerUi() {
        if (playerContainer != null) return

        val root = findViewById<ViewGroup>(android.R.id.content)
        if (root.childCount > 0) flutterContentView = root.getChildAt(0)

        val container = FrameLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT).apply {
                gravity = Gravity.CENTER
                setMargins(0, 0, 0, 0)
            }
            setBackgroundColor(Color.BLACK)
            visibility = View.GONE
            isClickable = true
            isFocusable = true
            fitsSystemWindows = false
            setPadding(0, 0, 0, 0)
            clipChildren = false
            clipToPadding = false
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT_WATCH) {
                setOnApplyWindowInsetsListener { _, _ -> WindowInsets.CONSUMED }
            }
        }

        val pv = buildNativePlayerView()
        playerView = pv
        container.addView(pv)
        pv.post { hideEpisodeNavigationControls(pv) }

        val loading = FrameLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT)
            setBackgroundColor(Color.TRANSPARENT)
            visibility = View.GONE
            isClickable = false
            isFocusable = false
        }
        val loadingInner = FrameLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(dp(78), dp(78), Gravity.CENTER)
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(0x55000000)
            }
        }
        val spinner = DropletCircleLoaderView(this).apply {
            layoutParams = FrameLayout.LayoutParams(dp(56), dp(56), Gravity.CENTER)
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
        qualityButton = makeControlButton("Quality") { showVideoTracksDialog() }
        subtitleButton = makeControlButton("الترجمة") { showTextTracksDialog() }
        pipButton = makeControlButton("PiP") { enterNativePip() }
        closeButton = makeControlButton("✕") { closeNativePlayer() }

        listOf(fitButton, qualityButton, subtitleButton, pipButton, closeButton)
            .forEach { btn -> if (btn != null) bar.addView(btn) }

        scroll.addView(bar)
        container.addView(scroll)
        root.addView(container, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT).apply {
            gravity = Gravity.CENTER
            setMargins(0, 0, 0, 0)
        })
        playerContainer = container
        applyPlayerFullscreenWindow()
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

    private fun hideEpisodeNavigationControls(target: View? = playerView) {
        val root = target ?: return
        val ids = intArrayOf(
            androidx.media3.ui.R.id.exo_prev,
            androidx.media3.ui.R.id.exo_next
        )
        for (id in ids) {
            try {
                root.findViewById<View?>(id)?.apply {
                    visibility = View.GONE
                    alpha = 0f
                    isEnabled = false
                    isClickable = false
                    isFocusable = false
                }
            } catch (_: Exception) {}
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

        if (subtitleTracks.isNotEmpty()) {
            externalSubtitleTracks = mergeSubtitleTracks(externalSubtitleTracks, subtitleTracks)
        }

        if (manualSubtitleSelection) {
            updateOverlayVisibility()
            return
        }

        val current = selectedSubtitleUrl?.let { wanted -> externalSubtitleTracks.firstOrNull { it.url == wanted } }
        val shouldResetAutoSelection = current == null
        if (shouldResetAutoSelection) {
            selectedSubtitleUrl = null
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
        hideEpisodeNavigationControls()
        controlsScroll?.visibility =
            if (nativePlayerActive && !isInPictureInPictureMode && controllerVisible)
                View.VISIBLE else View.GONE
    }

    private fun showPlayerLoadingOverlay(message: String = "") {
        loadingTextView?.text = ""
        loadingTextView?.visibility = View.GONE
        loadingOverlay?.bringToFront()
        loadingOverlay?.visibility = View.VISIBLE
        controlsScroll?.bringToFront()
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
            trackSelector = null
            resetPlaybackFrameRatePreference()
            return
        }
        try { player.playWhenReady = false } catch (_: Exception) {}
        try { player.pause() } catch (_: Exception) {}
        try { player.stop() } catch (_: Exception) {}
        try { player.clearMediaItems() } catch (_: Exception) {}
        try { playerView?.player = null } catch (_: Exception) {}
        try { player.release() } catch (_: Exception) {}
        exoPlayer = null
        trackSelector = null
        resetPlaybackFrameRatePreference()
    }

    // ─── PiP ──────────────────────────────────────────────────────────────

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
        wasPlayingBeforeManualPip = false
        waitingForPlayableSource = false
        requestedPipRatio = null
        pageQualityOptions = emptyList()
        pageServerOptions = emptyList()
        externalSubtitleTracks = emptyList()
        selectedSubtitleUrl = null
        currentMediaUrl = null
        currentMediaMime = null
        currentMediaHeaders = emptyMap()
        hidePlayerLoadingOverlay()

        
        try { restoreRootSiblingsAfterPip() } catch (_: Exception) {}
        try {
            flutterContentView?.apply {
                visibility = beforePipFlutterVisibility
                alpha = 1f
                isClickable = true
                isEnabled = true
            }
        } catch (_: Exception) {}

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
        restorePlayerFullscreenWindow()
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        notifyNativePlayerChanged(false)

        nativePlayerClosing = false
    }

    private fun applyPlayerFullscreenWindow() {
        try {
            window.statusBarColor = Color.TRANSPARENT
            window.navigationBarColor = Color.TRANSPARENT
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            window.addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                    WindowManager.LayoutParams.FLAG_LAYOUT_INSET_DECOR
            )

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                window.attributes = window.attributes.apply {
                    layoutInDisplayCutoutMode =
                        WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
                }
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                window.setDecorFitsSystemWindows(false)
            }

            val root = findViewById<ViewGroup>(android.R.id.content)
            root?.apply {
                setPadding(0, 0, 0, 0)
                clipChildren = false
                clipToPadding = false
                fitsSystemWindows = false
                setBackgroundColor(Color.BLACK)
            }

            playerContainer?.apply {
                fitsSystemWindows = false
                setPadding(0, 0, 0, 0)
                clipChildren = false
                clipToPadding = false
                setBackgroundColor(Color.BLACK)
                layoutParams = FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT).apply {
                    gravity = Gravity.CENTER
                    setMargins(0, 0, 0, 0)
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT_WATCH) {
                    setOnApplyWindowInsetsListener { _, _ -> WindowInsets.CONSUMED }
                }
                bringToFront()
                requestLayout()
            }

            playerView?.apply {
                fitsSystemWindows = false
                setPadding(0, 0, 0, 0)
                resizeMode = currentResizeMode
                layoutParams = FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT).apply {
                    gravity = Gravity.CENTER
                    setMargins(0, 0, 0, 0)
                }
                requestLayout()
            }
            enterImmersiveMode(true)
        } catch (_: Exception) {
        }
    }

    private fun restorePlayerFullscreenWindow() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                window.setDecorFitsSystemWindows(true)
            }

            @Suppress("DEPRECATION")
            window.clearFlags(
                WindowManager.LayoutParams.FLAG_FULLSCREEN or
                    WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                    WindowManager.LayoutParams.FLAG_LAYOUT_INSET_DECOR
            )

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                window.attributes = window.attributes.apply {
                    layoutInDisplayCutoutMode =
                        WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_DEFAULT
                }
            }

            playerContainer?.setOnApplyWindowInsetsListener(null as View.OnApplyWindowInsetsListener?)
            enterImmersiveMode(false)
        } catch (_: Exception) {
            enterImmersiveMode(false)
        }
    }

    private fun applyLandscapeMode() {
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
        enterImmersiveMode(true)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    private fun enterImmersiveMode(hideBars: Boolean) {
        val flags = View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
            View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
            View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
            View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
            View.SYSTEM_UI_FLAG_FULLSCREEN or
            View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY

        if (hideBars) {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = flags
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                window.setDecorFitsSystemWindows(false)
                window.insetsController?.let { controller ->
                    controller.hide(WindowInsets.Type.systemBars())
                    controller.systemBarsBehavior =
                        WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                }
            }
        } else {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                window.setDecorFitsSystemWindows(true)
                window.insetsController?.show(WindowInsets.Type.systemBars())
            }
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_LAYOUT_STABLE
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
            .distinctBy { "${it.url.lowercase()}|${it.label.lowercase()}" }
        if (tracks.isEmpty()) {
            simpleMessage("لا توجد ترجمات - انتظر لحظة وحاول مجددًا")
            return
        }

        val accent = 0xFFC62828.toInt()
        val panel = 0xFF2D2D30.toInt()
        val panelAlt = 0xFF333337.toInt()
        val border = 0xFF3A3A3D.toInt()
        val softText = 0xB3FFFFFF.toInt()
        val mutedText = 0x88FFFFFF.toInt()

        fun trackDisplayLanguage(track: ExternalSubtitle): String {
            val lang = track.language.trim().lowercase()
            val blob = listOf(track.label, track.source, track.release, track.url)
                .joinToString(" ")
                .lowercase()
            return when {
                lang.startsWith("ar") || blob.contains("arabic") || blob.contains("عرب") -> "Arabic"
                lang.startsWith("en") || blob.contains("english") -> "English"
                lang.startsWith("tr") || blob.contains("turkish") -> "Turkish"
                lang.startsWith("fr") || blob.contains("french") -> "French"
                lang.startsWith("es") || blob.contains("spanish") -> "Spanish"
                lang.startsWith("de") || blob.contains("german") -> "German"
                lang.isNotEmpty() -> normalizeLanguage(track.language)
                else -> "Other"
            }
        }

        fun trackPrimaryTitle(track: ExternalSubtitle): String {
            val release = track.release.trim()
            if (release.isNotEmpty()) return release
            val parts = track.label.split('•').map { it.trim() }.filter { it.isNotEmpty() }
            val filtered = parts.filterNot {
                it.equals(track.source, ignoreCase = true) ||
                    it.equals("Arabic", ignoreCase = true) ||
                    it.equals("English", ignoreCase = true)
            }
            return filtered.lastOrNull().orEmpty().ifEmpty { track.label.trim().ifEmpty { "Subtitle" } }
        }

        fun trackSecondaryTitle(track: ExternalSubtitle): String {
            val lang = trackDisplayLanguage(track)
            val hi = if (track.hearingImpaired) " • HI" else ""
            return "${track.source.ifBlank { "Subtitle" }} • $lang$hi"
        }

        fun isSubdlTrack(track: ExternalSubtitle): Boolean {
            val blob = listOf(track.source, track.label, track.release, track.url)
                .joinToString(" ")
                .lowercase()
            return blob.contains("subdl")
        }

        val normalTracks = tracks.filterNot { isSubdlTrack(it) }
        val langs = normalTracks
            .map { trackDisplayLanguage(it) }
            .distinct()
            .sortedWith(compareBy<String> {
                when (it) {
                    "Arabic" -> 0
                    "English" -> 1
                    else -> 2
                }
            }.thenBy { it.lowercase() })

        var selectedLang = tracks.firstOrNull { it.url == selectedSubtitleUrl }
            ?.let { if (isSubdlTrack(it)) "__SUBDL__" else trackDisplayLanguage(it) }
            ?: if (tracks.any { isSubdlTrack(it) }) "__SUBDL__" else (langs.firstOrNull() ?: "Arabic")

        fun languageTabTitle(lang: String): String {
            return when (lang) {
                "__SUBDL__" -> "عربي 1"
                "Arabic" -> "عربي 2"
                else -> lang
            }
        }

        val dialog = Dialog(this, android.R.style.Theme_Black_NoTitleBar_Fullscreen)
        val root = FrameLayout(this).apply {
            setBackgroundColor(0xB8000000.toInt())
            layoutParams = ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT)
            setOnClickListener { dialog.dismiss() }
        }

        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(14), dp(8), dp(14), dp(12))
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadii = floatArrayOf(dpF(28f), dpF(28f), dpF(28f), dpF(28f), 0f, 0f, 0f, 0f)
                setColor(panel)
                setStroke(dp(1), border)
            }
            layoutParams = FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT).apply {
                gravity = Gravity.BOTTOM
                leftMargin = dp(12)
                rightMargin = dp(12)
                topMargin = dp(8)
            }
            isClickable = true
        }

        val body = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(MATCH_PARENT, 0, 1f)
        }

        fun makeDivider(): View = View(this).apply {
            layoutParams = LinearLayout.LayoutParams(dp(1), MATCH_PARENT).apply {
                leftMargin = dp(10)
                rightMargin = dp(10)
            }
            setBackgroundColor(0x16FFFFFF)
        }

        val languageColumn = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
        }
        val languageScroll = ScrollView(this).apply {
            isFillViewport = true
            overScrollMode = View.OVER_SCROLL_NEVER
            layoutParams = LinearLayout.LayoutParams(0, MATCH_PARENT, 0.24f)
            addView(languageColumn)
        }

        val optionsColumn = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
        }
        val optionsScroll = ScrollView(this).apply {
            isFillViewport = true
            overScrollMode = View.OVER_SCROLL_NEVER
            layoutParams = LinearLayout.LayoutParams(0, MATCH_PARENT, 0.48f)
            addView(optionsColumn)
        }

        val settingsColumn = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
        }
        val settingsScroll = ScrollView(this).apply {
            isFillViewport = true
            overScrollMode = View.OVER_SCROLL_NEVER
            layoutParams = LinearLayout.LayoutParams(0, MATCH_PARENT, 0.28f)
            addView(settingsColumn)
        }

        fun createPill(active: Boolean): GradientDrawable = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dpF(16f)
            setColor(if (active) accent else panel)
            setStroke(dp(1), if (active) accent else border)
        }

        fun createCardBackground(active: Boolean): GradientDrawable = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dpF(18f)
            setColor(if (active) 0xFF383A40.toInt() else panelAlt)
            setStroke(dp(1), if (active) accent else border)
        }

        fun sectionTitle(text: String): TextView = TextView(this).apply {
            this.text = text
            setTextColor(Color.WHITE)
            textSize = 14f
            setTypeface(typeface, Typeface.BOLD)
            setPadding(0, 0, 0, dp(12))
        }

        val settingRefreshers = mutableListOf<() -> Unit>()

        fun addSettingsStepper(
            title: String,
            valueProvider: () -> String,
            onMinus: () -> Unit,
            onPlus: () -> Unit,
            repeatOnHold: Boolean = false,
        ) {
            val row = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                layoutParams = LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                    bottomMargin = dp(12)
                }
                setPadding(dp(12), dp(12), dp(12), dp(12))
                background = createCardBackground(false)
            }

            fun runStepperAction(action: () -> Unit) {
                action()
                applySubtitleAppearance()
                saveSubtitlePrefs()
                settingRefreshers.forEach { it.invoke() }
            }

            fun control(symbol: String, action: () -> Unit): TextView = TextView(this).apply {
                text = symbol
                gravity = Gravity.CENTER
                textSize = 18f
                setTextColor(Color.WHITE)
                setTypeface(typeface, Typeface.BOLD)
                layoutParams = LinearLayout.LayoutParams(dp(38), dp(38))
                background = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(0x26FFFFFF)
                }

                if (repeatOnHold) {
                    var isRepeating = false
                    var repeatRunnable: Runnable? = null

                    fun stopRepeat() {
                        isRepeating = false
                        repeatRunnable?.let { removeCallbacks(it) }
                        repeatRunnable = null
                        isPressed = false
                    }

                    setOnTouchListener { _, event ->
                        when (event.actionMasked) {
                            MotionEvent.ACTION_DOWN -> {
                                parent?.requestDisallowInterceptTouchEvent(true)
                                isPressed = true
                                isRepeating = true
                                runStepperAction(action)
                                val runnable = object : Runnable {
                                    override fun run() {
                                        if (!isRepeating) return
                                        runStepperAction(action)
                                        postDelayed(this, 85L)
                                    }
                                }
                                repeatRunnable = runnable
                                postDelayed(runnable, 330L)
                                true
                            }
                            MotionEvent.ACTION_UP,
                            MotionEvent.ACTION_CANCEL,
                            MotionEvent.ACTION_OUTSIDE -> {
                                parent?.requestDisallowInterceptTouchEvent(false)
                                stopRepeat()
                                true
                            }
                            else -> true
                        }
                    }
                } else {
                    setOnClickListener { runStepperAction(action) }
                }
            }

            val center = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER
                layoutParams = LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f)
            }
            val valueView = TextView(this).apply {
                setTextColor(Color.WHITE)
                textSize = 14.5f
                setTypeface(typeface, Typeface.BOLD)
                gravity = Gravity.CENTER
            }
            center.addView(TextView(this).apply {
                text = title
                setTextColor(softText)
                textSize = 12.5f
                gravity = Gravity.CENTER
                setPadding(0, 0, 0, dp(4))
            })
            center.addView(valueView)
            row.addView(control("−") { onMinus() })
            row.addView(center)
            row.addView(control("+") { onPlus() })
            val refresh = { valueView.text = valueProvider() }
            settingRefreshers.add(refresh)
            refresh()
            settingsColumn.addView(row)
        }

        settingsColumn.addView(sectionTitle("إعدادات الترجمة"))
        addSettingsStepper(
            "التأخير",
            valueProvider = { String.format(java.util.Locale.US, "%.1fs", subtitleDelayMs / 1000f) },
            onMinus = { adjustSubtitleDelayBy(-100) },
            onPlus = { adjustSubtitleDelayBy(100) },
            repeatOnHold = true,
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
            setTextColor(softText)
            textSize = 12.5f
            setTypeface(typeface, Typeface.BOLD)
            setPadding(0, dp(4), 0, dp(10))
        })

        val chipRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                bottomMargin = dp(10)
            }
        }
        lateinit var coverOffChip: TextView
        lateinit var coverOnChip: TextView
        fun refreshCoverChips() {
            coverOffChip.background = createPill(!subtitleBackgroundEnabled)
            coverOnChip.background = createPill(subtitleBackgroundEnabled)
            coverOffChip.setTextColor(if (!subtitleBackgroundEnabled) Color.WHITE else softText)
            coverOnChip.setTextColor(if (subtitleBackgroundEnabled) Color.WHITE else softText)
        }
        fun makeChip(label: String, onClick: () -> Unit): TextView = TextView(this).apply {
            text = label
            textSize = 12.5f
            gravity = Gravity.CENTER
            setPadding(dp(12), dp(9), dp(12), dp(9))
            layoutParams = LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f)
            setOnClickListener {
                onClick()
                applySubtitleAppearance()
                saveSubtitlePrefs()
                refreshCoverChips()
            }
        }
        coverOffChip = makeChip("بدون غلاف") { subtitleBackgroundEnabled = false }
        coverOnChip = makeChip("غلاف") { subtitleBackgroundEnabled = true }
        chipRow.addView(coverOffChip)
        chipRow.addView(View(this).apply { layoutParams = LinearLayout.LayoutParams(dp(8), 1) })
        chipRow.addView(coverOnChip)
        settingsColumn.addView(chipRow)
        refreshCoverChips()

        settingsColumn.addView(TextView(this).apply {
            text = "الأزرار تعمل مباشرة الآن — وكل تغيير يُطبّق فورًا"
            setTextColor(mutedText)
            textSize = 11.5f
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(4), dp(2), dp(4), 0)
        })

        fun renderOptions() {
            optionsColumn.removeAllViews()
            optionsColumn.addView(sectionTitle("الترجمات"))
            if (selectedLang == "__OFF__") {
                optionsColumn.addView(TextView(this).apply {
                    text = "الترجمة متوقفة"
                    setTextColor(mutedText)
                    textSize = 14f
                    setPadding(dp(12), dp(10), dp(12), dp(10))
                })
                return
            }

            val current = when (selectedLang) {
                "__SUBDL__" -> tracks.filter { isSubdlTrack(it) }
                else -> {
                    val matching = normalTracks.filter { trackDisplayLanguage(it) == selectedLang }
                    if (matching.isNotEmpty()) matching else normalTracks
                }
            }

            if (current.isEmpty()) {
                optionsColumn.addView(TextView(this).apply {
                    text = "لا توجد ترجمات متاحة حاليًا"
                    setTextColor(mutedText)
                    textSize = 14f
                    setPadding(dp(12), dp(10), dp(12), dp(10))
                })
                return
            }

            val subdlTracks = current.filter { isSubdlTrack(it) }
            val otherTracks = current.filterNot { isSubdlTrack(it) }

            fun addSourceSection(title: String, items: List<ExternalSubtitle>) {
                if (items.isEmpty()) return

                optionsColumn.addView(TextView(this).apply {
                    text = title
                    setTextColor(softText)
                    textSize = 12.5f
                    setTypeface(typeface, Typeface.BOLD)
                    setPadding(dp(2), dp(4), dp(2), dp(10))
                })

                items.forEachIndexed { index, item ->
                    val isSelected = item.url == selectedSubtitleUrl
                    val row = LinearLayout(this).apply {
                        orientation = LinearLayout.HORIZONTAL
                        gravity = Gravity.CENTER_VERTICAL
                        layoutParams = LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                            bottomMargin = if (index == items.lastIndex) dp(12) else dp(10)
                        }
                        setPadding(dp(12), dp(12), dp(12), dp(12))
                        background = createCardBackground(isSelected)
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
                    left.addView(TextView(this).apply {
                        text = trackPrimaryTitle(item)
                        setTextColor(Color.WHITE)
                        textSize = 13.5f
                        setTypeface(typeface, if (isSelected) Typeface.BOLD else Typeface.NORMAL)
                        maxLines = 3
                    })
                    left.addView(TextView(this).apply {
                        text = trackSecondaryTitle(item)
                        setTextColor(softText)
                        textSize = 11.8f
                        setPadding(0, dp(4), 0, 0)
                        maxLines = 2
                    })
                    row.addView(left)

                    val fmt = when ((item.mimeType ?: "").lowercase()) {
                        "text/vtt" -> "VTT"
                        "text/x-ssa" -> "ASS"
                        "application/x-subrip" -> "SRT"
                        else -> item.url.substringAfterLast('.', "SUB").uppercase().take(4)
                    }
                    val side = LinearLayout(this).apply {
                        orientation = LinearLayout.VERTICAL
                        gravity = Gravity.CENTER_HORIZONTAL
                    }
                    side.addView(TextView(this).apply {
                        text = fmt
                        setTextColor(if (isSelected) Color.WHITE else softText)
                        textSize = 10.5f
                        setPadding(dp(10), dp(6), dp(10), dp(6))
                        background = createPill(isSelected)
                    })
                    side.addView(TextView(this).apply {
                        text = if (isSelected) "✓" else trackDisplayLanguage(item)
                        setTextColor(if (isSelected) accent else mutedText)
                        textSize = if (isSelected) 18f else 10.5f
                        setTypeface(typeface, Typeface.BOLD)
                        gravity = Gravity.CENTER
                        setPadding(0, dp(6), 0, 0)
                    })
                    row.addView(side)
                    optionsColumn.addView(row)
                }
            }

            addSourceSection("ترجمات عربي 1", subdlTracks)
            addSourceSection("ترجمات أخرى", otherTracks)
        }

        fun renderLanguages() {
            languageColumn.removeAllViews()
            languageColumn.addView(sectionTitle("اللغات"))
            fun addLangRow(text: String, active: Boolean, onClick: () -> Unit) {
                val row = LinearLayout(this).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.CENTER_VERTICAL
                    layoutParams = LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                        bottomMargin = dp(10)
                    }
                    setPadding(dp(12), dp(12), dp(12), dp(12))
                    background = createCardBackground(active)
                    setOnClickListener { onClick() }
                }
                row.addView(TextView(this).apply {
                    this.text = text
                    setTextColor(if (active) Color.WHITE else 0xFFEDE7F2.toInt())
                    textSize = 14f
                    setTypeface(typeface, if (active) Typeface.BOLD else Typeface.NORMAL)
                    layoutParams = LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f)
                })
                row.addView(TextView(this).apply {
                    this.text = if (active) "✓" else ""
                    setTextColor(accent)
                    textSize = 18f
                    setTypeface(typeface, Typeface.BOLD)
                })
                languageColumn.addView(row)
            }
            addLangRow("إيقاف", selectedLang == "__OFF__") {
                selectedLang = "__OFF__"
                manualSubtitleSelection = true
                applySubtitleSelection(null)
                renderLanguages()
                renderOptions()
            }
            if (tracks.any { isSubdlTrack(it) }) {
                addLangRow(languageTabTitle("__SUBDL__"), selectedLang == "__SUBDL__") {
                    selectedLang = "__SUBDL__"
                    renderLanguages()
                    renderOptions()
                }
            }
            langs.forEach { lang ->
                addLangRow(languageTabTitle(lang), selectedLang == lang) {
                    selectedLang = lang
                    renderLanguages()
                    renderOptions()
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

        if (rawSelectedTrack == null) {
            subtitleDelayMs = 0
            resetActiveSubtitleProfile()
        } else {
            subtitleDelayMs = resolveAutoDelayForTrack(rawSelectedTrack)
            activeSubtitleRateMultiplier = computeSubtitleRateMultiplier(rawSelectedTrack)
        }

        val selectedTrack = withAppliedDelay(rawSelectedTrack)
        selectedSubtitleResolvedUrl = selectedTrack?.url

        Log.d(
            LOG_TAG,
            "applySubtitleSelection subtitleUrl=$subtitleUrl selected=${selectedTrack?.label} mime=${selectedTrack?.mimeType} lang=${selectedTrack?.language} delayMs=$subtitleDelayMs fpsScale=$activeSubtitleRateMultiplier profile=$activeSubtitleProfileKey raw=${rawSelectedTrack?.url} resolved=${selectedTrack?.url}"
        )

        player.trackSelectionParameters = player.trackSelectionParameters
            .buildUpon()
            .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, selectedTrack == null)
            .setPreferredTextLanguage(rawSelectedTrack?.language?.takeIf { it.isNotBlank() })
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
            .ifBlank { "generic" }
    }

    private fun detectFpsValue(text: String?): Double? {
        if (text.isNullOrBlank()) return null
        val s = text.lowercase()
        fun parse(raw: String): Double? = raw.replace(',', '.').toDoubleOrNull()

        Regex("""(?<!\d)(23[.,]?976|29[.,]?97|59[.,]?94)(?!\d)""")
            .find(s)?.groupValues?.getOrNull(1)?.let { return parse(it) }

        Regex("""(?<!\d)(24|25|30|50|60)(?!\d)\s*(?:fps|hz)""")
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
            layoutParams = ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT)
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

        fun addStepperRow(
            title: String,
            valueText: () -> String,
            onMinus: () -> Unit,
            onPlus: () -> Unit,
            repeatOnHold: Boolean = false,
        ) {
            val row = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                layoutParams = LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                    bottomMargin = dp(12)
                }
            }

            fun makeCircleButton(symbol: String, action: () -> Unit, refresh: () -> Unit): TextView = TextView(this).apply {
                text = symbol
                gravity = Gravity.CENTER
                textSize = 18f
                setTextColor(Color.WHITE)
                layoutParams = LinearLayout.LayoutParams(dp(40), dp(40))
                background = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(0xFF2B2734.toInt())
                }

                fun runAction() {
                    action()
                    refresh()
                }

                if (repeatOnHold) {
                    var isRepeating = false
                    var repeatRunnable: Runnable? = null

                    fun stopRepeat() {
                        isRepeating = false
                        repeatRunnable?.let { removeCallbacks(it) }
                        repeatRunnable = null
                        isPressed = false
                    }

                    setOnTouchListener { _, event ->
                        when (event.actionMasked) {
                            MotionEvent.ACTION_DOWN -> {
                                parent?.requestDisallowInterceptTouchEvent(true)
                                isPressed = true
                                isRepeating = true
                                runAction()
                                val runnable = object : Runnable {
                                    override fun run() {
                                        if (!isRepeating) return
                                        runAction()
                                        postDelayed(this, 85L)
                                    }
                                }
                                repeatRunnable = runnable
                                postDelayed(runnable, 330L)
                                true
                            }
                            MotionEvent.ACTION_UP,
                            MotionEvent.ACTION_CANCEL,
                            MotionEvent.ACTION_OUTSIDE -> {
                                parent?.requestDisallowInterceptTouchEvent(false)
                                stopRepeat()
                                true
                            }
                            else -> true
                        }
                    }
                } else {
                    setOnClickListener { runAction() }
                }
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

            row.addView(makeCircleButton("−", onMinus, ::refresh))
            row.addView(center)
            row.addView(makeCircleButton("+", onPlus, ::refresh))
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
            repeatOnHold = true,
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
        val rateMultiplier = if (activeSubtitleRawTrack?.url == track.url && activeSubtitleRateMultiplier > 0.0) {
            activeSubtitleRateMultiplier
        } else {
            computeSubtitleRateMultiplier(track)
        }
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
            track.copy(url = outFile.toURI().toString(), mimeType = mime)
        } catch (e: Exception) {
            Log.e(LOG_TAG, "withAppliedDelay failed for ${track.url}", e)
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
