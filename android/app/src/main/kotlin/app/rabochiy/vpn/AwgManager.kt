package app.rabochiy.vpn

import android.content.Context
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
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
 * The [GoBackend] constructor loads `libwg-go.so` (the Go runtime). On some
 * devices (notably Honor / Huawei EMUI 9-10 on Kirin SoCs) loading the Go
 * runtime from the main thread at app startup triggers a non-catchable
 * native crash. To stay safe we:
 *   * defer backend creation to the first connect call (`ensureBackend`),
 *   * run that creation on the IO dispatcher,
 *   * surface a regular [Result.failure] when the load fails so the
 *     Flutter side can show a user-friendly error instead of crashing.
 */
class AwgManager(
    private val context: Context,
    private val onStateChange: (State, Statistics?) -> Unit
) {
    companion object {
        private const val TAG = "RabochiyAwgManager"

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

    @Volatile
    private var backend: Backend? = null
    private var currentTunnel: Tunnel? = null

    /**
     * Bumped by [disconnect] so an in-flight [connect] knows it was
     * cancelled: after `setState(UP)` completes it checks this counter
     * and immediately tears the tunnel down, instead of leaving a live
     * tunnel behind a "cancelled" UI state.
     */
    private val cancelGeneration = java.util.concurrent.atomic.AtomicInteger(0)
    private var currentConfig: Config? = null

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
            val stats = b.getStatistics(t)
            stats.totalRx() > 0 || stats.totalTx() > 0
        } catch (_: Exception) {
            false
        }
    }

    /**
     * Brings up an AmneziaWG tunnel using a base64-encoded `awg-quick`
     * configuration.
     */
    suspend fun connect(
        remark: String,
        awgConfigBase64: String,
        blockedApps: List<String>? = null
    ): Result<Tunnel> = withContext(Dispatchers.IO) {
        val gen = cancelGeneration.get()
        try {
            currentState = State.CONNECTING
            onStateChange(State.CONNECTING, null)

            val b = ensureBackend() ?: run {
                onStateChange(State.ERROR, null)
                return@withContext Result.failure<Tunnel>(
                    IllegalStateException("AmneziaWG backend unavailable on this device")
                )
            }

            val configBytes = android.util.Base64.decode(
                awgConfigBase64,
                android.util.Base64.DEFAULT
            )
            // Split tunneling is injected as an ExcludedApplications line of
            // the [Interface] section — the static GoBackend.excludedPackages
            // hook no longer exists in the AmneziaWG 3.1 module.
            val configText = if (blockedApps.isNullOrEmpty()) {
                String(configBytes, Charsets.UTF_8)
            } else {
                Log.d(TAG, "Excluded packages: $blockedApps")
                injectExcludedApplications(String(configBytes, Charsets.UTF_8), blockedApps)
            }
            val config = Config.parse(ByteArrayInputStream(configText.toByteArray(Charsets.UTF_8)))
            currentConfig = config

            // Sanitize tunnel name to max 15 chars (Tunnel.NAME_MAX_LENGTH).
            val sanitizedName = remark.take(Tunnel.NAME_MAX_LENGTH).ifEmpty { "rabochiy_awg" }
            val tunnel = createTunnel(sanitizedName)
            currentTunnel = tunnel

            b.setState(tunnel, Tunnel.State.UP, config)

            // The user cancelled while the handshake was in flight —
            // tear the just-raised tunnel straight back down.
            if (cancelGeneration.get() != gen) {
                Log.i(TAG, "Connect was cancelled mid-handshake — rolling back")
                try {
                    b.setState(tunnel, Tunnel.State.DOWN, null)
                } catch (e: Exception) {
                    Log.w(TAG, "Rollback after cancel failed", e)
                }
                currentTunnel = null
                currentConfig = null
                currentState = State.DISCONNECTED
                onStateChange(State.DISCONNECTED, null)
                return@withContext Result.failure<Tunnel>(
                    InterruptedException("cancelled")
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

    /**
     * Tears down the active tunnel.
     */
    suspend fun disconnect(): Result<Unit> = withContext(Dispatchers.IO) {
        try {
            cancelGeneration.incrementAndGet()
            onStateChange(State.DISCONNECTING, null)
            val b = backend ?: run {
                // Nothing was ever started — treat as a clean state.
                onStateChange(State.DISCONNECTED, null)
                return@withContext Result.success(Unit)
            }
            val t = currentTunnel ?: createTunnel()
            b.setState(t, Tunnel.State.DOWN, null)
            currentTunnel = null
            currentConfig = null
            excludedPackages = null
            onStateChange(State.DISCONNECTED, null)
            Result.success(Unit)
        } catch (e: Exception) {
            Log.e(TAG, "Disconnect error", e)
            onStateChange(State.ERROR, null)
            Result.failure(e)
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

}
