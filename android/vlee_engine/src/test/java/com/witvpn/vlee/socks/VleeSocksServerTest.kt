package com.witvpn.vlee.socks

import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.DataInputStream
import java.io.DataOutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.Socket
import java.util.concurrent.atomic.AtomicInteger

/**
 * Resource bounds of the SOCKS front-end on the plain JVM. The Play Console
 * OutOfMemoryError crashes came from UDP associations that never ended and
 * from unbounded thread creation; these tests pin both down.
 */
class VleeSocksServerTest {
    private val loopback = InetAddress.getByName("127.0.0.1")
    private val clients = mutableListOf<Socket>()
    private var server: VleeSocksServer? = null

    private fun start(
        idleMs: Long = 60_000L,
        resolver: ((String, ByteArray) -> ByteArray?)? = null,
    ): VleeSocksServer =
        VleeSocksServer(
            transportProvider = { null },
            udpIdleTimeoutMs = idleMs,
            dnsResolver = resolver,
        ).also {
            it.start()
            server = it
        }

    @After
    fun tearDown() {
        clients.forEach { runCatching { it.close() } }
        server?.stop()
        // Pools use fixed thread names; let this server's threads exit before the next test counts them.
        eventually { threads("vlee-") == 0 }
    }

    @Test
    fun udpAssociationsDoNotPinWorkerThreads() {
        val server = start()
        repeat(200) { associate(server) }
        eventually { server.activeConnections == 200L }
        // Previously every association parked its own worker thread forever.
        assertTrue(threads("vlee-socks-worker") < 32)
    }

    @Test
    fun idleUdpAssociationIsClosed() {
        val server = start(idleMs = 300)
        val (control, _) = associate(server)
        eventually { server.activeConnections == 0L }
        control.soTimeout = 3_000
        assertEquals(-1, control.getInputStream().read())
    }

    @Test
    fun udpAssociationCountIsCapped() {
        val server = start()
        val idlest = associate(server).first
        Thread.sleep(20)
        repeat(VleeSocksServer.MAX_UDP_ASSOCIATIONS) { associate(server) }
        eventually { server.activeConnections == VleeSocksServer.MAX_UDP_ASSOCIATIONS.toLong() }
        idlest.soTimeout = 3_000
        assertEquals(-1, idlest.getInputStream().read())
    }

    @Test
    fun nonDnsDatagramsAreDroppedWithoutWorkers() {
        val server = start()
        val (_, port) = associate(server)
        DatagramSocket().use { udp ->
            val packet = header(byteArrayOf(1, 1, 1, 1), 443) + ByteArray(1200)
            repeat(500) { udp.send(DatagramPacket(packet, packet.size, loopback, port)) }
        }
        Thread.sleep(300)
        assertEquals(0, threads("vlee-udp-relay"))
    }

    @Test
    fun dnsReplyUsesQueriedServerAddressAndRetransmitsHitCache() {
        val upstreamCalls = AtomicInteger()
        val server = start(resolver = { _, query ->
            upstreamCalls.incrementAndGet()
            // Minimal response: echo the ID, QR+RD+RA flags, no records.
            byteArrayOf(query[0], query[1], 0x81.toByte(), 0x80.toByte()) + ByteArray(8)
        })
        val (_, port) = associate(server)
        val header = header(byteArrayOf(8, 8, 8, 8), 53)
        val query = byteArrayOf(0x12, 0x34, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0) +
            byteArrayOf(7) + "example".toByteArray() + byteArrayOf(3) + "com".toByteArray() +
            byteArrayOf(0, 0, 1, 0, 1)
        DatagramSocket().use { udp ->
            udp.soTimeout = 5_000
            repeat(2) {
                udp.send(DatagramPacket(header + query, header.size + query.size, loopback, port))
                val buf = ByteArray(1500)
                val reply = DatagramPacket(buf, buf.size)
                udp.receive(reply)
                // The source must be the server the app queried (never 127.0.0.53):
                // tun2socks uses this address as the reply's source.
                assertArrayEquals(header, buf.copyOfRange(0, 10))
                assertEquals(0x12, buf[10].toInt())
                assertEquals(0x34, buf[11].toInt())
            }
        }
        assertEquals(1, upstreamCalls.get())
    }

    @Test
    fun dnsFloodUsesBoundedThreads() {
        val server = start(resolver = { _, _ ->
            Thread.sleep(200)
            null
        })
        val (_, port) = associate(server)
        DatagramSocket().use { udp ->
            repeat(1_000) { i ->
                val query = byteArrayOf((i shr 8).toByte(), i.toByte()) + ByteArray(20)
                val packet = header(byteArrayOf(8, 8, 8, 8), 53) + query
                udp.send(DatagramPacket(packet, packet.size, loopback, port))
            }
        }
        Thread.sleep(500)
        assertTrue(threads("vlee-udp-relay") <= 8)
        assertTrue(threads("vlee-dns-tcp") <= 8)
    }

    @Test
    fun sessionsAreBoundedAndExcessClientsAreRejected() {
        val server = start()
        // Clients that never send the handshake each hold one session worker.
        repeat(VleeSocksServer.MAX_SESSIONS) { clients += Socket(loopback, server.port) }
        eventually { threads("vlee-socks-worker") == VleeSocksServer.MAX_SESSIONS }

        val extra = Socket(loopback, server.port).also { clients += it }
        extra.soTimeout = 3_000
        assertEquals(-1, extra.getInputStream().read())
        assertEquals(VleeSocksServer.MAX_SESSIONS, threads("vlee-socks-worker"))

        // A freed slot is reused for new clients.
        clients.first().close()
        eventually { runCatching { associate(server) }.isSuccess }
    }

    /** Performs the SOCKS5 greeting and UDP ASSOCIATE; returns the control socket and relay port. */
    private fun associate(server: VleeSocksServer): Pair<Socket, Int> {
        val socket = Socket(loopback, server.port).also { clients += it }
        socket.soTimeout = 5_000
        val out = DataOutputStream(socket.getOutputStream())
        val input = DataInputStream(socket.getInputStream())
        out.write(byteArrayOf(5, 1, 0))
        out.flush()
        assertEquals(5, input.readUnsignedByte())
        assertEquals(0, input.readUnsignedByte())
        out.write(byteArrayOf(5, 3, 0, 1, 0, 0, 0, 0, 0, 0))
        out.flush()
        val reply = ByteArray(10)
        input.readFully(reply)
        assertEquals(0, reply[1].toInt())
        return socket to (((reply[8].toInt() and 0xFF) shl 8) or (reply[9].toInt() and 0xFF))
    }

    private fun header(ipv4: ByteArray, port: Int): ByteArray =
        byteArrayOf(0, 0, 0, 1) + ipv4 + byteArrayOf((port shr 8).toByte(), port.toByte())

    private fun threads(prefix: String): Int =
        Thread.getAllStackTraces().keys.count { it.isAlive && it.name.startsWith(prefix) }

    private fun eventually(timeoutMs: Long = 10_000, condition: () -> Boolean) {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            if (condition()) return
            Thread.sleep(50)
        }
        assertTrue("condition not met within $timeoutMs ms", condition())
    }
}
