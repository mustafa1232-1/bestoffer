package com.maslaki.user

import android.app.Application
import android.content.pm.ApplicationInfo
import android.os.Bundle
import android.util.Log
import com.hiennv.flutter_callkit_incoming.CallkitEventCallback
import com.hiennv.flutter_callkit_incoming.FlutterCallkitIncomingPlugin
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import org.json.JSONObject

/**
 * Declining an incoming in-app call from the native call UI must reach the
 * server even when the Flutter engine is not running (app closed), otherwise
 * the caller keeps ringing until the timeout and only sees "missed".
 *
 * The call push carries a short-lived signed `callActionToken` plus the
 * `declineUrl`; this posts them from a background thread. The Dart side sends
 * the same request when it is alive — the server treats it idempotently.
 */
class MainApplication : Application() {
    // FlutterCallkitIncomingPlugin keeps only a WeakReference: hold it here.
    private val callkitEventCallback = object : CallkitEventCallback {
        override fun onCallEvent(event: CallkitEventCallback.CallEvent, callData: Bundle) {
            if (event == CallkitEventCallback.CallEvent.DECLINE) {
                sendDecline(readExtra(callData))
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        FlutterCallkitIncomingPlugin.registerEventCallback(callkitEventCallback)
    }

    @Suppress("DEPRECATION", "UNCHECKED_CAST")
    private fun readExtra(callData: Bundle): Map<String, Any?> {
        val raw = callData.getSerializable("EXTRA_CALLKIT_EXTRA")
        return (raw as? Map<String, Any?>) ?: emptyMap()
    }

    private fun sendDecline(extra: Map<String, Any?>) {
        val token = extra["callActionToken"]?.toString()?.trim().orEmpty()
        val url = extra["declineUrl"]?.toString()?.trim().orEmpty()
        val debuggable = (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        // Release builds only ever talk to the HTTPS API.
        if (token.isEmpty() || url.isEmpty()) return
        if (!url.startsWith("https://") && !debuggable) return
        Thread {
            var connection: HttpURLConnection? = null
            try {
                connection = (URL(url).openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"
                    connectTimeout = 8000
                    readTimeout = 8000
                    doOutput = true
                    setRequestProperty("Content-Type", "application/json")
                    setRequestProperty("Accept", "application/json")
                }
                OutputStreamWriter(connection.outputStream, Charsets.UTF_8).use {
                    it.write(JSONObject(mapOf("token" to token)).toString())
                }
                Log.d(TAG, "call decline sent: ${connection.responseCode}")
            } catch (error: Exception) {
                Log.w(TAG, "call decline failed: ${error.message}")
            } finally {
                connection?.disconnect()
            }
        }.start()
    }

    private companion object {
        const val TAG = "MaslakiCalls"
    }
}
