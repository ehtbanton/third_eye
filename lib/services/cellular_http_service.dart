import 'package:flutter/services.dart';
import 'dart:convert';

/// Service for making HTTP requests over cellular network only
/// This ensures API requests go over mobile data while WiFi is used for ESP32-CAM
class CellularHttpService {
  static const MethodChannel _channel = MethodChannel('com.example.third_eye/cellular_http');

  bool _isInitialized = false;
  bool _cellularAvailable = false;

  /// Initialize cellular network access
  /// Must be called before making any HTTP requests
  /// Set forceReinitialize to true to request cellular network again even if already initialized
  Future<bool> initialize({bool forceReinitialize = false}) async {
    if (_isInitialized && !forceReinitialize) {
      print('CellularHttpService already initialized (cellular available: $_cellularAvailable)');
      return _cellularAvailable;
    }

    try {
      print('Requesting cellular network access${forceReinitialize ? ' (forced reinitialize)' : ''}...');
      final success = await _channel.invokeMethod<bool>('requestCellularNetwork');

      _isInitialized = true;
      _cellularAvailable = success ?? false;

      if (_cellularAvailable) {
        print('✓ Cellular network available');
      } else {
        print('✗ Cellular network unavailable - requests will fail');
        print('Make sure:');
        print('  1. Mobile data is enabled in phone settings');
        print('  2. You have cellular signal');
        print('  3. Airplane mode is OFF');
      }

      return _cellularAvailable;
    } catch (e) {
      print('Error initializing cellular network: $e');
      _isInitialized = false;
      _cellularAvailable = false;
      return false;
    }
  }

  /// Execute HTTP POST request over cellular network
  ///
  /// @param url The URL to send the request to
  /// @param headers Map of HTTP headers
  /// @param body Request body (will be JSON encoded if Map, or used as String)
  /// @param contentType Content-Type header (default: application/json)
  /// @return Response body as String
  Future<String> post({
    required String url,
    Map<String, String>? headers,
    dynamic body,
    String contentType = 'application/json',
  }) async {
    if (!_isInitialized || !_cellularAvailable) {
      throw Exception(
        'Cellular network not available. Call initialize() first and ensure cellular is enabled.',
      );
    }

    try {
      // Convert body to String if it's a Map (JSON)
      String bodyString;
      if (body is Map) {
        bodyString = jsonEncode(body);
      } else if (body is String) {
        bodyString = body;
      } else {
        bodyString = body.toString();
      }

      print('POST $url over cellular (${bodyString.length} bytes)');

      final response = await _channel.invokeMethod<String>(
        'executePost',
        {
          'url': url,
          'headers': headers ?? {},
          'body': bodyString,
          'contentType': contentType,
        },
      );

      if (response == null) {
        throw Exception('Null response from cellular HTTP POST');
      }

      print('✓ POST response received (${response.length} bytes)');
      return response;
    } catch (e) {
      print('✗ Cellular POST request failed: $e');
      rethrow;
    }
  }

  /// Execute HTTP GET request over cellular network
  ///
  /// @param url The URL to send the request to
  /// @param headers Map of HTTP headers
  /// @return Response body as String
  Future<String> get({
    required String url,
    Map<String, String>? headers,
  }) async {
    if (!_isInitialized || !_cellularAvailable) {
      throw Exception(
        'Cellular network not available. Call initialize() first and ensure cellular is enabled.',
      );
    }

    try {
      print('GET $url over cellular');

      final response = await _channel.invokeMethod<String>(
        'executeGet',
        {
          'url': url,
          'headers': headers ?? {},
        },
      );

      if (response == null) {
        throw Exception('Null response from cellular HTTP GET');
      }

      print('✓ GET response received (${response.length} bytes)');
      return response;
    } catch (e) {
      print('✗ Cellular GET request failed: $e');
      rethrow;
    }
  }

  /// Check if cellular network is currently available
  Future<bool> isCellularAvailable() async {
    try {
      final available = await _channel.invokeMethod<bool>('isCellularAvailable');
      _cellularAvailable = available ?? false;
      return _cellularAvailable;
    } catch (e) {
      print('Error checking cellular availability: $e');
      return false;
    }
  }

  /// Release cellular network (optional cleanup)
  Future<void> release() async {
    try {
      await _channel.invokeMethod('releaseCellularNetwork');
      _isInitialized = false;
      _cellularAvailable = false;
      print('Cellular network released');
    } catch (e) {
      print('Error releasing cellular network: $e');
    }
  }

  /// Check if service is initialized
  bool get isInitialized => _isInitialized;

  /// Check if cellular is available
  bool get cellularAvailable => _cellularAvailable;
}
