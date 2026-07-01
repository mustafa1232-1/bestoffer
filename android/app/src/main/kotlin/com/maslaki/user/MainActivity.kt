package com.maslaki.user

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.core.content.ContextCompat
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.util.Locale
import java.util.UUID

class MainActivity : FlutterActivity() {
    private val printerChannel = "maslaki/printer_bridge"
    private val rfcommUuid: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    private val iposServicePackage = "com.iposprinter.iposprinterservice"

    // Android 15 (API 35) enforces edge-to-edge for apps targeting SDK 35.
    // `WindowCompat.setDecorFitsSystemWindows(window, false)` is the modern,
    // non-deprecated AndroidX core API that opts the window into edge-to-edge
    // layout; it is the exact mechanism `enableEdgeToEdge()` uses internally, but
    // (unlike that ComponentActivity-only extension) it works with the framework
    // `android.app.Activity` that Flutter's `FlutterActivity` extends. Doing it
    // here makes the same edge-to-edge behaviour apply consistently on Android 14
    // and below too — what Google Play's "edge-to-edge may not display for all
    // users" notice asks for — without calling the deprecated
    // Window.setStatusBarColor / setNavigationBarColor APIs. Flutter then reads
    // the resulting system-bar insets and exposes them via MediaQuery, so the
    // existing SafeArea widgets keep content clear of the status/navigation bars.
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, printerChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getIposStatus" -> handleGetIposStatus(result)
                    "printEscPosBytes" -> handlePrintEscPosBytes(call, result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun hasBluetoothConnectPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.BLUETOOTH_CONNECT,
        ) == PackageManager.PERMISSION_GRANTED
    }

    @SuppressLint("MissingPermission")
    private fun findIposBondedDevice(adapter: BluetoothAdapter?): BluetoothDevice? {
        if (adapter == null) return null
        if (!hasBluetoothConnectPermission()) return null
        val bonded = adapter.bondedDevices ?: return null
        val namedMatch = bonded.firstOrNull { device ->
            val name = device.name?.lowercase(Locale.US) ?: ""
            name.contains("iposprinter") || name.contains("ipos")
        }
        if (namedMatch != null) return namedMatch
        // Fallback: if device vendor changed the default printer name, use first bonded device.
        return bonded.firstOrNull()
    }

    private fun isIposServiceInstalled(): Boolean {
        return try {
            packageManager.getPackageInfo(iposServicePackage, 0)
            true
        } catch (_: Exception) {
            false
        }
    }

    @SuppressLint("MissingPermission")
    private fun handleGetIposStatus(result: MethodChannel.Result) {
        try {
            val adapter = BluetoothAdapter.getDefaultAdapter()
            val btEnabled = adapter?.isEnabled == true
            val device = findIposBondedDevice(adapter)
            result.success(
                mapOf(
                    "bluetoothEnabled" to btEnabled,
                    "bondedIposFound" to (device != null),
                    "iposServiceInstalled" to isIposServiceInstalled(),
                    "deviceName" to (device?.name ?: ""),
                    "deviceAddress" to (device?.address ?: ""),
                ),
            )
        } catch (e: Exception) {
            result.error("IPOS_STATUS_FAILED", e.message, null)
        }
    }

    private fun handlePrintEscPosBytes(call: MethodCall, result: MethodChannel.Result) {
        val bytes = call.argument<ByteArray>("bytes")
        if (bytes == null || bytes.isEmpty()) {
            result.error("INVALID_BYTES", "No bytes provided", null)
            return
        }
        if (!hasBluetoothConnectPermission()) {
            result.error(
                "NO_BT_PERMISSION",
                "BLUETOOTH_CONNECT permission is required",
                null,
            )
            return
        }

        val adapter = BluetoothAdapter.getDefaultAdapter()
        if (adapter == null) {
            result.error("NO_BLUETOOTH", "Bluetooth adapter not available", null)
            return
        }
        if (!adapter.isEnabled) {
            result.error("BT_DISABLED", "Bluetooth is disabled", null)
            return
        }

        val device = findIposBondedDevice(adapter)
        if (device == null) {
            result.error("IPOS_NOT_FOUND", "Bonded IposPrinter not found", null)
            return
        }

        Thread {
            adapter.cancelDiscovery()
            var lastError: String? = null
            val ok = printWithDevice(device, bytes) { err ->
                lastError = err
            }
            runOnUiThread {
                if (ok) {
                    result.success(true)
                } else {
                    result.error("IPOS_PRINT_FAILED", lastError ?: "Failed", null)
                }
            }
        }.start()
    }

    @SuppressLint("MissingPermission")
    private fun printWithDevice(
        device: BluetoothDevice,
        bytes: ByteArray,
        onError: (String) -> Unit,
    ): Boolean {
        val creators = listOf<(BluetoothDevice) -> android.bluetooth.BluetoothSocket>(
            { d -> d.createRfcommSocketToServiceRecord(rfcommUuid) },
            { d -> d.createInsecureRfcommSocketToServiceRecord(rfcommUuid) },
        )

        for (create in creators) {
            var socket: android.bluetooth.BluetoothSocket? = null
            try {
                socket = create(device)
                socket.connect()
                val out = socket.outputStream
                out.write(bytes)
                out.flush()
                Thread.sleep(180)
                socket.close()
                return true
            } catch (e: IOException) {
                onError(e.message ?: "I/O error")
                try {
                    socket?.close()
                } catch (_: Exception) {
                }
            } catch (e: Exception) {
                onError(e.message ?: "Unknown error")
                try {
                    socket?.close()
                } catch (_: Exception) {
                }
            }
        }

        return false
    }
}
