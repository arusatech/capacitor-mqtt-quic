package ai.annadata.mqttquic

import ai.annadata.mqttquic.client.MQTTClient
import ai.annadata.mqttquic.mqtt.MQTT5PropertyType
import com.getcapacitor.JSObject
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.CapacitorPlugin
import android.os.Handler
import android.os.Looper
import android.system.Os
import android.util.Base64
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.nio.charset.StandardCharsets
import java.io.File
import java.io.IOException

/**
 * Capacitor plugin bridge. Phase 3: connect/publish/subscribe call into MQTTClient.
 */
@CapacitorPlugin(name = "MqttQuic")
class MqttQuicPlugin : Plugin() {

    private var client = MQTTClient(MQTTClient.ProtocolVersion.AUTO)
    private val scope = CoroutineScope(Dispatchers.Main)

    private fun bundledCaFilePath(): String? {
        return try {
            val assetName = "mqttquic_ca.pem"
            val content = context.assets.open(assetName).bufferedReader().use { it.readText() }
            if (!content.contains("BEGIN CERTIFICATE")) {
                return null
            }
            val outFile = File(context.filesDir, assetName)
            outFile.writeText(content)
            outFile.absolutePath
        } catch (_: IOException) {
            null
        }
    }

    @PluginMethod
    fun connect(call: PluginCall) {
        val host = call.getString("host") ?: ""
        val port = call.getInt("port") ?: 1884
        val clientId = call.getString("clientId") ?: ""
        val username = call.getString("username")
        val password = call.getString("password")
        val cleanSession = call.getBoolean("cleanSession", true)
        val keepalive = call.getInt("keepalive", 20)
        val protocolVersionStr = call.getString("protocolVersion") ?: "auto"
        val sessionExpiryInterval = call.getInt("sessionExpiryInterval")
        val caFile = call.getString("caFile")
        val caPath = call.getString("caPath")
        
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
                try {
                    val bundled = bundledCaFilePath()
                    when {
                        caFile != null -> Os.setenv("MQTT_QUIC_CA_FILE", caFile, true)
                        bundled != null -> Os.setenv("MQTT_QUIC_CA_FILE", bundled, true)
                        else -> Os.setenv("MQTT_QUIC_CA_FILE", "", true)
                    }
                    if (caPath != null) {
                        Os.setenv("MQTT_QUIC_CA_PATH", caPath, true)
                    } else {
                        Os.setenv("MQTT_QUIC_CA_PATH", "", true)
                    }
                } catch (_: Exception) {
                    // Ignore env setup failures; native layer will report verification errors.
                }
                if (client.getState() == MQTTClient.State.CONNECTED) {
                    client.disconnect()
                }
                client = MQTTClient(protocolVersion)
                // Forward every incoming PUBLISH to JS so addListener('message', ...) receives topic + payload
                client.onPublish = { topic, payload ->
                    val payloadStr = try {
                        String(payload, StandardCharsets.UTF_8)
                    } catch (_: Exception) {
                        Base64.encodeToString(payload, Base64.NO_WRAP)
                    }
                    val data = JSObject().put("topic", topic).put("payload", payloadStr)
                    Handler(Looper.getMainLooper()).post {
                        notifyListeners("message", data)
                    }
                }
                client.connect(host, port, clientId, username, password, cleanSession, keepalive, sessionExpiryInterval)
                call.resolve(JSObject().put("connected", true))
                notifyListeners("connected", JSObject().put("connected", true))
            } catch (e: Exception) {
                call.reject(e.message ?: "Connection failed")
            }
        }
    }

    @PluginMethod
    fun testHarness(call: PluginCall) {
        val host = call.getString("host") ?: ""
        val port = call.getInt("port") ?: 1884
        val clientId = call.getString("clientId") ?: "mqttquic_test_client"
        val topic = call.getString("topic") ?: "test/topic"
        val payload = call.getString("payload") ?: "Hello QUIC!"
        val caFile = call.getString("caFile")
        val caPath = call.getString("caPath")

        if (host.isEmpty()) {
            call.reject("host is required")
            return
        }

        scope.launch {
            try {
                try {
                    val bundled = bundledCaFilePath()
                    when {
                        caFile != null -> Os.setenv("MQTT_QUIC_CA_FILE", caFile, true)
                        bundled != null -> Os.setenv("MQTT_QUIC_CA_FILE", bundled, true)
                        else -> Os.setenv("MQTT_QUIC_CA_FILE", "", true)
                    }
                    if (caPath != null) {
                        Os.setenv("MQTT_QUIC_CA_PATH", caPath, true)
                    } else {
                        Os.setenv("MQTT_QUIC_CA_PATH", "", true)
                    }
                } catch (_: Exception) {
                    // Ignore env setup failures; native layer will report verification errors.
                }

                client = MQTTClient(MQTTClient.ProtocolVersion.AUTO)
                client.connect(host, port, clientId, null, null, true, 60, null)
                client.subscribe(topic, 0, null)
                client.publish(topic, payload.toByteArray(StandardCharsets.UTF_8), 0, null)
                client.disconnect()
                call.resolve(JSObject().put("success", true))
                notifyListeners("subscribed", JSObject().put("topic", topic))
            } catch (e: Exception) {
                call.reject(e.message ?: "Test harness failed")
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
                val msg = e.message ?: "Publish failed"
                val code = when {
                    msg.contains("not connected", ignoreCase = true) -> "CONNECTION_LOST"
                    msg.contains("stream", ignoreCase = true) || msg.contains("connection", ignoreCase = true) -> "CONNECTION_LOST"
                    else -> "PUBLISH_FAILED"
                }
                call.reject(msg, code)
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
