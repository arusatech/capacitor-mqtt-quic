package ai.annadata.mqttquic.mqtt

/**
 * MQTT 5.0 Protocol implementation. Matches MQTTD mqttd/protocol_v5.py.
 */
object MQTT5Protocol {
    
    fun buildConnectV5(
        clientId: String,
        username: String? = null,
        password: String? = null,
        keepalive: Int = 60,
        cleanStart: Boolean = true,
        sessionExpiryInterval: Int? = null,
        receiveMaximum: Int? = null,
        maximumPacketSize: Int? = null,
        topicAliasMaximum: Int? = null,
        requestResponseInformation: Int? = null,
        requestProblemInformation: Int? = null,
        authenticationMethod: String? = null,
        authenticationData: ByteArray? = null,
        properties: Map<Int, Any>? = null
    ): ByteArray {
        val variableHeader = mutableListOf<Byte>()
        variableHeader.addAll(MQTTProtocol.encodeString("MQTT").toList())
        variableHeader.add(MQTTProtocolLevel.V5)
        
        var flags = 0
        if (cleanStart) flags = flags or 0x02
        if (username != null) flags = flags or MQTTConnectFlags.USERNAME
        if (password != null) flags = flags or MQTTConnectFlags.PASSWORD
        variableHeader.add(flags.toByte())
        variableHeader.add((keepalive shr 8).toByte())
        variableHeader.add((keepalive and 0xFF).toByte())
        
        val connectProps = mutableMapOf<Int, Any>()
        sessionExpiryInterval?.let { connectProps[MQTT5PropertyType.SESSION_EXPIRY_INTERVAL.toInt()] = it }
        receiveMaximum?.let { connectProps[MQTT5PropertyType.RECEIVE_MAXIMUM.toInt()] = it }
        maximumPacketSize?.let { connectProps[MQTT5PropertyType.MAXIMUM_PACKET_SIZE.toInt()] = it }
        topicAliasMaximum?.let { connectProps[MQTT5PropertyType.TOPIC_ALIAS_MAXIMUM.toInt()] = it }
        requestResponseInformation?.let { connectProps[MQTT5PropertyType.REQUEST_RESPONSE_INFORMATION.toInt()] = it }
        requestProblemInformation?.let { connectProps[MQTT5PropertyType.REQUEST_PROBLEM_INFORMATION.toInt()] = it }
        authenticationMethod?.let { connectProps[MQTT5PropertyType.AUTHENTICATION_METHOD.toInt()] = it }
        authenticationData?.let { connectProps[MQTT5PropertyType.AUTHENTICATION_DATA.toInt()] = it }
        properties?.let { connectProps.putAll(it) }
        
        val propsBytes = MQTT5PropertyEncoder.encodeProperties(connectProps)
        val propsLen = MQTTProtocol.encodeRemainingLength(propsBytes.size)
        variableHeader.addAll(propsLen.toList())
        variableHeader.addAll(propsBytes.toList())
        
        val payload = mutableListOf<Byte>()
        payload.addAll(MQTTProtocol.encodeString(clientId).toList())
        payload.add(0x00) // Will Properties length = 0
        username?.let { payload.addAll(MQTTProtocol.encodeString(it).toList()) }
        password?.let { payload.addAll(MQTTProtocol.encodeString(it).toList()) }
        
        val remLen = variableHeader.size + payload.size
        val fixed = mutableListOf<Byte>()
        fixed.add(MQTTMessageType.CONNECT)
        fixed.addAll(MQTTProtocol.encodeRemainingLength(remLen).toList())
        
        return (fixed + variableHeader + payload).toByteArray()
    }
    
    fun buildConnackV5(
        reasonCode: Int = MQTT5ReasonCode.SUCCESS,
        sessionPresent: Boolean = false,
        properties: Map<Int, Any>? = null
    ): ByteArray {
        val variableHeader = mutableListOf<Byte>()
        variableHeader.add(if (sessionPresent) 0x01 else 0x00)
        variableHeader.add(reasonCode.toByte())
        
        val props = properties ?: emptyMap()
        val propsBytes = MQTT5PropertyEncoder.encodeProperties(props)
        val propsLen = MQTTProtocol.encodeRemainingLength(propsBytes.size)
        variableHeader.addAll(propsLen.toList())
        variableHeader.addAll(propsBytes.toList())
        
        val remLen = variableHeader.size
        val fixed = mutableListOf<Byte>()
        fixed.add(MQTTMessageType.CONNACK)
        fixed.addAll(MQTTProtocol.encodeRemainingLength(remLen).toList())
        
        return (fixed + variableHeader).toByteArray()
    }
    
    fun parseConnackV5(data: ByteArray, offset: Int = 0): Triple<Boolean, Int, Map<Int, Any>> {
        if (offset + 2 > data.size) throw IllegalArgumentException("Insufficient data for CONNACK")
        val sessionPresent = (data[offset].toInt() and 0x01) != 0
        val reasonCode = data[offset + 1].toInt() and 0xFF
        var pos = offset + 2
        
        val (propLen, propLenBytes) = MQTTProtocol.decodeRemainingLength(data, pos)
        pos += propLenBytes
        val (props, _) = MQTT5PropertyEncoder.decodeProperties(data.copyOfRange(pos, pos + propLen), 0)
        pos += propLen
        
        return Triple(sessionPresent, reasonCode, props)
    }
    
    fun buildPublishV5(
        topic: String,
        payload: ByteArray,
        packetId: Int? = null,
        qos: Int = 0,
        retain: Boolean = false,
        properties: Map<Int, Any>? = null
    ): ByteArray {
        var msgType = MQTTMessageType.PUBLISH.toInt()
        if (qos > 0) msgType = msgType or (qos shl 1)
        if (retain) msgType = msgType or 0x01
        
        val vh = mutableListOf<Byte>()
        vh.addAll(MQTTProtocol.encodeString(topic).toList())
        if (qos > 0 && packetId != null) {
            vh.add((packetId shr 8).toByte())
            vh.add((packetId and 0xFF).toByte())
        }
        
        val props = properties ?: emptyMap()
        val propsBytes = MQTT5PropertyEncoder.encodeProperties(props)
        val propsLen = MQTTProtocol.encodeRemainingLength(propsBytes.size)
        vh.addAll(propsLen.toList())
        vh.addAll(propsBytes.toList())
        
        val pl = (vh + payload.toList()).toByteArray()
        val remLen = pl.size
        return byteArrayOf(
            msgType.toByte(),
            *MQTTProtocol.encodeRemainingLength(remLen),
            *pl
        )
    }
    
    fun buildSubscribeV5(
        packetId: Int,
        topic: String,
        qos: Int = 0,
        subscriptionIdentifier: Int? = null,
        properties: Map<Int, Any>? = null
    ): ByteArray {
        val vh = mutableListOf<Byte>()
        vh.add((packetId shr 8).toByte())
        vh.add((packetId and 0xFF).toByte())
        
        val props = mutableMapOf<Int, Any>()
        subscriptionIdentifier?.let { props[MQTT5PropertyType.SUBSCRIPTION_IDENTIFIER.toInt()] = it }
        properties?.let { props.putAll(it) }
        val propsBytes = MQTT5PropertyEncoder.encodeProperties(props)
        val propsLen = MQTTProtocol.encodeRemainingLength(propsBytes.size)
        vh.addAll(propsLen.toList())
        vh.addAll(propsBytes.toList())
        
        val pl = MQTTProtocol.encodeString(topic) + byteArrayOf((qos and 0x03).toByte())
        val rem = vh.size + pl.size
        return byteArrayOf(
            (MQTTMessageType.SUBSCRIBE.toInt() or 0x02).toByte(),
            *MQTTProtocol.encodeRemainingLength(rem),
            *vh.toByteArray(),
            *pl
        )
    }
    
    fun buildSubackV5(
        packetId: Int,
        reasonCodes: List<Int>,
        properties: Map<Int, Any>? = null
    ): ByteArray {
        val vh = mutableListOf<Byte>()
        vh.add((packetId shr 8).toByte())
        vh.add((packetId and 0xFF).toByte())
        
        val props = properties ?: emptyMap()
        val propsBytes = MQTT5PropertyEncoder.encodeProperties(props)
        val propsLen = MQTTProtocol.encodeRemainingLength(propsBytes.size)
        vh.addAll(propsLen.toList())
        vh.addAll(propsBytes.toList())
        
        val pl = reasonCodes.map { it.toByte() }.toByteArray()
        val rem = vh.size + pl.size
        return byteArrayOf(
            MQTTMessageType.SUBACK,
            *MQTTProtocol.encodeRemainingLength(rem),
            *vh.toByteArray(),
            *pl
        )
    }
    
    fun parseSubackV5(data: ByteArray, offset: Int = 0): Triple<Int, List<Int>, Map<Int, Any>> {
        if (offset + 2 > data.size) throw IllegalArgumentException("Insufficient data for SUBACK packet ID")
        val pid = ((data[offset].toInt() and 0xFF) shl 8) or (data[offset + 1].toInt() and 0xFF)
        var pos = offset + 2
        
        val (propLen, propLenBytes) = MQTTProtocol.decodeRemainingLength(data, pos)
        pos += propLenBytes
        val (props, _) = MQTT5PropertyEncoder.decodeProperties(data.copyOfRange(pos, pos + propLen), 0)
        pos += propLen
        
        val reasonCodes = mutableListOf<Int>()
        while (pos < data.size) {
            reasonCodes.add(data[pos].toInt() and 0xFF)
            pos++
        }
        
        return Triple(pid, reasonCodes, props)
    }
    
    fun buildUnsubscribeV5(
        packetId: Int,
        topics: List<String>,
        properties: Map<Int, Any>? = null
    ): ByteArray {
        val vh = mutableListOf<Byte>()
        vh.add((packetId shr 8).toByte())
        vh.add((packetId and 0xFF).toByte())
        
        val props = properties ?: emptyMap()
        val propsBytes = MQTT5PropertyEncoder.encodeProperties(props)
        val propsLen = MQTTProtocol.encodeRemainingLength(propsBytes.size)
        vh.addAll(propsLen.toList())
        vh.addAll(propsBytes.toList())
        
        val plList = topics.flatMap { MQTTProtocol.encodeString(it).toList() }
        val pl = ByteArray(plList.size) { plList[it] }
        val rem = vh.size + pl.size
        return byteArrayOf(
            (MQTTMessageType.UNSUBSCRIBE.toInt() or 0x02).toByte(),
            *MQTTProtocol.encodeRemainingLength(rem),
            *vh.toByteArray(),
            *pl
        )
    }
    
    fun buildUnsubackV5(
        packetId: Int,
        reasonCodes: List<Int>? = null,
        properties: Map<Int, Any>? = null
    ): ByteArray {
        val vh = mutableListOf<Byte>()
        vh.add((packetId shr 8).toByte())
        vh.add((packetId and 0xFF).toByte())
        
        val props = properties ?: emptyMap()
        val propsBytes = MQTT5PropertyEncoder.encodeProperties(props)
        val propsLen = MQTTProtocol.encodeRemainingLength(propsBytes.size)
        vh.addAll(propsLen.toList())
        vh.addAll(propsBytes.toList())
        
        val pl = reasonCodes?.map { it.toByte() }?.toByteArray() ?: ByteArray(0)
        val rem = vh.size + pl.size
        return byteArrayOf(
            MQTTMessageType.UNSUBACK,
            *MQTTProtocol.encodeRemainingLength(rem),
            *vh.toByteArray(),
            *pl
        )
    }
    
    fun buildDisconnectV5(
        reasonCode: Int = MQTT5ReasonCode.NORMAL_DISCONNECTION_DISC,
        properties: Map<Int, Any>? = null
    ): ByteArray {
        val vh = mutableListOf<Byte>()
        vh.add(reasonCode.toByte())
        
        val props = properties ?: emptyMap()
        val propsBytes = MQTT5PropertyEncoder.encodeProperties(props)
        val propsLen = MQTTProtocol.encodeRemainingLength(propsBytes.size)
        vh.addAll(propsLen.toList())
        vh.addAll(propsBytes.toList())
        
        val remLen = vh.size
        val fixed = mutableListOf<Byte>()
        fixed.add(MQTTMessageType.DISCONNECT)
        fixed.addAll(MQTTProtocol.encodeRemainingLength(remLen).toList())
        
        return (fixed + vh).toByteArray()
    }
}
