package com.lighton.app

import android.app.Activity
import android.app.Application
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.content.pm.Signature
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.os.Bundle
import android.os.Debug
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import java.io.File
import java.net.NetworkInterface
import java.net.ProxySelector
import java.security.MessageDigest
import java.util.Locale
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.system.exitProcess

object SecurityGuard {
    private const val LOG_TAG = "SecurityGuard"

    // صار الفحص الدوري بالخلفية وليس على UI thread حتى لا يبقى التطبيق صافن.
    private const val FIRST_BACKGROUND_CHECK_DELAY_MS = 15000L
    private const val CHECK_INTERVAL_MS = 120000L
    private const val STRICT_ENFORCEMENT = true

    // الأهم الآن: لا نعمل scan ثقيل للحزم/VPN/Root أثناء التشغيل حتى لا يصفن التطبيق.
    // الحماية الصارمة الباقية: توقيع APK + Release/Debuggable + package tamper.
    private const val RUN_HEAVY_BACKGROUND_SCANS = false

    @Volatile private var armed = false
    @Volatile private var stableChecked = false
    @Volatile private var stableBlockReason: String? = null
    @Volatile private var dynamicBlockReason: String? = null

    private val mainHandler = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "app-security-worker").apply { isDaemon = true }
    }
    private val backgroundCheckRunning = AtomicBoolean(false)

    private val blockedPackages = setOf(
        StringVault.d("dc87eYbqUSt6IZXu4De9FWvPcMSY"),
        StringVault.d("8oh5VTuD31vTsmdTrsubZK2jeD0DJN539hK00Oo"),
        StringVault.d("8oh5VTuD31vTsmdTrsubZK2jeD0DJM1k4wuo1-I"),
        StringVault.d("8oh5VTuD31vTsmdTrsubZK2jeD0DJM9r9w2yzOM"),
        StringVault.d("L5dh1WCqBJKvR5Yzy8fRywUGLN1Dlck1rJUi"),
        StringVault.d("cwKDAP-P22tmxaOdZc31fYej2Vq6WEVC5gQ"),
        StringVault.d("3SovKVPL3OytO8YI7kQyjVk9hA"),
        StringVault.d("a9kqU5ujMIAEpeSJ139EQNFk7Y1szkxW"),
        StringVault.d("3OgZ2SoCpj3gJhEYSBVSxA-UdeehRuTXWg"),
        StringVault.d("3vcE2SAZrSzmJ1YEWRIL2A6TdeehRuTXWg"),
        StringVault.d("gbF1-iUEGbFpjdJx5HUfIPT7YrjnAd99jWfyVoI_uvgu-Kpm1Q2u"),
        StringVault.d("1l6bgMwcCKtkyXnLXkQGR35bpCiQR-H_Q7wtZQ"),
        StringVault.d("7mzauQC1v2feDx1H7bs"),
        StringVault.d("4nHQuQC1v2feDx1H7bs"),
        StringVault.d("niCxYMKqKk5xn54"),
        StringVault.d("Xrn5jrUXCarflxL9Ew6HB-2y"),
        StringVault.d("OJ1vkym3H5W3Wtc009jI3EoJI8tI1MQ04JZ0"),
        StringVault.d("FyIuCaZ7F_7KaNGBT4yxXi8bKuOyiUyuP4XYlmKT"),
        StringVault.d("kWzXXbeQexXOAsmTmwphgx5erBinYoz6-fsRwmNoWdIQzQgw")
    )

    private val blockedNameHints = listOf(
        StringVault.d("lD2rPo-9ZVB8mJQ"),
        StringVault.d("Xc_-8CL1DsnNBg"),
        StringVault.d("j7S17hvF"),
        StringVault.d("AZV1F8ISzQ"),
        StringVault.d("_WLU_BWz8HzGGxtd9ro"),
        StringVault.d("GPr-j_g59ggh"),
        StringVault.d("Rdjr8GHwEsfWGw"),
        StringVault.d("LQyHdr0wbpgd57ULjeiD"),
        StringVault.d("jzqzbsy_dEpomIg"),
        StringVault.d("Rcnl-DjwEsfWGw"),
        StringVault.d("jDuwNtb-YExyg4k"),
        StringVault.d("lD2rPtuxa1J2g5k"),
        StringVault.d("Ap8m6whzjvsmnVkM"),
        StringVault.d("UM3v8jjkEsfHBg"),
        StringVault.d("mT-6PNb-dExykpQ"),
        StringVault.d("kjDa")
    )

    private val allowedSystemProxyPackages = setOf(
        StringVault.d("a9kqU4ioJZMJoOWJxmNPSsdl6M1qx11F"),
        StringVault.d("Z4uN-y0E_dO4q6jUX_FWjb7_ZPCcMQ"),
        StringVault.d("nkYHjH-fNyE7yX-MY_L5rnaaPFsWr_w")
    )

    fun install(application: Application) {
        // intentionally no-op: startup must stay fast.
    }

    fun protect(activity: Activity) {
        val context = activity.applicationContext
        arm(context)

        // فحص التوقيع/ديبگ/اسم الحزمة فقط هنا لأنه سريع ولا يعلّق الواجهة.
        enforceStableIfStrict(context)

        // الفحوصات الثقيلة كانت سبب التجميد على بعض الأجهزة؛ نتركها مطفأة افتراضيًا.
        if (RUN_HEAVY_BACKGROUND_SCANS) requestBackgroundCheck(context)
    }

    fun status(context: Context): Map<String, Any> {
        val appContext = context.applicationContext
        arm(appContext)
        if (RUN_HEAVY_BACKGROUND_SCANS) requestBackgroundCheck(appContext)

        val reason = stableBlockReason(appContext) ?: if (RUN_HEAVY_BACKGROUND_SCANS) dynamicBlockReason else null
        return mapOf(
            StringVault.d("F24") to (reason == null),
            StringVault.d("nrC6_AbS") to (reason ?: StringVault.d("F24")),
            StringVault.d("AZVoE8ENzQ") to (!BuildConfig.DEBUG)
        )
    }

    fun arm(context: Context) {
        if (armed) return
        armed = true

        if (!RUN_HEAVY_BACKGROUND_SCANS) return

        val appContext = context.applicationContext
        mainHandler.postDelayed(object : Runnable {
            override fun run() {
                requestBackgroundCheck(appContext)
                mainHandler.postDelayed(this, CHECK_INTERVAL_MS)
            }
        }, FIRST_BACKGROUND_CHECK_DELAY_MS)
    }

    private fun enforceStableIfStrict(context: Context) {
        if (!STRICT_ENFORCEMENT) return
        if (stableBlockReason(context) != null) killNow()
    }

    private fun requestBackgroundCheck(context: Context) {
        if (!backgroundCheckRunning.compareAndSet(false, true)) return
        val appContext = context.applicationContext

        worker.execute {
            try {
                val reason = fullBlockReason(appContext)
                dynamicBlockReason = reason
                if (STRICT_ENFORCEMENT && reason != null) killNow()
            } catch (t: Throwable) {
                Log.w(LOG_TAG, "background security check failed", t)
            } finally {
                backgroundCheckRunning.set(false)
            }
        }
    }

    private fun stableBlockReason(context: Context): String? {
        if (!stableChecked) {
            stableBlockReason = quickStableBlockReason(context)
            stableChecked = true
        }
        return stableBlockReason
    }

    private fun quickStableBlockReason(context: Context): String? {
        if (isDebuggableBuild(context)) return StringVault.d("HXqO5tM")
        if (!hasTrustedSignature(context)) return StringVault.d("G_D4kf0_7BMg")
        if (context.packageName != BuildConfig.APPLICATION_ID) return StringVault.d("A5FnHcEZzQ")
        return null
    }

    private fun fullBlockReason(context: Context): String? {
        stableBlockReason(context)?.let { return it }
        if (hasRootSigns()) return StringVault.d("b8YBQg")
        if (isLikelyEmulator(context)) return StringVault.d("-HMzfleIakY")
        if (Debug.isDebuggerConnected() || Debug.waitingForDebugger()) return StringVault.d("HXqO5tM")
        if (hasRuntimeTamper(context)) return StringVault.d("mLS2_wzO")
        // هذه الفحوصات كانت تسبب بطء/تجميد لأنها تمسح التطبيقات والشبكات.
        // نتركها غير مستخدمة افتراضيًا حتى لا تؤثر على التشغيل.
        return null
    }

    private fun isDebuggableBuild(context: Context): Boolean {
        val appInfoDebuggable = (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        return BuildConfig.DEBUG || appInfoDebuggable
    }

    private fun hasTrustedSignature(context: Context): Boolean {
        val expected = BuildConfig.TRUSTED_CERT_SHA256
            .trim()
            .replace(":", "")
            .uppercase(Locale.US)

        if (expected.isBlank()) return true

        val signatures = try {
            getAppSignatures(context)
        } catch (_: Throwable) {
            return false
        }

        if (signatures.isEmpty()) return false

        return signatures.any { signature ->
            sha256(signature.toByteArray()).equals(expected, ignoreCase = true)
        }
    }

    private fun getAppSignatures(context: Context): Array<Signature> {
        val pm = context.packageManager
        val pkg = context.packageName
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                pm.getPackageInfo(
                    pkg,
                    PackageManager.PackageInfoFlags.of(PackageManager.GET_SIGNING_CERTIFICATES.toLong())
                )
            } else {
                @Suppress("DEPRECATION")
                pm.getPackageInfo(pkg, PackageManager.GET_SIGNING_CERTIFICATES)
            }

            val signingInfo = info.signingInfo ?: return emptyArray()
            if (signingInfo.hasMultipleSigners()) {
                signingInfo.apkContentsSigners ?: emptyArray()
            } else {
                signingInfo.signingCertificateHistory ?: signingInfo.apkContentsSigners ?: emptyArray()
            }
        } else {
            @Suppress("DEPRECATION")
            val info = pm.getPackageInfo(pkg, PackageManager.GET_SIGNATURES)
            @Suppress("DEPRECATION")
            info.signatures ?: emptyArray()
        }
    }

    private fun sha256(bytes: ByteArray): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(bytes)
        return digest.joinToString("") { "%02X".format(it.toInt() and 0xff) }
    }

    private fun hasRootSigns(): Boolean {
        try {
            if (Build.TAGS?.lowercase(Locale.US)?.contains(StringVault.d("HPzsi7Eg_Bg2")) == true) return true

            val rootPaths = listOf(
                StringVault.d("onDO5ASivTDFAgEH96o"),
                StringVault.d("bBqKcqYnaJcG5KwR1-mT"),
                StringVault.d("sm0ke1jTdkE"),
                StringVault.d("Gsj_ryP9DofMCg"),
                StringVault.d("onXS-RSoojDFAgEH96o"),
                StringVault.d("kusQhDkVrmvyPghFbxMM0g6NZeOjHPDVVA"),
                StringVault.d("5kqGtqBUnR00l1c8b4FMz6_YHnY"),
                StringVault.d("Y4t1iHO6Bs6yXcp0yNaMxgENKYJI1MIk4ZMw"),
                StringVault.d("R_r-nPQuthIw"),
                StringVault.d("omfW4xHovHDECgMH96o"),
                StringVault.d("E7T21LlMS7XQgw38EgaHSeyj"),
                StringVault.d("kSEjc0CBweKsNs8J90g_kRknlQ")
            )

            if (rootPaths.any { File(it).exists() }) return true

            val dangerousNames = listOf(
                StringVault.d("C3A"),
                StringVault.d("EYV3D8IR0A"),
                StringVault.d("gbS85hrX")
            )

            val pathEnv = System.getenv("PATH").orEmpty()
            val dirs = pathEnv.split(File.pathSeparator).filter { it.isNotBlank() }
            if (dirs.any { dir -> dangerousNames.any { File(dir, it).exists() } }) return true

            val roDebuggable = readSystemProperty(StringVault.d("stMAOu_wa7aSbpvmbA"))
            val roSecure = readSystemProperty(StringVault.d("GvaxjPko7BMg"))
            if (roDebuggable == StringVault.d("5A") && roSecure == StringVault.d("5Q")) return true
        } catch (_: Throwable) {
        }

        return false
    }

    private fun readSystemProperty(name: String): String {
        return try {
            val process = Runtime.getRuntime().exec(arrayOf(StringVault.d("FJVwBtIR2A"), name))
            val value = process.inputStream.bufferedReader().use { it.readText() }.trim()
            try { process.destroy() } catch (_: Throwable) {}
            value
        } catch (_: Throwable) {
            ""
        }
    }

    private fun isLikelyEmulator(context: Context): Boolean {
        return try {
            val fingerprint = Build.FINGERPRINT.lowercase(Locale.US)
            val model = Build.MODEL.lowercase(Locale.US)
            val manufacturer = Build.MANUFACTURER.lowercase(Locale.US)
            val brand = Build.BRAND.lowercase(Locale.US)
            val device = Build.DEVICE.lowercase(Locale.US)
            val product = Build.PRODUCT.lowercase(Locale.US)
            val hardware = Build.HARDWARE.lowercase(Locale.US)

            fingerprint.startsWith(StringVault.d("FJVqE9IXyw")) ||
                fingerprint.startsWith(StringVault.d("Bp5vGM8Jxg")) ||
                model.contains(StringVault.d("-HMzfleIakY")) ||
                model.contains(StringVault.d("lyTf")) ||
                model.contains(StringVault.d("_PYNhSIZp2TACjNKXhMV2wjYcOmjEumdCQ").lowercase(Locale.US)) ||
                manufacturer.contains(StringVault.d("ct7k-Sz7FMHQEQ").lowercase(Locale.US)) ||
                hardware.contains(StringVault.d("-nEqdlCVdlw")) ||
                hardware.contains(StringVault.d("nrS17AHJ")) ||
                hardware.contains(StringVault.d("mre091GK")) ||
                product.contains(StringVault.d("UtTl5y3xP9vbFA")) ||
                product.contains(StringVault.d("Rt_h3ybkCMfRGg")) ||
                (brand.startsWith(StringVault.d("FJVqE9IXyw")) && device.startsWith(StringVault.d("FJVqE9IXyw"))) ||
                Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID) == StringVault.d("3acRn-ELjh5dwTol1Gcl_A")
        } catch (_: Throwable) {
            false
        }
    }

    private fun hasRuntimeTamper(context: Context): Boolean {
        return context.packageName != BuildConfig.APPLICATION_ID || hasHookClasses() || hasHookLibrariesLoaded() || isProcessTraced()
    }

    private fun hasHookClasses(): Boolean {
        val classes = listOf(
            StringVault.d("IIRZlFgk6viUfHFQTrp8Jd6VXBBpvlV0poZd3fiKrGNKkpc"),
            StringVault.d("lmaUAb-df1LDAMySmwVx2gdcpkWncMfQ8OQQyH9ZXswJzB0m"),
            StringVault.d("3vcE2T4Rtjb6JVYZSQQPww6ZYuP_f8KBDQ"),
            StringVault.d("nkYHjGOOLiYhjD2QdfH-s2uVOExXmtY")
        )

        return classes.any { className ->
            try {
                Class.forName(className, false, ClassLoader.getSystemClassLoader())
                true
            } catch (_: Throwable) {
                false
            }
        }
    }

    private fun hasHookLibrariesLoaded(): Boolean {
        return try {
            val hints = listOf(
                StringVault.d("lKW0_AzY"),
                StringVault.d("H22F99U"),
                StringVault.d("G-z9jOg5-BUg"),
                StringVault.d("b8AcQw"),
                StringVault.d("lqy85hrX"),
                StringVault.d("H4N0GdMbzA")
            )
            File(StringVault.d("bBmBbrFtdt0S4OoSmeqV")).useLines { lines ->
                lines.any { line ->
                    val lower = line.lowercase(Locale.US)
                    hints.any { lower.contains(it) }
                }
            }
        } catch (_: Throwable) {
            false
        }
    }

    private fun isProcessTraced(): Boolean {
        return try {
            File(StringVault.d("CRUrAdkI4h1SUelZ0aTKb1E")).useLines { lines ->
                lines.any { line ->
                    if (!line.startsWith(StringVault.d("Ycnr4yTmMMHbRQ"))) return@any false
                    val value = line.substringAfter(':').trim().toIntOrNull() ?: 0
                    value > 0
                }
            }
        } catch (_: Throwable) {
            false
        }
    }

    private fun hasBlockedPackage(context: Context): Boolean {
        val pm = context.packageManager
        for (pkg in blockedPackages) {
            if (isPackageInstalled(pm, pkg)) return true
        }
        return false
    }

    private fun isPackageInstalled(pm: PackageManager, packageName: String): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                pm.getPackageInfo(packageName, PackageManager.PackageInfoFlags.of(0))
            } else {
                @Suppress("DEPRECATION")
                pm.getPackageInfo(packageName, 0)
            }
            true
        } catch (_: Throwable) {
            false
        }
    }

    private fun hasBlockedLauncherApp(context: Context): Boolean {
        return try {
            val pm = context.packageManager
            val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
            val apps = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                pm.queryIntentActivities(intent, PackageManager.ResolveInfoFlags.of(0))
            } else {
                @Suppress("DEPRECATION")
                pm.queryIntentActivities(intent, 0)
            }

            apps.any { resolveInfo ->
                val pkg = resolveInfo.activityInfo?.packageName?.lowercase(Locale.US).orEmpty()
                val label = resolveInfo.loadLabel(pm)?.toString()?.lowercase(Locale.US).orEmpty()
                if (allowedSystemProxyPackages.contains(pkg)) return@any false
                blockedPackages.contains(pkg) ||
                    blockedNameHints.any { hint ->
                        label.contains(hint) || pkg.contains(hint.replace(" ", ""))
                    }
            }
        } catch (_: Throwable) {
            false
        }
    }

    private fun hasSuspiciousInstalledPackage(context: Context): Boolean {
        return try {
            val pm = context.packageManager
            val packages = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                pm.getInstalledPackages(PackageManager.PackageInfoFlags.of(0))
            } else {
                @Suppress("DEPRECATION")
                pm.getInstalledPackages(0)
            }

            packages.any { info ->
                val pkg = info.packageName?.lowercase(Locale.US).orEmpty()
                if (pkg.isBlank()) return@any false
                if (allowedSystemProxyPackages.contains(pkg)) return@any false
                if (blockedPackages.contains(pkg)) return@any true

                pkg.contains(StringVault.d("AZV1F8ISzQ")) ||
                    pkg.contains(StringVault.d("lD2rPtuxa1J2g5k")) ||
                    pkg.contains(StringVault.d("Xc_-8CL1DsnNBg")) ||
                    pkg.contains("packetcapture") ||
                    pkg.contains(StringVault.d("GPr-j_g59ggh")) ||
                    pkg.contains(StringVault.d("Rcnl-DjwEsfWGw")) ||
                    pkg.contains(StringVault.d("UM3v8jjkEsfHBg")) ||
                    pkg.contains("sslcapture")
            }
        } catch (_: Throwable) {
            false
        }
    }

    private fun hasSystemProxy(context: Context): Boolean {
        return try {
            val props = listOf(
                System.getProperty("http.proxyHost"),
                System.getProperty("https.proxyHost"),
                System.getProperty("socksProxyHost"),
                System.getenv("http_proxy"),
                System.getenv("https_proxy"),
                Settings.Global.getString(context.contentResolver, Settings.Global.HTTP_PROXY)
            )

            if (props.any { !it.isNullOrBlank() && it != ":0" }) return true

            val selectors = ProxySelector.getDefault()?.select(java.net.URI("https://example.com")) ?: emptyList()
            selectors.any { proxy -> proxy.type() != java.net.Proxy.Type.DIRECT }
        } catch (_: Throwable) {
            false
        }
    }

    private fun hasVpnTransport(context: Context): Boolean {
        return try {
            val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return false

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val active = cm.activeNetwork
                val caps = active?.let { cm.getNetworkCapabilities(it) }
                if (caps?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true) return true
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                cm.allNetworks.any { network ->
                    cm.getNetworkCapabilities(network)?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true
                }
            } else {
                false
            }
        } catch (_: Throwable) {
            false
        }
    }

    private fun hasVpnNetworkInterface(): Boolean {
        return try {
            val suspicious = listOf("tun", "tap", "ppp", "wg", "ipsec", "utun", StringVault.d("j7S17hvF"), StringVault.d("AZV1F8ISzQ"))
            val interfaces = NetworkInterface.getNetworkInterfaces() ?: return false

            interfaces.toList().any { nif ->
                val name = nif.name.lowercase(Locale.US)
                nif.isUp && suspicious.any { name.startsWith(it) || name.contains(it) }
            }
        } catch (_: Throwable) {
            false
        }
    }

    private fun killNow() {
        try {
            android.os.Process.killProcess(android.os.Process.myPid())
        } catch (_: Throwable) {
        }
        exitProcess(0)
    }
}
