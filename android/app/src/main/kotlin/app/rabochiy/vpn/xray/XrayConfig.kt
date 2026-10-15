package app.rabochiy.vpn.xray

import org.json.JSONArray
import org.json.JSONObject
import java.net.URLDecoder

/** Parsed `vless://` share link (v2rayN / Xray URI scheme). */
class VlessLink private constructor(
    val uuid: String,
    val host: String,
    val port: Int,
    private val params: Map<String, String>,
) {
    fun param(name: String): String = params[name]?.trim().orEmpty()

    /** Xray transport name; legacy `tcp` / `splithttp` map to their current names. */
    val network: String
        get() = when (val type = param("type").lowercase()) {
            "", "tcp", "raw" -> "raw"
            "splithttp" -> "xhttp"
            else -> type
        }

    val security: String
        get() = param("security").lowercase().ifEmpty { "none" }

    companion object {
        fun parse(raw: String): VlessLink {
            var rest = raw.trim()
            require(rest.startsWith("vless://", ignoreCase = true)) { "not a vless link" }
            rest = rest.substring("vless://".length).substringBefore('#')
            val query = rest.substringAfter('?', "")
            val authority = rest.substringBefore('?').trimEnd('/')

            val at = authority.lastIndexOf('@')
            require(at > 0) { "vless link without user id" }
            val uuid = decode(authority.substring(0, at))
            val hostPort = authority.substring(at + 1)

            val host: String
            val portText: String
            if (hostPort.startsWith("[")) {
                val end = hostPort.indexOf(']')
                require(end > 1) { "bad IPv6 host" }
                host = hostPort.substring(1, end)
                portText = hostPort.substring(end + 1).removePrefix(":")
            } else {
                val colon = hostPort.lastIndexOf(':')
                require(colon > 0) { "vless link without port" }
                host = hostPort.substring(0, colon)
                portText = hostPort.substring(colon + 1)
            }
            val port = portText.toIntOrNull()
            require(port != null && port in 1..65535) { "bad port" }
            require(uuid.isNotBlank() && host.isNotBlank()) { "incomplete vless link" }

            val params = LinkedHashMap<String, String>()
            for (pair in query.split('&')) {
                if (pair.isEmpty()) continue
                val key = decode(pair.substringBefore('='))
                if (key.isNotEmpty()) params[key] = decode(pair.substringAfter('=', ""))
            }
            return VlessLink(uuid, host, port, params)
        }

        // '+' is literal in share links; only %XX sequences are escapes.
        private fun decode(value: String): String = try {
            URLDecoder.decode(value.replace("+", "%2B"), "UTF-8")
        } catch (_: IllegalArgumentException) {
            value
        }
    }
}

/**
 * Builds a full Xray-core JSON config for one VLESS server in VPN mode:
 * the TUN fd is handed to Xray's own `tun` inbound, every DNS query from the
 * tunnel is answered by Xray's DNS module whose upstreams are reached through
 * the proxy, and IPv6 is not routed at all (blocked by the VpnService).
 */
object XrayConfigBuilder {
    const val TUN_MTU = 1500
    const val PROXY_TAG = "proxy"

    private val SUPPORTED_NETWORKS = setOf("raw", "ws", "grpc", "xhttp", "httpupgrade")

    private val LOCAL_RANGES = listOf(
        "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "169.254.0.0/16",
        "100.64.0.0/10", "224.0.0.0/4", "255.255.255.255/32", "fc00::/7", "fe80::/10",
    )

    fun build(link: VlessLink): String {
        val root = JSONObject()
        root.put("log", JSONObject().put("loglevel", "warning").put("access", "none"))
        root.put("stats", JSONObject())
        root.put(
            "policy",
            JSONObject()
                .put(
                    "levels",
                    JSONObject().put(
                        "8",
                        JSONObject()
                            .put("handshake", 4)
                            .put("connIdle", 300)
                            .put("uplinkOnly", 1)
                            .put("downlinkOnly", 1),
                    ),
                )
                .put(
                    "system",
                    JSONObject().put("statsOutboundUplink", true).put("statsOutboundDownlink", true),
                ),
        )
        // DoH over TCP first (survives servers without UDP), plain UDP last.
        root.put(
            "dns",
            JSONObject()
                .put(
                    "servers",
                    JSONArray()
                        .put("https://1.1.1.1/dns-query")
                        .put("https://8.8.8.8/dns-query")
                        .put("1.1.1.1"),
                )
                .put("queryStrategy", "UseIPv4"),
        )
        root.put(
            "inbounds",
            JSONArray().put(
                JSONObject()
                    .put("tag", "tun")
                    .put("protocol", "tun")
                    .put(
                        "settings",
                        JSONObject().put("name", "xray0").put("MTU", TUN_MTU).put("userLevel", 8),
                    )
                    .put(
                        "sniffing",
                        JSONObject()
                            .put("enabled", true)
                            .put("destOverride", JSONArray().put("http").put("tls").put("quic"))
                            .put("routeOnly", true),
                    ),
            ),
        )
        root.put(
            "outbounds",
            JSONArray()
                .put(proxyOutbound(link))
                .put(JSONObject().put("tag", "direct").put("protocol", "freedom"))
                .put(JSONObject().put("tag", "block").put("protocol", "blackhole"))
                .put(JSONObject().put("tag", "dns-out").put("protocol", "dns")),
        )
        root.put(
            "routing",
            JSONObject()
                .put("domainStrategy", "AsIs")
                .put(
                    "rules",
                    JSONArray()
                        .put(
                            JSONObject()
                                .put("type", "field")
                                .put("inboundTag", JSONArray().put("tun"))
                                .put("port", "53")
                                .put("outboundTag", "dns-out"),
                        )
                        .put(
                            JSONObject()
                                .put("type", "field")
                                .put("ip", JSONArray(LOCAL_RANGES))
                                .put("outboundTag", "direct"),
                        ),
                ),
        )
        return root.toString()
    }

    private fun proxyOutbound(link: VlessLink): JSONObject {
        val network = link.network
        require(network in SUPPORTED_NETWORKS) { "unsupported transport: $network" }
        val security = link.security
        require(security in setOf("none", "tls", "reality")) { "unsupported security: $security" }

        val user = JSONObject()
            .put("id", link.uuid)
            .put("encryption", link.param("encryption").ifEmpty { "none" })
            .put("level", 8)
        val flow = link.param("flow")
        // Vision only works over raw TLS/REALITY; elsewhere Xray rejects it.
        if (flow.isNotEmpty() && network == "raw" && security != "none") user.put("flow", flow)

        val stream = JSONObject().put("network", network).put("security", security)
        val hostHeader = link.param("host")
        val path = link.param("path")
        when (network) {
            "raw" -> if (link.param("headerType").equals("http", ignoreCase = true)) {
                val request = JSONObject()
                    .put("path", JSONArray().put(path.ifEmpty { "/" }))
                if (hostHeader.isNotEmpty()) {
                    request.put(
                        "headers",
                        JSONObject().put("Host", JSONArray(hostHeader.split(',').map { it.trim() })),
                    )
                }
                stream.put(
                    "rawSettings",
                    JSONObject().put("header", JSONObject().put("type", "http").put("request", request)),
                )
            }
            "ws" -> stream.put(
                "wsSettings",
                JSONObject().put("path", path.ifEmpty { "/" }).apply {
                    if (hostHeader.isNotEmpty()) put("host", hostHeader)
                },
            )
            "httpupgrade" -> stream.put(
                "httpupgradeSettings",
                JSONObject().put("path", path.ifEmpty { "/" }).apply {
                    if (hostHeader.isNotEmpty()) put("host", hostHeader)
                },
            )
            "grpc" -> stream.put(
                "grpcSettings",
                JSONObject()
                    .put("serviceName", link.param("serviceName").ifEmpty { path })
                    .put("multiMode", link.param("mode").equals("multi", ignoreCase = true))
                    .apply {
                        val authority = link.param("authority")
                        if (authority.isNotEmpty()) put("authority", authority)
                    },
            )
            "xhttp" -> stream.put(
                "xhttpSettings",
                JSONObject().put("path", path.ifEmpty { "/" }).apply {
                    if (hostHeader.isNotEmpty()) put("host", hostHeader)
                    val mode = link.param("mode")
                    if (mode.isNotEmpty()) put("mode", mode)
                    parseObject(link.param("extra"))?.let { put("extra", it) }
                },
            )
        }

        val sni = link.param("sni").ifEmpty { link.param("peer") }.ifEmpty { hostHeader.substringBefore(',') }
        val fingerprint = link.param("fp").ifEmpty { "chrome" }
        when (security) {
            "tls" -> stream.put(
                "tlsSettings",
                JSONObject().put("fingerprint", fingerprint).apply {
                    if (sni.isNotEmpty()) put("serverName", sni)
                    val alpn = parseAlpn(link.param("alpn"))
                    if (alpn.length() > 0) put("alpn", alpn)
                },
            )
            "reality" -> {
                val publicKey = link.param("pbk")
                require(publicKey.isNotEmpty()) { "reality link without public key" }
                stream.put(
                    "realitySettings",
                    JSONObject()
                        .put("fingerprint", fingerprint)
                        .put("publicKey", publicKey)
                        .put("shortId", link.param("sid"))
                        .put("spiderX", link.param("spx"))
                        .apply {
                            if (sni.isNotEmpty()) put("serverName", sni)
                            val pqv = link.param("pqv")
                            if (pqv.isNotEmpty()) put("mldsa65Verify", pqv)
                        },
                )
            }
        }

        return JSONObject()
            .put("tag", PROXY_TAG)
            .put("protocol", "vless")
            .put(
                "settings",
                JSONObject().put(
                    "vnext",
                    JSONArray().put(
                        JSONObject()
                            .put("address", link.host)
                            .put("port", link.port)
                            .put("users", JSONArray().put(user)),
                    ),
                ),
            )
            .put("streamSettings", stream)
    }

    private fun parseAlpn(raw: String): JSONArray {
        val out = JSONArray()
        raw.split(',')
            .map { it.trim().trim('+').trim() }
            .filter { it.isNotEmpty() }
            .distinct()
            .forEach { out.put(it) }
        return out
    }

    private fun parseObject(raw: String): JSONObject? {
        if (raw.isEmpty()) return null
        return try {
            JSONObject(raw)
        } catch (_: Exception) {
            null
        }
    }
}
