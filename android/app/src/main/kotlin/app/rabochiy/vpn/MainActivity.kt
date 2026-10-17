package app.rabochiy.vpn

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.graphics.Color
import android.net.VpnService
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import androidx.activity.SystemBarStyle
import androidx.activity.enableEdgeToEdge
import com.witvpn.vlee.VleeManager
import com.witvpn.vlee.model.VleeServerConfig
import app.rabochiy.vpn.play.PlayStoreBridge
import app.rabochiy.vpn.xray.XrayEngine
import app.rabochiy.vpn.xray.XrayUnreachableException
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// FlutterFragmentActivity (a ComponentActivity) so androidx enableEdgeToEdge() is available.
class MainActivity : FlutterFragmentActivity() {
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
    // Google Play review / update flows. Must stay a property initializer:
    // it registers an ActivityResultLauncher, which is only allowed before
    // the activity is STARTED.
    private val playStore = PlayStoreBridge(this)
    private var statsJob: Job? = null
    private var lastRxBytes: Long = 0
    private var lastTxBytes: Long = 0
    private var lastStatsTime: Long = 0
    private var awgManager: AwgManager? = null

    // Kept as fields: onDestroy detaches only its own listeners, a recreated
    // activity may already have attached new ones.
    private val awgListener: (AwgManager.State, org.amnezia.awg.backend.Statistics?) -> Unit =
        { state, stats -> emitStatus(state.name, stats) }
    private val xrayListener: (XrayEngine.State) -> Unit = { state -> emitStatus(state.name, null) }
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
        // Call after super.onCreate so FlutterFragmentActivity switches from
        // LaunchTheme to NormalTheme before DecorView is installed.
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(Color.TRANSPARENT),
        )
    }

    override fun onResume() {
        super.onResume()
        isAppInForeground = true
        if (isVpnConnected && statsJob == null) {
            startTrafficPolling()
        }
    }

    override fun onPause() {
        super.onPause()
        isAppInForeground = false
        stopTrafficPolling()
    }

    override fun onDestroy() {
        stopTrafficPolling()
        if (XrayEngine.listener === xrayListener) XrayEngine.listener = null
        awgManager?.let { if (it.listener === awgListener) it.listener = null }
        vleeListener?.let { VleeManager.unregisterListener(it) }
        vleeListener = null
        eventSink = null
        vleeStatusSink = null
        try {
            pendingPermissionResult?.success(false)
        } catch (e: Exception) {
            Log.w("MainActivity", "Permission channel already closed", e)
        }
        pendingPermissionResult = null
        playStore.dispose()
        mainHandler.removeCallbacksAndMessages(null)
        scope.cancel()
        super.onDestroy()
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

        // Google Play In-App Review / In-App Updates
        playStore.attach(flutterEngine.dartExecutor.binaryMessenger)

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

        // VPN engine control channel (AmneziaWG + GW engines)
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
                val awg = AwgManager.get(applicationContext)
                awg.listener = awgListener
                awgManager = awg
                XrayEngine.listener = xrayListener
                // Tunnels outlive the activity: tell a fresh UI what runs.
                val snapshot = tunnelSnapshot()
                if (snapshot["state"] == "CONNECTED" && snapshot["protocol"] != "gw") {
                    isVpnConnected = true
                    startTrafficPolling()
                }
                result.success(snapshot)
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
                val vlessUri = call.argument<String>("vlessUri") ?: ""
                val blockedApps = call.argument<List<String>>("blockedApps")

                scope.launch {
                    try {
                        val connectResult = when (protocol) {
                            "awg" -> {
                                XrayEngine.disconnect()
                                awgManager?.connect(remark, awgConfig, blockedApps)
                            }
                            "vless" -> {
                                // AwgManager.disconnect() emits DISCONNECTED even when idle,
                                // which would flip the UI out of "connecting".
                                awgManager?.takeIf { it.isTunnelActive() }?.disconnect()
                                XrayEngine.connect(applicationContext, vlessUri, remark, blockedApps)
                            }
                            else -> Result.failure(IllegalArgumentException("Unknown protocol: $protocol"))
                        }
                        val failure = connectResult?.exceptionOrNull()
                        if (failure is java.net.SocketTimeoutException || failure is XrayUnreachableException) {
                            // Tunnel came up but the server never answered the
                            // handshake — surface a dedicated code so the UI can
                            // say "server unreachable" instead of "engine broken".
                            result.error("AWG_HANDSHAKE_TIMEOUT", "awg_handshake_timeout", null)
                        } else {
                            result.success(connectResult?.isSuccess ?: false)
                        }
                    } catch (e: Exception) {
                        android.util.Log.e("MainActivity", "Connect failed", e)
                        result.error("CONNECT_ERROR", e.message, e.stackTraceToString())
                    }
                }
            }
            "disconnect" -> {
                scope.launch {
                    val xrayWasRunning = XrayEngine.hasRunningService()
                    val xrayResult = XrayEngine.disconnect()
                    val awg = awgManager
                    val awgResult = if (awg != null && !(xrayWasRunning && !awg.isTunnelActive())) {
                        awg.disconnect()
                    } else {
                        Result.success(Unit)
                    }
                    result.success(awgResult.isSuccess && xrayResult.isSuccess)
                }
            }
            "pingServer" -> {
                val protocol = call.argument<String>("protocol") ?: "awg"
                val address = call.argument<String>("address") ?: ""
                val port = call.argument<Int>("port") ?: 0
                scope.launch {
                    val ping = when (protocol) {
                        "awg" -> awgManager?.ping()
                        "vless" -> XrayEngine.ping(address, port)
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
        statsJob = scope.launch {
            while (isActive && isAppInForeground && isVpnConnected) {
                delay(1000)
                emitTrafficStats()
            }
        }
    }

    private fun stopTrafficPolling() {
        statsJob?.cancel()
        statsJob = null
        lastRxBytes = 0
        lastTxBytes = 0
        lastStatsTime = 0
    }

    private suspend fun emitTrafficStats() {
        val totals = withContext(Dispatchers.IO) {
            if (XrayEngine.state == XrayEngine.State.CONNECTED) {
                XrayEngine.trafficTotals()
            } else {
                awgManager?.statistics()?.let { it.totalRx() to it.totalTx() }
            }
        } ?: return
        if (!isVpnConnected || !isAppInForeground) return
        val now = SystemClock.elapsedRealtime()

        val rxTotal = totals.first
        val txTotal = totals.second

        val downloadSpeed: Long
        val uploadSpeed: Long

        if (lastStatsTime > 0 && rxTotal >= lastRxBytes && txTotal >= lastTxBytes) {
            val dt = (now - lastStatsTime) / 1000.0
            if (dt > 0) {
                downloadSpeed = ((rxTotal - lastRxBytes) / dt).toLong()
                uploadSpeed = ((txTotal - lastTxBytes) / dt).toLong()
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
        data["download"] = rxTotal.coerceAtLeast(0L)
        data["upload"] = txTotal.coerceAtLeast(0L)
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
        if (Looper.myLooper() != Looper.getMainLooper()) {
            mainHandler.post { emitStatus(state, stats) }
            return
        }
        if (isDestroyed) return
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
                    lastStatsTime = SystemClock.elapsedRealtime()
                }
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

    private fun tunnelSnapshot(): Map<String, String> {
        val awg = awgManager
        val (protocol, state) = when {
            XrayEngine.state == XrayEngine.State.CONNECTED ||
                XrayEngine.state == XrayEngine.State.CONNECTING ->
                "vless" to XrayEngine.state.name
            // An AWG connect runs in the activity scope and dies with it.
            awg != null && awg.currentState == AwgManager.State.CONNECTED -> "awg" to "CONNECTED"
            VleeManager.state == VleeManager.State.CONNECTED ||
                VleeManager.state == VleeManager.State.CONNECTING ->
                "gw" to VleeManager.state.name
            else -> "" to "DISCONNECTED"
        }
        return mapOf("protocol" to protocol, "state" to state)
    }

    private fun AwgManager.isTunnelActive(): Boolean =
        currentState == AwgManager.State.CONNECTED || currentState == AwgManager.State.CONNECTING
}
