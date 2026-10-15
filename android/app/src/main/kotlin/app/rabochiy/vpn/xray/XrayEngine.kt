package app.rabochiy.vpn.xray

import android.content.Context
import android.content.Intent
import android.os.SystemClock
import android.util.Log
import androidx.core.content.ContextCompat
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import libv2ray.CoreController
import libv2ray.Libv2ray
import java.io.IOException
import java.net.InetSocketAddress
import java.net.Socket

/** Error raised when the server never carried a real request through the tunnel. */
class XrayUnreachableException(message: String) : IOException(message)

/**
 * Process-wide state of the VLESS (Xray-core) engine. [XrayVpnService] owns the
 * tunnel; MainActivity talks to the engine only through this object.
 */
object XrayEngine {
    private const val TAG = "XrayEngine"

    /** Covers TUN setup plus two 12 s connectivity probes inside the service. */
    private const val CONNECT_TIMEOUT_MS = 45_000L
    private const val STOP_TIMEOUT_MS = 5_000L
    private const val PING_TIMEOUT_MS = 3_000

    enum class State { DISCONNECTED, CONNECTING, CONNECTED, ERROR }

    @Volatile
    var state: State = State.DISCONNECTED
        private set

    /** Receives every state change (called from worker threads). */
    @Volatile
    var listener: ((State) -> Unit)? = null

    private val lock = Any()
    private var pendingConnect: CompletableDeferred<Result<Unit>>? = null
    private var pendingStop: CompletableDeferred<Unit>? = null

    @Volatile
    internal var controller: CoreController? = null
    private var envReady = false
    private var rxTotal = 0L
    private var txTotal = 0L

    val isActive: Boolean
        get() = state == State.CONNECTING || state == State.CONNECTED

    internal fun ensureCoreEnv(context: Context) {
        synchronized(lock) {
            if (envReady) return
            go.Seq.setContext(context.applicationContext)
            Libv2ray.initCoreEnv(context.filesDir.absolutePath, "")
            envReady = true
            Log.i(TAG, Libv2ray.checkVersionX())
        }
    }

    suspend fun connect(
        context: Context,
        vlessUri: String,
        remark: String,
        blockedApps: List<String>?,
    ): Result<Unit> {
        val deferred = CompletableDeferred<Result<Unit>>()
        synchronized(lock) {
            pendingConnect?.complete(Result.failure(IOException("superseded")))
            pendingConnect = deferred
        }
        val intent = Intent(context, XrayVpnService::class.java)
            .setAction(XrayVpnService.ACTION_START)
            .putExtra(XrayVpnService.EXTRA_URI, vlessUri)
            .putExtra(XrayVpnService.EXTRA_REMARK, remark)
            .putStringArrayListExtra(
                XrayVpnService.EXTRA_BLOCKED_APPS,
                ArrayList(blockedApps.orEmpty()),
            )
        try {
            ContextCompat.startForegroundService(context, intent)
        } catch (e: Exception) {
            synchronized(lock) { if (pendingConnect === deferred) pendingConnect = null }
            return Result.failure(e)
        }
        val result = withTimeoutOrNull(CONNECT_TIMEOUT_MS) { deferred.await() }
        if (result != null) return result
        synchronized(lock) { if (pendingConnect === deferred) pendingConnect = null }
        disconnect()
        return Result.failure(XrayUnreachableException("xray connect timeout"))
    }

    /** Stops the tunnel if it runs and waits (bounded) until it is down. */
    fun hasRunningService(): Boolean = XrayVpnService.instance != null

    suspend fun disconnect(): Result<Unit> {
        val service = XrayVpnService.instance ?: run {
            // Nothing runs: reset silently so callers starting another engine
            // do not get a stray DISCONNECTED event.
            state = State.DISCONNECTED
            return Result.success(Unit)
        }
        val waiter = CompletableDeferred<Unit>()
        synchronized(lock) {
            pendingConnect?.complete(Result.failure(IOException("cancelled")))
            pendingConnect = null
            pendingStop = waiter
        }
        service.requestStop()
        withTimeoutOrNull(STOP_TIMEOUT_MS) { waiter.await() }
        return Result.success(Unit)
    }

    /** A stop request lost to a newer start: release its waiter only. */
    internal fun onStopSuperseded() {
        val stop = synchronized(lock) { pendingStop.also { pendingStop = null } }
        stop?.complete(Unit)
    }

    internal fun onState(newState: State, error: Throwable? = null) {
        state = newState
        val connect: CompletableDeferred<Result<Unit>>?
        val stop: CompletableDeferred<Unit>?
        synchronized(lock) {
            if (newState == State.CONNECTING) {
                rxTotal = 0L
                txTotal = 0L
            }
            connect = if (newState != State.CONNECTING) pendingConnect else null
            if (connect != null) pendingConnect = null
            stop = if (newState == State.DISCONNECTED || newState == State.ERROR) pendingStop else null
            if (stop != null) pendingStop = null
        }
        connect?.complete(
            if (newState == State.CONNECTED) {
                Result.success(Unit)
            } else {
                Result.failure(error ?: IOException("disconnected"))
            },
        )
        stop?.complete(Unit)
        try {
            listener?.invoke(newState)
        } catch (e: Exception) {
            Log.w(TAG, "state listener failed", e)
        }
    }

    /** Cumulative (rx, tx) bytes of the proxy outbound for the live session. */
    fun trafficTotals(): Pair<Long, Long> {
        val stats = try {
            controller?.queryAllOutboundTrafficStats().orEmpty()
        } catch (_: Exception) {
            ""
        }
        synchronized(lock) {
            // Format: tag,direction,value; — counters reset on every read.
            for (entry in stats.split(';')) {
                val parts = entry.split(',')
                if (parts.size != 3 || parts[0] != XrayConfigBuilder.PROXY_TAG) continue
                val value = parts[2].toLongOrNull() ?: continue
                when (parts[1]) {
                    "downlink" -> rxTotal += value
                    "uplink" -> txTotal += value
                }
            }
            return rxTotal to txTotal
        }
    }

    /** TCP connect time to the server in ms, or null when it is unreachable. */
    suspend fun ping(host: String, port: Int): Int? = withContext(Dispatchers.IO) {
        if (host.isBlank() || port !in 1..65535) return@withContext null
        try {
            Socket().use { socket ->
                val started = SystemClock.elapsedRealtime()
                socket.connect(InetSocketAddress(host, port), PING_TIMEOUT_MS)
                (SystemClock.elapsedRealtime() - started).toInt().coerceAtLeast(1)
            }
        } catch (_: Exception) {
            null
        }
    }
}
