package com.example.playground

import android.content.Context
import android.net.wifi.WifiManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "playground.sync/multicast"
    private var multicastLock: WifiManager.MulticastLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

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
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("RELEASE_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        multicastLock?.release()
        wifiLock?.release()
        super.onDestroy()
    }
}
