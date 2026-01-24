package ai.annadata.mqttquic

import ai.annadata.mqttquic.client.MQTTClient
import ai.annadata.mqttquic.mqtt.MQTT5PropertyType
import com.getcapacitor.JSObject
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.CapacitorPlugin
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.nio.charset.StandardCharsets

/**
 * Capacitor plugin bridge. Phase 3: connect/publish/subscribe call into MQTTClient.
 */
@CapacitorPlugin(name = "MqttQuic")
class MqttQuicPlugin : Plugin() {

    private var client = MQTTClient(MQTTClient.ProtocolVersion.AUTO)
    private val scope = CoroutineScope(Dispatchers.Main)

    @PluginMethod
    fun connect(call: PluginCall) {
        val host = call.getString("host") ?: ""
        val port = call.getInt("port") ?: 1884
        val clientId = call.getString("clientId") ?: ""
        val username = call.getString("username")
        val password = call.getString("password")
        val cleanSession = call.getBoolean("cleanSession", true)
        val keepalive = call.getInt("keepalive", 60)
        val protocolVersionStr = call.getString("protocolVersion") ?: "auto"
        val sessionExpiryInterval = call.getInt("sessionExpiryInterval")
        
        val protocolVersion = when (protocolVersionStr) {
            "5.0" -> MQTTClient.ProtocolVersion.V5
            "3.1.1" -> MQTTClient.ProtocolVersion.V311
            else -> MQTTClient.ProtocolVersion.AUTO
        }

        if (host.isEmpty() || clientId.isEmpty()) {
            call.reject("host and clientId are required")
            return
        }

        scope.launch {
            try {
                if (client.getState() == MQTTClient.State.CONNECTED) {
                    client.disconnect()
                }
                client = MQTTClient(protocolVersion)
                client.connect(host, port, clientId, username, password, cleanSession, keepalive, sessionExpiryInterval)
                call.resolve(JSObject().put("connected", true))
            } catch (e: Exception) {
                call.reject(e.message ?: "Connection failed")
            }
        }
    }

    @PluginMethod
    fun disconnect(call: PluginCall) {
        scope.launch {
            try {
                client.disconnect()
                call.resolve()
            } catch (e: Exception) {
                call.reject(e.message ?: "Disconnect failed")
            }
        }
    }

    @PluginMethod
    fun publish(call: PluginCall) {
        val topic = call.getString("topic") ?: ""
        val qos = call.getInt("qos", 0)
        val messageExpiryInterval = call.getInt("messageExpiryInterval")
        val contentType = call.getString("contentType")

        if (topic.isEmpty()) {
            call.reject("topic is required")
            return
        }

        val data: ByteArray = when {
            call.getString("payload") != null ->
                call.getString("payload")!!.toByteArray(StandardCharsets.UTF_8)
            call.getArray("payload") != null -> {
                val arr = call.getArray("payload")!!
                (0 until arr.length()).mapNotNull { i ->
                    (arr.get(i) as? Number)?.toInt()?.and(0xFF)?.toByte()
                }.toByteArray()
            }
            else -> {
                call.reject("payload must be string or number array")
                return
            }
        }

        scope.launch {
            try {
                val properties = mutableMapOf<Int, Any>()
                messageExpiryInterval?.let { properties[MQTT5PropertyType.MESSAGE_EXPIRY_INTERVAL.toInt()] = it }
                contentType?.let { properties[MQTT5PropertyType.CONTENT_TYPE.toInt()] = it }
                client.publish(topic, data, minOf(qos, 2), if (properties.isNotEmpty()) properties else null)
                call.resolve(JSObject().put("success", true))
            } catch (e: Exception) {
                call.reject(e.message ?: "Publish failed")
            }
        }
    }

    @PluginMethod
    fun subscribe(call: PluginCall) {
        val topic = call.getString("topic") ?: ""
        val qos = call.getInt("qos", 0)
        val subscriptionIdentifier = call.getInt("subscriptionIdentifier")

        if (topic.isEmpty()) {
            call.reject("topic is required")
            return
        }

        scope.launch {
            try {
                client.subscribe(topic, minOf(qos, 2), subscriptionIdentifier)
                call.resolve(JSObject().put("success", true))
            } catch (e: Exception) {
                call.reject(e.message ?: "Subscribe failed")
            }
        }
    }

    @PluginMethod
    fun unsubscribe(call: PluginCall) {
        val topic = call.getString("topic") ?: ""

        if (topic.isEmpty()) {
            call.reject("topic is required")
            return
        }

        scope.launch {
            try {
                client.unsubscribe(topic)
                call.resolve(JSObject().put("success", true))
            } catch (e: Exception) {
                call.reject(e.message ?: "Unsubscribe failed")
            }
        }
    }
}
