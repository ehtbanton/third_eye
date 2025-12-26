package com.example.third_eye

import android.net.Network
import android.util.Log
import java.net.DatagramPacket
import java.net.DatagramSocket
import kotlin.concurrent.thread

/**
 * UDP packet receiver for H264 video streams.
 * Listens on a specified port and delivers received packets via callback.
 */
class UdpReceiver(private val port: Int, private val network: Network? = null) {
    companion object {
        private const val TAG = "UdpReceiver"
        private const val BUFFER_SIZE = 65535  // Max UDP packet size
    }

    private var socket: DatagramSocket? = null
    private var running = false
    private var receiverThread: Thread? = null

    // Stats for debugging
    private var packetsReceived = 0L
    private var bytesReceived = 0L

    /**
     * Start listening for UDP packets on the configured port.
     * @param onPacketReceived Callback invoked for each received packet with (data, length)
     */
    fun start(onPacketReceived: (ByteArray, Int) -> Unit) {
        if (running) {
            Log.w(TAG, "Receiver already running on port $port")
            return
        }

        running = true
        packetsReceived = 0
        bytesReceived = 0

        receiverThread = thread(name = "UdpReceiver-$port") {
            try {
                socket = DatagramSocket(port)
                socket?.reuseAddress = true

                // Bind socket to specific network if provided (required for WifiNetworkSpecifier)
                if (network != null) {
                    network.bindSocket(socket!!)
                    Log.i(TAG, "Socket bound to WiFi network")
                }

                Log.i(TAG, "Started listening on UDP port $port")

                val buffer = ByteArray(BUFFER_SIZE)

                while (running) {
                    try {
                        val packet = DatagramPacket(buffer, buffer.size)
                        socket?.receive(packet)

                        if (packet.length > 0) {
                            packetsReceived++
                            bytesReceived += packet.length

                            // Log every 100 packets for debugging
                            if (packetsReceived % 100 == 0L) {
                                Log.d(TAG, "Received $packetsReceived packets, $bytesReceived bytes total")
                            }

                            // Copy data and invoke callback
                            val data = buffer.copyOf(packet.length)
                            onPacketReceived(data, packet.length)
                        }
                    } catch (e: Exception) {
                        if (running) {
                            Log.e(TAG, "Error receiving packet: ${e.message}")
                        }
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start UDP receiver: ${e.message}")
            } finally {
                socket?.close()
                socket = null
                Log.i(TAG, "UDP receiver stopped. Total: $packetsReceived packets, $bytesReceived bytes")
            }
        }
    }

    /**
     * Stop the UDP receiver and close the socket.
     */
    fun stop() {
        Log.i(TAG, "Stopping UDP receiver on port $port")
        running = false
        socket?.close()
        receiverThread?.join(1000)  // Wait up to 1 second for thread to finish
        receiverThread = null
    }

    /**
     * Check if the receiver is currently running.
     */
    fun isRunning(): Boolean = running

    /**
     * Get the number of packets received since start.
     */
    fun getPacketsReceived(): Long = packetsReceived

    /**
     * Get the number of bytes received since start.
     */
    fun getBytesReceived(): Long = bytesReceived
}
