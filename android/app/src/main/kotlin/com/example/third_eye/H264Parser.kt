package com.example.third_eye

import android.util.Log
import java.io.ByteArrayOutputStream

/**
 * Parser for H264 NAL units from raw UDP stream.
 * Handles NAL unit start code detection and frame assembly.
 */
class H264Parser {
    companion object {
        private const val TAG = "H264Parser"

        // NAL unit types
        const val NAL_TYPE_SLICE = 1       // P-frame slice
        const val NAL_TYPE_DPA = 2         // Data partition A
        const val NAL_TYPE_DPB = 3         // Data partition B
        const val NAL_TYPE_DPC = 4         // Data partition C
        const val NAL_TYPE_IDR = 5         // IDR frame (keyframe)
        const val NAL_TYPE_SEI = 6         // Supplemental enhancement info
        const val NAL_TYPE_SPS = 7         // Sequence parameter set
        const val NAL_TYPE_PPS = 8         // Picture parameter set
        const val NAL_TYPE_AUD = 9         // Access unit delimiter
        const val NAL_TYPE_FILLER = 12     // Filler data

        // Start code patterns
        private val START_CODE_3 = byteArrayOf(0x00, 0x00, 0x01)
        private val START_CODE_4 = byteArrayOf(0x00, 0x00, 0x00, 0x01)

        fun getNalTypeName(type: Int): String {
            return when (type) {
                NAL_TYPE_SLICE -> "P-SLICE"
                NAL_TYPE_IDR -> "IDR"
                NAL_TYPE_SEI -> "SEI"
                NAL_TYPE_SPS -> "SPS"
                NAL_TYPE_PPS -> "PPS"
                NAL_TYPE_AUD -> "AUD"
                NAL_TYPE_FILLER -> "FILLER"
                else -> "TYPE_$type"
            }
        }
    }

    // Buffer for accumulating data across UDP packets
    private val buffer = ByteArrayOutputStream()

    // Stored SPS and PPS for decoder initialization
    var sps: ByteArray? = null
        private set
    var pps: ByteArray? = null
        private set

    // Stats
    private var nalUnitsFound = 0L
    private var framesFound = 0L

    /**
     * Callback interface for parsed NAL units
     */
    interface NalUnitCallback {
        fun onNalUnit(nalUnit: ByteArray, nalType: Int)
        fun onSpsReceived(sps: ByteArray)
        fun onPpsReceived(pps: ByteArray)
        fun onKeyFrame(nalUnit: ByteArray)
    }

    private var callback: NalUnitCallback? = null

    fun setCallback(callback: NalUnitCallback) {
        this.callback = callback
    }

    /**
     * Feed raw UDP packet data into the parser.
     * NAL units will be extracted and delivered via callback.
     */
    fun feedData(data: ByteArray) {
        buffer.write(data)
        parseBuffer()
    }

    /**
     * Parse accumulated buffer for complete NAL units.
     */
    private fun parseBuffer() {
        val data = buffer.toByteArray()
        if (data.size < 5) return  // Need at least start code + 1 byte

        var searchStart = 0
        var lastNalStart = -1

        while (searchStart < data.size - 4) {
            val startCodePos = findStartCode(data, searchStart)
            if (startCodePos == -1) break

            // Determine start code length (3 or 4 bytes)
            val startCodeLen = if (startCodePos > 0 && data[startCodePos - 1] == 0.toByte()) 4 else 3
            val nalStart = startCodePos + startCodeLen - (if (startCodeLen == 4) 1 else 0)

            // If we found a previous NAL, extract it
            if (lastNalStart != -1) {
                val nalEnd = startCodePos - (if (startCodeLen == 4) 1 else 0)
                if (nalEnd > lastNalStart) {
                    val nalUnit = data.copyOfRange(lastNalStart, nalEnd)
                    processNalUnit(nalUnit)
                }
            }

            lastNalStart = startCodePos
            searchStart = startCodePos + 3
        }

        // Keep unprocessed data in buffer
        if (lastNalStart != -1) {
            buffer.reset()
            buffer.write(data, lastNalStart, data.size - lastNalStart)
        } else if (data.size > 65535) {
            // Buffer too large without finding NAL, clear it
            Log.w(TAG, "Buffer overflow without NAL units, clearing")
            buffer.reset()
        }
    }

    /**
     * Find start code (0x00 0x00 0x01) position in data.
     */
    private fun findStartCode(data: ByteArray, offset: Int): Int {
        for (i in offset until data.size - 2) {
            if (data[i] == 0.toByte() &&
                data[i + 1] == 0.toByte() &&
                data[i + 2] == 1.toByte()) {
                // Check for 4-byte start code
                return if (i > 0 && data[i - 1] == 0.toByte()) i - 1 else i
            }
        }
        return -1
    }

    /**
     * Process a complete NAL unit.
     */
    private fun processNalUnit(nalData: ByteArray) {
        if (nalData.isEmpty()) return

        // Find actual NAL header (after start code)
        val headerOffset = when {
            nalData.size >= 4 && nalData[0] == 0.toByte() && nalData[1] == 0.toByte() &&
                    nalData[2] == 0.toByte() && nalData[3] == 1.toByte() -> 4
            nalData.size >= 3 && nalData[0] == 0.toByte() && nalData[1] == 0.toByte() &&
                    nalData[2] == 1.toByte() -> 3
            else -> 0
        }

        if (headerOffset >= nalData.size) return

        val nalType = nalData[headerOffset].toInt() and 0x1F
        nalUnitsFound++

        // Log every 100th NAL unit
        if (nalUnitsFound % 100 == 0L) {
            Log.d(TAG, "NAL units found: $nalUnitsFound, type: ${getNalTypeName(nalType)}")
        }

        when (nalType) {
            NAL_TYPE_SPS -> {
                sps = nalData.copyOfRange(headerOffset, nalData.size)
                Log.i(TAG, "SPS received (${sps?.size} bytes)")
                callback?.onSpsReceived(nalData)
            }
            NAL_TYPE_PPS -> {
                pps = nalData.copyOfRange(headerOffset, nalData.size)
                Log.i(TAG, "PPS received (${pps?.size} bytes)")
                callback?.onPpsReceived(nalData)
            }
            NAL_TYPE_IDR -> {
                framesFound++
                Log.v(TAG, "IDR frame (keyframe) received")
                callback?.onKeyFrame(nalData)
                callback?.onNalUnit(nalData, nalType)
            }
            NAL_TYPE_SLICE -> {
                framesFound++
                callback?.onNalUnit(nalData, nalType)
            }
            else -> {
                callback?.onNalUnit(nalData, nalType)
            }
        }
    }

    /**
     * Check if we have received SPS and PPS (required for decoder init).
     */
    fun hasDecoderConfig(): Boolean = sps != null && pps != null

    /**
     * Reset parser state.
     */
    fun reset() {
        buffer.reset()
        sps = null
        pps = null
        nalUnitsFound = 0
        framesFound = 0
    }

    /**
     * Get parser statistics.
     */
    fun getStats(): Map<String, Long> {
        return mapOf(
            "nalUnitsFound" to nalUnitsFound,
            "framesFound" to framesFound
        )
    }
}
