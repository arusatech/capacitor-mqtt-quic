package ai.annadata.mqttquic.client

import ai.annadata.mqttquic.mqtt.MQTTConnAckCode
import ai.annadata.mqttquic.mqtt.MQTTMessageType
import ai.annadata.mqttquic.mqtt.MQTTProtocol
import ai.annadata.mqttquic.mqtt.MQTT5Protocol
import ai.annadata.mqttquic.mqtt.MQTT5ReasonCode
import ai.annadata.mqttquic.mqtt.MQTTProtocolLevel
import ai.annadata.mqttquic.quic.QuicClient
import ai.annadata.mqttquic.quic.QuicClientStub
import ai.annadata.mqttquic.quic.QuicStream
import ai.annadata.mqttquic.transport.MQTTStreamReader
import ai.annadata.mqttquic.transport.MQTTStreamWriter
import ai.annadata.mqttquic.transport.QUICStreamReader
import ai.annadata.mqttquic.transport.QUICStreamWriter
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.SupervisorJob

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
    private var quicClient: QuicClient? = null
    private var stream: QuicStream? = null
    private var reader: MQTTStreamReader? = null
    private var writer: MQTTStreamWriter? = null
    private var messageLoopJob: kotlinx.coroutines.Job? = null
    private var nextPacketId = 1
    private val subscribedTopics = mutableMapOf<String, (ByteArray) -> Unit>()
    private val lock = Mutex()
    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())

    constructor(protocolVersion: ProtocolVersion = ProtocolVersion.AUTO) {
        this.protocolVersion = protocolVersion
    }

    fun getState(): State = runBlocking { lock.withLock { state } }

    suspend fun connect(
        host: String,
        port: Int,
        clientId: String,
        username: String?,
        password: String?,
        cleanSession: Boolean,
        keepalive: Int,
        sessionExpiryInterval: Int? = null
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
            
            val quic = QuicClientStub(connack.toList())
            quic.connect(host, port)
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

            val fixed = r.readexactly(2)
            val (msgType, remLen, hdrLen) = MQTTProtocol.parseFixedHeader(fixed)
            val rest = r.readexactly(remLen)
            val full = fixed + rest
            if (msgType != MQTTMessageType.CONNACK) {
                lock.withLock { state = State.ERROR }
                throw IllegalArgumentException("expected CONNACK, got $msgType")
            }
            
            if (activeProtocolVersion == MQTTProtocolLevel.V5) {
                val (_, reasonCode, _) = MQTT5Protocol.parseConnackV5(full, hdrLen)
                if (reasonCode != MQTT5ReasonCode.SUCCESS) {
                    lock.withLock { state = State.ERROR }
                    throw IllegalArgumentException("CONNACK refused: $reasonCode")
                }
            } else {
                val (_, returnCode) = MQTTProtocol.parseConnack(full, hdrLen)
                if (returnCode != MQTTConnAckCode.ACCEPTED) {
                    lock.withLock { state = State.ERROR }
                    throw IllegalArgumentException("CONNACK refused: $returnCode")
                }
            }

            lock.withLock { state = State.CONNECTED }
            startMessageLoop()
        } catch (e: Exception) {
            val wr = lock.withLock {
                val w = writer
                quicClient = null
                stream = null
                reader = null
                writer = null
                state = State.ERROR
                w
            }
            try {
                wr?.close()
            } catch (_: Exception) { /* ignore */ }
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
        w.write(data)
        w.drain()
    }

    suspend fun subscribe(topic: String, qos: Int, subscriptionIdentifier: Int? = null) {
        if (getState() != State.CONNECTED) throw IllegalStateException("not connected")
        val (r, w, version) = lock.withLock { Triple(reader, writer, activeProtocolVersion) }
        if (r == null || w == null) throw IllegalStateException("no reader/writer")

        val pid = nextPacketIdUsed()
        val data: ByteArray
        if (version == MQTTProtocolLevel.V5) {
            data = MQTT5Protocol.buildSubscribeV5(pid, topic, qos, subscriptionIdentifier)
        } else {
            data = MQTTProtocol.buildSubscribe(pid, topic, qos)
        }
        w.write(data)
        w.drain()

        val fixed = r.readexactly(2)
        val (_, remLen, hdrLen) = MQTTProtocol.parseFixedHeader(fixed)
        val rest = r.readexactly(remLen)
        val full = fixed + rest
        
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
    }

    suspend fun unsubscribe(topic: String) {
        if (getState() != State.CONNECTED) throw IllegalStateException("not connected")
        val (r, w, version) = lock.withLock {
            subscribedTopics.remove(topic)
            Triple(reader, writer, activeProtocolVersion)
        }
        if (r == null || w == null) throw IllegalStateException("no reader/writer")

        val pid = nextPacketIdUsed()
        val data: ByteArray
        if (version == MQTTProtocolLevel.V5) {
            data = MQTT5Protocol.buildUnsubscribeV5(pid, listOf(topic))
        } else {
            data = MQTTProtocol.buildUnsubscribe(pid, listOf(topic))
        }
        w.write(data)
        w.drain()

        val fixed = r.readexactly(2)
        val (_, remLen, _) = MQTTProtocol.parseFixedHeader(fixed)
        r.readexactly(remLen)
    }

    suspend fun disconnect() {
        val job = messageLoopJob
        messageLoopJob = null
        job?.cancel()
        job?.join()

        val (w, version) = lock.withLock {
            val wr = writer
            val v = activeProtocolVersion
            quicClient = null
            stream = null
            reader = null
            writer = null
            state = State.DISCONNECTED
            activeProtocolVersion = 0
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

    private fun startMessageLoop() {
        messageLoopJob = scope.launch {
            while (isActive) {
                val r = lock.withLock { reader } ?: break
                try {
                    val fixed = r.readexactly(2)
                    val (msgType, remLen, _) = MQTTProtocol.parseFixedHeader(fixed)
                    val rest = r.readexactly(remLen)
                    val type = (msgType.toInt() and 0xF0).toByte()
                    when (type) {
                        MQTTMessageType.PINGREQ -> {
                            val w = lock.withLock { writer }
                            w?.let {
                                val pr = MQTTProtocol.buildPingresp()
                                it.write(pr)
                                it.drain()
                            }
                        }
                        MQTTMessageType.PUBLISH -> {
                            val qos = ((msgType.toInt() shr 1) and 0x03).toByte()
                            val (topic, packetId, payload) = MQTTProtocol.parsePublish(rest, 0, qos.toInt())

                            val (cb, _) = lock.withLock {
                                subscribedTopics[topic] to activeProtocolVersion
                            }
                            cb?.invoke(payload)

                            if (qos.toInt() >= 1 && packetId != null) {
                                val w = lock.withLock { writer }
                                w?.let {
                                    val puback = MQTTProtocol.buildPuback(packetId)
                                    it.write(puback)
                                    it.drain()
                                }
                            }
                        }
                    }
                } catch (e: Exception) {
                    if (!isActive) break
                }
            }
        }
    }
}
