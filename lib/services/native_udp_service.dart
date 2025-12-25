import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// Service for controlling native UDP H264 video receiver.
/// Uses platform channel to communicate with Android native code.
class NativeUdpService {
  static const _channel = MethodChannel('com.example.third_eye/udp_h264');

  /// Start receiving UDP packets on the specified port.
  Future<bool> startReceiver({int port = 5000}) async {
    try {
      debugPrint('NativeUdp: Starting receiver on port $port');
      final result = await _channel.invokeMethod<bool>('startReceiver', {'port': port});
      debugPrint('NativeUdp: Receiver started: $result');
      return result ?? false;
    } catch (e) {
      debugPrint('NativeUdp: Failed to start receiver: $e');
      return false;
    }
  }

  /// Stop the UDP receiver.
  Future<void> stopReceiver() async {
    try {
      debugPrint('NativeUdp: Stopping receiver');
      await _channel.invokeMethod('stopReceiver');
      debugPrint('NativeUdp: Receiver stopped');
    } catch (e) {
      debugPrint('NativeUdp: Failed to stop receiver: $e');
    }
  }

  /// Check if the receiver is currently running.
  Future<bool> isReceiving() async {
    try {
      final result = await _channel.invokeMethod<bool>('isReceiving');
      return result ?? false;
    } catch (e) {
      debugPrint('NativeUdp: Failed to check receiver status: $e');
      return false;
    }
  }

  /// Get receiver statistics (packets received, bytes received, etc.)
  Future<Map<String, dynamic>> getStats() async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('getStats');
      if (result != null) {
        return Map<String, dynamic>.from(result);
      }
      return {
        'packetsReceived': 0,
        'bytesReceived': 0,
        'isRunning': false,
      };
    } catch (e) {
      debugPrint('NativeUdp: Failed to get stats: $e');
      return {
        'packetsReceived': 0,
        'bytesReceived': 0,
        'isRunning': false,
      };
    }
  }
}
