package com.example.playground

import android.content.Context
import android.net.wifi.WifiManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import kotlinx.coroutines.*

class MainActivity : FlutterActivity() {
    private val scope = CoroutineScope(Dispatchers.IO)
    private val CHANNEL = "playground.sync/multicast"
    private var multicastLock: WifiManager.MulticastLock? = null
    private var wifiLock: WifiManager.WifiLock? = null
    private var broadcastSocket: DatagramSocket? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "acquire" -> {
                    try {
                        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager

                        // Multicast lock for receiving
                        multicastLock = wifiManager.createMulticastLock("playground_sync")
                        multicastLock?.setReferenceCounted(false)
                        multicastLock?.acquire()

                        // WiFi lock for sending broadcasts
                        wifiLock = wifiManager.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "playground_broadcast")
                        wifiLock?.setReferenceCounted(false)
                        wifiLock?.acquire()

                        // Create a dedicated broadcast socket bound to ephemeral port
                        broadcastSocket = DatagramSocket(0)  // 0 = any available port
                        broadcastSocket?.broadcast = true
                        broadcastSocket?.reuseAddress = true

                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ACQUIRE_FAILED", e.message, null)
                    }
                }
                "release" -> {
                    try {
                        multicastLock?.release()
                        multicastLock = null
                        wifiLock?.release()
                        wifiLock = null
                        broadcastSocket?.close()
                        broadcastSocket = null
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("RELEASE_FAILED", e.message, null)
                    }
                }
                "sendBroadcast" -> {
                    // Flutter sends Uint8List which comes as a ByteArray
                    val data = call.argument<ByteArray>("data")
                            ?: call.argument<List<Int>>("data")?.map { it.toByte() }?.toByteArray()
                    val address = call.argument<String>("address")
                    val port = call.argument<Int>("port")

                    if (data == null || address == null || port == null) {
                        result.error("INVALID_ARGS", "Missing required arguments", null)
                        return@setMethodCallHandler
                    }

                    val socket = broadcastSocket
                    if (socket == null || socket.isClosed) {
                        result.error("NO_SOCKET", "Broadcast socket not initialized", null)
                        return@setMethodCallHandler
                    }

                    // Run network operation in background thread
                    scope.launch {
                        try {
                            val packet = DatagramPacket(data, data.size, InetAddress.getByName(address), port)
                            socket.send(packet)
                            withContext(Dispatchers.Main) {
                                result.success(data.size)
                            }
                        } catch (e: Exception) {
                            android.util.Log.e("Playground", "Broadcast send failed: ${e.message}", e)
                            withContext(Dispatchers.Main) {
                                result.error("SEND_FAILED", "${e.javaClass.simpleName}: ${e.message}", null)
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        scope.cancel()
        multicastLock?.release()
        wifiLock?.release()
        broadcastSocket?.close()
        super.onDestroy()
    }
}
