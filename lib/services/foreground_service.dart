import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// Service for controlling the Android Foreground Service for persistent UDP streaming.
/// This keeps the UDP receiver alive when the app is minimized or screen is off.
/// Also handles background triggers from hardware buttons (clicker) via MediaSession.
class ForegroundService {
  static const _channel =
      MethodChannel('com.example.third_eye/foreground_service');

  /// Stream controller for trigger events from the background service.
  final _triggerController = StreamController<Map<String, dynamic>>.broadcast();

  /// Stream of trigger events from the background service.
  /// Listen to this to handle scene description triggers when app is backgrounded.
  Stream<Map<String, dynamic>> get triggerStream => _triggerController.stream;

  /// Singleton instance
  static final ForegroundService _instance = ForegroundService._internal();
  factory ForegroundService() => _instance;

  ForegroundService._internal() {
    _setupMethodCallHandler();
  }

  /// Set up method call handler for callbacks from native service.
  void _setupMethodCallHandler() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onTrigger':
          debugPrint('ForegroundService: Received trigger from background');
          final args = Map<String, dynamic>.from(call.arguments ?? {});
          _triggerController.add(args);
          break;
        default:
          debugPrint('ForegroundService: Unknown method ${call.method}');
      }
    });
  }

  /// Dispose of resources.
  void dispose() {
    _triggerController.close();
  }

  /// Start the foreground service and begin UDP streaming on the specified port.
  Future<bool> startService({int port = 5000}) async {
    try {
      debugPrint('ForegroundService: Starting service on port $port');
      final result =
          await _channel.invokeMethod<bool>('startService', {'port': port});
      debugPrint('ForegroundService: Service started: $result');
      return result ?? false;
    } catch (e) {
      debugPrint('ForegroundService: Failed to start service: $e');
      return false;
    }
  }

  /// Stop the foreground service and UDP streaming.
  Future<void> stopService() async {
    try {
      debugPrint('ForegroundService: Stopping service');
      await _channel.invokeMethod('stopService');
      debugPrint('ForegroundService: Service stopped');
    } catch (e) {
      debugPrint('ForegroundService: Failed to stop service: $e');
    }
  }

  /// Check if the foreground service is currently running.
  Future<bool> isRunning() async {
    try {
      final result = await _channel.invokeMethod<bool>('isServiceRunning');
      return result ?? false;
    } catch (e) {
      debugPrint('ForegroundService: Failed to check service status: $e');
      return false;
    }
  }

  /// Get service statistics (packets received, bytes received, etc.)
  Future<Map<String, dynamic>> getStats() async {
    try {
      final result =
          await _channel.invokeMethod<Map<dynamic, dynamic>>('getServiceStats');
      if (result != null) {
        return Map<String, dynamic>.from(result);
      }
      return _emptyStats();
    } catch (e) {
      debugPrint('ForegroundService: Failed to get stats: $e');
      return _emptyStats();
    }
  }

  /// Request notification permission (required for Android 13+)
  Future<void> requestNotificationPermission() async {
    try {
      await _channel.invokeMethod('requestNotificationPermission');
    } catch (e) {
      debugPrint(
          'ForegroundService: Failed to request notification permission: $e');
    }
  }

  /// Check if notification permission is granted
  Future<bool> hasNotificationPermission() async {
    try {
      final result =
          await _channel.invokeMethod<bool>('hasNotificationPermission');
      return result ?? false;
    } catch (e) {
      debugPrint(
          'ForegroundService: Failed to check notification permission: $e');
      return false;
    }
  }

  /// Request battery optimization exemption (helps prevent service from being killed)
  Future<void> requestBatteryOptimizationExemption() async {
    try {
      await _channel.invokeMethod('requestBatteryOptimizationExemption');
    } catch (e) {
      debugPrint(
          'ForegroundService: Failed to request battery exemption: $e');
    }
  }

  /// Update the notification text
  Future<void> updateNotification(String text) async {
    try {
      await _channel.invokeMethod('updateNotification', {'text': text});
    } catch (e) {
      debugPrint('ForegroundService: Failed to update notification: $e');
    }
  }

  Map<String, dynamic> _emptyStats() {
    return {
      'isStreaming': false,
      'port': 0,
      'packetsReceived': 0,
      'bytesReceived': 0,
      'hasNetwork': false,
    };
  }
}
