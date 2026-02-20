package ai.annadata.mqttquic.client

import android.util.Log
import ai.annadata.mqttquic.mqtt.MQTT5PropertyType
import ai.annadata.mqttquic.mqtt.MQTTConnAckCode
import ai.annadata.mqttquic.mqtt.MQTTMessageType
import ai.annadata.mqttquic.mqtt.MQTTProtocol
import ai.annadata.mqttquic.mqtt.MQTT5Protocol
import ai.annadata.mqttquic.mqtt.MQTT5ReasonCode
import ai.annadata.mqttquic.mqtt.MQTTProtocolLevel
import ai.annadata.mqttquic.quic.NGTCP2Client
import ai.annadata.mqttquic.quic.QuicClient
import ai.annadata.mqttquic.quic.QuicClientStub
import ai.annadata.mqttquic.quic.QuicStream
import ai.annadata.mqttquic.transport.MQTTStreamReader
import ai.annadata.mqttquic.transport.MQTTStreamWriter
import ai.annadata.mqttquic.transport.QUICStreamReader
import ai.annadata.mqttquic.transport.QUICStreamWriter
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.withTimeout

/**
 * High-level MQTT client: connect, publish, subscribe, disconnect.
 * Uses QuicClient + stream adapters + MQTT protocol.
 */
class MQTTClient {

    enum class State {
        DISCONNECTED,
        CONNECTING,
        CONNECTED,
        ERROR
    }

    enum class ProtocolVersion {
        V311, V5, AUTO
    }

    private var state = State.DISCONNECTED
    private var protocolVersion = ProtocolVersion.AUTO
    private var activeProtocolVersion: Byte = 0  // 0x04 or 0x05
    /** Effective keepalive in seconds (from CONNACK Server Keep Alive, or connect param). Used when sending PINGREQ. */
    private var effectiveKeepalive: Int = 0
    /** Assigned Client Identifier from CONNACK when client sent empty ClientID; null otherwise. */
    private var assignedClientIdentifier: String? = null
    private var quicClient: QuicClient? = null
    private var stream: QuicStream? = null
    private var reader: MQTTStreamReader? = null
    private var writer: MQTTStreamWriter? = null
    private var messageLoopJob: kotlinx.coroutines.Job? = null
    private var keepaliveJob: kotlinx.coroutines.Job? = null
    private var nextPacketId = 1
    private val subscribedTopics = mutableMapOf<String, (ByteArray) -> Unit>()
    /** Optional global callback for every incoming PUBLISH (topic, payload). Used by plugin to forward to JS. */
    @Volatile
    var onPublish: ((String, ByteArray) -> Unit)? = null
    /** Per-connection Topic Alias map (alias -> topic name) for MQTT 5.0 incoming PUBLISH. */
    private val topicAliasMap = mutableMapOf<Int, String>()
    /** Pending SUBACK by packet ID. Message loop completes with (fullPacket, hdrLen). Single reader: only message loop reads stream. */
    private val pendingSubacks = mutableMapOf<Int, CompletableDeferred<Pair<ByteArray, Int>>>()
    /** Pending UNSUBACK by packet ID. Message loop completes when UNSUBACK is read. */
    private val pendingUnsubacks = mutableMapOf<Int, CompletableDeferred<Unit>>()
    /** Pending PINGRESP for sendMqttPing(). Message loop completes when PINGRESP is read. */
    @Volatile
    private var pendingPingresp: CompletableDeferred<Unit>? = null
    private val lock = Mutex()
    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())

    constructor(protocolVersion: ProtocolVersion = ProtocolVersion.AUTO) {
        this.protocolVersion = protocolVersion
    }

    fun getState(): State = runBlocking { lock.withLock { state } }

    /** Effective keepalive in seconds (Server Keep Alive from CONNACK, or value sent in CONNECT). */
    fun getEffectiveKeepalive(): Int = runBlocking { lock.withLock { effectiveKeepalive } }

    /** Assigned Client Identifier from CONNACK when client sent empty ClientID; null otherwise. */
    fun getAssignedClientIdentifier(): String? = runBlocking { lock.withLock { assignedClientIdentifier } }

    /** Resolved IP used for the current/last QUIC connection (from native getaddrinfo). Used by plugin to cache for reconnect when Java DNS fails. */
    fun getLastResolvedAddress(): String? = (quicClient as? NGTCP2Client)?.getLastResolvedAddress()

    /** Read full MQTT fixed header (1 byte type + 1–4 bytes remaining length per MQTT v5.0 §2.1.4). Returns (msgType, remLen, fixedHeaderBytes). */
    private suspend fun readFixedHeader(r: MQTTStreamReader): Triple<Byte, Int, ByteArray> {
        Log.i("MQTTClient", "readFixedHeader: requesting first byte")
        var fixed = r.readexactly(1).toMutableList()
        val firstByte = fixed[0].toInt() and 0xFF
        Log.i("MQTTClient", "readFixedHeader: got type byte 0x${Integer.toHexString(firstByte)} ($firstByte)")
        repeat(5) { // 1 type + up to 4 remaining-length bytes (Variable Byte Integer)
            try {
                val (rem, _) = MQTTProtocol.decodeRemainingLength(fixed.toByteArray(), 1)
                Log.i("MQTTClient", "readFixedHeader: decoded remLen=$rem fixedSize=${fixed.size}")
                return Triple(fixed[0], rem, fixed.toByteArray())
            } catch (_: IllegalArgumentException) {
                if (fixed.size > 5) throw IllegalArgumentException("Invalid remaining length")
                fixed.addAll(r.readexactly(1).toList())
                Log.i("MQTTClient", "readFixedHeader: added byte, fixedSize=${fixed.size}")
            }
        }
        throw IllegalArgumentException("Invalid remaining length")
    }

    suspend fun connect(
        host: String,
        port: Int,
        clientId: String,
        username: String?,
        password: String?,
        cleanSession: Boolean,
        keepalive: Int,
        sessionExpiryInterval: Int? = null,
        connectAddress: String? = null
    ) {
        lock.withLock {
            if (state == State.CONNECTING) {
                throw IllegalStateException("already connecting")
            }
            state = State.CONNECTING
        }

        try {
            val useV5 = protocolVersion == ProtocolVersion.V5 || protocolVersion == ProtocolVersion.AUTO
            
            val connack: ByteArray
            if (useV5) {
                connack = MQTT5Protocol.buildConnackV5(MQTT5ReasonCode.SUCCESS, false)
            } else {
                connack = MQTTProtocol.buildConnack(MQTTConnAckCode.ACCEPTED)
            }
            
            val quic: QuicClient = if (NGTCP2Client.isAvailable()) {
                NGTCP2Client()
            } else {
                QuicClientStub(connack.toList())
            }
            quic.connect(host, port, connectAddress)
            val s = quic.openStream()
            val r = QUICStreamReader(s)
            val w = QUICStreamWriter(s)

            lock.withLock {
                quicClient = quic
                stream = s
                reader = r
                writer = w
            }

            val connectData: ByteArray
            if (useV5) {
                connectData = MQTT5Protocol.buildConnectV5(
                    clientId,
                    username,
                    password,
                    keepalive,
                    cleanSession,
                    sessionExpiryInterval
                )
                activeProtocolVersion = MQTTProtocolLevel.V5
            } else {
                connectData = MQTTProtocol.buildConnect(
                    clientId,
                    username,
                    password,
                    keepalive,
                    cleanSession
                )
                activeProtocolVersion = MQTTProtocolLevel.V311
            }
            
            w.write(connectData)
            w.drain()

            // MQTT 5.0: server may send AUTH before CONNACK; loop until CONNACK. Timeout so we don't block 30s until ERR_IDLE_CLOSE.
            // Efficient path: drain stream (read until empty), then parse first complete packet; repeat until CONNACK or timeout.
            var full: ByteArray
            var hdrLen: Int
            val connackTimeoutMs = 15_000L
            try {
                if (activeProtocolVersion == MQTTProtocolLevel.V5) {
                    Log.i("MQTTClient", "reading CONNACK (MQTT5) timeout=${connackTimeoutMs}ms (drain then parse)")
                    withTimeout(connackTimeoutMs) {
                        while (true) {
                            if (r is QUICStreamReader) {
                                r.drain()
                                val avail = r.available()
                                Log.i("MQTTClient", "CONNACK loop: after drain available=$avail")
                                val packet = r.tryConsumeNextPacket()
                                if (packet != null) {
                                    val (msgType, _, fixedLen) = MQTTProtocol.parseFixedHeader(packet.copyOf(minOf(5, packet.size)))
                                    val typeByte = msgType.toInt() and 0xFF
                                    Log.i("MQTTClient", "CONNACK loop: packet type=0x${Integer.toHexString(typeByte)} len=${packet.size} hdrLen=$fixedLen")
                                    when (typeByte) {
                                        0x20 -> {
                                            full = packet
                                            hdrLen = fixedLen
                                            return@withTimeout
                                        }
                                        0xF0 -> {
                                            lock.withLock { state = State.ERROR }
                                            try {
                                                w.write(MQTT5Protocol.buildDisconnectV5(MQTT5ReasonCode.BAD_AUTHENTICATION_METHOD_DISC))
                                                w.drain()
                                                w.close()
                                            } catch (_: Exception) { /* ignore */ }
                                            throw IllegalArgumentException("Enhanced authentication not supported")
                                        }
                                        0xE0 -> {
                                            lock.withLock { state = State.ERROR }
                                            throw IllegalArgumentException("Server sent DISCONNECT before CONNACK")
                                        }
                                        else -> Log.i("MQTTClient", "CONNACK loop: skipping non-CONNACK packet type=0x${Integer.toHexString(typeByte)}")
                                    }
                                } else {
                                    // Only delay when no data; if we have data but no packet, retry soon (avoid suspend then timeout before next iteration)
                                    if (avail == 0) delay(50) else delay(10)
                                }
                            } else {
                                // Fallback for non-QUIC reader (e.g. mock)
                                val (msgType, remLen, fixed) = readFixedHeader(r)
                                val typeByte = fixed[0].toInt() and 0xFF
                                val rest = r.readexactly(remLen)
                                full = fixed + rest
                                hdrLen = fixed.size
                                when (typeByte) {
                                    0x20 -> return@withTimeout
                                    0xF0 -> {
                                        lock.withLock { state = State.ERROR }
                                        try {
                                            w.write(MQTT5Protocol.buildDisconnectV5(MQTT5ReasonCode.BAD_AUTHENTICATION_METHOD_DISC))
                                            w.drain()
                                            w.close()
                                        } catch (_: Exception) { /* ignore */ }
                                        throw IllegalArgumentException("Enhanced authentication not supported")
                                    }
                                    0xE0 -> {
                                        lock.withLock { state = State.ERROR }
                                        throw IllegalArgumentException("Server sent DISCONNECT before CONNACK")
                                    }
                                    else -> { /* skip; continue */ }
                                }
                            }
                        }
                    }
                    Log.i("MQTTClient", "got CONNACK (MQTT5) (fullLen=${full.size} hdrLen=$hdrLen)")
                } else {
                    Log.i("MQTTClient", "reading CONNACK (3.1.1) timeout=${connackTimeoutMs}ms")
                    withTimeout(connackTimeoutMs) {
                        if (r is QUICStreamReader) {
                            while (true) {
                                r.drain()
                                val packet = r.tryConsumeNextPacket()
                                if (packet != null) {
                                    val (msgType, _, fixedLen) = MQTTProtocol.parseFixedHeader(packet.copyOf(minOf(5, packet.size)))
                                    if (msgType == MQTTMessageType.CONNACK) {
                                        full = packet
                                        hdrLen = fixedLen
                                        break
                                    }
                                    lock.withLock { state = State.ERROR }
                                    throw IllegalArgumentException("expected CONNACK, got $msgType")
                                }
                                delay(50)
                            }
                        } else {
                            val (msgType, remLen, fixed) = readFixedHeader(r)
                            val rest = r.readexactly(remLen)
                            full = fixed + rest
                            hdrLen = fixed.size
                            if (msgType != MQTTMessageType.CONNACK) {
                                lock.withLock { state = State.ERROR }
                                throw IllegalArgumentException("expected CONNACK, got $msgType")
                            }
                        }
                        Log.i("MQTTClient", "got CONNACK (3.1.1)")
                    }
                }
            } catch (e: TimeoutCancellationException) {
                lock.withLock { state = State.ERROR }
                Log.w("MQTTClient", "CONNACK read timed out after ${connackTimeoutMs}ms", e)
                throw IllegalStateException("CONNACK read timed out. Drain+parse did not receive a complete CONNACK in time. Ask server to send full CONNACK (loop writev_stream until all bytes sent); or check network.", e)
            }

            if (activeProtocolVersion == MQTTProtocolLevel.V5) {
                Log.i("MQTTClient", "parsing CONNACK v5 (offset=$hdrLen)")
                val (_, reasonCode, props) = MQTT5Protocol.parseConnackV5(full, hdrLen)
                if (reasonCode != MQTT5ReasonCode.SUCCESS) {
                    lock.withLock { state = State.ERROR }
                    throw IllegalArgumentException("CONNACK refused: $reasonCode")
                }
                // [MQTT-3.2.2-21] Use Server Keep Alive from CONNACK if present
                lock.withLock {
                    effectiveKeepalive = (props[MQTT5PropertyType.SERVER_KEEP_ALIVE.toInt()] as? Int) ?: keepalive
                    assignedClientIdentifier = props[MQTT5PropertyType.ASSIGNED_CLIENT_IDENTIFIER.toInt()] as? String
                }
            } else {
                val (_, returnCode) = MQTTProtocol.parseConnack(full, hdrLen)
                if (returnCode != MQTTConnAckCode.ACCEPTED) {
                    lock.withLock { state = State.ERROR }
                    throw IllegalArgumentException("CONNACK refused: $returnCode")
                }
                lock.withLock { effectiveKeepalive = keepalive }
            }

            lock.withLock { state = State.CONNECTED }
            Log.i("MQTTClient", "state=CONNECTED, starting message and keepalive loops")
            startMessageLoop()
            startKeepaliveLoop()
        } catch (e: Exception) {
            val (wr, quic) = lock.withLock {
                val w = writer
                val q = quicClient
                quicClient = null
                stream = null
                reader = null
                writer = null
                state = State.ERROR
                Pair(w, q)
            }
            try {
                wr?.close()
            } catch (_: Exception) { /* ignore */ }
            // Skip quic.close() on timeout/cancellation: server may have already sent idle close, and native close() can crash. Prefer leak over crash.
            val isTimeoutOrCancel = e is TimeoutCancellationException ||
                e is CancellationException ||
                e.cause is TimeoutCancellationException ||
                (e.message?.contains("Timed out", ignoreCase = true) == true)
            if (!isTimeoutOrCancel) {
                try {
                    quic?.close()
                } catch (ex: Exception) {
                    Log.w("MQTTClient", "Error closing QUIC connection on connect failure", ex)
                }
            } else {
                Log.i("MQTTClient", "Skipping quic.close() on timeout/cancellation to avoid native crash")
            }
            throw e
        }
    }

    suspend fun publish(topic: String, payload: ByteArray, qos: Int, properties: Map<Int, Any>? = null) {
        if (getState() != State.CONNECTED) throw IllegalStateException("not connected")
        val (w, version) = lock.withLock { writer to activeProtocolVersion }
        if (w == null) throw IllegalStateException("no writer")

        val pid: Int? = if (qos > 0) nextPacketIdUsed() else null
        val data: ByteArray
        if (version == MQTTProtocolLevel.V5) {
            data = MQTT5Protocol.buildPublishV5(topic, payload, pid, qos, false, properties)
        } else {
            data = MQTTProtocol.buildPublish(topic, payload, pid, qos, false)
        }
        try {
            w.write(data)
            w.drain()
        } catch (e: Exception) {
            lock.withLock {
                keepaliveJob?.cancel()
                keepaliveJob = null
                quicClient = null
                stream = null
                reader = null
                writer = null
                state = State.DISCONNECTED
            }
            throw e
        }
    }

    suspend fun subscribe(topic: String, qos: Int, subscriptionIdentifier: Int? = null) {
        if (getState() != State.CONNECTED) throw IllegalStateException("not connected")
        val (w, version) = lock.withLock { writer to activeProtocolVersion }
        if (w == null) throw IllegalStateException("no writer")

        val pid = nextPacketIdUsed()
        val deferred = CompletableDeferred<Pair<ByteArray, Int>>()
        lock.withLock { pendingSubacks[pid] = deferred }
        try {
            val data: ByteArray
            if (version == MQTTProtocolLevel.V5) {
                data = MQTT5Protocol.buildSubscribeV5(pid, topic, qos, subscriptionIdentifier)
            } else {
                data = MQTTProtocol.buildSubscribe(pid, topic, qos)
            }
            w.write(data)
            w.drain()

            val (full, hdrLen) = withTimeout(15_000L) { deferred.await() }

            if (version == MQTTProtocolLevel.V5) {
                val (_, reasonCodes, _) = MQTT5Protocol.parseSubackV5(full, hdrLen)
                if (reasonCodes.isNotEmpty()) {
                    val firstRC = reasonCodes[0]
                    if (firstRC != MQTT5ReasonCode.GRANTED_QOS_0 && firstRC != MQTT5ReasonCode.GRANTED_QOS_1 && firstRC != MQTT5ReasonCode.GRANTED_QOS_2) {
                        throw IllegalArgumentException("SUBACK error $firstRC")
                    }
                }
            } else {
                val (_, rc, _) = MQTTProtocol.parseSuback(full, hdrLen)
                if (rc > 0x02) throw IllegalArgumentException("SUBACK error $rc")
            }
        } finally {
            lock.withLock { pendingSubacks.remove(pid) }
        }
    }

    suspend fun unsubscribe(topic: String) {
        if (getState() != State.CONNECTED) throw IllegalStateException("not connected")
        val (w, version) = lock.withLock {
            subscribedTopics.remove(topic)
            writer to activeProtocolVersion
        }
        if (w == null) throw IllegalStateException("no writer")

        val pid = nextPacketIdUsed()
        val deferred = CompletableDeferred<Unit>()
        lock.withLock { pendingUnsubacks[pid] = deferred }
        try {
            val data: ByteArray
            if (version == MQTTProtocolLevel.V5) {
                data = MQTT5Protocol.buildUnsubscribeV5(pid, listOf(topic))
            } else {
                data = MQTTProtocol.buildUnsubscribe(pid, listOf(topic))
            }
            w.write(data)
            w.drain()

            withTimeout(15_000L) { deferred.await() }
        } finally {
            lock.withLock { pendingUnsubacks.remove(pid) }
        }
    }

    suspend fun disconnect() {
        val job = messageLoopJob
        messageLoopJob = null
        keepaliveJob?.cancel()
        keepaliveJob = null
        job?.cancel()
        job?.join()

        failPendingSubacksUnsubacks(IllegalStateException("Disconnected"))

        val (w, version) = lock.withLock {
            val wr = writer
            val v = activeProtocolVersion
            quicClient = null
                stream = null
                reader = null
                writer = null
                state = State.DISCONNECTED
                activeProtocolVersion = 0
                assignedClientIdentifier = null
                topicAliasMap.clear()
                wr to v
        }

        w?.let {
            val data: ByteArray
            if (version == MQTTProtocolLevel.V5) {
                data = MQTT5Protocol.buildDisconnectV5(MQTT5ReasonCode.NORMAL_DISCONNECTION_DISC)
            } else {
                data = MQTTProtocol.buildDisconnect()
            }
            try {
                it.write(data)
                it.drain()
                it.close()
            } catch (e: Exception) {
                // Ignore errors during disconnect
            }
        }
    }

    fun onMessage(topic: String, callback: (ByteArray) -> Unit) {
        kotlinx.coroutines.runBlocking {
            lock.withLock {
                subscribedTopics[topic] = callback
            }
        }
    }

    private suspend fun nextPacketIdUsed(): Int = lock.withLock {
        val pid = nextPacketId
        nextPacketId = (nextPacketId + 1) % 65536
        if (nextPacketId == 0) nextPacketId = 1
        pid
    }

    private suspend fun failPendingSubacksUnsubacks(cause: Throwable) {
        lock.withLock {
            pendingSubacks.values.forEach { it.completeExceptionally(cause) }
            pendingSubacks.clear()
            pendingUnsubacks.values.forEach { it.completeExceptionally(cause) }
            pendingUnsubacks.clear()
            pendingPingresp?.completeExceptionally(cause)
            pendingPingresp = null
        }
    }

    /**
     * Send MQTT PINGREQ and wait for PINGRESP. Resets server's idle timer.
     * Returns true if PINGRESP received within timeout, false on timeout or error.
     */
    suspend fun sendMqttPing(timeoutMs: Long = 5000): Boolean {
        if (getState() != State.CONNECTED) return false
        val (w, defToAwait) = lock.withLock {
            val existing = pendingPingresp
            if (existing != null) return@withLock (null as MQTTStreamWriter?) to existing
            val deferred = CompletableDeferred<Unit>()
            pendingPingresp = deferred
            writer to deferred
        }
        return try {
            if (w != null) {
                w.write(MQTTProtocol.buildPingreq())
                w.drain()
            }
            if (defToAwait != null) withTimeout(timeoutMs) { defToAwait.await() }
            true
        } catch (e: Exception) {
            lock.withLock {
                pendingPingresp?.completeExceptionally(e)
                pendingPingresp = null
            }
            false
        }
    }

    /** Send PINGREQ at effectiveKeepalive interval so server sees activity and does not close (idle/keepalive). [MQTT-3.1.2-20] */
    private fun startKeepaliveLoop() {
        keepaliveJob?.cancel()
        keepaliveJob = scope.launch {
            val ka = lock.withLock { effectiveKeepalive }
            if (ka <= 0) return@launch
            while (isActive) {
                delay(ka * 1000L) // seconds to ms
                val (w, stillConnected) = lock.withLock {
                    writer to (state == State.CONNECTED)
                }
                if (!stillConnected || w == null) break
                try {
                    w.write(MQTTProtocol.buildPingreq())
                    w.drain()
                } catch (_: Exception) { break }
            }
        }
    }

    private fun startMessageLoop() {
        messageLoopJob = scope.launch {
            while (isActive) {
                val r = lock.withLock { reader } ?: break
                try {
                    val (msgType, remLen, fixed) = readFixedHeader(r)
                    val rest = r.readexactly(remLen)
                    val type = (msgType.toInt() and 0xF0).toByte()
                    when (type) {
                        MQTTMessageType.SUBACK -> {
                            if (rest.size >= 2) {
                                val pid = ((rest[0].toInt() and 0xFF) shl 8) or (rest[1].toInt() and 0xFF)
                                val full = fixed + rest
                                val hdrLen = fixed.size
                                lock.withLock { pendingSubacks.remove(pid)?.complete(Pair(full, hdrLen)) }
                            }
                        }
                        MQTTMessageType.UNSUBACK -> {
                            if (rest.size >= 2) {
                                val pid = ((rest[0].toInt() and 0xFF) shl 8) or (rest[1].toInt() and 0xFF)
                                lock.withLock { pendingUnsubacks.remove(pid)?.complete(Unit) }
                            }
                        }
                        MQTTMessageType.DISCONNECT -> {
                            val reasonCode = if (rest.isNotEmpty()) rest[0].toInt() and 0xFF else 0x00
                            lock.withLock {
                                keepaliveJob?.cancel()
                                keepaliveJob = null
                                quicClient = null
                                stream = null
                                reader = null
                                writer = null
                                assignedClientIdentifier = null
                                topicAliasMap.clear()
                                state = if (reasonCode >= 0x80) State.ERROR else State.DISCONNECTED
                            }
                            failPendingSubacksUnsubacks(IllegalStateException("Server sent DISCONNECT"))
                            break
                        }
                        MQTTMessageType.PINGREQ -> {
                            val w = lock.withLock { writer }
                            w?.let {
                                val pr = MQTTProtocol.buildPingresp()
                                it.write(pr)
                                it.drain()
                            }
                        }
                        MQTTMessageType.PINGRESP -> {
                            lock.withLock {
                                pendingPingresp?.complete(Unit)
                                pendingPingresp = null
                            }
                        }
                        MQTTMessageType.PUBLISH -> {
                            val qos = (msgType.toInt() shr 1) and 0x03
                            val (topic, packetId, payload) = lock.withLock {
                                if (activeProtocolVersion == MQTTProtocolLevel.V5) {
                                    MQTT5Protocol.parsePublishV5(rest, 0, qos, topicAliasMap)
                                } else {
                                    MQTTProtocol.parsePublish(rest, 0, qos)
                                }
                            }

                            val (cb, globalCb) = lock.withLock {
                                subscribedTopics[topic] to onPublish
                            }
                            globalCb?.invoke(topic, payload)
                            cb?.invoke(payload)

                            if (qos >= 1 && packetId != null) {
                                val w = lock.withLock { writer }
                                w?.let {
                                    if (qos == 1) {
                                        it.write(MQTTProtocol.buildPuback(packetId))
                                    } else {
                                        it.write(MQTTProtocol.buildPubrec(packetId))
                                    }
                                    it.drain()
                                }
                            }
                        }
                        MQTTMessageType.PUBREL -> {
                            if (rest.size < 2) break
                            val pubrelPid = MQTTProtocol.parsePubrel(rest, 0)
                            val w = lock.withLock { writer }
                            w?.let {
                                it.write(MQTTProtocol.buildPubcomp(pubrelPid))
                                it.drain()
                            }
                        }
                    }
                } catch (e: Exception) {
                    if (isActive) {
                        lock.withLock {
                            keepaliveJob?.cancel()
                            keepaliveJob = null
                            quicClient = null
                            stream = null
                            reader = null
                            writer = null
                            assignedClientIdentifier = null
                            topicAliasMap.clear()
                            state = State.DISCONNECTED
                        }
                        failPendingSubacksUnsubacks(e)
                    }
                    break
                }
            }
        }
    }
}
