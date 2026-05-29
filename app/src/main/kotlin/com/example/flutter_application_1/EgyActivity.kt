package com.example.flutter_application_1

import android.content.Intent
import android.app.AlertDialog
import android.app.PictureInPictureParams
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.content.res.ColorStateList
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.Rect
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.util.Rational
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import android.widget.Button
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import android.widget.ProgressBar
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
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
import androidx.media3.ui.PlayerView
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import kotlin.math.max

class EgyActivity : FlutterActivity() {

    override fun getDartEntrypointFunctionName(): String = "egyMain"


    companion object {
        private const val CHANNEL = "app.egy/pip"
        private const val MIN_PIP_RATIO = 0.41841
        private const val MAX_PIP_RATIO = 2.39
        private const val LOG_TAG = "NativePlayer"
        private var instance: EgyActivity? = null

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

    private data class TrackChoice(
        val label: String,
        val group: Tracks.Group,
        val trackIndex: Int,
        val selected: Boolean,
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

    private var channel: MethodChannel? = null
    private var exoPlayer: ExoPlayer? = null
    private var trackSelector: DefaultTrackSelector? = null
    private var playerView: PlayerView? = null
    private var playerContainer: FrameLayout? = null
    private var loadingOverlay: FrameLayout? = null
    private var controlsScroll: HorizontalScrollView? = null
    private var controlsBar: LinearLayout? = null
    private var flutterContentView: View? = null

    private var fitButton: Button? = null
    private var qualityButton: Button? = null
    private var serverButton: Button? = null
    private var pipButton: Button? = null
    private var closeButton: Button? = null

    private var controllerVisible = true
    private var waitFirstRenderedFrame = false
    private var waitingForPlayableSource = false
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

    private var currentMediaUrl: String? = null
    private var currentMediaMime: String? = null
    private var currentMediaHeaders: Map<String, String> = emptyMap()
    private var appliedPlaybackFrameRate: Float? = null
    private var autoHighestVideoApplied = false
    private var highestVideoAutoApplyTicket = 0

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
                SecurityGuard.protect(this)
instance = this
        window.decorView.setBackgroundColor(Color.BLACK)
        enableHighRefreshRate()
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        enableHighRefreshRate()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) enableHighRefreshRate()
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
                    val rawQualities = call.argument<List<Map<String, Any?>>>("qualityOptions")
                    val currentQualityLabel = call.argument<String>("currentQualityLabel")
                    @Suppress("UNCHECKED_CAST")
                    val rawServers = call.argument<List<Map<String, Any?>>>("serverOptions")
                    val currentServerLabel = call.argument<String>("currentServerLabel")

                    result.success(
                        openNativePlayer(
                            url = url,
                            startTime = startTime,
                            mimeType = mimeType,
                            headers = headers,
                            aspectW = aspectW,
                            aspectH = aspectH,
                            qualityOptions = parseQualityOptions(rawQualities, currentQualityLabel),
                            serverOptions = parseServerOptions(rawServers, currentServerLabel),
                        )
                    )
                }

                "openNativePlayerShell" -> {
                    val aspectW = call.argument<Int>("aspectRatioNumerator") ?: 16
                    val aspectH = call.argument<Int>("aspectRatioDenominator") ?: 9
                    @Suppress("UNCHECKED_CAST")
                    val rawQualities = call.argument<List<Map<String, Any?>>>("qualityOptions")
                    val currentQualityLabel = call.argument<String>("currentQualityLabel")
                    @Suppress("UNCHECKED_CAST")
                    val rawServers = call.argument<List<Map<String, Any?>>>("serverOptions")
                    val currentServerLabel = call.argument<String>("currentServerLabel")

                    result.success(
                        openNativePlayerShell(
                            aspectW = aspectW,
                            aspectH = aspectH,
                            qualityOptions = parseQualityOptions(rawQualities, currentQualityLabel),
                            serverOptions = parseServerOptions(rawServers, currentServerLabel),
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
                    val rawQualities = call.argument<List<Map<String, Any?>>>("qualityOptions")
                    val currentQualityLabel = call.argument<String>("currentQualityLabel")
                    @Suppress("UNCHECKED_CAST")
                    val rawServers = call.argument<List<Map<String, Any?>>>("serverOptions")
                    val currentServerLabel = call.argument<String>("currentServerLabel")

                    result.success(
                        updateNativePlayerSource(
                            url = url,
                            startTime = startTime,
                            mimeType = mimeType,
                            headers = headers,
                            aspectW = aspectW,
                            aspectH = aspectH,
                            qualityOptions = parseQualityOptions(rawQualities, currentQualityLabel),
                            serverOptions = parseServerOptions(rawServers, currentServerLabel),
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
                    applyUpdatedOptions(
                        qualityOptions = rawQualities ?: emptyList(),
                        currentQualityLabel = currentQualityLabel,
                        serverOptions = rawServers ?: emptyList(),
                        currentServerLabel = currentServerLabel,
                    )
                    result.success(true)
                }

                "updateServerOptions" -> {
                    @Suppress("UNCHECKED_CAST")
                    val rawServers = call.argument<List<Map<String, Any?>>>("serverOptions")
                    val currentServerLabel = call.argument<String>("currentServerLabel") ?: ""
                    pageServerOptions = parseServerOptions(rawServers, currentServerLabel)
                    updateOverlayVisibility()
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

    private fun parseQualityOptions(raw: List<Map<String, Any?>>?, currentLabel: String?): List<PageQualityOption> {
        if (raw.isNullOrEmpty()) return emptyList()
        val current = cleanQualityLabel(currentLabel).lowercase()
        val parsed = raw.mapNotNull { map ->
            val rawLabel = map["label"]?.toString()?.trim().orEmpty()
            val label = cleanQualityLabel(rawLabel)
            val key = map["key"]?.toString()?.trim().orEmpty()
            if (label.isBlank()) return@mapNotNull null
            PageQualityOption(
                label = label,
                key = if (key.isNotBlank()) key else label,
                url = map["url"]?.toString()?.trim().takeUnless { it.isNullOrEmpty() },
                selected = label.lowercase() == current || map["selected"] == true,
            )
        }
        return chooseHighestSelected(parsed, currentLabel)
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
            if (cleanKey.isNotEmpty() && cleanValue.isNotEmpty()) out[cleanKey] = cleanValue
        }
        extractEmbeddedMediaHeaders(url).forEach { (key, value) ->
            if (key.isNotBlank() && value.isNotBlank()) out[key] = value
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

    private fun isPipSupported(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    private fun cleanQualityLabel(raw: String?): String {
        val value = raw?.trim().orEmpty()
        if (value.isBlank()) return ""
        val match = Regex("""(?:^|[^0-9])([1-9][0-9]{2,3})\s*p\b""", RegexOption.IGNORE_CASE).find(value)
        return if (match != null) "${match.groupValues[1]}p" else value
    }

    private fun qualityRank(label: String?): Int {
        return Regex("""[0-9]+""").find(cleanQualityLabel(label))?.value?.toIntOrNull() ?: 0
    }

    private fun sortedQualityOptions(options: List<PageQualityOption>): List<PageQualityOption> {
        return options
            .mapNotNull { item ->
                val clean = cleanQualityLabel(item.label)
                if (clean.isBlank()) null else item.copy(label = clean)
            }
            .groupBy { it.label.lowercase() }
            .map { (_, items) ->
                items.firstOrNull { it.selected } ?: items.first()
            }
            .sortedWith(
                compareByDescending<PageQualityOption> { qualityRank(it.label) }
                    .thenBy { it.label }
            )
    }

    private fun chooseHighestSelected(options: List<PageQualityOption>, currentLabel: String?): List<PageQualityOption> {
        val sorted = sortedQualityOptions(options)
        if (sorted.isEmpty()) return emptyList()
        val currentClean = cleanQualityLabel(currentLabel)
        val highest = sorted.first()
        return sorted.map { item ->
            item.copy(selected = item.label.equals(highest.label, ignoreCase = true) ||
                (currentClean.isNotBlank() && item.label.equals(currentClean, ignoreCase = true) && highest.label.equals(currentClean, ignoreCase = true)))
        }
    }

    @OptIn(UnstableApi::class)
    private fun openNativePlayer(
        url: String?,
        startTime: Double,
        mimeType: String?,
        headers: Map<String, String>,
        aspectW: Int,
        aspectH: Int,
        qualityOptions: List<PageQualityOption>,
        serverOptions: List<PageServerOption>,
    ): Boolean {
        if (url.isNullOrBlank() || url.startsWith("blob:")) return false

        lastAspectW = max(1, aspectW)
        lastAspectH = max(1, aspectH)
        requestedPipRatio = sanitizeRatio(lastAspectW, lastAspectH)
        pageQualityOptions = chooseHighestSelected(qualityOptions, qualityOptions.firstOrNull { it.selected }?.label)
        pageServerOptions = serverOptions
        currentMediaUrl = url
        currentMediaMime = mimeType
        currentMediaHeaders = prepareMediaHeaders(url, headers)

        waitingForPlayableSource = false
        waitFirstRenderedFrame = true
        ensurePlayerUi()
        releasePlayerOnly()
        autoHighestVideoApplied = false
        playerContainer?.setBackgroundColor(Color.BLACK)
        playerContainer?.visibility = View.VISIBLE
        playerView?.alpha = 0f
        playerView?.visibility = View.INVISIBLE
        hidePlayerLoadingOverlay()
        applyLandscapeMode()

        buildAndLoadMedia(url, mimeType, currentMediaHeaders, (startTime * 1000.0).toLong())

        nativePlayerActive = true
        notifyNativePlayerChanged(true)
        updateOverlayVisibility()
        return true
    }

    private fun openNativePlayerShell(
        aspectW: Int,
        aspectH: Int,
        qualityOptions: List<PageQualityOption>,
        serverOptions: List<PageServerOption>,
    ): Boolean {
        lastAspectW = max(1, aspectW)
        lastAspectH = max(1, aspectH)
        requestedPipRatio = sanitizeRatio(lastAspectW, lastAspectH)
        pageQualityOptions = chooseHighestSelected(qualityOptions, qualityOptions.firstOrNull { it.selected }?.label)
        pageServerOptions = serverOptions
        ensurePlayerUi()
        releasePlayerOnly()
        autoHighestVideoApplied = false
        waitingForPlayableSource = true
        waitFirstRenderedFrame = false
        playerContainer?.setBackgroundColor(Color.BLACK)
        playerContainer?.visibility = View.VISIBLE
        playerView?.alpha = 0f
        playerView?.visibility = View.INVISIBLE
        controllerVisible = false
        showPlayerLoadingOverlay()
        applyLandscapeMode()
        if (!nativePlayerActive) {
            nativePlayerActive = true
            notifyNativePlayerChanged(true)
        }
        updateOverlayVisibility()
        return true
    }

    @OptIn(UnstableApi::class)
    private fun updateNativePlayerSource(
        url: String?,
        startTime: Double,
        mimeType: String?,
        headers: Map<String, String>,
        aspectW: Int,
        aspectH: Int,
        qualityOptions: List<PageQualityOption>,
        serverOptions: List<PageServerOption>,
    ): Boolean {
        if (url.isNullOrBlank() || url.startsWith("blob:")) return false

        lastAspectW = max(1, aspectW)
        lastAspectH = max(1, aspectH)
        requestedPipRatio = sanitizeRatio(lastAspectW, lastAspectH)
        pageQualityOptions = chooseHighestSelected(qualityOptions, qualityOptions.firstOrNull { it.selected }?.label)
        pageServerOptions = serverOptions
        currentMediaUrl = url
        currentMediaMime = mimeType
        currentMediaHeaders = prepareMediaHeaders(url, headers)

        waitingForPlayableSource = false
        waitFirstRenderedFrame = true
        ensurePlayerUi()
        playerContainer?.visibility = View.VISIBLE
        playerContainer?.setBackgroundColor(Color.BLACK)
        playerView?.alpha = 0f
        playerView?.visibility = View.INVISIBLE
        hidePlayerLoadingOverlay()

        releasePlayerOnly()
        autoHighestVideoApplied = false
        buildAndLoadMedia(url, mimeType, currentMediaHeaders, (startTime * 1000.0).toLong())
        if (!nativePlayerActive) {
            nativePlayerActive = true
            notifyNativePlayerChanged(true)
        }
        updateOverlayVisibility()
        return true
    }

    @OptIn(UnstableApi::class)
    private fun buildAndLoadMedia(
        url: String,
        mimeType: String?,
        headers: Map<String, String>,
        startTimeMs: Long = 0L,
        playWhenReady: Boolean = true,
    ) {
        val effectiveHeaders = prepareMediaHeaders(url, headers)
        autoHighestVideoApplied = false
        highestVideoAutoApplyTicket++
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
                    .setForceHighestSupportedBitrate(true)
                    .setMaxVideoSize(Int.MAX_VALUE, Int.MAX_VALUE)
                    .setMaxVideoBitrate(Int.MAX_VALUE)
                    .build()
            }
            trackSelector = selector

            val loadControl = DefaultLoadControl.Builder()
                .setBufferDurationsMs(30000, 90000, 1500, 5000)
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
            p.setVideoScalingMode(C.VIDEO_SCALING_MODE_SCALE_TO_FIT)
            p.setVideoChangeFrameRateStrategy(C.VIDEO_CHANGE_FRAME_RATE_STRATEGY_ONLY_IF_SEAMLESS)
            attachPlayerListeners(p)
            p
        }

        player.trackSelectionParameters = player.trackSelectionParameters
            .buildUpon()
            .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
            .clearOverridesOfType(C.TRACK_TYPE_TEXT)
            .build()

        player.trackSelectionParameters = player.trackSelectionParameters
            .buildUpon()
            .setForceHighestSupportedBitrate(true)
            .setMaxVideoSize(Int.MAX_VALUE, Int.MAX_VALUE)
            .setMaxVideoBitrate(Int.MAX_VALUE)
            .build()

        player.playWhenReady = playWhenReady
        player.setMediaItem(buildMediaItem(url, mimeType), startTimeMs)
        player.prepare()
        scheduleApplyHighestVideoTrack()
        if (playWhenReady) player.play()

        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
            if (waitFirstRenderedFrame && nativePlayerActive) {
                waitFirstRenderedFrame = false
                waitingForPlayableSource = false
                hidePlayerLoadingOverlay()
                playerView?.alpha = 1f
                playerView?.visibility = View.VISIBLE
                playerContainer?.visibility = View.VISIBLE
                Log.d(LOG_TAG, "buildAndLoadMedia: fallback timeout - forcing player visible")
            }
        }, 4000L)
    }

    private fun buildMediaItem(url: String, mimeType: String?): MediaItem {
        val lowerUrl = url.lowercase()
        val lowerMime = (mimeType ?: "").lowercase()
        val builder = MediaItem.Builder().setUri(Uri.parse(url))

        when {
            lowerMime.contains("mpegurl") || lowerUrl.contains(".m3u8") -> builder.setMimeType(MimeTypes.APPLICATION_M3U8)
            lowerMime.contains("dash+xml") || lowerUrl.contains(".mpd") -> builder.setMimeType(MimeTypes.APPLICATION_MPD)
            lowerMime == "video/mp4" || lowerUrl.contains(".mp4") -> builder.setMimeType(MimeTypes.VIDEO_MP4)
            lowerMime == "video/webm" || lowerUrl.contains(".webm") -> builder.setMimeType(MimeTypes.VIDEO_WEBM)
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
                scheduleApplyHighestVideoTrack()
                updatePipParams()
                applyPlaybackFrameRatePreference(detectSelectedVideoFrameRate(player))
            }

            override fun onPlaybackStateChanged(playbackState: Int) {
                when (playbackState) {
                    Player.STATE_READY -> {
                        scheduleApplyHighestVideoTrack()
                        updatePipParams()
                        applyPlaybackFrameRatePreference(detectSelectedVideoFrameRate(player))
                        waitingForPlayableSource = false
                        hidePlayerLoadingOverlay()
                        if (!waitFirstRenderedFrame) showNativeSurface()
                    }
                    Player.STATE_BUFFERING, Player.STATE_IDLE -> {
                        if (waitingForPlayableSource) showPlayerLoadingOverlay() else hidePlayerLoadingOverlay()
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

            override fun onPlayerError(error: PlaybackException) {
                waitingForPlayableSource = false
                hidePlayerLoadingOverlay()
                resetPlaybackFrameRatePreference()
                Log.e(LOG_TAG, "onPlayerError url=${currentMediaUrl ?: ""} message=${error.message}", error)
                channel?.invokeMethod("onNativePipError", error.message ?: "فشل تشغيل الفيديو")
            }
        })
    }

    private fun ensurePlayerUi() {
        if (playerContainer != null) return

        val root = findViewById<ViewGroup>(android.R.id.content)
        if (root.childCount > 0) flutterContentView = root.getChildAt(0)

        val container = FrameLayout(this).apply {
            layoutParams = ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT)
            setBackgroundColor(Color.BLACK)
            visibility = View.GONE
            isClickable = true
            isFocusable = true
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

        val spinnerBox = FrameLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(dp(78), dp(78), Gravity.CENTER)
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(0x55000000)
            }
        }

        val spinner = ProgressBar(this).apply {
            isIndeterminate = true
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                indeterminateTintList = ColorStateList.valueOf(Color.WHITE)
            }
            layoutParams = FrameLayout.LayoutParams(dp(48), dp(48), Gravity.CENTER)
        }

        spinnerBox.addView(spinner)
        loading.addView(spinnerBox)
        container.addView(loading)
        loadingOverlay = loading

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
        serverButton = null
        pipButton = makeControlButton("PiP") { enterNativePip() }
        closeButton = makeControlButton("✕") { closeNativePlayer() }

        listOf(fitButton, qualityButton, pipButton, closeButton)
            .forEach { btn -> if (btn != null) bar.addView(btn) }

        scroll.addView(bar)
        container.addView(scroll)
        root.addView(container)
        playerContainer = container
        updateOverlayVisibility()
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
            setKeepContentOnPlayerReset(true)
            setControllerVisibilityListener(
                PlayerView.ControllerVisibilityListener { visibility ->
                    controllerVisible = visibility == View.VISIBLE
                    hideEpisodeNavigationControls(this)
                    updateOverlayVisibility()
                }
            )
            post { hideEpisodeNavigationControls(this) }
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
        if (oldView != null) container.removeView(oldView)
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
    ) {
        pageQualityOptions = parseQualityOptions(qualityOptions, currentQualityLabel)
        pageServerOptions = parseServerOptions(serverOptions, currentServerLabel)
        updateOverlayVisibility()
    }

    private fun makeControlButton(text: String, onClick: () -> Unit): Button {
        return Button(this).apply {
            this.text = text
            isAllCaps = false
            minHeight = 0
            minimumHeight = 0
            minWidth = 0
            minimumWidth = 0
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
                marginStart = dp(2)
                marginEnd = dp(2)
            }
        }
    }

    private fun updateOverlayVisibility() {
        hideEpisodeNavigationControls()
        serverButton?.visibility = View.GONE
        controlsScroll?.visibility =
            if (nativePlayerActive && !isInPictureInPictureMode && controllerVisible) View.VISIBLE else View.GONE
        controlsScroll?.bringToFront()
    }

    private fun showPlayerLoadingOverlay() {
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
        autoHighestVideoApplied = false
        highestVideoAutoApplyTicket++
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
        waitingForPlayableSource = false
        requestedPipRatio = null
        pageQualityOptions = emptyList()
        pageServerOptions = emptyList()
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
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val controller = window.insetsController ?: return
            if (hideBars) {
                controller.hide(WindowInsets.Type.systemBars())
                controller.systemBarsBehavior = WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            } else {
                controller.show(WindowInsets.Type.systemBars())
            }
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = if (hideBars) {
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                    View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                    View.SYSTEM_UI_FLAG_FULLSCREEN or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
            } else {
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE
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

    private fun showVideoTracksDialog() {
        if (pageQualityOptions.isNotEmpty()) {
            val sortedOptions = sortedQualityOptions(pageQualityOptions)
            val labels = sortedOptions.map { it.label }.toTypedArray()
            val checked = sortedOptions.indexOfFirst { it.selected }.let { if (it >= 0) it else 0 }
            AlertDialog.Builder(this)
                .setTitle("الجودة")
                .setSingleChoiceItems(labels, checked) { dialog, which ->
                    val option = sortedOptions[which]
                    pageQualityOptions = sortedOptions.mapIndexed { i, item -> item.copy(selected = i == which) }
                    channel?.invokeMethod(
                        "onQualitySelected",
                        mapOf("label" to option.label, "key" to option.key, "url" to (option.url ?: ""))
                    )
                    dialog.dismiss()
                }
                .setNegativeButton("إغلاق", null)
                .show()
            return
        }

        val player = exoPlayer ?: return
        val tracks = collectTrackChoices(player.currentTracks, C.TRACK_TYPE_VIDEO)
        if (tracks.isEmpty()) {
            simpleMessage("لا توجد جودات متعددة")
            return
        }

        val labels = tracks.map { it.label }.toTypedArray()
        val checked = tracks.indexOfFirst { it.selected }.coerceAtLeast(0)
        AlertDialog.Builder(this)
            .setTitle("الجودة")
            .setSingleChoiceItems(labels, checked) { dialog, which ->
                applyTrackSelection(C.TRACK_TYPE_VIDEO, tracks[which])
                dialog.dismiss()
            }
            .setNegativeButton("إغلاق", null)
            .show()
    }

    private fun showServerDialog() {
        if (pageServerOptions.isEmpty()) {
            simpleMessage("لا توجد سيرفرات متعددة")
            return
        }
        val labels = pageServerOptions.map { it.label }.toTypedArray()
        val checked = pageServerOptions.indexOfFirst { it.selected }.let { if (it >= 0) it else 0 }
        AlertDialog.Builder(this)
            .setTitle("السيرفر")
            .setSingleChoiceItems(labels, checked) { dialog, which ->
                val option = pageServerOptions[which]
                pageServerOptions = pageServerOptions.mapIndexed { i, item -> item.copy(selected = i == which) }
                channel?.invokeMethod(
                    "onServerSelected",
                    mapOf("label" to option.label, "key" to option.key, "url" to (option.embedUrl ?: ""))
                )
                dialog.dismiss()
            }
            .setNegativeButton("إغلاق", null)
            .show()
    }

    private fun collectTrackChoices(tracks: Tracks, type: Int): List<TrackChoice> {
        val byLabel = LinkedHashMap<String, TrackChoice>()
        val byLabelRank = LinkedHashMap<String, Int>()

        for (group in tracks.groups) {
            if (group.type != type) continue
            for (i in 0 until group.length) {
                if (!group.isTrackSupported(i)) continue
                val format = group.getTrackFormat(i)
                val label = when (type) {
                    C.TRACK_TYPE_VIDEO -> {
                        if (format.height > 0) "${format.height}p" else "Video ${i + 1}"
                    }
                    else -> "Track ${i + 1}"
                }
                val clean = cleanQualityLabel(label).ifBlank { label }
                val score = (format.height.coerceAtLeast(0) * 1_000_000) + format.bitrate.coerceAtLeast(0)
                val oldScore = byLabelRank[clean.lowercase()]
                if (oldScore == null || score > oldScore || group.isTrackSelected(i)) {
                    byLabel[clean.lowercase()] = TrackChoice(clean, group, i, group.isTrackSelected(i))
                    byLabelRank[clean.lowercase()] = score
                }
            }
        }

        return byLabel.values.sortedWith(
            compareByDescending<TrackChoice> { qualityRank(it.label) }
                .thenBy { it.label }
        )
    }

    private fun applyHighestVideoTrackIfAvailable(player: ExoPlayer, force: Boolean = false) {
        if (autoHighestVideoApplied && !force) return

        var best: TrackChoice? = null
        var bestScore = -1
        var selectedScore = -1

        for (group in player.currentTracks.groups) {
            if (group.type != C.TRACK_TYPE_VIDEO) continue
            for (i in 0 until group.length) {
                if (!group.isTrackSupported(i)) continue

                val format = group.getTrackFormat(i)
                val height = format.height.coerceAtLeast(0)
                val bitrate = format.bitrate.coerceAtLeast(0)
                val score = (height * 1_000_000) + bitrate

                if (group.isTrackSelected(i)) {
                    selectedScore = max(selectedScore, score)
                }

                if (score > bestScore) {
                    bestScore = score
                    val label = if (format.height > 0) "${format.height}p" else "Video ${i + 1}"
                    best = TrackChoice(cleanQualityLabel(label).ifBlank { label }, group, i, group.isTrackSelected(i))
                }
            }
        }

        val choice = best ?: return

        if (choice.selected || (bestScore > 0 && selectedScore == bestScore)) {
            autoHighestVideoApplied = true
            return
        }

        applyTrackSelection(C.TRACK_TYPE_VIDEO, choice)
    }

    private fun scheduleApplyHighestVideoTrack() {
        val player = exoPlayer ?: return
        val ticket = ++highestVideoAutoApplyTicket
        autoHighestVideoApplied = false

        val delays = longArrayOf(0L, 120L, 350L, 800L, 1400L, 2300L)
        val handler = android.os.Handler(android.os.Looper.getMainLooper())

        for (delay in delays) {
            handler.postDelayed({
                if (ticket != highestVideoAutoApplyTicket) return@postDelayed
                val p = exoPlayer ?: return@postDelayed
                if (!nativePlayerActive) return@postDelayed
                applyHighestVideoTrackIfAvailable(p, force = true)
            }, delay)
        }
    }

    private fun applyTrackSelection(type: Int, choice: TrackChoice) {
        val player = exoPlayer ?: return
        val override = TrackSelectionOverride(choice.group.mediaTrackGroup, listOf(choice.trackIndex))
        val params = player.trackSelectionParameters.buildUpon()
            .clearOverridesOfType(type)
            .addOverride(override)
            .setTrackTypeDisabled(type, false)
            .build()

        player.trackSelectionParameters = params

        if (type == C.TRACK_TYPE_VIDEO) {
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                try {
                    val p = exoPlayer ?: return@postDelayed
                    p.trackSelectionParameters = params
                } catch (_: Exception) {}
            }, 180L)
        }
    }

    private fun simpleMessage(message: String) {
        AlertDialog.Builder(this).setMessage(message).setPositiveButton("حسنًا", null).show()
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

    private fun enableHighRefreshRate() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return

        val currentDisplay = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) display
        else @Suppress("DEPRECATION") windowManager.defaultDisplay
        val modes = currentDisplay?.supportedModes ?: emptyArray()
        val highestMode = modes.maxByOrNull { it.refreshRate }
        val params: WindowManager.LayoutParams = window.attributes

        if (highestMode != null) {
            val targetHz = highestMode.refreshRate
            val displayModeChanged = params.preferredDisplayModeId != highestMode.modeId
            val refreshChanged = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
                kotlin.math.abs(params.preferredRefreshRate - targetHz) > 0.01f

            if (displayModeChanged || refreshChanged) {
                params.preferredDisplayModeId = highestMode.modeId
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    params.preferredRefreshRate = targetHz
                }
                window.attributes = params
            }
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            if (kotlin.math.abs(params.preferredRefreshRate - 120f) > 0.01f) {
                params.preferredRefreshRate = 120f
                window.attributes = params
            }
        }

        appliedPlaybackFrameRate = null
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
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
        enableHighRefreshRate()
    }

    private fun resetPlaybackFrameRatePreference() {
        appliedPlaybackFrameRate = null
        enableHighRefreshRate()
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()
    private fun dpF(value: Float): Float = value * resources.displayMetrics.density

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
                SecurityGuard.protect(this)
enableHighRefreshRate()
        if (nativePlayerActive && !isInPictureInPictureMode) {
            applyLandscapeMode()
            showNativeSurface()
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
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
