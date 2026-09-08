package app.rabochiy.vpn

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.net.TrafficStats
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.util.Log
import android.view.WindowInsetsController
import androidx.core.view.WindowCompat
import com.witvpn.vlee.VleeManager
import com.witvpn.vlee.model.VleeServerConfig
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class MainActivity : FlutterActivity() {
    companion object {
        private const val PKG_CHANNEL = "app.rabochiy.vpn/pkg_info"
        private const val ENGINE_CHANNEL = "rabochiy_vpn/engine"
        private const val ENGINE_EVENT_CHANNEL = "rabochiy_vpn/engine/status"
        private const val VPN_REQUEST_CODE = 0x1A61
        private const val VLEE_METHOD_CHANNEL = "app.rabochiy.vpn/vlee"
        private const val VLEE_EVENT_CHANNEL = "app.rabochiy.vpn/vlee/status"
        private const val VLEE_VPN_REQUEST = 0x1A62
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val statsHandler = Handler(Looper.getMainLooper())
    private var statsRunnable: Runnable? = null
    private var lastRxBytes: Long = 0
    private var lastTxBytes: Long = 0
    private var lastStatsTime: Long = 0
    private var awgManager: AwgManager? = null
    private var eventSink: EventChannel.EventSink? = null

    // VLEE (GW protocol) engine state
    private var vleeStatusSink: EventChannel.EventSink? = null
    private var vleeListener: VleeManager.StateListener? = null
    private var pendingVleeConfig: VleeServerConfig? = null
    private var pendingVleeExcluded: List<String> = emptyList()
    private var pendingVleeAllowed: List<String> = emptyList()

    // Track app state to pause traffic polling
    private var isAppInForeground = true
    private var isVpnConnected = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        configureSystemBarsForEdgeToEdge()
    }

    private fun configureSystemBarsForEdgeToEdge() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            WindowCompat.setDecorFitsSystemWindows(window, false)
            window.insetsController?.setSystemBarsAppearance(
                0,
                WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS or
                    WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS
            )
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isNavigationBarContrastEnforced = false
        }
    }

    override fun onResume() {
        super.onResume()
        isAppInForeground = true
        if (isVpnConnected && statsRunnable == null) {
            startTrafficPolling()
        }
    }

    override fun onPause() {
        super.onPause()
        isAppInForeground = false
        statsRunnable?.let {
            statsHandler.removeCallbacks(it)
            statsRunnable = null
        }
    }

    /**
     * The MethodChannel.Result from the in-flight `requestPermission` call.
     * We hold onto it so we can resolve it from [onActivityResult] once the
     * user dismisses the system VPN permission dialog. Without this hand-off
     * the Flutter side gets `false` immediately and treats the connection
     * attempt as denied — which was the root cause of "приложение не
     * подключается" on first launch.
     */
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Package-info channel (split-tunnel support)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PKG_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getLaunchablePackages" -> {
                        try { result.success(getLaunchablePackages()) }
                        catch (e: Exception) { result.error("ERR", e.message, null) }
                    }
                    else -> result.notImplemented()
                }
            }

        // VPN engine control channel (IKEv2 + AmneziaWG)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ENGINE_CHANNEL)
            .setMethodCallHandler { call, result ->
                handleEngineCall(call, result)
            }

        // VPN engine status event channel
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, ENGINE_EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { eventSink = events }
                override fun onCancel(arguments: Any?) { eventSink = null }
            })

        // VLEE (GW protocol) engine control channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VLEE_METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "connect" -> {
                        val configJson = call.argument<String>("config")
                        val excluded = call.argument<List<String>>("excludedApps") ?: emptyList()
                        val allowed = call.argument<List<String>>("allowedApps") ?: emptyList()
                        val config = configJson?.let { VleeManager.configFromIntentExtra(it) }
                        if (config == null || config.ipAddress.isBlank()) {
                            result.error("BAD_ARGS", "Missing vlee config", null)
                        } else {
                            val prepare = VpnService.prepare(this)
                            if (prepare != null) {
                                pendingVleeConfig = config
                                pendingVleeExcluded = excluded
                                pendingVleeAllowed = allowed
                                startActivityForResult(prepare, VLEE_VPN_REQUEST)
                                result.success(true)
                            } else {
                                VleeManager.startVpn(this, config, excluded, allowed)
                                result.success(true)
                            }
                        }
                    }
                    "disconnect" -> {
                        VleeManager.stopVpn(applicationContext)
                        result.success(true)
                    }
                    "isConnected" -> result.success(VleeManager.isConnected())
                    else -> result.notImplemented()
                }
            }

        // VLEE status event channel (STATE:/TRAFFIC:/RECONNECTING: events)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, VLEE_EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    vleeStatusSink = events
                    val listener = object : VleeManager.StateListener {
                        override fun onStateChange(state: VleeManager.State) {
                            emitVlee("STATE:${state.name}")
                        }
                        override fun onTrafficUpdate(rx: Long, tx: Long) {
                            emitVlee("TRAFFIC:$tx:$rx")
                        }
                        override fun onReconnecting(active: Boolean) {
                            emitVlee("RECONNECTING:$active")
                        }
                    }
                    vleeListener = listener
                    VleeManager.registerListener(listener)
                    events?.success("STATE:${VleeManager.state.name}")
                }

                override fun onCancel(arguments: Any?) {
                    vleeListener?.let { VleeManager.unregisterListener(it) }
                    vleeListener = null
                    vleeStatusSink = null
                }
            })
    }

    /** VLEE events come from tunnel worker threads — hop to main looper. */
    private fun emitVlee(event: String) {
        runOnUiThread { vleeStatusSink?.success(event) }
    }

    @Suppress("UNCHECKED_CAST")
    private fun handleEngineCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> {
                awgManager = AwgManager(this) { state, stats -> emitStatus(state.name, stats) }
                result.success(true)
            }
            "requestPermission" -> {
                val intent = VpnService.prepare(this)
                if (intent == null) {
                    // Already authorised by the OS — fast path.
                    result.success(true)
                    return
                }
                // If a previous request is still in flight, reject it cleanly
                // so the new caller is the one that hears the user's answer.
                pendingPermissionResult?.success(false)
                pendingPermissionResult = result
                try {
                    startActivityForResult(intent, VPN_REQUEST_CODE)
                } catch (e: Exception) {
                    Log.e("MainActivity", "Failed to launch VPN permission dialog", e)
                    pendingPermissionResult = null
                    result.success(false)
                }
            }
            "connect" -> {
                // Use explicit argument<String> for Java interop safety
                val protocol = call.argument<String>("protocol") ?: "awg"
                val remark = call.argument<String>("remark") ?: "Rabochiy"
                val address = call.argument<String>("address") ?: ""
                val port = call.argument<Int>("port") ?: 51820
                val username = call.argument<String>("username") ?: ""
                val password = call.argument<String>("password") ?: ""
                val caFile = call.argument<String>("caFile")
                val awgConfig = call.argument<String>("awgConfig") ?: ""
                val blockedApps = call.argument<List<String>>("blockedApps")

                scope.launch {
                    try {
                        val connectResult = when (protocol) {
                            "awg" -> awgManager?.connect(remark, awgConfig, blockedApps)
                            else -> Result.failure(IllegalArgumentException("Unknown protocol: $protocol"))
                        }
                        result.success(connectResult?.isSuccess ?: false)
                    } catch (e: Exception) {
                        android.util.Log.e("MainActivity", "Connect failed", e)
                        result.error("CONNECT_ERROR", e.message, e.stackTraceToString())
                    }
                }
            }
            "disconnect" -> {
                scope.launch {
                    val awg = awgManager
                    val awgResult = if (awg != null &&
                        (awg.isActive || awg.currentState != AwgManager.State.DISCONNECTED)
                    ) {
                        awg.disconnect()
                    } else {
                        Result.success(Unit)
                    }
                    result.success(awgResult.isSuccess)
                }
            }
            "pingServer" -> {
                val protocol = call.argument<String>("protocol") ?: "awg"
                scope.launch {
                    val ping = when (protocol) {
                        "awg" -> awgManager?.ping()
                        else -> null
                    }
                    result.success(ping)
                }
            }
            else -> result.notImplemented()
        }
    }

    /**
     * Called from [AwgManager] state callbacks. These
     * callbacks may fire from a coroutine running on `Dispatchers.IO`
     * (the Go backend tears the tunnel down on a background worker).
     *
     * Flutter's [EventChannel.EventSink.success] is annotated `@UiThread`
     * and crashes the process with `RuntimeException: Methods marked
     * with @UiThread must be executed on the main thread` if invoked
     * off the main looper — which was the exact crash users saw on
     * logout / delete-account ("прила выкидывает после нажатия").
     *
     * Hop onto the main looper unconditionally so we never trip that
     * assertion regardless of which dispatcher the caller is on.
     */
    private fun startTrafficPolling() {
        stopTrafficPolling()
        if (!isAppInForeground) return
        val runnable = object : Runnable {
            override fun run() {
                emitTrafficStats()
                statsHandler.postDelayed(this, 1000)
            }
        }
        statsRunnable = runnable
        statsHandler.postDelayed(runnable, 1000)
    }

    private fun stopTrafficPolling() {
        statsRunnable?.let { statsHandler.removeCallbacks(it) }
        statsRunnable = null
        lastRxBytes = 0
        lastTxBytes = 0
        lastStatsTime = 0
    }

    private fun emitTrafficStats() {
        val now = System.currentTimeMillis()

        val rxTotal: Long
        val txTotal: Long

        val awgStats = awgManager?.statistics()
        if (awgStats != null) {
            rxTotal = awgStats.totalRx()
            txTotal = awgStats.totalTx()
        } else {
            val uid = Process.myUid()
            rxTotal = TrafficStats.getUidRxBytes(uid)
            txTotal = TrafficStats.getUidTxBytes(uid)
        }

        val downloadSpeed: Int
        val uploadSpeed: Int

        if (lastStatsTime > 0 && rxTotal >= lastRxBytes && txTotal >= lastTxBytes) {
            val dt = (now - lastStatsTime) / 1000.0
            if (dt > 0) {
                downloadSpeed = ((rxTotal - lastRxBytes) / dt).toInt()
                uploadSpeed = ((txTotal - lastTxBytes) / dt).toInt()
            } else {
                downloadSpeed = 0
                uploadSpeed = 0
            }
        } else {
            downloadSpeed = 0
            uploadSpeed = 0
        }

        lastRxBytes = rxTotal
        lastTxBytes = txTotal
        lastStatsTime = now

        val data = HashMap<String, Any>()
        data["state"] = "CONNECTED"
        data["duration"] = 0
        data["download"] = if (rxTotal > 0) rxTotal.toInt() else 0
        data["upload"] = if (txTotal > 0) txTotal.toInt() else 0
        data["downloadSpeed"] = downloadSpeed
        data["uploadSpeed"] = uploadSpeed

        val deliver = Runnable {
            try {
                eventSink?.success(data)
            } catch (e: Exception) {
                Log.w("MainActivity", "emitTrafficStats delivery failed", e)
            }
        }
        if (Looper.myLooper() == Looper.getMainLooper()) {
            deliver.run()
        } else {
            mainHandler.post(deliver)
        }
    }

    private fun emitStatus(state: String, stats: Any?) {
        when (state.uppercase()) {
            "CONNECTED" -> {
                isVpnConnected = true
                lastRxBytes = 0
                lastTxBytes = 0
                lastStatsTime = 0
                startTrafficPolling()
                if (stats is org.amnezia.awg.backend.Statistics) {
                    lastRxBytes = stats.totalRx()
                    lastTxBytes = stats.totalTx()
                    lastStatsTime = System.currentTimeMillis()
                }
                return
            }
            "DISCONNECTED", "ERROR" -> {
                isVpnConnected = false
                stopTrafficPolling()
            }
        }

        val data = HashMap<String, Any>()
        data["state"] = state
        data["duration"] = 0
        data["download"] = 0
        data["upload"] = 0
        data["downloadSpeed"] = 0
        data["uploadSpeed"] = 0

        val deliver = Runnable {
            try {
                eventSink?.success(data)
            } catch (e: Exception) {
                Log.w("MainActivity", "emitStatus delivery failed", e)
            }
        }
        if (Looper.myLooper() == Looper.getMainLooper()) {
            deliver.run()
        } else {
            mainHandler.post(deliver)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VLEE_VPN_REQUEST) {
            val config = pendingVleeConfig
            pendingVleeConfig = null
            if (resultCode == Activity.RESULT_OK && config != null) {
                VleeManager.startVpn(this, config, pendingVleeExcluded, pendingVleeAllowed)
            }
            return
        }
        if (requestCode != VPN_REQUEST_CODE) return

        val granted = resultCode == Activity.RESULT_OK
        val pending = pendingPermissionResult
        pendingPermissionResult = null
        if (pending != null) {
            try {
                pending.success(granted)
            } catch (e: Exception) {
                // Flutter may already have torn the channel down; nothing
                // useful to do beyond logging.
                Log.w("MainActivity", "Failed to deliver VPN permission result", e)
            }
        } else {
            Log.w("MainActivity", "Got VPN permission result with no pending caller (granted=$granted)")
        }
    }

    /** Returns packages that have a launcher activity (apps the user sees in app drawer). */
    private fun getLaunchablePackages(): List<String> {
        val pm: PackageManager = packageManager
        val intent = Intent(Intent.ACTION_MAIN).apply { addCategory(Intent.CATEGORY_LAUNCHER) }
        val resolved: List<ResolveInfo> = pm.queryIntentActivities(intent, 0)
        val out = LinkedHashSet<String>(resolved.size)
        for (ri in resolved) {
            val pkg = ri.activityInfo?.packageName ?: continue
            if (pkg.isNotEmpty()) out.add(pkg)
        }
        return out.toList()
    }
}
