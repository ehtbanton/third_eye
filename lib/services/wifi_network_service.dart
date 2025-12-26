import 'package:flutter/services.dart';

/// Service for connecting to WiFi networks programmatically while keeping mobile data active.
///
/// Uses Android's WifiNetworkSpecifier (API 29+) to:
/// - Connect to a specific SSID/password
/// - Keep mobile data active for internet traffic
/// - Route only local traffic through WiFi
class WifiNetworkService {
  static const MethodChannel _channel =
      MethodChannel('com.example.third_eye/wifi_network');

  // Default CM4/SLP2 network credentials
  static const String defaultSsid = 'cosmostreamer';
  static const String defaultPassword = '1234512345';

  bool _isConnected = false;
  String? _connectedSsid;

  /// Connect to the CM4/SLP2 WiFi network using default credentials
  Future<bool> connectToCm4() async {
    return await connectToWifi(defaultSsid, defaultPassword);
  }

  /// Connect to a specific WiFi network by SSID and password
  ///
  /// Returns true if connection was successful.
  /// Note: On Android 10+, a system dialog will be shown to the user.
  Future<bool> connectToWifi(String ssid, String password) async {
    try {
      print('WifiNetworkService: Connecting to WiFi "$ssid"...');

      final success = await _channel.invokeMethod<bool>('connectToWifi', {
        'ssid': ssid,
        'password': password,
      });

      _isConnected = success ?? false;
      _connectedSsid = _isConnected ? ssid : null;

      if (_isConnected) {
        print('WifiNetworkService: Connected to "$ssid"');
      } else {
        print('WifiNetworkService: Failed to connect to "$ssid"');
      }

      return _isConnected;
    } catch (e) {
      print('WifiNetworkService: Error connecting to WiFi: $e');
      _isConnected = false;
      _connectedSsid = null;
      return false;
    }
  }

  /// Disconnect from the current WiFi network
  Future<void> disconnect() async {
    try {
      print('WifiNetworkService: Disconnecting from WiFi...');
      await _channel.invokeMethod('disconnectWifi');
      _isConnected = false;
      _connectedSsid = null;
      print('WifiNetworkService: Disconnected');
    } catch (e) {
      print('WifiNetworkService: Error disconnecting: $e');
    }
  }

  /// Check if connected to a specific WiFi network
  ///
  /// If ssid is null, checks if connected to any managed WiFi network.
  Future<bool> isConnectedToWifi([String? ssid]) async {
    try {
      final connected = await _channel.invokeMethod<bool>('isConnectedToWifi', {
        'ssid': ssid,
      });
      return connected ?? false;
    } catch (e) {
      print('WifiNetworkService: Error checking connection: $e');
      return false;
    }
  }

  /// Get the current WiFi connection state
  ///
  /// Returns a map with:
  /// - 'connected': bool - whether connected to managed WiFi
  /// - 'ssid': String? - the SSID of the connected network
  /// - 'ip': String? - the IP address assigned to the WiFi interface
  Future<Map<String, dynamic>> getWifiState() async {
    try {
      final state = await _channel.invokeMethod<Map>('getWifiState');
      return Map<String, dynamic>.from(state ?? {});
    } catch (e) {
      print('WifiNetworkService: Error getting WiFi state: $e');
      return {'connected': false, 'ssid': null, 'ip': null};
    }
  }

  /// Whether currently connected to a managed WiFi network
  bool get isConnected => _isConnected;

  /// The SSID of the currently connected network, if any
  String? get connectedSsid => _connectedSsid;
}
