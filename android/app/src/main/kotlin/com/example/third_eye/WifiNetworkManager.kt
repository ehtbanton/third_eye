package com.example.third_eye

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiNetworkSpecifier
import android.os.Build
import android.util.Log
import kotlinx.coroutines.*
import java.net.Inet4Address
import java.net.NetworkInterface

/**
 * WifiNetworkManager - Connects to a specific WiFi network while keeping mobile data active
 *
 * Uses Android's WifiNetworkSpecifier (API 29+) to:
 * - Connect to a specific SSID/password programmatically
 * - Mark the network as local-only (no internet validation)
 * - Allow mobile data to remain active for internet traffic
 */
class WifiNetworkManager(private val context: Context) {
    private val TAG = "WifiNetworkManager"

    companion object {
        // Static reference to current WiFi network for socket binding
        @Volatile
        var currentWifiNetwork: Network? = null
            private set
    }

    private val connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    private var wifiNetwork: Network? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var currentSsid: String? = null

    /**
     * Connect to a WiFi network by SSID and password
     *
     * @param ssid The WiFi network name
     * @param password The WiFi password
     * @return true if connection was successful
     */
    suspend fun connectToWifi(ssid: String, password: String): Boolean = withContext(Dispatchers.IO) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            Log.e(TAG, "WifiNetworkSpecifier requires Android 10 (API 29) or higher")
            return@withContext false
        }

        // Disconnect from any existing managed connection first
        disconnect()

        Log.d(TAG, "=== Connecting to WiFi ===")
        Log.d(TAG, "SSID: $ssid")

        return@withContext suspendCancellableCoroutine { continuation ->
            try {
                // Build WiFi network specifier
                val wifiNetworkSpecifier = WifiNetworkSpecifier.Builder()
                    .setSsid(ssid)
                    .setWpa2Passphrase(password)
                    .build()

                // Build network request
                // Note: We explicitly do NOT request NET_CAPABILITY_INTERNET
                // This tells Android this is a local network without internet
                val networkRequest = NetworkRequest.Builder()
                    .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                    .setNetworkSpecifier(wifiNetworkSpecifier)
                    .build()

                networkCallback = object : ConnectivityManager.NetworkCallback() {
                    override fun onAvailable(network: Network) {
                        Log.d(TAG, "WiFi network available: $network")
                        wifiNetwork = network
                        currentSsid = ssid
                        currentWifiNetwork = network  // Set static reference for socket binding

                        // Bind this network for WiFi traffic
                        // Note: We do NOT call bindProcessToNetwork here because
                        // we want only local traffic to go over WiFi

                        if (continuation.isActive) {
                            continuation.resume(true) {}
                        }
                    }

                    override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) {
                        Log.d(TAG, "WiFi capabilities changed: $capabilities")
                    }

                    override fun onLost(network: Network) {
                        Log.d(TAG, "WiFi network lost: $network")
                        if (wifiNetwork == network) {
                            wifiNetwork = null
                            currentSsid = null
                        }
                    }

                    override fun onUnavailable() {
                        Log.e(TAG, "WiFi network unavailable - user may have declined or network not found")
                        if (continuation.isActive) {
                            continuation.resume(false) {}
                        }
                    }
                }

                Log.d(TAG, "Requesting WiFi network connection...")
                connectivityManager.requestNetwork(networkRequest, networkCallback!!)

                // Timeout after 30 seconds
                GlobalScope.launch {
                    delay(30000)
                    if (continuation.isActive && wifiNetwork == null) {
                        Log.e(TAG, "WiFi connection timeout after 30 seconds")
                        continuation.resume(false) {}
                    }
                }

            } catch (e: Exception) {
                Log.e(TAG, "Error requesting WiFi network: ${e.message}")
                e.printStackTrace()
                if (continuation.isActive) {
                    continuation.resume(false) {}
                }
            }
        }
    }

    /**
     * Disconnect from the managed WiFi network
     */
    fun disconnect() {
        Log.d(TAG, "Disconnecting from WiFi...")
        networkCallback?.let {
            try {
                connectivityManager.unregisterNetworkCallback(it)
            } catch (e: Exception) {
                Log.w(TAG, "Error unregistering callback: ${e.message}")
            }
        }
        networkCallback = null
        wifiNetwork = null
        currentSsid = null
        currentWifiNetwork = null  // Clear static reference
        Log.d(TAG, "WiFi disconnected")
    }

    /**
     * Check if connected to the specified WiFi network
     */
    fun isConnectedToWifi(ssid: String? = null): Boolean {
        if (wifiNetwork == null) return false
        if (ssid != null && currentSsid != ssid) return false

        // Verify the network is still valid
        val capabilities = connectivityManager.getNetworkCapabilities(wifiNetwork)
        return capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
    }

    /**
     * Get current WiFi connection state
     */
    fun getWifiState(): Map<String, Any?> {
        val connected = wifiNetwork != null
        var ipAddress: String? = null

        if (connected) {
            // Try to get the IP address assigned to the WiFi interface
            try {
                val linkProperties = connectivityManager.getLinkProperties(wifiNetwork)
                linkProperties?.linkAddresses?.forEach { linkAddress ->
                    val address = linkAddress.address
                    if (address is Inet4Address && !address.isLoopbackAddress) {
                        ipAddress = address.hostAddress
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "Error getting IP address: ${e.message}")
            }
        }

        return mapOf(
            "connected" to connected,
            "ssid" to currentSsid,
            "ip" to ipAddress
        )
    }

    /**
     * Get the WiFi network for binding specific sockets
     * Use this to route specific traffic through WiFi
     */
    fun getWifiNetwork(): Network? = wifiNetwork

    /**
     * Bind a socket factory to the WiFi network
     * Use this when you need to make HTTP requests over WiFi specifically
     */
    fun getWifiSocketFactory(): javax.net.SocketFactory? {
        return wifiNetwork?.socketFactory
    }
}
