import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:wifi_iot/wifi_iot.dart';
import 'package:permission_handler/permission_handler.dart';

/// Service to manage phone's WiFi hotspot for CM4 connectivity
/// Creates a known hotspot that CM4 connects to with static IP
class PhoneHotspotService {
  // Hotspot configuration
  static const String defaultSsid = 'ThirdEye_Hotspot';
  static const String defaultPassword = 'thirdeye123';
  static const String cm4StaticIp = '192.168.43.100';

  String _ssid = defaultSsid;
  String _password = defaultPassword;
  bool _isHotspotEnabled = false;

  /// Check if hotspot is currently enabled
  Future<bool> isHotspotEnabled() async {
    try {
      final enabled = await WiFiForIoTPlugin.isWiFiAPEnabled();
      _isHotspotEnabled = enabled ?? false;
      return _isHotspotEnabled;
    } catch (e) {
      debugPrint('PhoneHotspotService: Error checking hotspot status: $e');
      return false;
    }
  }

  /// Request necessary permissions for hotspot
  Future<bool> requestPermissions() async {
    try {
      final locationStatus = await Permission.location.request();
      final locationAlways = await Permission.locationAlways.request();

      if (locationStatus.isGranted || locationAlways.isGranted) {
        debugPrint('PhoneHotspotService: Permissions granted');
        return true;
      } else {
        debugPrint('PhoneHotspotService: Permissions denied');
        return false;
      }
    } catch (e) {
      debugPrint('PhoneHotspotService: Error requesting permissions: $e');
      return false;
    }
  }

  /// Enable WiFi hotspot with configured SSID and password
  Future<bool> enableHotspot({String? ssid, String? password}) async {
    if (ssid != null) _ssid = ssid;
    if (password != null) _password = password;

    try {
      debugPrint('PhoneHotspotService: Enabling hotspot "$_ssid"...');

      // Check if already enabled
      if (await isHotspotEnabled()) {
        debugPrint('PhoneHotspotService: Hotspot already enabled');
        return true;
      }

      // Enable hotspot
      final result = await WiFiForIoTPlugin.setWiFiAPEnabled(true);

      if (result) {
        // Configure hotspot
        await WiFiForIoTPlugin.setWiFiAPSSID(_ssid);
        await WiFiForIoTPlugin.setWiFiAPPreSharedKey(_password);

        _isHotspotEnabled = true;
        debugPrint('PhoneHotspotService: Hotspot enabled successfully');

        // Wait a moment for hotspot to fully initialize
        await Future.delayed(const Duration(seconds: 2));

        return true;
      } else {
        debugPrint('PhoneHotspotService: Failed to enable hotspot');
        return false;
      }
    } catch (e) {
      debugPrint('PhoneHotspotService: Error enabling hotspot: $e');
      return false;
    }
  }

  /// Disable WiFi hotspot
  Future<bool> disableHotspot() async {
    try {
      debugPrint('PhoneHotspotService: Disabling hotspot...');

      final result = await WiFiForIoTPlugin.setWiFiAPEnabled(false);

      if (result) {
        _isHotspotEnabled = false;
        debugPrint('PhoneHotspotService: Hotspot disabled successfully');
        return true;
      } else {
        debugPrint('PhoneHotspotService: Failed to disable hotspot');
        return false;
      }
    } catch (e) {
      debugPrint('PhoneHotspotService: Error disabling hotspot: $e');
      return false;
    }
  }

  /// Get CM4 static IP address
  String getCm4IpAddress() {
    return cm4StaticIp;
  }

  /// Get current hotspot configuration
  Map<String, String> getConfiguration() {
    return {
      'ssid': _ssid,
      'password': _password,
      'cm4_ip': cm4StaticIp,
    };
  }

  /// Get stream URLs for all cameras
  Map<String, String> getCameraUrls() {
    return {
      'left': 'http://$cm4StaticIp:8081/stream',
      'right': 'http://$cm4StaticIp:8082/stream',
      'eye': 'http://$cm4StaticIp:8083/stream',
    };
  }
}
