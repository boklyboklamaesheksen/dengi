package app.rabochiy.vpn

import android.content.Context
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.amnezia.awg.backend.Backend
import org.amnezia.awg.backend.BackendException
import org.amnezia.awg.backend.GoBackend
import org.amnezia.awg.backend.Statistics
import org.amnezia.awg.backend.Tunnel
import org.amnezia.awg.config.Config
import java.io.ByteArrayInputStream

/**
 * Kotlin manager that wraps the vendored [GoBackend] (AmneziaWG) and exposes
 * suspend-friendly methods for the Flutter [VpnService] bridge.
 *
 * One per process ([get]): the tunnel outlives MainActivity (swiped from
 * recents, recreated by the system), and a per-activity manager forgot the
 * running tunnel, so the reopened app showed "disconnected" and a new
 * connect leaked a second engine.
 *
 * Loads the Go runtime lazily on an IO worker. Java loading exceptions can
 * be reported to Flutter; a native SIGSEGV cannot be caught here.
 */
class AwgManager private constructor(private val context: Context) {
    companion object {
        private const val TAG = "RabochiyAwgManager"

        @Volatile
        private var instance: AwgManager? = null

        fun get(context: Context): AwgManager =
            instance ?: synchronized(this) {
                instance ?: AwgManager(context.applicationContext).also { instance = it }
            }

        /**
         * How long we wait for the first WireGuard handshake before
         * declaring the server unreachable. A healthy peer answers in well
         * under a second; the engine retransmits the initiation every 5 s,
         * so 20 s gives four attempts on slow or DPI-throttled links (and
         * matches the GW engine's connect timeout).
         */
        const val HANDSHAKE_TIMEOUT_MS = 20_000L
        private const val HANDSHAKE_POLL_MS = 250L

        /**
         * Keepalive injected when the server config lacks one. 25 s is the
         * de-facto WireGuard default for NATed clients.
         */
        private const val DEFAULT_KEEPALIVE_SEC = 25

        /** Static holder for excluded packages requested by the Flutter side. */
        @Volatile
        var excludedPackages: List<String>? = null
    }

    enum class State {
        DISCONNECTED,
        CONNECTING,
        CONNECTED,
        DISCONNECTING,
        ERROR
    }

    /** State callback of the current MainActivity; null while none is attached. */
    @Volatile
    var listener: ((State, Statistics?) -> Unit)? = null

    private fun onStateChange(state: State, stats: Statistics?) {
        try {
            listener?.invoke(state, stats)
        } catch (e: Exception) {
            Log.w(TAG, "state listener failed", e)
        }
    }

    @Volatile
    private var backend: Backend? = null
    @Volatile private var currentTunnel: Tunnel? = null
    private val operationMutex = Mutex()

    /**
     * Bumped by [disconnect] so an in-flight [connect] knows it was
     * cancelled: after `setState(UP)` completes it checks this counter
     * and immediately tears the tunnel down, instead of leaving a live
     * tunnel behind a "cancelled" UI state.
     */
    private val cancelGeneration = java.util.concurrent.atomic.AtomicInteger(0)
    @Volatile private var currentConfig: Config? = null

    /**
     * Lazily creates the [GoBackend] on first use. Subsequent calls reuse
     * the cached instance. Returns `null` when libwg-go.so cannot be loaded
     * on the current device.
     */
    private fun ensureBackend(): Backend? {
        backend?.let { return it }
        return try {
            val created = GoBackend(context.applicationContext)
            backend = created
            created
        } catch (t: Throwable) {
            Log.e(TAG, "Failed to create AmneziaWG backend", t)
            null
        }
    }

    /** Whether the manager thinks the tunnel is (or should be) up. */
    val isActive: Boolean
        get() = try {
            val b = backend ?: return false
            b.getState(tunnel()).let {
                it == Tunnel.State.UP || it == Tunnel.State.TOGGLE
            }
        } catch (_: Exception) {
            false
        }

    /** Current state exposed for reachability checks. */
    @Volatile
    var currentState: State = State.DISCONNECTED
        private set

    /** Returns true if a WireGuard handshake has occurred (server is alive). */
    fun isHandshakeAlive(): Boolean {
        val b = backend ?: return false
        val t = currentTunnel ?: return false
        return try {
            b.getLastHandshake(t) > 0L
        } catch (_: Exception) {
            false
        }
    }

    /**
     * Brings up an AmneziaWG tunnel using a base64-encoded `awg-quick`
     * configuration.
     *
     * WireGuard has no connection setup phase: `setState(UP)` only opens
     * the TUN device and starts the userspace engine, so it returns long
     * before (or regardless of whether) the server ever answers. To keep
     * the UI honest we stay in [State.CONNECTING] until the first
     * handshake completes and only then report [State.CONNECTED]. If no
     * handshake arrives within [HANDSHAKE_TIMEOUT_MS] the tunnel is torn
     * down and [State.ERROR] is reported instead of a fake "connected"
     * with a black-holed network.
     */
    suspend fun connect(
        remark: String,
        awgConfigBase64: String,
        blockedApps: List<String>? = null
    ): Result<Tunnel> {
        val gen = cancelGeneration.get()
        return withContext(Dispatchers.IO) {
            operationMutex.withLock {
                if (cancelGeneration.get() != gen) {
                    return@withLock Result.failure<Tunnel>(InterruptedException("cancelled"))
                }
                try {
                    currentState = State.CONNECTING
                    onStateChange(State.CONNECTING, null)

                    val b = ensureBackend() ?: run {
                        currentState = State.ERROR
                        onStateChange(State.ERROR, null)
                        return@withLock Result.failure<Tunnel>(
                            IllegalStateException("AmneziaWG backend unavailable on this device")
                        )
                    }

                    val configBytes = android.util.Base64.decode(
                        awgConfigBase64,
                        android.util.Base64.DEFAULT
                    )
                    // The 3.1 config parser owns per-app exclusions.
                    var configText = if (blockedApps.isNullOrEmpty()) {
                        String(configBytes, Charsets.UTF_8)
                    } else {
                        injectExcludedApplications(String(configBytes, Charsets.UTF_8), blockedApps)
                    }
                    // A keepalive makes the engine fire the first handshake
                    // immediately on UP (instead of waiting for user traffic)
                    // and keeps NAT mappings alive while the app is idle.
                    configText = ensurePersistentKeepalive(configText)
                    val config = Config.parse(ByteArrayInputStream(configText.toByteArray(Charsets.UTF_8)))

                    val sanitizedName = remark.take(Tunnel.NAME_MAX_LENGTH).ifEmpty { "rabochiy_awg" }
                    val tunnel = createTunnel(sanitizedName)

                    b.setState(tunnel, Tunnel.State.UP, config)
                    currentTunnel = tunnel
                    currentConfig = config

                    // Undo a tunnel raised after the user cancelled.
                    if (cancelGeneration.get() != gen) {
                        Log.i(TAG, "Connect was cancelled mid-handshake — rolling back")
                        tearDown(b, tunnel)
                        currentState = State.DISCONNECTED
                        onStateChange(State.DISCONNECTED, null)
                        return@withLock Result.failure<Tunnel>(InterruptedException("cancelled"))
                    }

                    val handshakeAt = awaitFirstHandshake(b, tunnel, gen)
                    if (cancelGeneration.get() != gen) {
                        Log.i(TAG, "Connect was cancelled while waiting for handshake — rolling back")
                        tearDown(b, tunnel)
                        currentState = State.DISCONNECTED
                        onStateChange(State.DISCONNECTED, null)
                        return@withLock Result.failure<Tunnel>(InterruptedException("cancelled"))
                    }
                    if (handshakeAt <= 0L) {
                        Log.w(TAG, "No AmneziaWG handshake within ${HANDSHAKE_TIMEOUT_MS} ms — server unreachable")
                        tearDown(b, tunnel)
                        currentState = State.ERROR
                        onStateChange(State.ERROR, null)
                        return@withLock Result.failure<Tunnel>(
                            java.net.SocketTimeoutException("awg_handshake_timeout")
                        )
                    }

                    currentState = State.CONNECTED
                    onStateChange(State.CONNECTED, b.getStatistics(tunnel))
                    Result.success(tunnel)
                } catch (e: BackendException) {
                    Log.e(TAG, "AWG backend error", e)
                    currentState = State.ERROR
                    onStateChange(State.ERROR, null)
                    Result.failure(e)
                } catch (e: Exception) {
                    Log.e(TAG, "Unexpected AWG error", e)
                    currentState = State.ERROR
                    onStateChange(State.ERROR, null)
                    Result.failure(e)
                }
            }
        }
    }

    /**
     * Polls the Go engine until the peer reports a handshake or the
     * deadline passes. Returns the handshake time (epoch ms) or 0 on
     * timeout. Bails out early if [disconnect] bumped the cancel counter.
     */
    private suspend fun awaitFirstHandshake(b: Backend, tunnel: Tunnel, gen: Int): Long {
        val deadline = android.os.SystemClock.elapsedRealtime() + HANDSHAKE_TIMEOUT_MS
        while (android.os.SystemClock.elapsedRealtime() < deadline) {
            if (cancelGeneration.get() != gen) return 0L
            val hs = try {
                b.getLastHandshake(tunnel)
            } catch (e: Exception) {
                Log.w(TAG, "getLastHandshake failed", e)
                -2L
            }
            // -3 == tunnel no longer active (torn down underneath us).
            if (hs == -3L) return 0L
            if (hs > 0L) return hs * 1000L
            delay(HANDSHAKE_POLL_MS)
        }
        return 0L
    }

    private fun tearDown(b: Backend, tunnel: Tunnel) {
        try {
            b.setState(tunnel, Tunnel.State.DOWN, null)
        } catch (e: Exception) {
            Log.w(TAG, "Tear-down after failed connect threw", e)
        }
        currentTunnel = null
        currentConfig = null
    }

    /**
     * Tears down the active tunnel.
     */
    suspend fun disconnect(): Result<Unit> {
        cancelGeneration.incrementAndGet()
        return withContext(Dispatchers.IO) {
            operationMutex.withLock {
                try {
                    currentState = State.DISCONNECTING
                    onStateChange(State.DISCONNECTING, null)
                    val b = backend ?: run {
                        currentState = State.DISCONNECTED
                        onStateChange(State.DISCONNECTED, null)
                        return@withLock Result.success(Unit)
                    }
                    val t = currentTunnel ?: createTunnel()
                    b.setState(t, Tunnel.State.DOWN, null)
                    currentTunnel = null
                    currentConfig = null
                    excludedPackages = null
                    currentState = State.DISCONNECTED
                    onStateChange(State.DISCONNECTED, null)
                    Result.success(Unit)
                } catch (e: Exception) {
                    Log.e(TAG, "Disconnect error", e)
                    currentState = State.ERROR
                    onStateChange(State.ERROR, null)
                    Result.failure(e)
                }
            }
        }
    }

    /**
     * Returns live statistics for the active tunnel or a default-zero
     * stats object when the backend is not yet initialised.
     */
    fun statistics(): Statistics? {
        val b = backend ?: return null
        val t = currentTunnel ?: return null
        return try {
            b.getStatistics(t)
        } catch (_: Exception) {
            null
        }
    }

    fun backendState(): Tunnel.State = try {
        backend?.getState(tunnel()) ?: Tunnel.State.DOWN
    } catch (_: Exception) {
        Tunnel.State.DOWN
    }

    /**
     * Best-effort ping via TCP connect to the peer endpoint extracted
     * from the parsed config. Returns null when we don't have a live
     * config or the probe times out.
     */
    suspend fun ping(): Int? = withContext(Dispatchers.IO) {
        try {
            val cfg = currentConfig ?: return@withContext null
            val peers = cfg.peers
            if (peers.isEmpty()) return@withContext null
            val peer = peers[0]
            val endpointOpt = peer.endpoint
            if (!endpointOpt.isPresent) return@withContext null
            val resolvedOpt = endpointOpt.get().resolved
            if (!resolvedOpt.isPresent) return@withContext null
            val resolved = resolvedOpt.get()
            val host = resolved.host
            val port = resolved.port

            val start = System.currentTimeMillis()
            java.net.Socket().use { socket ->
                socket.connect(java.net.InetSocketAddress(host, port), 3000)
            }
            (System.currentTimeMillis() - start).toInt()
        } catch (_: Exception) {
            null
        }
    }

    // ── Internal helpers ────────────────────────────────────────────────

    private fun createTunnel(name: String = "rabochiy_awg"): Tunnel {
        return object : Tunnel {
            override fun getName(): String = name
            override fun onStateChange(newState: Tunnel.State) {
                Log.d(TAG, "Tunnel state -> $newState")
                // Our own connect/disconnect hold the mutex and report state
                // themselves; outside of them DOWN means the system revoked
                // the VPN (another VPN app, settings, killed service). It was
                // only logged, so the UI kept "connected" with no tunnel.
                if (newState != Tunnel.State.DOWN || operationMutex.isLocked) return
                if (currentTunnel !== this) return
                currentTunnel = null
                currentConfig = null
                if (currentState == State.CONNECTED || currentState == State.CONNECTING) {
                    Log.w(TAG, "Tunnel torn down outside the app")
                    currentState = State.DISCONNECTED
                    onStateChange(State.DISCONNECTED, null)
                }
            }
        }
    }

    private fun tunnel(): Tunnel = currentTunnel ?: createTunnel()
    /**
     * Injects `ExcludedApplications = a, b, c` right after the `[Interface]`
     * header line. The 3.1 config parser merges repeated attributes, so a
     * server-provided exclusion list (if any) is preserved.
     */
    private fun injectExcludedApplications(configText: String, packages: List<String>): String {
        return try {
            if (packages.isEmpty()) return configText
            val lines = configText.lines().toMutableList()
            val interfaceIndex = lines.indexOfFirst {
                it.trim().equals("[Interface]", ignoreCase = true)
            }
            if (interfaceIndex == -1) {
                Log.w(TAG, "No [Interface] section in AWG config, skip split tunneling")
                return configText
            }
            lines.add(interfaceIndex + 1, "ExcludedApplications = " + packages.joinToString(", "))
            lines.joinToString("\n")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to apply split tunneling to AWG config", e)
            configText
        }
    }

    /**
     * Adds `PersistentKeepalive = 25` to every `[Peer]` section that does
     * not already declare one. Server-provided values are left untouched.
     */
    private fun ensurePersistentKeepalive(configText: String): String {
        return try {
            val lines = configText.lines().toMutableList()
            val out = ArrayList<String>(lines.size + 2)
            var inPeer = false
            var peerHasKeepalive = false
            fun closePeer() {
                if (inPeer && !peerHasKeepalive) {
                    out.add("PersistentKeepalive = $DEFAULT_KEEPALIVE_SEC")
                }
            }
            for (line in lines) {
                val trimmed = line.trim()
                if (trimmed.startsWith("[")) {
                    closePeer()
                    inPeer = trimmed.equals("[Peer]", ignoreCase = true)
                    peerHasKeepalive = false
                } else if (inPeer) {
                    val key = trimmed.substringBefore('=').trim()
                    if (key.equals("PersistentKeepalive", ignoreCase = true)) {
                        peerHasKeepalive = true
                    }
                }
                out.add(line)
            }
            closePeer()
            out.joinToString("\n")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to inject keepalive into AWG config", e)
            configText
        }
    }

}
