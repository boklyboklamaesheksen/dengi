package app.rabochiy.vpn.xray

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import android.util.Log
import libv2ray.CoreCallbackHandler
import libv2ray.CoreController
import libv2ray.Libv2ray
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import com.witvpn.vlee.R as VleeR

/**
 * VLESS tunnel: the TUN fd goes straight into Xray-core's `tun` inbound.
 *
 * Leak guards: all IPv4 is routed into the tunnel, IPv6 gets no route (Android
 * then blocks it for tunnelled apps), and DNS servers are tunnel-routed IPs
 * whose queries Xray answers through the proxy. The app itself is excluded so
 * Xray's own sockets reach the server directly instead of looping.
 */
class XrayVpnService : VpnService() {

    companion object {
        const val ACTION_START = "app.rabochiy.vpn.xray.START"
        const val EXTRA_URI = "uri"
        const val EXTRA_REMARK = "remark"
        const val EXTRA_BLOCKED_APPS = "blocked_apps"

        private const val TAG = "XrayVpnService"
        private const val CHANNEL_ID = "xray_vpn_service"
        private const val NOTIFICATION_ID = 4712
        private const val TUN_ADDRESS = "10.10.14.1"
        private val TUN_DNS = listOf("1.1.1.1", "8.8.8.8")
        private val PROBE_URLS = listOf(
            "https://www.gstatic.com/generate_204",
            "https://cp.cloudflare.com/generate_204",
        )

        /** Go's MeasureDelay gives up after 12 s; the probes run in parallel. */
        private const val PROBE_BUDGET_MS = 13_000L

        /** TCP handshake to the server itself: blocked IPs fail here in seconds. */
        private const val PRECHECK_TIMEOUT_MS = 5_000
        private const val WAIT_STEP_MS = 100L
        private val IPV4_LITERAL = Regex("^\\d{1,3}(\\.\\d{1,3}){3}$")
        private val TCP_NETWORKS = setOf("raw", "ws", "grpc", "httpupgrade", "xhttp")

        @Volatile
        internal var instance: XrayVpnService? = null
            private set
    }

    /** Serialises start/stop so two quick taps never run two cores. */
    private val worker: ExecutorService = Executors.newSingleThreadExecutor { r ->
        Thread(r, "xray-vpn-worker")
    }

    /** Bumped by every START/STOP; a worker of an older epoch backs off. */
    private val epoch = AtomicInteger(0)

    @Volatile private var lastStartId = 0
    private var tun: ParcelFileDescriptor? = null

    /** Written by the worker, read by [abortInFlight] from other threads. */
    @Volatile private var core: CoreController? = null

    /** The START the worker is serving; [abortInFlight] cancels its waits. */
    @Volatile private var attempt: Attempt? = null

    /** stopLoop() can block on the core mutex, so it never runs on the main thread. */
    private val aborter: ExecutorService = Executors.newSingleThreadExecutor { r ->
        Thread(r, "xray-abort")
    }

    /** Pre-check and probes; the worker waits for them without blocking an abort. */
    private val probes: ExecutorService = Executors.newCachedThreadPool { r ->
        Thread(r, "xray-probe")
    }

    private class Attempt {
        private val aborted = CountDownLatch(1)
        @Volatile var socket: Socket? = null

        val isAborted: Boolean
            get() = aborted.count == 0L

        fun abort() {
            aborted.countDown()
            // Interrupts a TCP pre-check stuck in connect().
            socket?.let { runCatching { it.close() } }
        }
    }

    private val coreCallback = object : CoreCallbackHandler {
        override fun startup(): Long = 0
        override fun shutdown(): Long = 0
        override fun onEmitStatus(p0: Long, p1: String?): Long {
            Log.d(TAG, "core: $p1")
            return 0
        }
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        lastStartId = startId
        startForegroundNotification()
        if (intent?.action != ACTION_START) {
            // System restart without our extras: never resurrect a tunnel the UI
            // does not know about.
            requestStop()
            return START_NOT_STICKY
        }
        val uri = intent.getStringExtra(EXTRA_URI).orEmpty()
        val remark = intent.getStringExtra(EXTRA_REMARK).orEmpty()
        val blocked = intent.getStringArrayListExtra(EXTRA_BLOCKED_APPS).orEmpty()
        startTunnel(uri, remark, blocked)
        return START_NOT_STICKY
    }

    private fun startTunnel(uri: String, remark: String, blocked: List<String>) {
        val myEpoch = epoch.incrementAndGet()
        abortInFlight()
        val myAttempt = Attempt().also { attempt = it }
        XrayEngine.onState(XrayEngine.State.CONNECTING)
        worker.execute {
            fun stale() = epoch.get() != myEpoch
            if (stale()) return@execute
            stopCore()
            try {
                val link = VlessLink.parse(uri)
                val config = XrayConfigBuilder.build(link)
                XrayEngine.ensureCoreEnv(applicationContext)

                // A banned server IP usually just drops the SYN: report it
                // before raising a TUN that would cut the device off meanwhile.
                if (precheckApplies(link) && !tcpReachable(link.host, link.port, myAttempt)) {
                    if (stale()) return@execute
                    throw XrayUnreachableException("vless server unreachable (tcp)")
                }
                if (stale()) return@execute

                val pfd = establishTun(remark, blocked)
                    ?: throw IllegalStateException("vpn_permission_denied")
                tun = pfd
                if (stale()) {
                    stopCore()
                    return@execute
                }

                val controller = Libv2ray.newCoreController(coreCallback)
                core = controller
                XrayEngine.controller = controller
                controller.startLoop(config, pfd.fd)
                check(controller.isRunning) { "xray core failed to start" }

                // Honest connect: report CONNECTED only after a real request
                // went through the server.
                val reachable = anyProbeSucceeds(controller, myAttempt)
                if (stale()) {
                    stopCore()
                    return@execute
                }
                if (!reachable) throw XrayUnreachableException("vless server unreachable")

                updateNotification(getString(VleeR.string.vlee_notif_connected))
                XrayEngine.onState(XrayEngine.State.CONNECTED)
            } catch (t: Throwable) {
                // Throwable: a broken .so surfaces as UnsatisfiedLinkError.
                Log.e(TAG, "VLESS tunnel failed: ${t.javaClass.simpleName}: ${t.message}")
                stopCore()
                if (!stale()) {
                    XrayEngine.onState(XrayEngine.State.ERROR, t)
                    finish(lastStartId)
                }
            }
        }
    }

    /** Stops the tunnel from any thread; safe to call repeatedly. */
    fun requestStop() {
        val myEpoch = epoch.incrementAndGet()
        val startId = lastStartId
        abortInFlight()
        try {
            worker.execute {
                if (epoch.get() != myEpoch) {
                    // A newer START is queued behind us and restarts the core
                    // itself; reporting DISCONNECTED here would fail it.
                    XrayEngine.onStopSuperseded()
                    return@execute
                }
                stopCore()
                XrayEngine.onState(XrayEngine.State.DISCONNECTED)
                finish(startId)
            }
        } catch (_: Exception) {
            // Executor already shut down by onDestroy; it stopped the core.
            XrayEngine.onState(XrayEngine.State.DISCONNECTED)
        }
    }

    private fun finish(startId: Int) {
        runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        }
        // A newer START keeps the service alive: stopSelf(id) ignores stale ids.
        stopSelf(startId)
    }

    /**
     * Releases the worker from the attempt it is serving (pre-check, probes)
     * and stops its core, so a cancel or a new START never waits for a dead
     * server. The worker still owns the cleanup (TUN fd, state).
     */
    private fun abortInFlight() {
        attempt?.abort()
        val controller = core ?: return
        runCatching { aborter.execute { runCatching { controller.stopLoop() } } }
    }

    /**
     * Only IP literals over TCP transports: resolving a domain here could
     * disagree with Xray's own lookup, and xhttp over h3 is QUIC (UDP).
     */
    private fun precheckApplies(link: VlessLink): Boolean {
        val host = link.host
        val literal = IPV4_LITERAL.matches(host) || host.contains(':')
        val quic = link.param("alpn").split(',').any { it.trim().equals("h3", ignoreCase = true) }
        return literal && !quic && link.network in TCP_NETWORKS
    }

    private fun tcpReachable(host: String, port: Int, attempt: Attempt): Boolean {
        val results = LinkedBlockingQueue<Boolean>()
        probes.execute {
            val socket = Socket()
            attempt.socket = socket
            val ok = try {
                if (attempt.isAborted) {
                    false
                } else {
                    socket.connect(InetSocketAddress(InetAddress.getByName(host), port), PRECHECK_TIMEOUT_MS)
                    true
                }
            } catch (e: Exception) {
                Log.w(TAG, "tcp pre-check failed: ${e.javaClass.simpleName}")
                false
            } finally {
                attempt.socket = null
                runCatching { socket.close() }
            }
            results.offer(ok)
        }
        return anySuccess(results, 1, PRECHECK_TIMEOUT_MS + 1_000L, attempt)
    }

    private fun anyProbeSucceeds(controller: CoreController, attempt: Attempt): Boolean {
        val results = LinkedBlockingQueue<Boolean>()
        for (url in PROBE_URLS) {
            probes.execute {
                val ok = try {
                    controller.measureDelay(url) >= 0
                } catch (e: Exception) {
                    Log.w(TAG, "probe failed: ${e.javaClass.simpleName}")
                    false
                }
                results.offer(ok)
            }
        }
        return anySuccess(results, PROBE_URLS.size, PROBE_BUDGET_MS, attempt)
    }

    /**
     * True on the first successful result; false once all [expected] results
     * failed, the budget ran out or the attempt was aborted.
     */
    private fun anySuccess(
        results: LinkedBlockingQueue<Boolean>,
        expected: Int,
        budgetMs: Long,
        attempt: Attempt,
    ): Boolean {
        val deadline = SystemClock.elapsedRealtime() + budgetMs
        var pending = expected
        while (pending > 0 && !attempt.isAborted) {
            val left = deadline - SystemClock.elapsedRealtime()
            if (left <= 0) return false
            val ok = results.poll(minOf(left, WAIT_STEP_MS), TimeUnit.MILLISECONDS) ?: continue
            if (ok) return true
            pending--
        }
        return false
    }

    private fun stopCore() {
        core?.let { controller ->
            runCatching { controller.stopLoop() }
                .onFailure { Log.w(TAG, "stopLoop failed: ${it.message}") }
        }
        core = null
        XrayEngine.controller = null
        runCatching { tun?.close() }
        tun = null
    }

    private fun establishTun(remark: String, blocked: List<String>): ParcelFileDescriptor? {
        val builder = Builder()
            .setSession(remark.ifBlank { getString(VleeR.string.vlee_notif_title) })
            .setMtu(XrayConfigBuilder.TUN_MTU)
            .addAddress(TUN_ADDRESS, 30)
            .addRoute("0.0.0.0", 0)
        TUN_DNS.forEach { builder.addDnsServer(it) }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) builder.setMetered(false)

        builder.addDisallowedApplication(packageName)
        for (pkg in blocked) {
            if (pkg == packageName) continue
            try {
                builder.addDisallowedApplication(pkg)
            } catch (_: Exception) {
                // Uninstalled since the list was built.
            }
        }
        return builder.establish()
    }

    private fun startForegroundNotification() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    getString(VleeR.string.vlee_notif_channel),
                    NotificationManager.IMPORTANCE_LOW,
                )
                getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
            }
            val notification = buildNotification(getString(VleeR.string.vlee_notif_title))
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            Log.e(TAG, "notification failed", e)
        }
    }

    private fun updateNotification(text: String) {
        runCatching {
            getSystemService(NotificationManager::class.java)
                ?.notify(NOTIFICATION_ID, buildNotification(text))
        }
    }

    private fun buildNotification(text: String): Notification {
        val openIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pending = openIntent?.let {
            PendingIntent.getActivity(
                this,
                0,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle(getString(VleeR.string.vlee_notif_title))
            .setContentText(text)
            .setSmallIcon(applicationInfo.icon.takeIf { it != 0 } ?: android.R.drawable.ic_lock_lock)
            .setContentIntent(pending)
            .setOngoing(true)
            .build()
    }

    override fun onRevoke() {
        requestStop()
        super.onRevoke()
    }

    override fun onDestroy() {
        epoch.incrementAndGet()
        attempt?.abort()
        if (instance === this) instance = null
        // Never block the main thread on a core that is still starting.
        runCatching {
            worker.execute {
                stopCore()
                // A replacement service may already be connecting.
                if (instance == null && XrayEngine.state != XrayEngine.State.DISCONNECTED) {
                    XrayEngine.onState(XrayEngine.State.DISCONNECTED)
                }
            }
        }
        worker.shutdown()
        aborter.shutdown()
        probes.shutdown()
        super.onDestroy()
    }
}
