package com.witvpn.vlee.socks

import android.util.Log
import com.witvpn.vlee.ssh.VleeSshTransport
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.IOException
import java.io.OutputStream
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.SocketAddress
import java.net.StandardProtocolFamily
import java.nio.ByteBuffer
import java.nio.channels.CancelledKeyException
import java.nio.channels.ClosedSelectorException
import java.nio.channels.DatagramChannel
import java.nio.channels.SelectionKey
import java.nio.channels.Selector
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.BlockingQueue
import java.util.concurrent.Callable
import java.util.concurrent.CompletableFuture
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.CountDownLatch
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.SynchronousQueue
import java.util.concurrent.ThreadFactory
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong

/**
 * SOCKS5-фронтенд для tun2socks.
 *
 * Транспорт берётся через [transportProvider], а не передаётся один раз: при
 * обрыве сети SSH пересобирается заново, и если бы ссылка была фиксированной,
 * пришлось бы поднимать заново весь стек — новый порт, новый yaml, перезапуск
 * tun2socks, пересоздание TUN. Теперь порт и tun живут через переподключения
 * нетронутыми, а меняется только транспорт под ними.
 *
 * Все ресурсы ограничены сверху: пулы потоков, очереди, число UDP-ассоциаций и
 * DNS-кэш. Раньше UDP-ассоциацию закрывало только наше собственное закрытие
 * сокета, которого никогда не было, — каждый UDP-поток через tun2socks навсегда
 * оставлял поток и буфер 64 КБ, и через несколько часов процесс падал с
 * OutOfMemoryError (куча или pthread_create).
 *
 * @param udpIdleTimeoutMs через сколько молчащая UDP-ассоциация закрывается.
 * @param dnsResolver подмена DNS-over-TCP резолва (host, запрос) -> ответ; для тестов.
 */
class VleeSocksServer(
    private val transportProvider: () -> VleeSshTransport?,
    private val onTransportFailure: () -> Unit = {},
    private val dnsOverTcp: Boolean = true,
    private val udpIdleTimeoutMs: Long = UDP_IDLE_TIMEOUT_MS,
    private val dnsResolver: ((String, ByteArray) -> ByteArray?)? = null,
) {
    companion object {
        private const val TAG = "VleeSocks"
        private const val VERSION = 0x05
        private const val CMD_CONNECT = 0x01
        private const val CMD_UDP_ASSOCIATE = 0x03
        private const val ATYP_IPV4 = 0x01
        private const val ATYP_DOMAIN = 0x03
        private const val ATYP_IPV6 = 0x04
        private const val DNS_PORT = 53
        private const val DNS_TCP_TIMEOUT_MS = 5000
        private const val DNS_WORKERS = 8
        private const val RELAY_BUFFER_BYTES = 16 * 1024
        /** Сколько ждём догрузки ответа после EOF от приложения. */
        private const val RELAY_DRAIN_TIMEOUT_MS = 30_000L

        /**
         * Сколько подряд неудачных открытий канала считаем приговором транспорту.
         * Один отказ — это чаще всего недоступный адрес и рвать туннель незачем;
         * а вот когда падает всё подряд, соединение мертво, даже если TCP об этом
         * ещё не знает (оборванный Wi-Fi выглядит именно так).
         */
        private const val DEAD_AFTER_FAILURES = 3

        /**
         * Одновременных SOCKS-сессий; CONNECT занимает два потока. Сверх лимита
         * клиенту сразу отказываем: это лучше, чем уронить процесс.
         */
        internal const val MAX_SESSIONS = 128

        /** UDP-ассоциаций одновременно; при переполнении закрывается самая тихая. */
        internal const val MAX_UDP_ASSOCIATIONS = 256

        /** Меньше, чем hev держит сессию (60 с): закрываем первыми, он видит EOF. */
        private const val UDP_IDLE_TIMEOUT_MS = 30_000L
        private const val UDP_SWEEP_MS = 1_000L
        private const val UDP_READS_PER_WAKEUP = 32
        private const val UDP_BUFFER_BYTES = 65_535
        private const val UDP_RELAY_WORKERS = 8
        private const val UDP_RELAY_QUEUE = 128
        private const val DNS_QUEUE = 64
        private const val DNS_CACHE_MAX = 512

        /** Ключ кэша содержит ID запроса, поэтому кэш ловит только ретрансмиты. */
        private const val DNS_CACHE_TTL_MS = 15_000L
        private const val POOL_KEEPALIVE_SEC = 30L
        private const val ACCEPT_BACKOFF_MS = 200L
        private const val LOG_INTERVAL_MS = 10_000L

        private val SUCCESS_REPLY = byteArrayOf(VERSION.toByte(), 0x00, 0x00, ATYP_IPV4.toByte(), 0, 0, 0, 0, 0, 0)
        private val GENERAL_FAILURE = byteArrayOf(VERSION.toByte(), 0x01, 0x00, ATYP_IPV4.toByte(), 0, 0, 0, 0, 0, 0)
        private val CMD_UNSUPPORTED = byteArrayOf(VERSION.toByte(), 0x07, 0x00, ATYP_IPV4.toByte(), 0, 0, 0, 0, 0, 0)

        private fun nowMs(): Long = System.nanoTime() / 1_000_000

        /**
         * Задачи сами ловят Throwable, так что сюда доходят только сбои самого
         * ThreadPoolExecutor (OutOfMemoryError от pthread_create при замене
         * воркера). Раньше такой сбой убивал весь процесс.
         */
        private val LOG_UNCAUGHT = Thread.UncaughtExceptionHandler { t, e ->
            Log.e(TAG, "uncaught in ${t.name}", e)
        }

        private fun daemonThreads(name: String): ThreadFactory {
            val seq = AtomicInteger()
            return ThreadFactory { r ->
                Thread(r, "$name-${seq.incrementAndGet()}").apply {
                    isDaemon = true
                    uncaughtExceptionHandler = LOG_UNCAUGHT
                }
            }
        }

        /** Переиспользует свободные потоки, растёт до [max], дальше — отказ. */
        private fun elasticPool(name: String, max: Int) = ThreadPoolExecutor(
            0, max, POOL_KEEPALIVE_SEC, TimeUnit.SECONDS,
            SynchronousQueue<Runnable>(), daemonThreads(name),
        )

        private fun fixedPool(name: String, threads: Int, queue: BlockingQueue<Runnable>) =
            ThreadPoolExecutor(
                threads, threads, POOL_KEEPALIVE_SEC, TimeUnit.SECONDS, queue, daemonThreads(name),
            ).apply { allowCoreThreadTimeOut(true) }
    }

    /** Предупреждение не чаще раза в [LOG_INTERVAL_MS]: UDP-флуд не должен забивать logcat. */
    private class ThrottledLog {
        private val last = AtomicLong(nowMs() - LOG_INTERVAL_MS)
        private val suppressed = AtomicInteger()

        fun warn(message: () -> String) {
            val now = nowMs()
            val prev = last.get()
            if (now - prev < LOG_INTERVAL_MS || !last.compareAndSet(prev, now)) {
                suppressed.incrementAndGet()
                return
            }
            val skipped = suppressed.getAndSet(0)
            Log.w(TAG, if (skipped == 0) message() else "${message()} (+$skipped similar)")
        }
    }

    private class DnsCacheEntry(val response: ByteArray, val expiresAtMs: Long)

    private var serverSocket: ServerSocket? = null
    @Volatile private var stopped = false

    /** Рукопожатия и CONNECT-сессии (download-половина работает здесь же). */
    private val sessionExecutor = elasticPool("vlee-socks-worker", MAX_SESSIONS)

    /** Upload-половина CONNECT: сессий не больше MAX_SESSIONS, значит и насосов. */
    private val pumpExecutor = elasticPool("vlee-socks-up", MAX_SESSIONS)

    /** DNS-датаграммы ждут ответа здесь; переполнение очереди = потеря датаграммы. */
    private val udpRelayExecutor =
        fixedPool("vlee-udp-relay", UDP_RELAY_WORKERS, ArrayBlockingQueue(UDP_RELAY_QUEUE))

    // DNS-over-TCP резолвы идут параллельно: один медленный апстрим не должен
    // задерживать остальные запросы (раньше единственный поток + таймаут 5 с
    // на запрос выстраивали все резолвы страницы в очередь).
    private val dnsExecutor = fixedPool("vlee-dns-tcp", DNS_WORKERS, ArrayBlockingQueue(DNS_QUEUE))

    // Все UDP-ассоциации обслуживает один селекторный поток. Поток на
    // ассоциацию (как раньше) при DNS-трафике быстро упирался в лимит потоков.
    @Volatile private var udpSelector: Selector? = null
    private val udpAssociations: MutableSet<UdpAssociation> = ConcurrentHashMap.newKeySet()
    private val pendingUdp = ConcurrentLinkedQueue<UdpAssociation>()

    // ─── DNS-кэш и дедупликация ───
    // Каждый DNS-over-TCP запрос открывал НОВЫЙ SSH-канал, а нода — новое
    // TCP-соединение на публичный резолвер. Тысячи туннелей × повторяющиеся
    // запросы = TCP SYN флуд на 8.8.8.8:53 (OVH банит ноду как DNS-атакера).
    // Кэш ретрансмитов + дедупликация одинаковых запросов в полёте срезают
    // повторы. Кэш — LRU с потолком: безразмерная карта росла весь сеанс.
    private val dnsCache = object : LinkedHashMap<String, DnsCacheEntry>(64, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, DnsCacheEntry>?) =
            size > DNS_CACHE_MAX
    }
    private val dnsInFlight = ConcurrentHashMap<String, CompletableFuture<ByteArray?>>()
    /**
     * Предпочитаемый апстрим — локальный резолвер самой ноды (127.0.0.53,
     * systemd-resolved): наружные запросы идут обычным UDP от её кэша, без
     * TCP-шторма на публичные DNS. Фолбэк на исходный хост на 2 мин.
     */
    @Volatile private var localResolverUsable = true
    private var localResolverLastTry = 0L
    private val connections = AtomicLong(0)

    /** Подряд идущие неудачи открытия канала; сбрасывается на первом успехе. */
    private val openFailures = AtomicInteger(0)

    private val rejectLog = ThrottledLog()
    private val udpDropLog = ThrottledLog()
    private val udpNoRouteLog = ThrottledLog()

    /**
     * Открывает direct-tcpip канал через текущий транспорт.
     *
     * Возвращает null при неудаче и, если похоже, что виноват не адрес, а сам
     * транспорт, дёргает [onTransportFailure] — сервис пересоберёт SSH. Без
     * этого сигнала мёртвое соединение никто не замечал: keepalive ждёт своей
     * минуты, а приложения всё это время получали отказы.
     *
     * [countsTowardDeath] = false — для DNS-over-TCP: неудачный резолв чаще
     * говорит о проблемах апстрим-резолвера, а не туннеля, и всплеск DNS-запросов
     * при пробуждении телефона не должен приговаривать только что собранный SSH.
     */
    private fun openChannel(
        host: String,
        port: Int,
        countsTowardDeath: Boolean = true,
    ): net.schmizz.sshj.connection.channel.direct.DirectConnection? {
        val transport = transportProvider()
        if (transport == null || !transport.isConnected) {
            Log.w(TAG, "open $host:$port — транспорт недоступен, просим переподключение")
            onTransportFailure()
            return null
        }
        return try {
            val ch = transport.openChannel(host, port)
            openFailures.set(0)
            ch
        } catch (e: Exception) {
            val failures = if (countsTowardDeath) openFailures.incrementAndGet() else openFailures.get()
            // Обрыв транспорта — приговор сразу. Одиночный отказ по адресу
            // (закрытый порт, недоступный хост) приговором быть не должен, иначе
            // туннель переподключался бы от каждого неудачного соединения.
            // А вот когда падает подряд DEAD_AFTER_FAILURES штук — соединение
            // мертво, даже если TCP об этом ещё не сообщил (типичная картина
            // после потери Wi-Fi: каждое открытие канала уходит в таймаут).
            val dead = e is net.schmizz.sshj.transport.TransportException ||
                !transport.isConnected ||
                (countsTowardDeath && failures >= DEAD_AFTER_FAILURES)
            Log.w(TAG, "open $host:$port failed (подряд=$failures, dead=$dead): $e")
            if (dead) {
                transport.markDead()
                onTransportFailure()
            }
            null
        }
    }

    @Volatile var port: Int = 0
        private set

    /** Живые CONNECT/UDP-сессии. Раньше это было отдельное поле, которое никто
     *  не обновлял, и статистика всегда показывала 0. */
    val activeConnections: Long get() = connections.get()

    /**
     * Транспорт заменён — счётчик подряд идущих отказов больше не относится к
     * делу. Без сброса пара «висячих» отказов старого соединения плюс один
     * честный отказ по адресу дали бы приговор уже живому транспорту.
     */
    fun onTransportReplaced() {
        openFailures.set(0)
    }

    fun start() {
        try {
            val ss = ServerSocket(0, 128, InetAddress.getByName("127.0.0.1"))
            serverSocket = ss
            port = ss.localPort
            val selector = Selector.open()
            udpSelector = selector
            Log.i(TAG, "listening on 127.0.0.1:$port")
            startDaemon("vlee-socks-accept") { acceptLoop(ss) }
            startDaemon("vlee-socks-udp") { udpLoop(selector) }
        } catch (t: Throwable) {
            // Сервис назначает socksServer только после start(): закрыть
            // полуоткрытое, кроме нас, некому.
            stop()
            throw t
        }
    }

    fun stop() {
        stopped = true
        runCatching { serverSocket?.close() }
        runCatching { udpSelector?.close() }
        closeAllUdp()
        sessionExecutor.shutdownNow()
        pumpExecutor.shutdownNow()
        udpRelayExecutor.shutdownNow()
        dnsExecutor.shutdownNow()
    }

    private fun startDaemon(name: String, body: () -> Unit) {
        Thread(body, name).apply {
            isDaemon = true
            uncaughtExceptionHandler = LOG_UNCAUGHT
        }.start()
    }

    private fun acceptLoop(ss: ServerSocket) {
        while (!ss.isClosed) {
            val client = try {
                ss.accept()
            } catch (_: IOException) {
                break
            }
            try {
                Log.d(TAG, "accepted ${client.remoteSocketAddress}")
                sessionExecutor.execute { handleClient(client) }
            } catch (_: RejectedExecutionException) {
                if (!stopped) rejectLog.warn { "session limit ($MAX_SESSIONS) reached, client dropped" }
                closeQuietly(client)
            } catch (t: Throwable) {
                // pthread_create отказал (OutOfMemoryError): раньше это роняло
                // процесс прямо из accept-цикла. Теперь отказ одному клиенту.
                Log.e(TAG, "cannot start session worker: $t")
                closeQuietly(client)
                try {
                    Thread.sleep(ACCEPT_BACKOFF_MS)
                } catch (_: InterruptedException) {
                    Thread.currentThread().interrupt()
                }
            }
        }
    }

    private fun handleClient(socket: Socket) {
        try {
            socket.tcpNoDelay = true
            socket.soTimeout = 30_000
            val input = DataInputStream(socket.getInputStream())
            val output = DataOutputStream(socket.getOutputStream())

            if (input.readByte() != VERSION.toByte()) {
                Log.w(TAG, "bad socks version from ${socket.remoteSocketAddress}")
                return closeQuietly(socket)
            }
            val nMethods = input.readByte().toInt() and 0xFF
            var chosen = -1
            repeat(nMethods) {
                val m = input.readByte().toInt()
                if (m == 0x00 && chosen == -1) chosen = m
            }
            if (chosen != 0x00) {
                Log.w(TAG, "no acceptable auth method from ${socket.remoteSocketAddress}")
                output.write(byteArrayOf(VERSION.toByte(), 0xFF.toByte()))
                output.flush()
                return closeQuietly(socket)
            }
            output.write(byteArrayOf(VERSION.toByte(), 0x00))
            output.flush()

            socket.soTimeout = 0

            // Запрос: VER CMD RSV ATYP DST.ADDR DST.PORT (RFC 1928, §4).
            // ВАЖНО: у запроса СВОЙ байт версии — он идёт ПЕРЕД командой.
            // Раньше первый байт запроса (0x05) читался как CMD, не совпадал
            // ни с CONNECT (0x01), ни с UDP ASSOCIATE (0x03), и каждому
            // соединению уходил rep=0x07 «command not supported». Именно это
            // видно в hev-логах как сплошные "socks5 client res.rep 7":
            // туннель поднимался, а данные не шли ни по одному соединению.
            val reqVersion = input.readByte().toInt() and 0xFF
            if (reqVersion != VERSION) {
                Log.w(TAG, "bad request version $reqVersion from ${socket.remoteSocketAddress}")
                return replyAndClose(output, GENERAL_FAILURE, socket)
            }

            when (val cmd = input.readByte().toInt() and 0xFF) {
                CMD_CONNECT -> handleConnect(socket, input, output)
                CMD_UDP_ASSOCIATE -> handleUdpAssociate(socket, input, output)
                else -> {
                    // Тихий выход отсюда и был причиной «логов нет»: клиент
                    // получал ошибку, а в logcat не появлялось ни строки.
                    Log.w(TAG, "unsupported SOCKS command $cmd from ${socket.remoteSocketAddress}")
                    output.write(CMD_UNSUPPORTED)
                    output.flush()
                    closeQuietly(socket)
                }
            }
        } catch (t: Throwable) {
            // Throwable, а не Exception: Error (OOM при старте потока), вылетев
            // из задачи, заставлял пул создавать поток-замену — и падать уже там.
            Log.w(TAG, "socks session failed for ${socket.remoteSocketAddress}: $t")
            closeQuietly(socket)
        }
    }

    private fun handleConnect(socket: Socket, input: DataInputStream, output: DataOutputStream) {
        readSkipReserved(input)
        val target = readAddress(input)
        if (target == null) {
            Log.w(TAG, "CONNECT with unparsable address from ${socket.remoteSocketAddress}")
            return replyAndClose(output, GENERAL_FAILURE, socket)
        }
        Log.d(TAG, "CONNECT ${target.first}:${target.second}")

        val channel = openChannel(target.first, target.second)
            ?: return replyAndClose(output, GENERAL_FAILURE, socket)

        connections.incrementAndGet()
        try {
            val chIn = channel.inputStream
            val chOut = channel.outputStream

            // Обе половины дуплекса живут независимо. Раньше выход из upload-цикла
            // по EOF от приложения сразу закрывал канал и сокет в finally — ответ
            // сервера, ещё летящий в обратную сторону, обрезался на полуслове.
            val upstreamDone = CountDownLatch(1)
            try {
                pumpExecutor.execute {
                    try {
                        pumpUpstream(socket, chOut)
                    } catch (t: Throwable) {
                        Log.w(TAG, "upstream relay failed: $t")
                    } finally {
                        upstreamDone.countDown()
                    }
                }
            } catch (t: Throwable) {
                // Нет потока для upload-половины (лимит или pthread_create):
                // честный отказ клиенту вместо падения процесса.
                Log.w(TAG, "CONNECT ${target.first}:${target.second}: no relay thread: $t")
                runCatching {
                    output.write(GENERAL_FAILURE)
                    output.flush()
                }
                return
            }

            // Ответ — внутри try: если запись упадёт, канал всё равно закроется
            // в finally (раньше он оставался открытым на сервере).
            output.write(SUCCESS_REPLY)
            output.flush()

            // Downstream крутим прямо в текущем воркере: на соединение уходит два
            // потока, а не три (на загрузке страницы это десятки соединений).
            try {
                val buf = ByteArray(RELAY_BUFFER_BYTES)
                val localOut = socket.getOutputStream()
                while (true) {
                    val n = chIn.read(buf)
                    if (n < 0) break
                    localOut.write(buf, 0, n)
                    localOut.flush()
                }
            } catch (_: IOException) {
            } finally {
                // Полузакрытие: приложение видит EOF, но может продолжать слать.
                runCatching { socket.shutdownOutput() }
            }

            // Ответ уже дочитан; на догрузку запроса даём ограниченное время:
            // иначе застрявший на read() upload-поток жил бы до конца сессии,
            // даже когда удалённая сторона давно закрылась.
            upstreamDone.await(RELAY_DRAIN_TIMEOUT_MS, TimeUnit.MILLISECONDS)
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
        } finally {
            connections.decrementAndGet()
            // Закрытие здесь же разблокирует upstream, если он всё ещё в read().
            runCatching { channel.close() }
            closeQuietly(socket)
        }
    }

    private fun pumpUpstream(socket: Socket, chOut: OutputStream) {
        try {
            val buf = ByteArray(RELAY_BUFFER_BYTES)
            val localIn = socket.getInputStream()
            while (true) {
                val n = localIn.read(buf)
                if (n < 0) break
                chOut.write(buf, 0, n)
                chOut.flush()
            }
        } catch (_: IOException) {
        } finally {
            // EOF вверх по потоку — сообщаем его SSH-каналу, но канал не
            // рвём: сервер ещё может досылать ответ.
            runCatching { chOut.close() }
        }
    }

    /**
     * UDP ASSOCIATE. Воркер освобождается сразу после ответа: датаграммы
     * обслуживает общий [udpLoop], а закрывает ассоциацию таймаут простоя.
     * Раньше воркер крутил здесь цикл `while (!socket.isClosed)`, который
     * никогда не завершался: isClosed отражает только НАШЕ закрытие, а
     * tun2socks закрывает управляющее соединение со своей стороны.
     */
    private fun handleUdpAssociate(socket: Socket, input: DataInputStream, output: DataOutputStream) {
        readSkipReserved(input)
        readAddress(input)

        val channel = DatagramChannel.open(StandardProtocolFamily.INET)
        try {
            channel.socket().bind(InetSocketAddress(InetAddress.getByName("127.0.0.1"), 0))
            channel.configureBlocking(false)
            val udpPort = channel.socket().localPort
            val reply = byteArrayOf(
                VERSION.toByte(), 0x00, 0x00, ATYP_IPV4.toByte(),
                127, 0, 0, 1,
                (udpPort shr 8).toByte(), udpPort.toByte(),
            )
            output.write(reply)
            output.flush()
        } catch (t: Throwable) {
            runCatching { channel.close() }
            throw t
        }

        val association = UdpAssociation(socket, channel)
        udpAssociations.add(association)
        if (udpAssociations.size > MAX_UDP_ASSOCIATIONS) evictIdlestUdp(except = association)
        // stop() мог пройти между созданием и регистрацией.
        if (stopped) {
            association.close()
            return
        }
        pendingUdp.add(association)
        udpSelector?.wakeup()
    }

    private inner class UdpAssociation(
        val control: Socket,
        val channel: DatagramChannel,
    ) {
        @Volatile var lastActiveMs = nowMs()
        private val closed = AtomicBoolean(false)
        val isClosed: Boolean get() = closed.get()

        init {
            connections.incrementAndGet()
        }

        /** Неблокирующая отправка: при полном буфере датаграмма теряется, как и положено UDP. */
        fun send(packet: ByteArray, to: SocketAddress) {
            if (closed.get()) return
            try {
                channel.send(ByteBuffer.wrap(packet), to)
                lastActiveMs = nowMs()
            } catch (_: IOException) {
            }
        }

        fun close() {
            if (!closed.compareAndSet(false, true)) return
            udpAssociations.remove(this)
            runCatching { channel.close() }
            // tun2socks видит EOF управляющего соединения и завершает свою сессию.
            closeQuietly(control)
            connections.decrementAndGet()
        }
    }

    private fun udpLoop(selector: Selector) {
        // Один буфер на все ассоциации вместо 64 КБ на каждую.
        val buffer = ByteBuffer.allocate(UDP_BUFFER_BYTES)
        var nextSweepMs = nowMs() + UDP_SWEEP_MS
        try {
            while (!stopped) {
                selector.select(UDP_SWEEP_MS)
                registerPendingUdp(selector)
                val keys = selector.selectedKeys().iterator()
                while (keys.hasNext()) {
                    val key = keys.next()
                    keys.remove()
                    val association = key.attachment() as UdpAssociation
                    try {
                        if (key.isValid && key.isReadable) drainUdp(association, buffer)
                    } catch (_: CancelledKeyException) {
                        association.close()
                    }
                }
                val now = nowMs()
                if (now >= nextSweepMs) {
                    closeIdleUdp(now)
                    nextSweepMs = now + UDP_SWEEP_MS
                }
            }
        } catch (_: ClosedSelectorException) {
        } catch (t: Throwable) {
            if (!stopped) Log.e(TAG, "UDP loop failed", t)
        } finally {
            closeAllUdp()
            runCatching { selector.close() }
        }
    }

    private fun registerPendingUdp(selector: Selector) {
        while (true) {
            val association = pendingUdp.poll() ?: return
            if (association.isClosed) continue
            try {
                association.channel.register(selector, SelectionKey.OP_READ, association)
            } catch (_: IOException) {
                association.close()
            }
        }
    }

    private fun drainUdp(association: UdpAssociation, buffer: ByteBuffer) {
        repeat(UDP_READS_PER_WAKEUP) {
            buffer.clear()
            val from = try {
                association.channel.receive(buffer)
            } catch (_: IOException) {
                association.close()
                return
            } ?: return
            association.lastActiveMs = nowMs()
            buffer.flip()
            val datagram = parseUdpDatagram(buffer.array(), buffer.arrayOffset(), buffer.limit())
                ?: return@repeat
            dispatchUdp(association, datagram, from)
        }
    }

    private fun dispatchUdp(association: UdpAssociation, datagram: UdpDatagram, replyTo: SocketAddress) {
        if (!dnsOverTcp || datagram.dstPort != DNS_PORT) {
            // Кроме DNS, UDP через SSH не ходит (QUIC и пр. откатываются на TCP);
            // отбрасываем сразу, не занимая воркеры.
            udpNoRouteLog.warn {
                "UDP ${datagram.dstHost.hostAddress}:${datagram.dstPort} " +
                    "len=${datagram.payload.size} no relay path"
            }
            return
        }
        try {
            // Ответ ждём в воркере — цикл приёма остаётся свободным и следующие
            // датаграммы не стоят в очереди за этой.
            udpRelayExecutor.execute {
                try {
                    relayDns(datagram)?.let { association.send(it, replyTo) }
                } catch (t: Throwable) {
                    Log.w(TAG, "UDP relay failed: $t")
                }
            }
        } catch (t: Throwable) {
            // Очередь полна (или нет потока): UDP допускает потери.
            udpDropLog.warn { "UDP relay saturated, datagram dropped: $t" }
        }
    }

    private fun closeIdleUdp(now: Long) {
        for (association in udpAssociations) {
            if (now - association.lastActiveMs > udpIdleTimeoutMs) association.close()
        }
    }

    private fun evictIdlestUdp(except: UdpAssociation) {
        val idlest = udpAssociations.filter { it !== except }.minByOrNull { it.lastActiveMs } ?: return
        udpDropLog.warn { "UDP association limit ($MAX_UDP_ASSOCIATIONS) reached, closing the idlest" }
        idlest.close()
    }

    private fun closeAllUdp() {
        for (association in udpAssociations) association.close()
        while (true) {
            (pendingUdp.poll() ?: break).close()
        }
    }

    private class UdpDatagram(
        val dstHost: InetAddress,
        val dstPort: Int,
        val payload: ByteArray,
    )

    private fun parseUdpDatagram(data: ByteArray, offset: Int, len: Int): UdpDatagram? {
        try {
            if (len < 10) return null
            if (data[offset + 2].toInt() != 0) return null
            var pos = offset + 3
            val atyp = data[pos].toInt(); pos += 1
            val host: InetAddress
            when (atyp) {
                ATYP_IPV4 -> {
                    host = InetAddress.getByAddress(data.copyOfRange(pos, pos + 4)); pos += 4
                }
                ATYP_IPV6 -> {
                    host = InetAddress.getByAddress(data.copyOfRange(pos, pos + 16)); pos += 16
                }
                else -> {
                    udpNoRouteLog.warn { "UDP datagram with unsupported ATYP $atyp dropped" }
                    return null
                }
            }
            val port = ((data[pos].toInt() and 0xFF) shl 8) or (data[pos + 1].toInt() and 0xFF)
            pos += 2
            val payloadLen = offset + len - pos
            if (payloadLen <= 0) return null
            val payload = data.copyOfRange(pos, pos + payloadLen)
            return UdpDatagram(host, port, payload)
        } catch (_: Exception) {
            return null
        }
    }

    /** DNS-запрос через DNS-over-TCP по SSH; возвращает готовую SOCKS-датаграмму. */
    private fun relayDns(dgram: UdpDatagram): ByteArray? {
        val dstHost = dgram.dstHost.hostAddress ?: return null
        // Точные байты запроса вместо хэш-кода: коллизия хэша отдавала чужой ответ.
        val key = dstHost + ":" + String(dgram.payload, Charsets.ISO_8859_1)
        dnsCacheGet(key)?.let { return buildUdpResponse(dgram.dstHost, DNS_PORT, it) }

        // Дедуп: идентичный запрос уже в полёте — ждём его результат.
        val mine = CompletableFuture<ByteArray?>()
        dnsInFlight.putIfAbsent(key, mine)?.let { inFlight ->
            val shared = try {
                inFlight.get(3_000L, TimeUnit.MILLISECONDS)
            } catch (_: Exception) {
                null
            }
            return shared?.let { buildUdpResponse(dgram.dstHost, DNS_PORT, it) }
        }

        var response: ByteArray? = null
        try {
            val resolve = dnsResolver ?: ::resolveDnsOverTcp
            val task = dnsExecutor.submit(Callable { resolve(dstHost, dgram.payload) })
            try {
                response = task.get(DNS_TCP_TIMEOUT_MS.toLong(), TimeUnit.MILLISECONDS)
                response?.let { dnsCachePut(key, it) }
            } catch (e: Exception) {
                // Прерываем зависший резолв: иначе он навсегда занимал DNS-воркер,
                // а новые запросы копились в очереди без предела.
                task.cancel(true)
                if (e is InterruptedException) Thread.currentThread().interrupt()
            }
        } catch (_: RejectedExecutionException) {
            // DNS-очередь полна: запрос теряется, клиент повторит.
        } finally {
            dnsInFlight.remove(key, mine)
            mine.complete(response)
        }
        return response?.let { buildUdpResponse(dgram.dstHost, DNS_PORT, it) }
    }

    private fun dnsCacheGet(key: String): ByteArray? = synchronized(dnsCache) {
        val entry = dnsCache[key] ?: return null
        if (entry.expiresAtMs > nowMs()) return entry.response
        dnsCache.remove(key)
        null
    }

    private fun dnsCachePut(key: String, response: ByteArray) {
        synchronized(dnsCache) {
            dnsCache[key] = DnsCacheEntry(response, nowMs() + DNS_CACHE_TTL_MS)
        }
    }

    /** Возвращает сырой DNS-ответ (без SOCKS-заголовка). */
    private fun resolveDnsOverTcp(host: String, query: ByteArray): ByteArray? {
        var upstream = host
        if (localResolverUsable || System.currentTimeMillis() - localResolverLastTry > 120_000) {
            upstream = "127.0.0.53"
        }
        val result = resolveDnsOverTcpInner(upstream, query)
        if (upstream == "127.0.0.53") {
            localResolverUsable = result != null
            if (result == null) localResolverLastTry = System.currentTimeMillis()
        }
        return result
    }

    private fun resolveDnsOverTcpInner(host: String, query: ByteArray): ByteArray? {
        val channel = openChannel(host, DNS_PORT, countsTowardDeath = false) ?: return null
        try {
            val chOut = DataOutputStream(channel.outputStream)
            val chIn = DataInputStream(channel.inputStream)
            chOut.writeShort(query.size)
            chOut.write(query)
            chOut.flush()

            val lenHi = chIn.read()
            val lenLo = chIn.read()
            if (lenHi < 0 || lenLo < 0) {
                Log.w(TAG, "DNS-TCP $host closed before response")
                return null
            }
            val respLen = (lenHi shl 8) or lenLo
            if (respLen <= 0 || respLen > 65535) return null
            val response = ByteArray(respLen)
            chIn.readFully(response)
            return response
        } catch (_: Exception) {
            return null
        } finally {
            runCatching { channel.close() }
        }
    }

    /**
     * [source] — адрес, на который слало приложение, даже если ответил
     * резолвер ноды: hev подставляет адрес из заголовка источником пакета.
     * Раньше туда попадал 127.0.0.53, и ядро отбрасывало такой ответ.
     */
    private fun buildUdpResponse(source: InetAddress, port: Int, payload: ByteArray): ByteArray {
        val out = ByteArrayOutputStream(payload.size + 22)
        out.write(byteArrayOf(0, 0, 0))
        val raw = source.address
        out.write(if (raw.size == 4) ATYP_IPV4 else ATYP_IPV6)
        out.write(raw)
        out.write((port shr 8) and 0xFF)
        out.write(port and 0xFF)
        out.write(payload)
        return out.toByteArray()
    }

    /** Consumes the single RSV byte between CMD and ATYP. */
    private fun readSkipReserved(input: DataInputStream) {
        input.readByte()
    }

    private fun readAddress(input: DataInputStream): Pair<String, Int>? {
        return try {
            when (input.readByte().toInt()) {
                ATYP_IPV4 -> {
                    val addr = ByteArray(4)
                    input.readFully(addr)
                    InetAddress.getByAddress(addr).hostAddress to readPort(input)
                }
                ATYP_IPV6 -> {
                    val addr = ByteArray(16)
                    input.readFully(addr)
                    InetAddress.getByAddress(addr).hostAddress to readPort(input)
                }
                ATYP_DOMAIN -> {
                    val len = input.readByte().toInt() and 0xFF
                    val domain = ByteArray(len)
                    input.readFully(domain)
                    String(domain, Charsets.US_ASCII) to readPort(input)
                }
                else -> null
            }
        } catch (_: IOException) {
            null
        }
    }

    private fun readPort(input: DataInputStream): Int {
        val hi = input.readUnsignedByte()
        val lo = input.readUnsignedByte()
        return (hi shl 8) or lo
    }

    private fun replyAndClose(output: DataOutputStream, reply: ByteArray, socket: Socket) {
        runCatching {
            output.write(reply)
            output.flush()
        }
        closeQuietly(socket)
    }

    private fun closeQuietly(socket: Socket) {
        runCatching { socket.close() }
    }
}
