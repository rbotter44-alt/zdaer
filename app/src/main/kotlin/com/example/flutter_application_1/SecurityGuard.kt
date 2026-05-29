package com.example.flutter_application_1

import android.app.Activity
import android.app.Application
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import java.net.NetworkInterface
import java.net.ProxySelector
import kotlin.system.exitProcess

object SecurityGuard {
    private const val LOG_TAG = "SecurityGuard"
    private const val CHECK_INTERVAL_MS = 700L

    @Volatile private var armed = false
    private val mainHandler = Handler(Looper.getMainLooper())

    private val blockedPackages = setOf(
        "com.guoshi.httpcanary",
        "com.guoshi.httpcanary.premium",
        "com.guoshi.httpcanary.capture",
        "com.guoshi.httpcanary.android",
        "com.guoshi.httpcanary.debug",
        "com.guoshi.httpcanary.beta",
        "com.reqable.android",
        "com.reqable.android.beta",
        "app.greyshirts.sslcapture",
        "com.minhui.networkcapture",
        "jp.co.taosoftware.android.packetcapture",
        "com.emanuelef.remote_capture",
        "com.proxydroid",
        "org.proxydroid",
        "bin.mt.plus",
        "bin.mt.plus.canary",
        "tech.httptoolkit.android.v1",
        "com.gorillasoftware.everyproxy",
        "com.gorillasoftware.everyproxybridge",
      
    )

    private val blockedNameHints = listOf(
        "http canary",
        "httpcanary",
        "canary",
        "reqable",
        "packet capture",
        "pcapdroid",
        "pcap droid",
        "network capture",
        "ssl capture",
        "proxydroid",
        "proxy droid",
        "httptoolkit",
        "http toolkit",
        "everyproxy",
        "every proxy",
        "vpn"
    )

    private val allowedSystemProxyPackages = setOf(
        "com.android.proxyhandler",
        "com.android.vpndialogs",
        "com.oplus.locationproxy"
    )


    fun install(application: Application) {
        arm(application.applicationContext)
        application.registerActivityLifecycleCallbacks(object : Application.ActivityLifecycleCallbacks {
            override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {
                protect(activity)
            }

            override fun onActivityResumed(activity: Activity) {
                protect(activity)
            }

            override fun onActivityStarted(activity: Activity) {}
            override fun onActivityPaused(activity: Activity) {}
            override fun onActivityStopped(activity: Activity) {}
            override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}
            override fun onActivityDestroyed(activity: Activity) {}
        })
    }

    fun protect(activity: Activity) {
        arm(activity.applicationContext)
        if (isBlockedEnvironment(activity.applicationContext)) killNow()
    }

    fun arm(context: Context) {
        if (armed) return
        armed = true

        val appContext = context.applicationContext
        mainHandler.post(object : Runnable {
            override fun run() {
                try {
                    if (isBlockedEnvironment(appContext)) killNow()
                } catch (e: Throwable) {
                    Log.w(LOG_TAG, "periodic check failed", e)
                }

                mainHandler.postDelayed(this, CHECK_INTERVAL_MS)
            }
        })
    }

    private fun isBlockedEnvironment(context: Context): Boolean {
        return hasBlockedPackage(context) ||
            hasBlockedLauncherApp(context) ||
            hasSuspiciousInstalledPackage(context) ||
            hasSystemProxy(context) ||
            hasVpnTransport(context) ||
            hasVpnNetworkInterface()
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
                val pkg = resolveInfo.activityInfo?.packageName?.lowercase().orEmpty()
                val label = resolveInfo.loadLabel(pm)?.toString()?.lowercase().orEmpty()
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
                val pkg = info.packageName?.lowercase().orEmpty()
                if (pkg.isBlank()) return@any false
                if (allowedSystemProxyPackages.contains(pkg)) return@any false
                if (blockedPackages.contains(pkg)) return@any true

                // Catch renamed/forked capture tools without killing Android system proxy packages.
                pkg.contains("reqable") ||
                    pkg.contains("httptoolkit") ||
                    pkg.contains("httpcanary") ||
                    pkg.contains("packetcapture") ||
                    pkg.contains("pcapdroid") ||
                    pkg.contains("proxydroid") ||
                    pkg.contains("everyproxy") ||
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
            val suspicious = listOf("tun", "tap", "ppp", "wg", "ipsec", "utun", "canary", "reqable")
            val interfaces = NetworkInterface.getNetworkInterfaces() ?: return false

            interfaces.toList().any { nif ->
                val name = nif.name.lowercase()
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
