package app.rabochiy.vpn.xray

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class XrayConfigBuilderTest {
    private val uuid = "00000000-0000-4000-8000-000000000001"

    private fun build(query: String, host: String = "203.0.113.5", port: Int = 443): JSONObject =
        JSONObject(XrayConfigBuilder.build(VlessLink.parse("vless://$uuid@$host:$port?$query#name")))

    private fun proxy(config: JSONObject): JSONObject =
        config.getJSONArray("outbounds").getJSONObject(0)

    @Test
    fun tunInboundAndDnsHijackAreAlwaysPresent() {
        val config = build("security=tls&type=ws&sni=example.com")
        val inbound = config.getJSONArray("inbounds").getJSONObject(0)
        assertEquals("tun", inbound.getString("protocol"))
        assertEquals(XrayConfigBuilder.TUN_MTU, inbound.getJSONObject("settings").getInt("MTU"))

        val dnsRule = config.getJSONObject("routing").getJSONArray("rules").getJSONObject(0)
        assertEquals("53", dnsRule.getString("port"))
        assertEquals("dns-out", dnsRule.getString("outboundTag"))
        assertEquals("UseIPv4", config.getJSONObject("dns").getString("queryStrategy"))
        assertEquals(XrayConfigBuilder.PROXY_TAG, proxy(config).getString("tag"))
    }

    @Test
    fun xhttpTlsKeepsExtraAndCleansAlpn() {
        val extra = java.net.URLEncoder.encode("""{"xPaddingBytes":"100-1000","headers":null}""", "UTF-8")
        val stream = proxy(
            build("encryption=none&security=tls&type=xhttp&mode=auto&path=%2Fx&host=cdn.example&sni=sni.example&fp=firefox&alpn=h2%2C%2Bhttp%2F1.1&extra=$extra"),
        ).getJSONObject("streamSettings")
        assertEquals("xhttp", stream.getString("network"))
        val xhttp = stream.getJSONObject("xhttpSettings")
        assertEquals("/x", xhttp.getString("path"))
        assertEquals("cdn.example", xhttp.getString("host"))
        assertEquals("auto", xhttp.getString("mode"))
        assertEquals("100-1000", xhttp.getJSONObject("extra").getString("xPaddingBytes"))
        val tls = stream.getJSONObject("tlsSettings")
        assertEquals("sni.example", tls.getString("serverName"))
        assertEquals("firefox", tls.getString("fingerprint"))
        assertEquals("[\"h2\",\"http/1.1\"]", tls.getJSONArray("alpn").toString())
    }

    @Test
    fun realityVisionOverRaw() {
        val out = proxy(build("security=reality&type=tcp&flow=xtls-rprx-vision&sni=www.example.com&pbk=PUBKEY&sid=ab12&spx=%2F&fp=random"))
        val user = out.getJSONObject("settings").getJSONArray("vnext").getJSONObject(0)
            .getJSONArray("users").getJSONObject(0)
        assertEquals(uuid, user.getString("id"))
        assertEquals("none", user.getString("encryption"))
        assertEquals("xtls-rprx-vision", user.getString("flow"))
        val stream = out.getJSONObject("streamSettings")
        assertEquals("raw", stream.getString("network"))
        val reality = stream.getJSONObject("realitySettings")
        assertEquals("PUBKEY", reality.getString("publicKey"))
        assertEquals("ab12", reality.getString("shortId"))
        assertEquals("www.example.com", reality.getString("serverName"))
    }

    @Test
    fun flowIsDroppedOutsideRaw() {
        val user = proxy(build("security=tls&type=ws&flow=xtls-rprx-vision"))
            .getJSONObject("settings").getJSONArray("vnext").getJSONObject(0)
            .getJSONArray("users").getJSONObject(0)
        assertFalse(user.has("flow"))
    }

    @Test
    fun grpcAndWsSettings() {
        val grpc = proxy(build("security=tls&type=grpc&serviceName=svc&mode=multi"))
            .getJSONObject("streamSettings").getJSONObject("grpcSettings")
        assertEquals("svc", grpc.getString("serviceName"))
        assertTrue(grpc.getBoolean("multiMode"))

        val stream = proxy(build("security=tls&type=ws&path=%2Fws%3Fed%3D2560&host=front.example"))
            .getJSONObject("streamSettings")
        assertEquals("/ws?ed=2560", stream.getJSONObject("wsSettings").getString("path"))
        // SNI falls back to the Host header when the link has none.
        assertEquals("front.example", stream.getJSONObject("tlsSettings").getString("serverName"))
    }

    @Test
    fun parsesIpv6AndRejectsBrokenLinks() {
        val link = VlessLink.parse("vless://$uuid@[2001:db8::1]:8443?security=none#x")
        assertEquals("2001:db8::1", link.host)
        assertEquals(8443, link.port)
        assertThrows(IllegalArgumentException::class.java) { VlessLink.parse("vmess://abc") }
        assertThrows(IllegalArgumentException::class.java) { VlessLink.parse("vless://host:443") }
        assertThrows(IllegalArgumentException::class.java) { VlessLink.parse("vless://$uuid@host:0") }
        assertThrows(IllegalArgumentException::class.java) { build("security=tls&type=kcp") }
        assertThrows(IllegalArgumentException::class.java) { build("security=reality&type=tcp") }
    }
}
