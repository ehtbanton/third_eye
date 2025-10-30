package com.example.third_eye

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.util.Log
import kotlinx.coroutines.*
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException
import java.util.concurrent.TimeUnit

/**
 * CellularHttpClient - Binds HTTP requests to cellular network only
 * This ensures Gemini API requests go over mobile data while WiFi is used for ESP32-CAM
 */
class CellularHttpClient(private val context: Context) {
    private var cellularNetwork: Network? = null
    private var cellularCallback: ConnectivityManager.NetworkCallback? = null
    private val connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

    private val TAG = "CellularHttpClient"

    /**
     * Request access to cellular network
     * This must be called before making HTTP requests
     */
    suspend fun requestCellularNetwork(): Boolean = withContext(Dispatchers.IO) {
        return@withContext suspendCancellableCoroutine { continuation ->
            try {
                Log.d(TAG, "=== Requesting Cellular Network ===")

                // Check if mobile data is enabled
                val activeNetwork = connectivityManager.activeNetwork
                val capabilities = connectivityManager.getNetworkCapabilities(activeNetwork)
                Log.d(TAG, "Active network: $activeNetwork")
                Log.d(TAG, "Active network capabilities: $capabilities")

                if (capabilities != null) {
                    Log.d(TAG, "Has INTERNET: ${capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)}")
                    Log.d(TAG, "Has CELLULAR: ${capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)}")
                    Log.d(TAG, "Has WIFI: ${capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)}")
                }

                // Build network request for cellular only
                val networkRequest = NetworkRequest.Builder()
                    .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                    .addTransportType(NetworkCapabilities.TRANSPORT_CELLULAR)
                    .build()

                cellularCallback = object : ConnectivityManager.NetworkCallback() {
                    override fun onAvailable(network: Network) {
                        Log.d(TAG, "✓ Cellular network available: $network")
                        cellularNetwork = network

                        // Log cellular network capabilities
                        val cellularCapabilities = connectivityManager.getNetworkCapabilities(network)
                        Log.d(TAG, "Cellular network capabilities: $cellularCapabilities")

                        if (continuation.isActive) {
                            continuation.resume(true) {}
                        }
                    }

                    override fun onLost(network: Network) {
                        Log.d(TAG, "✗ Cellular network lost: $network")
                        if (cellularNetwork == network) {
                            cellularNetwork = null
                        }
                    }

                    override fun onUnavailable() {
                        Log.e(TAG, "✗ Cellular network unavailable - mobile data may be disabled")
                        if (continuation.isActive) {
                            continuation.resume(false) {}
                        }
                    }
                }

                // Request cellular network
                Log.d(TAG, "Calling requestNetwork()...")
                connectivityManager.requestNetwork(networkRequest, cellularCallback!!)

                // Set timeout for network acquisition
                GlobalScope.launch {
                    delay(10000) // 10 second timeout
                    if (continuation.isActive && cellularNetwork == null) {
                        Log.e(TAG, "✗ Cellular network request timeout after 10 seconds")
                        Log.e(TAG, "This usually means mobile data is disabled or unavailable")
                        continuation.resume(false) {}
                    }
                }

            } catch (e: Exception) {
                Log.e(TAG, "Error requesting cellular network: $e")
                e.printStackTrace()
                if (continuation.isActive) {
                    continuation.resume(false) {}
                }
            }
        }
    }

    /**
     * Execute HTTP POST request over cellular network
     *
     * @param url The URL to send the request to
     * @param headers Map of HTTP headers
     * @param body Request body as String (usually JSON)
     * @param contentType Content-Type header value
     * @return Response body as String, or throws exception on error
     */
    suspend fun executePost(
        url: String,
        headers: Map<String, String>,
        body: String,
        contentType: String = "application/json"
    ): String = withContext(Dispatchers.IO) {
        Log.d(TAG, "=== executePost called ===")
        Log.d(TAG, "URL: $url")
        Log.d(TAG, "Body length: ${body.length} bytes")
        Log.d(TAG, "Cellular network status: ${if (cellularNetwork != null) "AVAILABLE" else "NULL"}")

        if (cellularNetwork == null) {
            Log.e(TAG, "✗ Cellular network is NULL - cannot make request")
            throw IOException("Cellular network not available. Call requestCellularNetwork() first.")
        }

        // Store the current default network so we can restore it later
        val originalNetwork = connectivityManager.boundNetworkForProcess
        Log.d(TAG, "Original bound network: $originalNetwork")

        try {
            // CRITICAL FIX for Android 15: Bind the entire process to cellular network
            // This ensures DNS resolution and all network traffic goes through cellular
            Log.d(TAG, "Binding process to cellular network: $cellularNetwork")
            val bindSuccess = connectivityManager.bindProcessToNetwork(cellularNetwork)

            if (!bindSuccess) {
                Log.e(TAG, "✗ Failed to bind process to cellular network")
                throw IOException("Failed to bind process to cellular network")
            }

            Log.d(TAG, "✓ Process successfully bound to cellular network")

            // Create OkHttpClient (will now use cellular since process is bound)
            val client = OkHttpClient.Builder()
                .connectTimeout(30, TimeUnit.SECONDS)
                .readTimeout(60, TimeUnit.SECONDS)
                .writeTimeout(60, TimeUnit.SECONDS)
                .build()

            Log.d(TAG, "Building POST request...")

            // Build request
            val requestBuilder = Request.Builder()
                .url(url)
                .post(body.toRequestBody(contentType.toMediaType()))

            // Add headers
            headers.forEach { (key, value) ->
                requestBuilder.addHeader(key, value)
                Log.d(TAG, "Header: $key = $value")
            }

            val request = requestBuilder.build()
            Log.d(TAG, "Executing POST request via cellular network...")

            // Execute request (will use cellular because process is bound)
            val response = client.newCall(request).execute()

            Log.d(TAG, "Response received: HTTP ${response.code}")

            if (!response.isSuccessful) {
                val errorBody = response.body?.string() ?: "No error body"
                Log.e(TAG, "✗ HTTP error ${response.code}: $errorBody")
                throw IOException("HTTP ${response.code}: $errorBody")
            }

            val responseBody = response.body?.string() ?: ""
            Log.d(TAG, "✓ POST request successful (${responseBody.length} bytes)")

            return@withContext responseBody
        } catch (e: Exception) {
            Log.e(TAG, "✗ POST request exception: ${e.message}")
            Log.e(TAG, "Exception type: ${e.javaClass.simpleName}")
            e.printStackTrace()
            throw e
        } finally {
            // IMPORTANT: Restore original network binding
            Log.d(TAG, "Restoring original network binding: $originalNetwork")
            connectivityManager.bindProcessToNetwork(originalNetwork)
            Log.d(TAG, "Network binding restored")
        }
    }

    /**
     * Execute HTTP GET request over cellular network
     *
     * @param url The URL to send the request to
     * @param headers Map of HTTP headers
     * @return Response body as String, or throws exception on error
     */
    suspend fun executeGet(
        url: String,
        headers: Map<String, String>
    ): String = withContext(Dispatchers.IO) {
        Log.d(TAG, "=== executeGet called ===")
        Log.d(TAG, "URL: $url")

        if (cellularNetwork == null) {
            Log.e(TAG, "✗ Cellular network is NULL - cannot make request")
            throw IOException("Cellular network not available. Call requestCellularNetwork() first.")
        }

        // Store the current default network so we can restore it later
        val originalNetwork = connectivityManager.boundNetworkForProcess
        Log.d(TAG, "Original bound network: $originalNetwork")

        try {
            // Bind the entire process to cellular network for Android 15 compatibility
            Log.d(TAG, "Binding process to cellular network: $cellularNetwork")
            val bindSuccess = connectivityManager.bindProcessToNetwork(cellularNetwork)

            if (!bindSuccess) {
                Log.e(TAG, "✗ Failed to bind process to cellular network")
                throw IOException("Failed to bind process to cellular network")
            }

            Log.d(TAG, "✓ Process successfully bound to cellular network")

            // Create OkHttpClient (will now use cellular since process is bound)
            val client = OkHttpClient.Builder()
                .connectTimeout(30, TimeUnit.SECONDS)
                .readTimeout(60, TimeUnit.SECONDS)
                .build()

            // Build request
            val requestBuilder = Request.Builder()
                .url(url)
                .get()

            // Add headers
            headers.forEach { (key, value) ->
                requestBuilder.addHeader(key, value)
            }

            val request = requestBuilder.build()
            Log.d(TAG, "Executing GET request via cellular network...")

            // Execute request
            val response = client.newCall(request).execute()

            Log.d(TAG, "Response received: HTTP ${response.code}")

            if (!response.isSuccessful) {
                val errorBody = response.body?.string() ?: "No error body"
                Log.e(TAG, "✗ HTTP error ${response.code}: $errorBody")
                throw IOException("HTTP ${response.code}: $errorBody")
            }

            val responseBody = response.body?.string() ?: ""
            Log.d(TAG, "✓ GET request successful (${responseBody.length} bytes)")

            return@withContext responseBody
        } catch (e: Exception) {
            Log.e(TAG, "✗ GET request exception: ${e.message}")
            Log.e(TAG, "Exception type: ${e.javaClass.simpleName}")
            e.printStackTrace()
            throw e
        } finally {
            // IMPORTANT: Restore original network binding
            Log.d(TAG, "Restoring original network binding: $originalNetwork")
            connectivityManager.bindProcessToNetwork(originalNetwork)
            Log.d(TAG, "Network binding restored")
        }
    }

    /**
     * Release cellular network request
     * Call this when no longer needing cellular network
     */
    fun release() {
        Log.d(TAG, "Releasing cellular network...")
        cellularCallback?.let {
            connectivityManager.unregisterNetworkCallback(it)
        }
        cellularNetwork = null
        cellularCallback = null
    }

    /**
     * Check if cellular network is currently available
     */
    fun isCellularAvailable(): Boolean {
        return cellularNetwork != null
    }
}
